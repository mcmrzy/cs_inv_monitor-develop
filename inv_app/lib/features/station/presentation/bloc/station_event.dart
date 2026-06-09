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

  const StationCreateRequested({required this.data});

  @override
  List<Object?> get props => [data];
}

class StationUpdateRequested extends StationEvent {
  final int stationId;
  final Map<String, dynamic> data;

  const StationUpdateRequested({
    required this.stationId,
    required this.data,
  });

  @override
  List<Object?> get props => [stationId, data];
}

class StationDeleteRequested extends StationEvent {
  final int stationId;

  const StationDeleteRequested({required this.stationId});

  @override
  List<Object?> get props => [stationId];
}
