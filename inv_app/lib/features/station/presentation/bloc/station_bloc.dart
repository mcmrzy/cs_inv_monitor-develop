import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/core/utils/offline_log_id.dart';

part 'station_event.dart';
part 'station_state.dart';

class StationBloc extends Bloc<StationEvent, StationState> {
  final StationRepository repository;
  final StorageService? storageService;
  final DataCacheService? dataCacheService;
  final BleDeviceKeyStore? bleKeyStore;
  final OfflineOpLogStore? offlineLogStore;
  final ConnectionModeService? connectionModeService;
  final LocalCacheDatabase? localCache;

  StationBloc({
    required this.repository,
    this.storageService,
    this.dataCacheService,
    this.bleKeyStore,
    this.offlineLogStore,
    this.connectionModeService,
    this.localCache,
  }) : super(StationInitial()) {
    on<StationSummaryRequested>(_onSummaryRequested);
    on<StationListRequested>(_onListRequested);
    on<StationDetailRequested>(_onDetailRequested);
    on<StationCreateRequested>(_onCreateRequested);
    on<StationUpdateRequested>(_onUpdateRequested);
    on<StationDeleteRequested>(_onDeleteRequested);
    on<DeviceUnbindRequested>(_onDeviceUnbindRequested);
    on<DeviceRebindRequested>(_onDeviceRebindRequested);
    on<DeviceBindRequested>(_onDeviceBindRequested);
    on<DeviceDeleteRequested>(_onDeleteDeviceRequested);
    on<DeviceReorderRequested>(_onDeviceReorderRequested);
    on<StationReorderRequested>(_onStationReorderRequested);
  }

  /// 快速检查是否有网络连接（带连续确认，启动瞬间不误判离线）
  Future<bool> _hasNetwork() async {
    try {
      return await getIt<NetworkStatusService>().checkConnectivity();
    } catch (_) {
      return true; // 检查失败时假定有网络
    }
  }

  Future<void> _onSummaryRequested(
    StationSummaryRequested event,
    Emitter<StationState> emit,
  ) async {
    // 本地离网模式：直接读快照库渲染主界面（需求 6，不等待网络、不复制页面）
    if (connectionModeService?.isLocal ?? false) {
      try {
        final rows =
            await localCache?.loadStations() ?? const <Map<String, dynamic>>[];
        final stations = rows.map<Map<String, dynamic>>((r) {
          return <String, dynamic>{
            'id': int.tryParse('${r['id']}'),
            'name': r['name'],
            'address': r['address'],
            'capacity': r['capacity'],
            'status': r['status'],
            'device_count': r['device_count'],
          };
        }).toList();
        final totalDevices = rows.fold<int>(
          0,
          (sum, r) => sum + ((r['device_count'] as int?) ?? 0),
        );
        final summary = <String, dynamic>{
          'totalStations': rows.length,
          'totalDevices': totalDevices,
          'onlineDevices': 0,
          'todayGeneration': 0.0,
          'monthGeneration': 0.0,
          'totalGeneration': 0.0,
          'totalIncome': 0.0,
        };
        debugPrint(
          '[StationBloc] local mode: ${rows.length} stations snapshot',
        );
        emit(
          StationSummaryLoaded(
            stations: stations,
            summary: summary,
            isFromCache: true,
          ),
        );
        return;
      } catch (e) {
        debugPrint('[StationBloc] local snapshot load failed: $e');
      }
    }

    // 断网时直接加载缓存，不等待 30s 超时
    if (!await _hasNetwork()) {
      if (dataCacheService != null) {
        final cached = dataCacheService!.load(DataCacheService.stationSummary);
        if (cached != null && cached is Map<String, dynamic>) {
          final stations = (cached['stations'] as List?) ?? [];
          final summary = (cached['summary'] as Map<String, dynamic>?) ?? {};
          emit(
            StationSummaryLoaded(
              stations: stations,
              summary: summary,
              isFromCache: true,
            ),
          );
          return;
        }
      }
    }

    final result = await repository.getSummary();
    result.fold(
      (failure) {
        // 失败时尝试从缓存加载
        if (failure is NetworkFailure && dataCacheService != null) {
          final cached =
              dataCacheService!.load(DataCacheService.stationSummary);
          if (cached != null && cached is Map<String, dynamic>) {
            final stations = (cached['stations'] as List?) ?? [];
            final summary = (cached['summary'] as Map<String, dynamic>?) ?? {};
            // 只有网络连接失败时才标记为缓存数据，其他错误（服务器错误等）静默使用缓存
            emit(
              StationSummaryLoaded(
                stations: stations,
                summary: summary,
                isFromCache: true,
              ),
            );
            return;
          }
        }
        emit(StationError(message: failure.message));
      },
      (data) {
        final stations = (data['stations'] as List?) ?? [];
        final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
        // 成功时保存到缓存
        dataCacheService?.save(DataCacheService.stationSummary, data);
        // 电站快照入库（支撑离网模式快照渲染，失败静默）
        unawaited(_saveStationSnapshot(stations));
        emit(StationSummaryLoaded(stations: stations, summary: summary));
      },
    );
  }

  /// 将云端电站列表写入本地快照库（离网模式数据源）
  Future<void> _saveStationSnapshot(List<dynamic> stations) async {
    try {
      await localCache?.upsertStations(
        stations.whereType<Map<String, dynamic>>().toList(),
      );
    } catch (e) {
      debugPrint('[StationBloc] upsert station snapshot failed: $e');
    }
  }

  Future<void> _onListRequested(
    StationListRequested event,
    Emitter<StationState> emit,
  ) async {
    if (state is! StationListLoaded) {
      emit(StationLoading());
    }
    final result =
        await repository.getList(page: event.page, pageSize: event.pageSize);
    result.fold(
      (failure) {
        if (state is! StationListLoaded) {
          emit(StationError(message: failure.message));
        }
      },
      (data) {
        final stations =
            (data['items'] as List?) ?? (data['list'] as List?) ?? [];
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

    // 断网时直接加载缓存
    if (!await _hasNetwork()) {
      if (dataCacheService != null) {
        final cached = dataCacheService!
            .load(DataCacheService.stationDetail(event.stationId));
        if (cached != null && cached is Map<String, dynamic>) {
          final station = cached['station'];
          final devices = (cached['devices'] as List?) ?? [];
          emit(
            StationDetailLoaded(
              stationId: event.stationId,
              station: station,
              devices: devices,
              isFromCache: true,
            ),
          );
          return;
        }
      }
    }

    final result = await repository.getDetail(event.stationId);
    result.fold(
      (failure) {
        // 失败时尝试从缓存加载
        if (failure is NetworkFailure && dataCacheService != null) {
          final cached = dataCacheService!
              .load(DataCacheService.stationDetail(event.stationId));
          if (cached != null && cached is Map<String, dynamic>) {
            final station = cached['station'];
            final devices = (cached['devices'] as List?) ?? [];
            emit(
              StationDetailLoaded(
                stationId: event.stationId,
                station: station,
                devices: devices,
                isFromCache: true,
              ),
            );
            return;
          }
        }
        emit(StationError(message: failure.message));
      },
      (data) {
        final station = data['station'];
        final devices = (data['devices'] as List?) ?? [];
        dataCacheService?.save(
          DataCacheService.stationDetail(event.stationId),
          data,
        );
        emit(
          StationDetailLoaded(
            stationId: event.stationId,
            station: station,
            devices: devices,
          ),
        );
      },
    );
  }

  Future<void> _onCreateRequested(
    StationCreateRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.create(event.data);
    result.fold(
      (failure) => emit(
        StationActionError(
          message: failure.message,
          action: 'create',
          requestId: event.requestId,
        ),
      ),
      (_) {
        emit(StationCreateSuccess(requestId: event.requestId));
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
      (failure) => emit(
        StationActionError(
          message: failure.message,
          action: 'update',
          stationId: event.stationId,
          requestId: event.requestId,
        ),
      ),
      (_) {
        emit(
          StationUpdateSuccess(
            stationId: event.stationId,
            requestId: event.requestId,
          ),
        );
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
      (failure) => emit(
        StationActionError(
          message: failure.message,
          action: 'delete',
          stationId: event.stationId,
          requestId: event.requestId,
        ),
      ),
      (_) async {
        // 联动删除本地快照（含下属设备），避免离网模式展示已删除的电站
        try {
          await localCache?.deleteStation('${event.stationId}');
        } catch (_) {}
        emit(
          StationDeleteSuccess(
            stationId: event.stationId,
            requestId: event.requestId,
          ),
        );
        add(StationSummaryRequested());
      },
    );
  }

  Future<void> _onDeviceUnbindRequested(
    DeviceUnbindRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.unbindDevice(event.sn);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) async {
        // 解绑副作用：清本地 BLE 凭证 + 记录解绑操作日志 + 删本地快照
        // （本地完成，失败不影响解绑结果）
        try {
          final keyStore = bleKeyStore ?? getIt<BleDeviceKeyStore>();
          await keyStore.delete(event.sn);
          final logStore = offlineLogStore ?? getIt<OfflineOpLogStore>();
          await logStore.add(
            OfflineOpLog(
              logId: newOfflineLogId(),
              deviceSn: event.sn,
              action: 'unbind',
              channel: 'cloud',
              opTime: DateTime.now(),
            ),
          );
          await localCache?.deleteDevice(event.sn);
        } catch (_) {
          // 本地副作用失败不阻塞解绑结果
        }
        emit(DeviceUnbindSuccess(sn: event.sn));
      },
    );
  }

  Future<void> _onDeviceRebindRequested(
    DeviceRebindRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.rebindDevice(event.sn, event.newStationId);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(DeviceRebindSuccess(sn: event.sn));
      },
    );
  }

  Future<void> _onDeviceBindRequested(
    DeviceBindRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.bindDevice(event.sn, event.stationId);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(DeviceBindSuccess(sn: event.sn));
      },
    );
  }

  Future<void> _onDeleteDeviceRequested(
    DeviceDeleteRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.deleteDevice(event.sn);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) async {
        // 联动删除本地快照，避免离网模式展示已删除的设备
        try {
          await localCache?.deleteDevice(event.sn);
        } catch (_) {}
        emit(DeviceDeleteSuccess(sn: event.sn));
      },
    );
  }

  Future<void> _onDeviceReorderRequested(
    DeviceReorderRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.reorderDevices(event.stationId, event.deviceOrder);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(DeviceReorderSuccess(stationId: event.stationId));
      },
    );
  }

  Future<void> _onStationReorderRequested(
    StationReorderRequested event,
    Emitter<StationState> emit,
  ) async {
    final result = await repository.reorderStations(event.stationOrder);
    result.fold(
      (failure) => emit(StationError(message: failure.message)),
      (_) {
        emit(StationReorderSuccess());
      },
    );
  }
}
