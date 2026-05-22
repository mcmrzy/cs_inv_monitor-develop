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

  const StationSummaryLoaded({
    required this.stations,
    required this.summary,
  });

  @override
  List<Object?> get props => [stations, summary];
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
  final dynamic station;
  final List<dynamic> devices;

  const StationDetailLoaded({
    required this.station,
    required this.devices,
  });

  @override
  List<Object?> get props => [station, devices];
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
