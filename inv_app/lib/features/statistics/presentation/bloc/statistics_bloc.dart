import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/statistics/domain/repositories/statistics_repository.dart';

part 'statistics_event.dart';
part 'statistics_state.dart';

class StatisticsBloc extends Bloc<StatisticsEvent, StatisticsState> {
  final StatisticsRepository repository;

  StatisticsBloc({required this.repository}) : super(StatisticsInitial()) {
    on<StatisticsOverviewRequested>(_onOverviewRequested);
    on<StatisticsDetailRequested>(_onDetailRequested);
  }

  Future<void> _onOverviewRequested(
    StatisticsOverviewRequested event,
    Emitter<StatisticsState> emit,
  ) async {
    final result = await repository.getOverview();
    result.fold(
      (failure) {
        if (state is StatisticsOverviewLoaded) return;
        emit(StatisticsError(message: failure.message));
      },
      (data) => emit(StatisticsOverviewLoaded(overview: data)),
    );
  }

  Future<void> _onDetailRequested(
    StatisticsDetailRequested event,
    Emitter<StatisticsState> emit,
  ) async {
    emit(StatisticsLoading());
    if (event.deviceSN != null) {
      final result = await repository.getDeviceStatistics(
        event.deviceSN!,
        event.startDate,
        event.endDate,
        event.period,
      );
      result.fold(
        (failure) => emit(StatisticsError(message: failure.message)),
        (data) => emit(StatisticsDetailLoaded(data: data)),
      );
    } else if (event.stationId != null) {
      final result = await repository.getStationStatistics(
        event.stationId!,
        event.startDate,
        event.endDate,
        event.period,
      );
      result.fold(
        (failure) => emit(StatisticsError(message: failure.message)),
        (data) => emit(StatisticsDetailLoaded(data: data)),
      );
    } else {
      emit(StatisticsError(message: '请选择电站或设备'));
    }
  }
}
