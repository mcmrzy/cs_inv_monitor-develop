import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';

part 'station_event.dart';
part 'station_state.dart';

class StationBloc extends Bloc<StationEvent, StationState> {
  final StationRepository repository;

  StationBloc({required this.repository}) : super(StationInitial()) {
    on<StationSummaryRequested>(_onSummaryRequested);
    on<StationListRequested>(_onListRequested);
    on<StationDetailRequested>(_onDetailRequested);
    on<StationCreateRequested>(_onCreateRequested);
    on<StationUpdateRequested>(_onUpdateRequested);
    on<StationDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onSummaryRequested(
    StationSummaryRequested event,
    Emitter<StationState> emit,
  ) async {
    emit(StationLoading());
    final result = await repository.getSummary();
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (data) {
        final stations = (data['stations'] as List?) ?? [];
        final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        emit(StationSummaryLoaded(stations: stations, summary: summary));
      },
    );
  }

  Future<void> _onListRequested(
    StationListRequested event,
    Emitter<StationState> emit,
  ) async {
    emit(StationLoading());
    final result = await repository.getList(page: event.page, pageSize: event.pageSize);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (data) {
        final stations = (data['list'] as List?) ?? [];
        final total = (data['total'] as int?) ?? 0;
        emit(StationListLoaded(stations: stations, total: total));
      },
    );
  }

  Future<void> _onDetailRequested(
    StationDetailRequested event,
    Emitter<StationState> emit,
  ) async {
    emit(StationLoading());
    final result = await repository.getDetail(event.stationId);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (data) {
        final station = data['station'];
        final devices = (data['devices'] as List?) ?? [];
        emit(StationDetailLoaded(station: station, devices: devices));
      },
    );
  }

  Future<void> _onCreateRequested(
    StationCreateRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.create(event.data);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) => emit(StationCreateSuccess()),
    );
  }

  Future<void> _onUpdateRequested(
    StationUpdateRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.update(event.stationId, event.data);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) => emit(StationUpdateSuccess()),
    );
  }

  Future<void> _onDeleteRequested(
    StationDeleteRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.delete(event.stationId);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) => emit(StationDeleteSuccess()),
    );
  }
}
