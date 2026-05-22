import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';

part 'device_event.dart';
part 'device_state.dart';

class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  final DeviceRepository repository;
  final MQTTService mqttService;
  StreamSubscription<InverterRealtime>? _mqttSub;
  String? _activeSN;

  DeviceBloc({
    required this.repository,
    required this.mqttService,
  }) : super(DeviceInitial()) {
    on<DeviceListRequested>(_onListRequested);
    on<DeviceDetailRequested>(_onDetailRequested);
    on<DeviceRealtimeRefresh>(_onRealtimeRefresh);
    on<DeviceRealtimeWSUpdate>(_onMQTTUpdate);
    on<DeviceControlRequested>(_onControlRequested);
    on<DeviceParamsRequested>(_onParamsRequested);
    on<DeviceParamsUpdateRequested>(_onParamsUpdateRequested);
    on<DeviceBindRequested>(_onBindRequested);
    on<DeviceUnbindRequested>(_onUnbindRequested);
    on<DeviceUnsubscribeRealtime>(_onUnsubscribeRealtime);
  }

  @override
  Future<void> close() {
    _mqttSub?.cancel();
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

    if (!mqttService.isConnected) {
      try {
        await mqttService.waitForConnection(timeout: const Duration(seconds: 10));
      } catch (e) {
        print('[MQTT] Failed to wait for connection: $e');
        return;
      }
    }

    mqttService.subscribeDeviceTopics(sn);

    _mqttSub = mqttService.realtimeDataStream.listen((rt) {
      if (!isClosed && sn == rt.deviceSN) {
        add(DeviceRealtimeWSUpdate(rt));
      }
    });
  }

  Future<void> _onRealtimeRefresh(
    DeviceRealtimeRefresh event,
    Emitter<DeviceState> emit,
  ) async {
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
    emit(DeviceLoading());
    final result = await repository.control(event.sn, event.cmdType, event.params);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(const DeviceControlSuccess(message: '命令已发送')),
    );
  }

  Future<void> _onParamsRequested(
    DeviceParamsRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.getParams(event.sn);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (params) => emit(DeviceParamsLoaded(params: params)),
    );
  }

  Future<void> _onParamsUpdateRequested(
    DeviceParamsUpdateRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(DeviceLoading());
    final result = await repository.updateParams(event.sn, event.params);
    result.fold(
      (failure) => emit(DeviceError(message: failure.message)),
      (_) => emit(DeviceParamsUpdateSuccess()),
    );
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
}
