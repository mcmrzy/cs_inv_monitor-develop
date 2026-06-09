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
    on<OTAProgressPollRequested>(_onProgressPollRequested);
    on<OTAHistoryRequested>(_onHistoryRequested);
    on<OTAFirmwareListRequested>(_onFirmwareListRequested);
    on<OTAProgressStopPoll>(_onProgressStopPoll);
  }

  Future<void> _onCheckRequested(
    OTACheckRequested event,
    Emitter<OtaState> emit,
  ) async {
    final result = await repository.checkUpdate(event.sn);
    result.fold(
      (failure) {
        if (state is OTAUpdateAvailable || state is OTAUpToDate || state is OTAFirmwareListLoaded) return;
        emit(OTAError(message: failure.message));
      },
      (data) {
        final hasUpdate = data['has_update'] == true;
        if (hasUpdate) {
          emit(OTAUpdateAvailable(info: data));
        } else {
          emit(OTAUpToDate());
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
        if (state is OTAUpdateAvailable || state is OTAUpToDate || state is OTAFirmwareListLoaded || state is OTATriggered) return;
        emit(OTAError(message: failure.message));
      },
      (data) {
        final taskId = data['task_id'];
        // task_id 可能是 int 或 String，统一转换为 int
        final taskIdInt = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? 0;
        emit(OTATriggered(taskId: taskIdInt));
        _startProgressPoll(taskIdInt);
      },
    );
  }

  void _startProgressPoll(int taskId) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      add(OTAProgressPollRequested(taskId: taskId));
    });
  }

  Future<void> _onProgressPollRequested(
    OTAProgressPollRequested event,
    Emitter<OtaState> emit,
  ) async {
    final result = await repository.getOTATaskProgress(event.taskId);
    result.fold(
      (failure) {
        _progressTimer?.cancel();
        emit(OTAError(message: failure.message));
      },
      (data) {
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
        emit(OTAProgress(progress: progress, status: status, detail: data));
        if (status == 'completed' || status == 'failed') {
          _progressTimer?.cancel();
          if (status == 'completed') {
            emit(OTAComplete());
          } else {
            emit(OTAError(message: data['error_message'] as String? ?? '升级失败'));
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

  Future<void> _onHistoryRequested(
    OTAHistoryRequested event,
    Emitter<OtaState> emit,
  ) async {
    emit(OTALoading());
    final result = await repository.getOTAHistory(event.sn, page: event.page);
    result.fold(
      (failure) => emit(OTAError(message: failure.message)),
      (data) => emit(OTAHistoryLoaded(history: data)),
    );
  }

  Future<void> _onFirmwareListRequested(
    OTAFirmwareListRequested event,
    Emitter<OtaState> emit,
  ) async {
    final result = await repository.getFirmwareList(page: event.page, pageSize: event.pageSize);
    result.fold(
      (failure) {
        if (state is OTAUpdateAvailable || state is OTAUpToDate || state is OTAFirmwareListLoaded) return;
        emit(OTAError(message: failure.message));
      },
      (data) => emit(OTAFirmwareListLoaded(firmwares: data)),
    );
  }

  @override
  Future<void> close() {
    _progressTimer?.cancel();
    return super.close();
  }
}
