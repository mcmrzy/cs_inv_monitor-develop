part of 'station_bloc.dart';

abstract class StationEvent extends Equatable {
  const StationEvent();

  @override
  List<Object?> get props => [];
}

class StationSummaryRequested extends StationEvent {}

class StationListRequested extends StationEvent {
  final int page;
  final int pageSize;

  const StationListRequested({
    this.page = 1,
    this.pageSize = 20,
  });

  @override
  List<Object?> get props => [page, pageSize];
}

class StationDetailRequested extends StationEvent {
  final int stationId;

  const StationDetailRequested({required this.stationId});

  @override
  List<Object?> get props => [stationId];
}

class StationCreateRequested extends StationEvent {
  final Map<String, dynamic> data;
  final String requestId;

  const StationCreateRequested({
    required this.data,
    required this.requestId,
  });

  @override
  List<Object?> get props => [data, requestId];
}

class StationUpdateRequested extends StationEvent {
  final int stationId;
  final Map<String, dynamic> data;
  final String requestId;

  const StationUpdateRequested({
    required this.stationId,
    required this.data,
    required this.requestId,
  });

  @override
  List<Object?> get props => [stationId, data, requestId];
}

class StationDeleteRequested extends StationEvent {
  final int stationId;
  final String requestId;

  const StationDeleteRequested({
    required this.stationId,
    required this.requestId,
  });

  @override
  List<Object?> get props => [stationId, requestId];
}

class StationActionRequestId {
  static int _sequence = 0;

  static String next() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$timestamp-${_sequence++}';
  }
}

class DeviceUnbindRequested extends StationEvent {
  final String sn;

  const DeviceUnbindRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceRebindRequested extends StationEvent {
  final String sn;
  final int newStationId;

  const DeviceRebindRequested({required this.sn, required this.newStationId});

  @override
  List<Object?> get props => [sn, newStationId];
}

class DeviceBindRequested extends StationEvent {
  final String sn;
  final int stationId;

  const DeviceBindRequested({required this.sn, required this.stationId});

  @override
  List<Object?> get props => [sn, stationId];
}

class DeviceDeleteRequested extends StationEvent {
  final String sn;

  const DeviceDeleteRequested({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceReorderRequested extends StationEvent {
  final int stationId;
  final List<String> deviceOrder;

  const DeviceReorderRequested({required this.stationId, required this.deviceOrder});

  @override
  List<Object?> get props => [stationId, deviceOrder];
}

/// 电站列表拖动排序（首页电站卡片）
class StationReorderRequested extends StationEvent {
  final List<int> stationOrder;

  const StationReorderRequested({required this.stationOrder});

  @override
  List<Object?> get props => [stationOrder];
}
