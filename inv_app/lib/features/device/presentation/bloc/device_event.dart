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

class DeviceHistoryRequested extends DeviceEvent {
  final String sn;
  final String period;
  final String startDate;
  final String endDate;
  final String metric;

  const DeviceHistoryRequested({
    required this.sn,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.metric,
  });

  @override
  List<Object?> get props => [sn, period, startDate, endDate, metric];
}

class DeviceStartLocalPoll extends DeviceEvent {
  final String deviceIP;

  const DeviceStartLocalPoll({required this.deviceIP});

  @override
  List<Object?> get props => [deviceIP];
}

class DeviceStopLocalPoll extends DeviceEvent {
  const DeviceStopLocalPoll();

  @override
  List<Object?> get props => [];
}

class DeviceLocalRealtimeUpdate extends DeviceEvent {
  final InverterRealtime data;

  const DeviceLocalRealtimeUpdate(this.data);

  @override
  List<Object?> get props => [data];
}

class DeviceLocalParamsRequested extends DeviceEvent {
  final String deviceIP;

  const DeviceLocalParamsRequested({required this.deviceIP});

  @override
  List<Object?> get props => [deviceIP];
}

class DeviceLocalParamsUpdateRequested extends DeviceEvent {
  final String deviceIP;
  final Map<String, dynamic> params;

  const DeviceLocalParamsUpdateRequested({
    required this.deviceIP,
    required this.params,
  });

  @override
  List<Object?> get props => [deviceIP, params];
}

/// 逆变器自动断开事件：30秒后检测到 AC 电流/功率均为 0，已自动断开设备热点
class DeviceAutoDisconnected extends DeviceEvent {
  const DeviceAutoDisconnected();

  @override
  List<Object?> get props => [];
}
