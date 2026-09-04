part of 'station_bloc.dart';

abstract class StationState extends Equatable {
  const StationState();

  @override
  List<Object?> get props => [];
}

class StationInitial extends StationState {}

class StationLoading extends StationState {}

class StationSummaryLoaded extends StationState {
  final List<dynamic> stations;
  final Map<String, dynamic> summary;
  final bool isFromCache;

  const StationSummaryLoaded({
    required this.stations,
    required this.summary,
    this.isFromCache = false,
  });

  @override
  List<Object?> get props => [stations, summary, isFromCache];
}

class StationListLoaded extends StationState {
  final List<dynamic> stations;
  final int total;

  const StationListLoaded({
    required this.stations,
    required this.total,
  });

  @override
  List<Object?> get props => [stations, total];
}

class StationDetailLoaded extends StationState {
  final int stationId;
  final dynamic station;
  final List<dynamic> devices;
  final bool isFromCache;

  const StationDetailLoaded({
    required this.stationId,
    required this.station,
    required this.devices,
    this.isFromCache = false,
  });

  @override
  List<Object?> get props => [stationId, station, devices, isFromCache];
}

class StationCreateSuccess extends StationState {
  final String requestId;

  const StationCreateSuccess({required this.requestId});

  @override
  List<Object?> get props => [requestId];
}

class StationUpdateSuccess extends StationState {
  final int stationId;
  final String requestId;

  const StationUpdateSuccess({
    required this.stationId,
    required this.requestId,
  });

  @override
  List<Object?> get props => [stationId, requestId];
}

class StationDeleteSuccess extends StationState {
  final int stationId;
  final String requestId;

  const StationDeleteSuccess({
    required this.stationId,
    required this.requestId,
  });

  @override
  List<Object?> get props => [stationId, requestId];
}

class DeviceUnbindSuccess extends StationState {
  final String sn;

  const DeviceUnbindSuccess({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceRebindSuccess extends StationState {
  final String sn;

  const DeviceRebindSuccess({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceBindSuccess extends StationState {
  final String sn;

  const DeviceBindSuccess({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceDeleteSuccess extends StationState {
  final String sn;

  const DeviceDeleteSuccess({required this.sn});

  @override
  List<Object?> get props => [sn];
}

class DeviceReorderSuccess extends StationState {
  final int stationId;

  const DeviceReorderSuccess({required this.stationId});

  @override
  List<Object?> get props => [stationId];
}

/// 电站排序保存成功
class StationReorderSuccess extends StationState {}

class StationError extends StationState {
  final String message;

  const StationError({required this.message});

  @override
  List<Object?> get props => [message];
}

class StationActionError extends StationError {
  final String action;
  final String requestId;
  final int? stationId;

  const StationActionError({
    required super.message,
    required this.action,
    required this.requestId,
    this.stationId,
  });

  @override
  List<Object?> get props => [message, action, requestId, stationId];
}
