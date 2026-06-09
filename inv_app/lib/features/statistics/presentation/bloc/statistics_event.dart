part of 'statistics_bloc.dart';

abstract class StatisticsEvent extends Equatable {
  const StatisticsEvent();

  @override
  List<Object?> get props => [];
}

class StatisticsOverviewRequested extends StatisticsEvent {}

class StatisticsDetailRequested extends StatisticsEvent {
  final String? deviceSN;
  final int? stationId;
  final String startDate;
  final String endDate;
  final String period;

  const StatisticsDetailRequested({
    this.deviceSN,
    this.stationId,
    required this.startDate,
    required this.endDate,
    this.period = 'day',
  });

  @override
  List<Object?> get props => [deviceSN, stationId, startDate, endDate, period];
}
