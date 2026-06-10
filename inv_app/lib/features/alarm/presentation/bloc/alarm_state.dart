part of 'alarm_bloc.dart';

abstract class AlarmState extends Equatable {
  const AlarmState();

  @override
  List<Object?> get props => [];
}

class AlarmInitial extends AlarmState {}

class AlarmLoading extends AlarmState {}

class AlarmListLoaded extends AlarmState {
  final List<dynamic> alarms;
  final int total;
  final bool isFromCache;

  const AlarmListLoaded({
    required this.alarms,
    required this.total,
    this.isFromCache = false,
  });

  @override
  List<Object?> get props => [alarms, total, isFromCache];
}

class AlarmDetailLoaded extends AlarmState {
  final dynamic alarm;

  const AlarmDetailLoaded({required this.alarm});

  @override
  List<Object?> get props => [alarm];
}

class AlarmMarkReadSuccess extends AlarmState {}

class AlarmError extends AlarmState {
  final String message;

  const AlarmError({required this.message});

  @override
  List<Object?> get props => [message];
}
