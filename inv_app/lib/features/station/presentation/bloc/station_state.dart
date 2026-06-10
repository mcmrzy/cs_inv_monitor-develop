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

class StationCreateSuccess extends StationState {}

class StationUpdateSuccess extends StationState {}

class StationDeleteSuccess extends StationState {}

class StationError extends StationState {
  final String message;

  const StationError({required this.message});

  @override
  List<Object?> get props => [message];
}
