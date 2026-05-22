part of 'device_bloc.dart';

abstract class DeviceEvent extends Equatable {
  const DeviceEvent();

  @override
  List<Object?> get props => [];
}

class DeviceListRequested extends DeviceEvent {
  final int? stationId;
  final int? status;
  final int page;
  final int pageSize;

  const DeviceListRequested({
    this.stationId,
    this.status,
    this.page = 1,
    this.pageSize = 20,
  });

  @override
  List<Object?> get props => [stationId, status, page, pageSize];
}

class DeviceDetailRequested extends DeviceEvent {
  final String sn;

  const DeviceDetailRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceRealtimeRefresh extends DeviceEvent {
  final String sn;

  const DeviceRealtimeRefresh({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceControlRequested extends DeviceEvent {
  final String sn;
  final String cmdType;
  final Map<String, dynamic> params;

  const DeviceControlRequested({
    required this.sn,
    required this.cmdType,
    required this.params,
  });

  @override
  List<Object?> get props => [sn, cmdType, params];
}

class DeviceParamsRequested extends DeviceEvent {
  final String sn;

  const DeviceParamsRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceParamsUpdateRequested extends DeviceEvent {
  final String sn;
  final Map<String, dynamic> params;

  const DeviceParamsUpdateRequested({
    required this.sn,
    required this.params,
  });

  @override
  List<Object?> get props => [sn, params];
}

class DeviceBindRequested extends DeviceEvent {
  final String sn;
  final int? stationId;

  const DeviceBindRequested({
    required this.sn,
    this.stationId,
  });

  @override
  List<Object?> get props => [sn, stationId];
}

class DeviceUnbindRequested extends DeviceEvent {
  final String sn;

  const DeviceUnbindRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceRealtimeWSUpdate extends DeviceEvent {
  final InverterRealtime data;

  const DeviceRealtimeWSUpdate(this.data);

  @override
  List<Object?> get props => [data];
}

class DeviceUnsubscribeRealtime extends DeviceEvent {
  const DeviceUnsubscribeRealtime();

  @override
  List<Object?> get props => [];
}
