import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';

part 'ota_event.dart';
part 'ota_state.dart';

class OtaBloc extends Bloc<OtaEvent, OtaState> {
  final OtaRepository repository;
  Timer? _progressTimer;

  // 轮询三级保护：总时长上限 / 连续失败阈值 / 进度停滞（假死）检测
  static const Duration _maxPollDuration = Duration(minutes: 15);
  static const Duration _stallTimeout = Duration(minutes: 5);
  static const int _maxConsecutiveFailures = 3;

  DateTime? _pollStartedAt;
  DateTime? _lastProgressChangedAt;
  double _lastProgress = -1;
  int _consecutiveFailures = 0;

  /// 是否处于升级流程中（已触发/轮询中）：
  /// 防重入守卫，避免多次点击并发触发多条升级命令
  bool get _upgradeActive => state is OTATriggered || state is OTAProgress;

  OtaBloc({required this.repository}) : super(OTAInitial()) {
    on<OTACheckRequested>(_onCheckRequested);
    on<OTATriggerRequested>(_onTriggerRequested);
    on<OTAPackageTriggerRequested>(_onPackageTriggerRequested);
    on<OTAProgressPollRequested>(_onProgressPollRequested);
    on<OTAProgressStopPoll>(_onProgressStopPoll);
    on<OTAFirmwareListRequested>(_onFirmwareListRequested);
    on<OTAFirmwareInstallRequested>(_onFirmwareInstallRequested);
    on<LoadAvailablePackages>(_onLoadAvailablePackages);
  }

  Future<void> _onCheckRequested(
    OTACheckRequested event,
    Emitter<OtaState> emit,
  ) async {
    final result = await repository.checkUpdate(event.sn);
    result.fold(
      (failure) {
        if (state is OTAUpdateAvailable || state is OTAUpToDate) return;
        emit(OTAError(message: failure.message));
      },
      (data) {
        final hasUpdate = data['has_update'] == true;
        if (hasUpdate) {
          emit(OTAUpdateAvailable(info: data));
        } else {
          emit(OTAUpToDate(info: data));
        }
      },
    );
  }

  Future<void> _onTriggerRequested(
    OTATriggerRequested event,
    Emitter<OtaState> emit,
  ) async {
    // 防重入：升级进行中禁止再次触发
    if (_upgradeActive) return;
    final result = await repository.triggerOTA(event.sn, event.packageId);
    result.fold(
      (failure) {
        if (state is OTAUpdateAvailable ||
            state is OTAUpToDate ||
            state is OTATriggered) {
          return;
        }
        emit(OTAError(message: failure.message));
      },
      (data) {
        // 从响应中提取 task_id 并保存到状态中
        final taskId = (data['task_id'] as num?)?.toInt() ?? 0;
        emit(OTATriggered(taskId: taskId));
        _startProgressPoll(event.sn);
      },
    );
  }

  /// Package mode: admin already pushed, but command may not have been delivered.
  /// Call resend API to ensure command is sent, then start polling.
  Future<void> _onPackageTriggerRequested(
    OTAPackageTriggerRequested event,
    Emitter<OtaState> emit,
  ) async {
    // 防重入：升级进行中禁止再次触发
    if (_upgradeActive) return;
    // 先调用 resend API 确保升级命令被发送到设备；
    // 下发失败时不再伪装"已触发"并空转轮询
    final result = await repository.resendUpgradeCommand(event.sn);
    result.fold(
      (failure) => emit(OTAError(message: failure.message)),
      (_) {
        emit(const OTATriggered(taskId: 0));
        _startProgressPoll(event.sn);
      },
    );
  }

  void _startProgressPoll(String deviceSn) {
    _progressTimer?.cancel();
    // 重置三级保护状态
    _pollStartedAt = DateTime.now();
    _lastProgressChangedAt = DateTime.now();
    _lastProgress = -1;
    _consecutiveFailures = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      add(OTAProgressPollRequested(deviceSn: deviceSn));
    });
  }

  void _stopProgressPoll() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _onProgressPollRequested(
    OTAProgressPollRequested event,
    Emitter<OtaState> emit,
  ) async {
    // 轮询已停止（离开页面/手动停止）时丢弃滞后的轮询事件
    if (_progressTimer == null) return;

    // 总时长上限：设备端卡死/后端任务异常时避免状态永久悬挂
    if (_pollStartedAt != null &&
        DateTime.now().difference(_pollStartedAt!) > _maxPollDuration) {
      _stopProgressPoll();
      emit(const OTAError(message: 'Upgrade timed out'));
      return;
    }

    final result = await repository.getDeviceOTAStatus(event.deviceSn);
    // 请求期间轮询被停止：丢弃本轮结果
    if (_progressTimer == null) return;

    result.fold(
      (failure) {
        // 单次失败容忍（弱网抖动）：连续失败达阈值才进错误态，
        // 避免设备仍在正常升级时误报失败
        _consecutiveFailures++;
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          _stopProgressPoll();
          emit(OTAError(message: failure.message));
        }
      },
      (data) {
        _consecutiveFailures = 0;
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;

        // 停滞（假死）检测：进度长时间不变视为设备端卡死
        if (progress != _lastProgress) {
          _lastProgress = progress;
          _lastProgressChangedAt = DateTime.now();
        } else if (_lastProgressChangedAt != null &&
            DateTime.now().difference(_lastProgressChangedAt!) >
                _stallTimeout) {
          _stopProgressPoll();
          emit(const OTAError(message: 'Upgrade timed out'));
          return;
        }

        emit(OTAProgress(progress: progress, status: status, detail: data));
        if (status == 'completed' ||
            status == 'success' ||
            status == 'failed') {
          _stopProgressPoll();
          if (status == 'completed' || status == 'success') {
            emit(OTAComplete());
          } else {
            emit(
              OTAError(
                message: data['error_message'] as String? ?? 'Upgrade failed',
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _onProgressStopPoll(
    OTAProgressStopPoll event,
    Emitter<OtaState> emit,
  ) async {
    _stopProgressPoll();
    emit(OTAInitial());
  }

  Future<void> _onFirmwareListRequested(
    OTAFirmwareListRequested event,
    Emitter<OtaState> emit,
  ) async {
    emit(OTAFirmwareListLoading());
    final result =
        await repository.listUpgradePackages(model: event.deviceModel);
    result.fold(
      (failure) => emit(OTAFirmwareListError(message: failure.message)),
      (packages) => emit(OTAFirmwareListLoaded(packages: packages)),
    );
  }

  Future<void> _onFirmwareInstallRequested(
    OTAFirmwareInstallRequested event,
    Emitter<OtaState> emit,
  ) async {
    // 防重入：升级进行中禁止再次触发
    if (_upgradeActive) return;
    emit(OTAFirmwareInstalling(packageId: event.packageId));
    final result = await repository.installPackage(event.sn, event.packageId);
    result.fold(
      (failure) => emit(OTAError(message: failure.message)),
      (data) {
        final taskId = (data['task_id'] as num?)?.toInt() ?? 0;
        emit(OTATriggered(taskId: taskId));
        _startProgressPoll(event.sn);
      },
    );
  }

  /// 加载设备可用升级包列表
  /// 调用 GET /ota/available-packages/:sn
  /// 响应: {code: 0, data: [{id, user_version, user_changelog, is_force, model, main_version, ...}]}
  Future<void> _onLoadAvailablePackages(
    LoadAvailablePackages event,
    Emitter<OtaState> emit,
  ) async {
    emit(OTAAvailablePackagesLoading());
    final result = await repository.getAvailablePackages(event.sn);
    result.fold(
      (failure) => emit(OTAAvailablePackagesError(message: failure.message)),
      (packages) => emit(OTAAvailablePackagesLoaded(packages: packages)),
    );
  }

  @override
  Future<void> close() {
    _stopProgressPoll();
    return super.close();
  }
}
