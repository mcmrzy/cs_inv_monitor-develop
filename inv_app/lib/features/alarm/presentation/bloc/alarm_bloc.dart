import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/alarm/domain/repositories/alarm_repository.dart';

part 'alarm_event.dart';
part 'alarm_state.dart';

class AlarmBloc extends Bloc<AlarmEvent, AlarmState> {
  final AlarmRepository repository;

  AlarmBloc({required this.repository}) : super(AlarmInitial()) {
    on<AlarmListRequested>(_onListRequested);
    on<AlarmDetailRequested>(_onDetailRequested);
    on<AlarmMarkReadRequested>(_onMarkReadRequested);
  }

  Future<void> _onListRequested(
    AlarmListRequested event,
    Emitter<AlarmState> emit,
  ) async {
    final result = await repository.getList(
      stationId: event.stationId,
      status: event.status,
      page: event.page,
      pageSize: event.pageSize,
    );
    result.fold(
      (failure) {
        if (state is AlarmListLoaded) return;
        emit(AlarmError(message: failure.message));
      },
      (data) {
        final alarms = (data['list'] as List?) ?? [];
        final total = (data['total'] as int?) ?? 0;
        emit(AlarmListLoaded(alarms: alarms, total: total));
      },
    );
  }

  Future<void> _onDetailRequested(
    AlarmDetailRequested event,
    Emitter<AlarmState> emit,
  ) async {
    final result = await repository.getDetail(event.alarmId);
    result.fold(
      (failure) {
        if (state is AlarmDetailLoaded) return;
        emit(AlarmError(message: failure.message));
      },
      (alarm) => emit(AlarmDetailLoaded(alarm: alarm)),
    );
  }

  Future<void> _onMarkReadRequested(
    AlarmMarkReadRequested event,
    Emitter<AlarmState> emit,
  ) async {
    emit(AlarmLoading());
    final result = await repository.markRead(event.alarmIds);
    result.fold(
      (failure) => emit(AlarmError(message: failure.message)),
      (_) => emit(AlarmMarkReadSuccess()),
    );
  }
}
