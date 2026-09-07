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
  String _lastStatus = '';
  int _consecutiveFailures = 0;
  int _pollGeneration = 0;
  bool _pollActive = false;
  bool _pollRequestInFlight = false;
  String? _pollDeviceSn;
  int? _pollTaskId;

  /// 命令提交中的同步锁。Bloc 的事件处理可并发执行，不能只依赖当前 state
  /// 防重入，否则首个请求 await 期间可能再次下发升级命令。
  bool _commandRequestInFlight = false;

  /// 是否处于升级流程中（已触发/轮询中）：
  /// 防重入守卫，避免多次点击并发触发多条升级命令
  bool get _upgradeActive =>
      _commandRequestInFlight ||
      state is OTATriggering ||
      state is OTAFirmwareInstalling ||
      state is OTATriggered ||
      state is OTAProgress;

  OtaBloc({required this.repository}) : super(OTAInitial()) {
    on<OTACheckRequested>(_onCheckRequested);
    on<OTATriggerRequested>(_onTriggerRequested);
    on<OTAPackageTriggerRequested>(_onPackageTriggerRequested);
    on<OTAProgressStartPollRequested>(_onProgressStartPollRequested);
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
    _commandRequestInFlight = true;
    emit(const OTATriggering());
    try {
      final result = await repository.triggerOTA(event.sn, event.packageId);
      result.fold(
        (failure) => emit(OTAError(message: failure.message)),
        (data) {
          // 从响应中提取 task_id 并保存到状态中
          final taskId = (data['task_id'] as num?)?.toInt() ?? 0;
          emit(OTATriggered(taskId: taskId));
          _startProgressPoll(event.sn, taskId: taskId, immediate: false);
        },
      );
    } catch (e) {
      emit(OTAError(message: e.toString()));
    } finally {
      _commandRequestInFlight = false;
    }
  }

  /// Package mode: admin already pushed, but command may not have been delivered.
  /// Call resend API to ensure command is sent, then start polling.
  Future<void> _onPackageTriggerRequested(
    OTAPackageTriggerRequested event,
    Emitter<OtaState> emit,
  ) async {
    // 防重入：升级进行中禁止再次触发
    if (_upgradeActive) return;
    _commandRequestInFlight = true;
    emit(const OTATriggering());
    // 先调用 resend API 确保升级命令被发送到设备；
    // 下发失败时不再伪装"已触发"并空转轮询
    try {
      final result = await repository.resendUpgradeCommand(event.sn);
      result.fold(
        (failure) => emit(OTAError(message: failure.message)),
        (data) {
          final taskId = (data['task_id'] as num?)?.toInt() ?? 0;
          emit(OTATriggered(taskId: taskId));
          _startProgressPoll(event.sn, taskId: taskId, immediate: false);
        },
      );
    } catch (e) {
      emit(OTAError(message: e.toString()));
    } finally {
      _commandRequestInFlight = false;
    }
  }

  Future<void> _onProgressStartPollRequested(
    OTAProgressStartPollRequested event,
    Emitter<OtaState> emit,
  ) async {
    _startProgressPoll(
      event.deviceSn,
      taskId: event.taskId,
      immediate: true,
    );
  }

  void _startProgressPoll(
    String deviceSn, {
    int? taskId,
    required bool immediate,
  }) {
    _progressTimer?.cancel();
    _pollGeneration++;
    _pollActive = true;
    _pollRequestInFlight = false;
    _pollDeviceSn = deviceSn;
    _pollTaskId = taskId != null && taskId > 0 ? taskId : null;
    // 重置三级保护状态
    _pollStartedAt = DateTime.now();
    _lastProgressChangedAt = DateTime.now();
    _lastProgress = -1;
    _lastStatus = '';
    _consecutiveFailures = 0;
    if (immediate) {
      _requestNextPoll(_pollGeneration);
    } else {
      _scheduleNextPoll(_pollGeneration);
    }
  }

  void _requestNextPoll(int generation) {
    if (!_pollActive || generation != _pollGeneration) return;
    add(
      OTAProgressPollRequested(
        deviceSn: _pollDeviceSn!,
        taskId: _pollTaskId,
        generation: generation,
      ),
    );
  }

  void _scheduleNextPoll(int generation) {
    if (!_pollActive || generation != _pollGeneration) return;
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(seconds: 2), () {
      _progressTimer = null;
      _requestNextPoll(generation);
    });
  }

  void _stopProgressPoll() {
    _pollGeneration++;
    _pollActive = false;
    _pollRequestInFlight = false;
    _pollDeviceSn = null;
    _pollTaskId = null;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _onProgressPollRequested(
    OTAProgressPollRequested event,
    Emitter<OtaState> emit,
  ) async {
    final generation = event.generation ?? _pollGeneration;
    // 轮询已停止、属于旧会话或已有请求执行中时丢弃事件。
    if (!_pollActive ||
        generation != _pollGeneration ||
        _pollRequestInFlight) {
      return;
    }
    _pollRequestInFlight = true;

    // 总时长上限：设备端卡死/后端任务异常时避免状态永久悬挂
    if (_pollStartedAt != null &&
        DateTime.now().difference(_pollStartedAt!) > _maxPollDuration) {
      _stopProgressPoll();
      emit(const OTAError(message: 'Upgrade timed out'));
      return;
    }

    final result = await repository.getDeviceOTAStatus(
      event.deviceSn,
      taskId: event.taskId ?? _pollTaskId,
    );
    // 请求期间轮询被停止或被新会话替换：丢弃本轮结果。
    if (!_pollActive || generation != _pollGeneration) return;
    _pollRequestInFlight = false;

    var shouldContinue = true;
    result.fold(
      (failure) {
        // 单次失败容忍（弱网抖动）：连续失败达阈值才进错误态，
        // 避免设备仍在正常升级时误报失败
        _consecutiveFailures++;
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          _stopProgressPoll();
          emit(OTAError(message: failure.message));
          shouldContinue = false;
        }
      },
      (data) {
        _consecutiveFailures = 0;
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;

        // 停滞（假死）检测：进度长时间不变视为设备端卡死
        if (progress != _lastProgress || status != _lastStatus) {
          _lastProgress = progress;
          _lastStatus = status;
          _lastProgressChangedAt = DateTime.now();
        } else if (_lastProgressChangedAt != null &&
            DateTime.now().difference(_lastProgressChangedAt!) >
                _stallTimeout) {
          _stopProgressPoll();
          emit(const OTAError(message: 'Upgrade timed out'));
          shouldContinue = false;
          return;
        }

        emit(OTAProgress(progress: progress, status: status, detail: data));
        if (status == 'completed' ||
            status == 'success' ||
            status == 'failed' ||
            status == 'cancelled' ||
            status == 'timeout') {
          _stopProgressPoll();
          shouldContinue = false;
          if (status == 'completed' || status == 'success') {
            emit(OTAComplete());
          } else {
            final serverMessage = (data['error_message'] as String?)?.trim();
            emit(
              OTAError(
                message: serverMessage != null && serverMessage.isNotEmpty
                    ? serverMessage
                    : status == 'cancelled'
                        ? 'Upgrade cancelled'
                        : status == 'timeout'
                            ? 'Upgrade timed out'
                            : 'Upgrade failed',
              ),
            );
          }
        }
      },
    );
    if (shouldContinue && _pollActive && generation == _pollGeneration) {
      _scheduleNextPoll(generation);
    }
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
    _commandRequestInFlight = true;
    emit(OTAFirmwareInstalling(packageId: event.packageId));
    try {
      final result = await repository.installPackage(event.sn, event.packageId);
      result.fold(
        (failure) => emit(OTAError(message: failure.message)),
        (data) {
          final taskId = (data['task_id'] as num?)?.toInt() ?? 0;
          emit(OTATriggered(taskId: taskId));
          _startProgressPoll(event.sn, taskId: taskId, immediate: false);
        },
      );
    } catch (e) {
      emit(OTAError(message: e.toString()));
    } finally {
      _commandRequestInFlight = false;
    }
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
