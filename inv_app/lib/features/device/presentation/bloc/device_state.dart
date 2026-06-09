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

  const DeviceListLoaded({
    required this.devices,
    required this.total,
  });

  @override
  List<Object?> get props => [devices, total];
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
