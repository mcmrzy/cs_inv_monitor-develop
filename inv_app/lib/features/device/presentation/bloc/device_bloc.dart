import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/offline_cache_service.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/offline_action.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';

part 'device_event.dart';
part 'device_state.dart';

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final DeviceRepository repository;
  final MQTTService mqttService;
  final LocalCommunicationService? localCommunicationService;
  final ConnectionModeService? connectionModeService;
  final OfflineCacheService? offlineCacheService;
  StreamSubscription<InverterRealtime>? _mqttSub;
  String? _activeSN;
  Timer? _localPollTimer;
  String? _localPollIP;

  DeviceBloc({
    required this.repository,
    required this.mqttService,
    this.localCommunicationService,
    this.connectionModeService,
    this.offlineCacheService,
  }) : super(DeviceInitial()) {
    on<DeviceListRequested>(_onListRequested);
    on<DeviceDetailRequested>(_onDetailRequested);
    on<DeviceRealtimeWSUpdate>(_onMQTTUpdate);
    on<DeviceControlRequested>(_onControlRequested);
    on<DeviceParamsUpdateRequested>(_onParamsUpdateRequested);
    on<DeviceBindRequested>(_onBindRequested);
    on<DeviceUnbindRequested>(_onUnbindRequested);
    on<DeviceUnsubscribeRealtime>(_onUnsubscribeRealtime);
    on<DeviceHistoryRequested>(_onHistoryRequested);
    on<DeviceStartLocalPoll>(_onStartLocalPoll);
    on<DeviceStopLocalPoll>(_onStopLocalPoll);
    on<DeviceLocalRealtimeUpdate>(_onLocalRealtimeUpdate);
    on<DeviceLocalParamsRequested>(_onLocalParamsRequested);
    on<DeviceLocalParamsUpdateRequested>(_onLocalParamsUpdateRequested);
  }

  @override
  Future<void> close() {
    _mqttSub?.cancel();
    _localPollTimer?.cancel();
    if (_activeSN != null) {
      mqttService.unsubscribeDeviceTopics(_activeSN!);
    }
    return super.close();
  }

  Future<void> _onListRequested(
    DeviceListRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.getList(
      stationId: event.stationId,
      status: event.status,
      page: event.page,
      pageSize: event.pageSize,
    );
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (data) {
        final devices = (data['list'] as List?) ?? [];
        final total = (data['total'] as int?) ?? 0;
        emit(DeviceListLoaded(devices: devices, total: total));
      },
    );
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
    if (_activeSN != null && mqttService.isConnected) {
      mqttService.unsubscribeDeviceTopics(_activeSN!);
    }
    _activeSN = sn;

    _mqttSub = mqttService.realtimeDataStream.listen((rt) {
      if (!isClosed && sn == rt.deviceSN) {
        add(DeviceRealtimeWSUpdate(rt));
      }
    });

    if (!mqttService.isConnected) {
      try {
        await mqttService.waitForConnection(timeout: const Duration(seconds: 10));
      } catch (e) {
        return;
      }
    }

    mqttService.subscribeDeviceTopics(sn);
  }

  void _onMQTTUpdate(
    DeviceRealtimeWSUpdate event,
    Emitter<DeviceState> emit,
  ) {
    final currentState = state;
    if (currentState is DeviceDetailLoaded) {
      emit(DeviceDetailLoaded(device: currentState.device, realtimeData: event.data));
    }
  }

  Future<void> _onControlRequested(
    DeviceControlRequested event,
    Emitter<DeviceState> emit,
  ) async {
    final isLocal = connectionModeService != null && await connectionModeService!.isLocalMode();

    if (isLocal && localCommunicationService != null && _localPollIP != null) {
      try {
        await localCommunicationService!.connect(_localPollIP!);
        await localCommunicationService!.sendCommand(event.cmdType, event.params);
        if (offlineCacheService != null) {
          await offlineCacheService!.saveAction(OfflineAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: 'control',
            sn: event.sn,
            data: {'cmd_type': event.cmdType, 'params': event.params},
            timestamp: DateTime.now(),
          ));
        }
        emit(const DeviceControlSuccess(message: '命令已发送'));
      } catch (e) {
        if (offlineCacheService != null) {
          await offlineCacheService!.saveAction(OfflineAction(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: 'control',
            sn: event.sn,
            data: {'cmd_type': event.cmdType, 'params': event.params},
            timestamp: DateTime.now(),
          ));
        }
        emit(DeviceError(message: e.toString()));
      }
      return;
    }

    emit(DeviceLoading());
    final result = await repository.control(event.sn, event.cmdType, event.params);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(const DeviceControlSuccess(message: '命令已发送')),
    );
  }

  Future<void> _onParamsUpdateRequested(
    DeviceParamsUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: '本地通信服务不可用'));
      return;
    }
    try {
      if (_localPollIP != null) {
        await localCommunicationService!.connect(_localPollIP!);
      }
      await localCommunicationService!.updateParams(event.params);
      if (offlineCacheService != null) {
        await offlineCacheService!.saveAction(OfflineAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'param_update',
          sn: event.sn,
          data: event.params,
          timestamp: DateTime.now(),
        ));
      }
      emit(DeviceParamsUpdateSuccess());
    } catch (e) {
      if (offlineCacheService != null) {
        await offlineCacheService!.saveAction(OfflineAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'param_update',
          sn: event.sn,
          data: event.params,
          timestamp: DateTime.now(),
        ));
      }
      emit(DeviceError(message: e.toString()));
    }
  }

  Future<void> _onBindRequested(
    DeviceBindRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.bind(event.sn, event.stationId);
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
      (_) => emit(DeviceUnbindSuccess()),
    );
  }

  void _onUnsubscribeRealtime(
    DeviceUnsubscribeRealtime event,
    Emitter<DeviceState> emit,
  ) {
    _mqttSub?.cancel();
    _mqttSub = null;
    if (_activeSN != null) {
      mqttService.unsubscribeDeviceTopics(_activeSN!);
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
        emit(DeviceHistoryLoaded(
          data: points,
          period: event.period,
          metric: event.metric,
        ));
      },
    );
  }

  void _onStartLocalPoll(
    DeviceStartLocalPoll event,
    Emitter<DeviceState> emit,
  ) {
    _localPollTimer?.cancel();
    _localPollIP = event.deviceIP;

    _localPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (localCommunicationService == null || isClosed) return;
      try {
        await localCommunicationService!.connect(_localPollIP!);
        final rawData = await localCommunicationService!.getRealtimeData();
        final realtime = InverterRealtime.fromJson(rawData);
        if (!isClosed) {
          add(DeviceLocalRealtimeUpdate(realtime));
        }
      } catch (_) {}
    });
  }

  void _onStopLocalPoll(
    DeviceStopLocalPoll event,
    Emitter<DeviceState> emit,
  ) {
    _localPollTimer?.cancel();
    _localPollTimer = null;
    _localPollIP = null;
  }

  void _onLocalRealtimeUpdate(
    DeviceLocalRealtimeUpdate event,
    Emitter<DeviceState> emit,
  ) {
    final currentState = state;
    if (currentState is DeviceDetailLoaded) {
      emit(DeviceDetailLoaded(device: currentState.device, realtimeData: event.data));
    }
  }

  Future<void> _onLocalParamsRequested(
    DeviceLocalParamsRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: '本地通信服务不可用'));
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

  Future<void> _onLocalParamsUpdateRequested(
    DeviceLocalParamsUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (localCommunicationService == null) {
      emit(const DeviceError(message: '本地通信服务不可用'));
      return;
    }
    try {
      await localCommunicationService!.connect(event.deviceIP);
      await localCommunicationService!.updateParams(event.params);
      if (offlineCacheService != null && _activeSN != null) {
        await offlineCacheService!.saveAction(OfflineAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'param_update',
          sn: _activeSN ?? '',
          data: event.params,
          timestamp: DateTime.now(),
        ));
      }
      emit(DeviceParamsUpdateSuccess());
    } catch (e) {
      if (offlineCacheService != null && _activeSN != null) {
        await offlineCacheService!.saveAction(OfflineAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'param_update',
          sn: _activeSN ?? '',
          data: event.params,
          timestamp: DateTime.now(),
        ));
      }
      emit(DeviceError(message: e.toString()));
    }
  }
}
