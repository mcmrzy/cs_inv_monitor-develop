import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';

part 'ota_event.dart';
part 'ota_state.dart';

class OtaBloc extends Bloc<OtaEvent, OtaState> {
  final OtaRepository repository;
  Timer? _progressTimer;

  OtaBloc({required this.repository}) : super(OTAInitial()) {
    on<OTACheckRequested>(_onCheckRequested);
    on<OTATriggerRequested>(_onTriggerRequested);
    on<OTAPackageTriggerRequested>(_onPackageTriggerRequested);
    on<OTAProgressPollRequested>(_onProgressPollRequested);
    on<OTAProgressStopPoll>(_onProgressStopPoll);
    on<OTAFirmwareListRequested>(_onFirmwareListRequested);
    on<OTAFirmwareInstallRequested>(_onFirmwareInstallRequested);
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
    final result = await repository.triggerOTA(event.sn, event.firmwareId);
    result.fold(
      (failure) {
        if (state is OTAUpdateAvailable || state is OTAUpToDate || state is OTATriggered) return;
        emit(OTAError(message: failure.message));
      },
      (data) {
        emit(OTATriggered(taskId: 0));
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
    // 先调用 resend API 确保升级命令被发送到设备
    await repository.resendUpgradeCommand(event.sn);
    emit(OTATriggered(taskId: 0));
    _startProgressPoll(event.sn);
  }

  void _startProgressPoll(String deviceSn) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      add(OTAProgressPollRequested(deviceSn: deviceSn));
    });
  }

  Future<void> _onProgressPollRequested(
    OTAProgressPollRequested event,
    Emitter<OtaState> emit,
  ) async {
    final result = await repository.getDeviceOTAStatus(event.deviceSn);
    result.fold(
      (failure) {
        _progressTimer?.cancel();
        emit(OTAError(message: failure.message));
      },
      (data) {
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
        emit(OTAProgress(progress: progress, status: status, detail: data));
        if (status == 'completed' || status == 'success' || status == 'failed') {
          _progressTimer?.cancel();
          if (status == 'completed' || status == 'success') {
            emit(OTAComplete());
          } else {
            emit(OTAError(message: data['error_message'] as String? ?? 'Upgrade failed'));
          }
        }
      },
    );
  }

  Future<void> _onProgressStopPoll(
    OTAProgressStopPoll event,
    Emitter<OtaState> emit,
  ) async {
    _progressTimer?.cancel();
    emit(OTAInitial());
  }

  Future<void> _onFirmwareListRequested(
    OTAFirmwareListRequested event,
    Emitter<OtaState> emit,
  ) async {
    emit(OTAFirmwareListLoading());
    final result = await repository.listUpgradePackages(model: event.deviceModel);
    result.fold(
      (failure) => emit(OTAFirmwareListError(message: failure.message)),
      (packages) => emit(OTAFirmwareListLoaded(packages: packages)),
    );
  }

  Future<void> _onFirmwareInstallRequested(
    OTAFirmwareInstallRequested event,
    Emitter<OtaState> emit,
  ) async {
    emit(OTAFirmwareInstalling(packageId: event.packageId));
    final result = await repository.installPackage(event.sn, event.packageId);
    result.fold(
      (failure) => emit(OTAError(message: failure.message)),
      (_) {
        emit(OTATriggered(taskId: 0));
        _startProgressPoll(event.sn);
      },
    );
  }

  @override
  Future<void> close() {
    _progressTimer?.cancel();
    return super.close();
  }
}
