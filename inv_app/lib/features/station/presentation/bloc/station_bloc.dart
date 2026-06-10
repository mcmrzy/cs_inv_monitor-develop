import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';

part 'station_event.dart';
part 'station_state.dart';

class StationBloc extends Bloc<StationEvent, StationState> {
  final StationRepository repository;
  final StorageService? storageService;
  final DataCacheService? dataCacheService;

  StationBloc({required this.repository, this.storageService, this.dataCacheService}) : super(StationInitial()) {
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
    final result = await repository.getSummary();
    result.fold(
      (failure) {
        // 失败时尝试从缓存加载
        if (dataCacheService != null) {
          final cached = dataCacheService!.load(DataCacheService.stationSummary);
          if (cached != null && cached is Map<String, dynamic>) {
            final stations = (cached['stations'] as List?) ?? [];
            final summary = (cached['summary'] as Map<String, dynamic>?) ?? {};
            emit(StationSummaryLoaded(stations: stations, summary: summary, isFromCache: true));
            return;
          }
        }
        if (state is! StationSummaryLoaded) {
          emit(StationError(message: failure.message));
        }
      },
      (data) {
        final stations = (data['stations'] as List?) ?? [];
        final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        // 成功时保存到缓存
        dataCacheService?.save(DataCacheService.stationSummary, data);
        emit(StationSummaryLoaded(stations: stations, summary: summary));
      },
    );
  }

  Future<void> _onListRequested(
    StationListRequested event,
    Emitter<StationState> emit,
  ) async {
    if (state is! StationListLoaded) {
      emit(StationLoading());
    }
    final result = await repository.getList(page: event.page, pageSize: event.pageSize);
    result.fold(
      (failure) {
        if (state is! StationListLoaded) {
          emit(StationError(message: failure.message));
        }
      },
      (data) {
        final stations = (data['items'] as List?) ?? (data['list'] as List?) ?? [];
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
      (failure) {
        // 失败时尝试从缓存加载
        if (dataCacheService != null) {
          final cached = dataCacheService!.load(DataCacheService.stationDetail(event.stationId));
          if (cached != null && cached is Map<String, dynamic>) {
            final station = cached['station'];
            final devices = (cached['devices'] as List?) ?? [];
            emit(StationDetailLoaded(stationId: event.stationId, station: station, devices: devices, isFromCache: true));
            return;
          }
        }
        emit(StationError(message: failure.message));
      },
      (data) {
        final station = data['station'];
        final devices = (data['devices'] as List?) ?? [];
        dataCacheService?.save(DataCacheService.stationDetail(event.stationId), data);
        emit(StationDetailLoaded(stationId: event.stationId, station: station, devices: devices));
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
      (_) {
        emit(StationCreateSuccess());
        add(StationSummaryRequested());
      },
    );
  }

  Future<void> _onUpdateRequested(
    StationUpdateRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.update(event.stationId, event.data);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(StationUpdateSuccess());
        add(StationSummaryRequested());
      },
    );
  }

  Future<void> _onDeleteRequested(
    StationDeleteRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.delete(event.stationId);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(StationDeleteSuccess());
        add(StationSummaryRequested());
      },
    );
  }
}
