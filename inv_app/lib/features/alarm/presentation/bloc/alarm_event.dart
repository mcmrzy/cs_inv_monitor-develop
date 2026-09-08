part of 'alarm_bloc.dart';

abstract class AlarmEvent extends Equatable {
  const AlarmEvent();

  @override
  List<Object?> get props => [];
}

class AlarmListRequested extends AlarmEvent {
  final int? stationId;
  final int? status;

  /// 告警级别筛选（与 Web 端 alarmLevel 参数对齐）：1=严重 2=警告 3=提示，null=全部
  final int? alarmLevel;
  final int page;
  final int pageSize;

  const AlarmListRequested({
    this.stationId,
    this.status,
    this.alarmLevel,
    this.page = 1,
    this.pageSize = 20,
  });

  @override
  List<Object?> get props => [stationId, status, alarmLevel, page, pageSize];
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

class AlarmDeleteRequested extends AlarmEvent {
  final int alarmId;

  const AlarmDeleteRequested({required this.alarmId});

  @override
  List<Object?> get props => [alarmId];
}

class AlarmMqttReceived extends AlarmEvent {
  const AlarmMqttReceived();

  @override
  List<Object?> get props => [];
}
