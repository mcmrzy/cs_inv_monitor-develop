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

  const DashboardLoaded({
    required this.data,
    this.isSSEConnected = false,
    this.selectedTimeRange = 'day',
  });

  DashboardLoaded copyWith({
    DashboardData? data,
    bool? isSSEConnected,
    String? selectedTimeRange,
  }) {
    return DashboardLoaded(
      data: data ?? this.data,
      isSSEConnected: isSSEConnected ?? this.isSSEConnected,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
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
