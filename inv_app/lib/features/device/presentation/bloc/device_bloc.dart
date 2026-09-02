import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/inverter_connection_monitor.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/utils/offline_log_id.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';

part 'device_event.dart';
part 'device_state.dart';

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final DeviceRepository repository;
  final RealtimeDataService realtimeDataService; // 用于远程实时数据
  final LocalCommunicationService? localCommunicationService;
  final ConnectionModeService? connectionModeService;
  final DataCacheService? dataCacheService;
  final BleDeviceKeyStore? bleKeyStore;
  final OfflineOpLogStore? offlineLogStore;
  final LocalCacheDatabase? localCache;
  StreamSubscription<InverterRealtime>? _mqttSub;
  String? _activeSN;
  Timer? _localPollTimer;
  String? _localPollIP;
  int? _localPollInFlightGeneration;
  int _localPollGeneration = 0;
  final InverterConnectionMonitor _connectionMonitor =
      InverterConnectionMonitor();

  DeviceBloc({
    required this.repository,
    required this.realtimeDataService,
    this.localCommunicationService,
    this.connectionModeService,
    this.dataCacheService,
    this.bleKeyStore,
    this.offlineLogStore,
    this.localCache,
  }) : super(DeviceInitial()) {
    on<DeviceListRequested>(_onListRequested);
    on<DeviceDetailRequested>(_onDetailRequested);
    on<DeviceRealtimeWSUpdate>(_onMQTTUpdate);
    on<DeviceControlRequested>(_onControlRequested);
    on<DeviceParamsUpdateRequested>(_onParamsUpdateRequested);
    on<DeviceBindRequested>(_onBindRequested);
    on<DeviceUnbindRequested>(_onUnbindRequested);
    on<DeviceUpdateRequested>(_onUpdateRequested);
    on<DeviceGlobalReorderRequested>(_onGlobalReorderRequested);
    on<DeviceUnsubscribeRealtime>(_onUnsubscribeRealtime);
    on<DeviceHistoryRequested>(_onHistoryRequested);
    on<DeviceStartLocalPoll>(_onStartLocalPoll);
    on<DeviceStopLocalPoll>(_onStopLocalPoll);
    on<DeviceLocalRealtimeUpdate>(_onLocalRealtimeUpdate);
    on<DeviceLocalParamsRequested>(_onLocalParamsRequested);
    on<DeviceLocalParamsUpdateRequested>(_onLocalParamsUpdateRequested);
    on<DeviceAutoDisconnected>(_onAutoDisconnected);
  }

  @override
  Future<void> close() {
    _localPollGeneration++;
    _mqttSub?.cancel();
    _localPollTimer?.cancel();
    _connectionMonitor.dispose();
    if (_activeSN != null) {
      realtimeDataService.stopPolling(_activeSN!);
    }
    return super.close();
  }

  Future<void> _onListRequested(
    DeviceListRequested event,
    Emitter<DeviceState> emit,
  ) async {
    // 本地离网模式：直接读设备快照库（需求 6，不等待网络超时）
    if (connectionModeService?.isLocal ?? false) {
      try {
        final rows =
            await localCache?.loadDevices() ?? const <Map<String, dynamic>>[];
        final devices = rows.map<Map<String, dynamic>>((r) {
          return <String, dynamic>{
            'sn': r['sn'],
            'name': r['name'],
            'device_model': r['model'],
            'firmware_arm': r['firmware_arm'],
            'firmware_esp': r['firmware_esp'],
            'station_id': r['station_id'],
            'status': r['status'],
          };
        }).toList();
        debugPrint(
          '[DeviceBloc] local mode: ${devices.length} devices snapshot',
        );
        emit(
          DeviceListLoaded(
            devices: devices,
            total: devices.length,
            isFromCache: true,
          ),
        );
        return;
      } catch (e) {
        debugPrint('[DeviceBloc] local device snapshot load failed: $e');
      }
    }

    // 如果已有数据，不显示loading（静默刷新）
    if (state is! DeviceListLoaded) {
      emit(DeviceLoading());
    }
    final result = await repository.getList(
      stationId: event.stationId,
      status: event.status,
      page: event.page,
      pageSize: event.pageSize,
    );
    result.fold(
      (failure) {
        // 如果已有数据，忽略错误
        if (failure is NetworkFailure && state is! DeviceListLoaded) {
          // 尝试从缓存加载
          if (dataCacheService != null) {
            final cacheKey = event.stationId != null
                ? '${DataCacheService.deviceList}_${event.stationId}'
                : DataCacheService.deviceList;
            final cached = dataCacheService!.load(cacheKey);
            if (cached != null && cached is Map<String, dynamic>) {
              final devices =
                  (cached['items'] as List?) ?? (cached['list'] as List?) ?? [];
              final total = (cached['total'] as int?) ?? 0;
              // 只有网络连接失败时才标记为缓存数据
              emit(
                DeviceListLoaded(
                  devices: devices,
                  total: total,
                  isFromCache: true,
                ),
              );
              return;
            }
          }
        }
        emit(DeviceError(message: failure.message));
      },
      (data) {
        final devices =
            (data['items'] as List?) ?? (data['list'] as List?) ?? [];
        final total = (data['total'] as int?) ?? 0;
        // 保存到缓存
        if (dataCacheService != null) {
          final cacheKey = event.stationId != null
              ? '${DataCacheService.deviceList}_${event.stationId}'
              : DataCacheService.deviceList;
          dataCacheService!.save(cacheKey, data);
        }
        // 设备快照入库（支撑离网模式设备列表渲染，失败静默）
        unawaited(_saveDeviceSnapshot(devices));
        emit(DeviceListLoaded(devices: devices, total: total));
      },
    );
  }

  /// 将云端设备列表写入本地快照库（离网模式数据源）
  Future<void> _saveDeviceSnapshot(List<dynamic> devices) async {
    try {
      await localCache?.upsertDevices(
        devices.whereType<Map<String, dynamic>>().toList(),
      );
    } catch (e) {
      debugPrint('[DeviceBloc] upsert device snapshot failed: $e');
    }
  }

  Future<void> _onDetailRequested(
    DeviceDetailRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.getDetail(event.sn);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (data) {
        final device = data['device'];
        emit(DeviceDetailLoaded(device: device, realtimeData: null));

        _startMQTTRealtime(event.sn);
      },
    );
  }

  Future<void> _startMQTTRealtime(String sn) async {
    _mqttSub?.cancel();
    _mqttSub = null;

    // 停止之前的设备轮询
    if (_activeSN != null) {
      realtimeDataService.stopPolling(_activeSN!);
    }
    _activeSN = sn;

    // 使用 API 轮询替代 MQTT 直连
    _mqttSub = realtimeDataService.realtimeDataStream.listen((rt) {
      if (!isClosed && sn == rt.deviceSN) {
        add(DeviceRealtimeWSUpdate(rt));
      }
    });

    // 启动 API 轮询（每 3 秒）
    realtimeDataService.startPolling(sn);
  }

  void _onMQTTUpdate(
    DeviceRealtimeWSUpdate event,
    Emitter<DeviceState> emit,
  ) {
    final currentState = state;
    if (currentState is DeviceDetailLoaded) {
      emit(
        DeviceDetailLoaded(
          device: currentState.device,
          realtimeData: event.data,
        ),
      );
    }
  }

  Future<void> _onControlRequested(
    DeviceControlRequested event,
    Emitter<DeviceState> emit,
  ) async {
    final isLocal = connectionModeService != null &&
        await connectionModeService!.isLocalMode();

    if (isLocal && localCommunicationService != null && _localPollIP != null) {
      try {
        await localCommunicationService!.connect(_localPollIP!);
        await localCommunicationService!
            .sendCommand(event.cmdType, event.params);
        // 记录操作日志（op-log 路线：仅记录不重放，
        // 避免联网后控制命令被二次下发）
        await _recordOfflineOpLog(
          sn: event.sn,
          action: 'control',
          params: {'cmd_type': event.cmdType, 'params': event.params},
          result: 'ok',
        );
        emit(const DeviceControlSuccess(message: 'Command sent'));
      } catch (e) {
        await _recordOfflineOpLog(
          sn: event.sn,
          action: 'control',
          params: {'cmd_type': event.cmdType, 'params': event.params},
          result: 'failed',
        );
        emit(DeviceError(message: e.toString()));
      }
      return;
    }

    emit(DeviceLoading());
    final result =
        await repository.control(event.sn, event.cmdType, event.params);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(const DeviceControlSuccess(message: 'Command sent')),
    );
  }

  Future<void> _onParamsUpdateRequested(
    DeviceParamsUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: 'Local service unavailable'));
      return;
    }
    try {
      if (_localPollIP != null) {
        await localCommunicationService!.connect(_localPollIP!);
      }
      await localCommunicationService!.updateParams(event.params);
      // 记录操作日志（op-log 路线：仅记录不重放）
      await _recordOfflineOpLog(
        sn: event.sn,
        action: 'param_update',
        params: event.params,
        result: 'ok',
      );
      emit(DeviceParamsUpdateSuccess());
    } catch (e) {
      await _recordOfflineOpLog(
        sn: event.sn,
        action: 'param_update',
        params: event.params,
        result: 'failed',
      );
      emit(DeviceError(message: e.toString()));
    }
  }

  Future<void> _onBindRequested(
    DeviceBindRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.bind(event.sn, event.stationId, pin: event.pin);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(DeviceBindSuccess()),
    );
  }

  Future<void> _onUnbindRequested(
    DeviceUnbindRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.unbind(event.sn);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) async {
        // 解绑副作用：清本地 BLE 凭证 + 记录解绑操作日志（本地完成，失败不影响解绑结果）
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
          // 联动删除本地快照，避免离网模式展示已解绑的设备
          await localCache?.deleteDevice(event.sn);
        } catch (_) {
          // 本地副作用失败不阻塞解绑结果
        }
        emit(DeviceUnbindSuccess());
      },
    );
  }

  Future<void> _onUpdateRequested(
    DeviceUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    final result = await repository.updateDevice(
      event.sn,
      alias: event.alias,
      remark: event.remark,
    );
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(DeviceUpdateSuccess(sn: event.sn)),
    );
  }

  Future<void> _onGlobalReorderRequested(
    DeviceGlobalReorderRequested event,
    Emitter<DeviceState> emit,
  ) async {
    final result = await repository.reorderDevicesGlobal(event.deviceOrder);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(DeviceGlobalReorderSuccess()),
    );
  }

  void _onUnsubscribeRealtime(
    DeviceUnsubscribeRealtime event,
    Emitter<DeviceState> emit,
  ) {
    _mqttSub?.cancel();
    _mqttSub = null;
    if (_activeSN != null) {
      realtimeDataService.stopPolling(_activeSN!);
      _activeSN = null;
    }
  }

  Future<void> _onHistoryRequested(
    DeviceHistoryRequested event,
    Emitter<DeviceState> emit,
  ) async {
    final result = await repository.getHistory(
      event.sn,
      event.startDate,
      event.endDate,
      event.period,
    );
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (data) {
        final points = data.map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) {
            return e;
          }
          return <String, dynamic>{};
        }).toList();
        emit(
          DeviceHistoryLoaded(
            data: points,
            period: event.period,
            metric: event.metric,
          ),
        );
      },
    );
  }

  void _onStartLocalPoll(
    DeviceStartLocalPoll event,
    Emitter<DeviceState> emit,
  ) {
    if (isClosed) return;
    _localPollTimer?.cancel();
    _localPollIP = event.deviceIP;
    final generation = ++_localPollGeneration;

    // 启动逆变器连接监控：30秒后检测通信应答，持续无响应则自动断开热点
    _connectionMonitor.start(
      onAutoDisconnected: () {
        if (!isClosed && generation == _localPollGeneration) {
          add(const DeviceAutoDisconnected());
        }
      },
    );

    _localPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (localCommunicationService == null ||
          _localPollInFlightGeneration == generation ||
          !_isCurrentLocalPoll(generation)) {
        return;
      }
      _localPollInFlightGeneration = generation;
      try {
        await localCommunicationService!.connect(event.deviceIP);
        if (!_isCurrentLocalPoll(generation)) return;
        final rawData = await localCommunicationService!.getRealtimeData();
        if (!_isCurrentLocalPoll(generation)) return;
        final realtime = InverterRealtime.fromJson(rawData);
        // 轮询成功：喂给监控器作为通信应答正常的信号
        _connectionMonitor.feedRealtime(realtime);
        add(DeviceLocalRealtimeUpdate(realtime));
      } catch (_) {
        // 轮询失败：喂失败信号，设备真正无响应时由监控器累计并自动断开
        if (_isCurrentLocalPoll(generation)) {
          _connectionMonitor.feedFailure();
        }
      } finally {
        if (_localPollInFlightGeneration == generation) {
          _localPollInFlightGeneration = null;
        }
      }
    });
  }

  bool _isCurrentLocalPoll(int generation) =>
      !isClosed &&
      generation == _localPollGeneration &&
      (_localPollTimer?.isActive ?? false);

  void _onStopLocalPoll(
    DeviceStopLocalPoll event,
    Emitter<DeviceState> emit,
  ) {
    _localPollGeneration++;
    _localPollTimer?.cancel();
    _localPollTimer = null;
    _localPollIP = null;
    _connectionMonitor.stop();
  }

  void _onLocalRealtimeUpdate(
    DeviceLocalRealtimeUpdate event,
    Emitter<DeviceState> emit,
  ) {
    final currentState = state;
    if (currentState is DeviceDetailLoaded) {
      emit(
        DeviceDetailLoaded(
          device: currentState.device,
          realtimeData: event.data,
        ),
      );
    }
  }

  void _onAutoDisconnected(
    DeviceAutoDisconnected event,
    Emitter<DeviceState> emit,
  ) {
    // 停止本地轮询和监控
    _localPollGeneration++;
    _localPollTimer?.cancel();
    _localPollTimer = null;
    _localPollIP = null;
    _connectionMonitor.stop();

    // 切换回远程模式（系统兜底切换：不置手动锁，保留断网自动切本地的能力）
    connectionModeService?.switchToRemote(byUser: false);
    localCommunicationService?.disconnect();

    emit(
      const DeviceLocalDisconnected(
        reason: 'inverter_no_response',
      ),
    );
  }

  Future<void> _onLocalParamsRequested(
    DeviceLocalParamsRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: 'Local service unavailable'));
      return;
    }
    emit(DeviceLoading());
    try {
      await localCommunicationService!.connect(event.deviceIP);
      final params = await localCommunicationService!.getParams();
      emit(DeviceParamsLoaded(params: params));
    } catch (e) {
      emit(DeviceError(message: e.toString()));
    }
  }

  /// 记录本地直连操作日志（op-log 路线：UUID 幂等，
  /// 联网后由 OfflineLogSyncService 上报）。
  /// 仅记录不重放：控制/参数命令已直发设备，
  /// 不会在联网后经云端再次下发（避免双重执行）
  Future<void> _recordOfflineOpLog({
    required String sn,
    required String action,
    required Map<String, dynamic> params,
    required String result,
  }) async {
    try {
      final logStore = offlineLogStore ?? getIt<OfflineOpLogStore>();
      await logStore.add(
        OfflineOpLog(
          logId: newOfflineLogId(),
          deviceSn: sn,
          action: action,
          params: params,
          result: result,
          channel: 'wifi_ap',
          opTime: DateTime.now(),
        ),
      );
    } catch (_) {
      // 日志记录失败不影响操作本身
    }
  }

  Future<void> _onLocalParamsUpdateRequested(
    DeviceLocalParamsUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: 'Local service unavailable'));
      return;
    }
    try {
      await localCommunicationService!.connect(event.deviceIP);
      await localCommunicationService!.updateParams(event.params);
      // 记录操作日志（op-log 路线：仅记录不重放）
      if (_activeSN != null) {
        await _recordOfflineOpLog(
          sn: _activeSN!,
          action: 'param_update',
          params: event.params,
          result: 'ok',
        );
      }
      emit(DeviceParamsUpdateSuccess());
    } catch (e) {
      if (_activeSN != null) {
        await _recordOfflineOpLog(
          sn: _activeSN!,
          action: 'param_update',
          params: event.params,
          result: 'failed',
        );
      }
      emit(DeviceError(message: e.toString()));
    }
  }
}
