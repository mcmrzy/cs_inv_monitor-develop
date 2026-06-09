part of 'statistics_bloc.dart';

abstract class StatisticsState extends Equatable {
  const StatisticsState();

  @override
  List<Object?> get props => [];
}

class StatisticsInitial extends StatisticsState {}

class StatisticsLoading extends StatisticsState {}

class StatisticsOverviewLoaded extends StatisticsState {
  final Map<String, dynamic> overview;

  const StatisticsOverviewLoaded({required this.overview});

  @override
  List<Object?> get props => [overview];
}

class StatisticsDetailLoaded extends StatisticsState {
  final Map<String, dynamic> data;

  const StatisticsDetailLoaded({required this.data});

  @override
  List<Object?> get props => [data];
}

class StatisticsError extends StatisticsState {
  final String message;

  const StatisticsError({required this.message});

  @override
  List<Object?> get props => [message];
}
