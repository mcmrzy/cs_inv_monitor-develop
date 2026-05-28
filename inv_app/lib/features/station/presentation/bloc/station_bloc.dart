import 'package:equatable/equatable.dart';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/core/services/storage_service.dart';

part 'station_event.dart';
part 'station_state.dart';

class StationBloc extends Bloc<StationEvent, StationState> {
  final StationRepository repository;
  final StorageService? storageService;

  StationBloc({required this.repository, this.storageService}) : super(StationInitial()) {
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
    if (storageService != null) {
      final cached = await storageService!.getStationCache();
      if (cached != null) {
        try {
          final cachedData = jsonDecode(cached) as Map<String, dynamic>;
          final cacheVersion = (cachedData['_cache_version'] as int?) ?? 0;
          final stations = (cachedData['stations'] as List?) ?? [];
          final summary = (cachedData['summary'] as Map<String, dynamic>?) ?? {};
          if (stations.isNotEmpty && cacheVersion >= 2) {
            emit(StationSummaryLoaded(stations: stations, summary: summary));
          }
        } catch (_) {}
      }
    }

    final result = await repository.getSummary();
    result.fold(
      (failure) {
        if (state is! StationSummaryLoaded) {
          emit(StationError(message: failure.message));
        }
      },
      (data) {
        final stations = (data['stations'] as List?) ?? [];
        final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        emit(StationSummaryLoaded(stations: stations, summary: summary));
        if (storageService != null) {
          storageService!.saveStationCache(jsonEncode({
            '_cache_version': 2,
            'stations': stations,
            'summary': summary,
          }));
        }
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
