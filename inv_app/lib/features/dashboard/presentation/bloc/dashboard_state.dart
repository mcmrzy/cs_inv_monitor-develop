part of 'dashboard_bloc.dart';

abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  final DashboardData data;
  final bool isSSEConnected;
  final String selectedTimeRange;
  final List<String> failedSections;

  const DashboardLoaded({
    required this.data,
    this.isSSEConnected = false,
    this.selectedTimeRange = 'day',
    this.failedSections = const [],
  });

  DashboardLoaded copyWith({
    DashboardData? data,
    bool? isSSEConnected,
    String? selectedTimeRange,
    List<String>? failedSections,
  }) {
    return DashboardLoaded(
      data: data ?? this.data,
      isSSEConnected: isSSEConnected ?? this.isSSEConnected,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
      failedSections: failedSections ?? this.failedSections,
    );
  }

  @override
  List<Object?> get props => [
        data.todayEnergy,
        data.totalEnergy,
        data.deviceTotal,
        data.onlineCount,
        data.offlineCount,
        data.faultCount,
        data.trendData,
        data.stationRanking,
        data.recentAlarms,
        data.isFromCache,
        isSSEConnected,
        selectedTimeRange,
        failedSections,
      ];
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}

/// SSE连接中状态
class DashboardSSEConnecting extends DashboardState {
  const DashboardSSEConnecting();
}

/// SSE连接错误状态
class DashboardSSEError extends DashboardState {
  final String message;

  const DashboardSSEError({required this.message});

  @override
  List<Object?> get props => [message];
}
