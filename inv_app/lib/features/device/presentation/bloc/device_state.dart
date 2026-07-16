part of 'device_bloc.dart';

abstract class DeviceState extends Equatable {
  const DeviceState();

  @override
  List<Object?> get props => [];
}

class DeviceInitial extends DeviceState {}

class DeviceLoading extends DeviceState {}

class DeviceListLoaded extends DeviceState {
  final List<dynamic> devices;
  final int total;
  final bool isFromCache;

  const DeviceListLoaded({
    required this.devices,
    required this.total,
    this.isFromCache = false,
  });

  @override
  List<Object?> get props => [devices, total, isFromCache];
}

class DeviceDetailLoaded extends DeviceState {
  final dynamic device;
  final InverterRealtime? realtimeData;

  const DeviceDetailLoaded({
    required this.device,
    required this.realtimeData,
  });

  @override
  List<Object?> get props => [device, realtimeData];
}

class DeviceControlSuccess extends DeviceState {
  final String? message;

  const DeviceControlSuccess({this.message});

  @override
  List<Object?> get props => [message];
}

class DeviceParamsLoaded extends DeviceState {
  final Map<String, dynamic> params;

  const DeviceParamsLoaded({required this.params});

  @override
  List<Object?> get props => [params];
}

class DeviceParamsUpdateSuccess extends DeviceState {}

class DeviceBindSuccess extends DeviceState {}

class DeviceUnbindSuccess extends DeviceState {}

class DeviceError extends DeviceState {
  final String message;

  const DeviceError({required this.message});

  @override
  List<Object?> get props => [message];
}

class DeviceHistoryLoaded extends DeviceState {
  final List<Map<String, dynamic>> data;
  final String period;
  final String metric;

  const DeviceHistoryLoaded({
    required this.data,
    required this.period,
    required this.metric,
  });

  @override
  List<Object?> get props => [data, period, metric];
}

/// 逆变器自动断开状态：30秒后检测到 AC 电流/功率均为 0，已自动断开设备热点并切回家用 WiFi
class DeviceLocalDisconnected extends DeviceState {
  /// 断开原因描述
  final String reason;

  const DeviceLocalDisconnected({required this.reason});

  @override
  List<Object?> get props => [reason];
}
