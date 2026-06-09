part of 'alarm_bloc.dart';

abstract class AlarmEvent extends Equatable {
  const AlarmEvent();

  @override
  List<Object?> get props => [];
}

class AlarmListRequested extends AlarmEvent {
  final int? stationId;
  final int? status;
  final int page;
  final int pageSize;

  const AlarmListRequested({
    this.stationId,
    this.status,
    this.page = 1,
    this.pageSize = 20,
  });

  @override
  List<Object?> get props => [stationId, status, page, pageSize];
}

class AlarmDetailRequested extends AlarmEvent {
  final int alarmId;

  const AlarmDetailRequested({required this.alarmId});

  @override
  List<Object?> get props => [alarmId];
}

class AlarmMarkReadRequested extends AlarmEvent {
  final List<int> alarmIds;

  const AlarmMarkReadRequested({required this.alarmIds});

  @override
  List<Object?> get props => [alarmIds];
}
