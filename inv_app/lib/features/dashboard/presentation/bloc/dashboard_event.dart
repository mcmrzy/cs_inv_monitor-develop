part of 'dashboard_bloc.dart';

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// 加载仪表盘数据（初始加载 + 下拉刷新）
class DashboardLoadRequested extends DashboardEvent {
  const DashboardLoadRequested();
}

/// 连接到SSE流
class DashboardSSEConnectRequested extends DashboardEvent {
  const DashboardSSEConnectRequested();
}

/// 断开SSE连接
class DashboardSSEDisconnectRequested extends DashboardEvent {
  const DashboardSSEDisconnectRequested();
}

/// SSE数据更新
class DashboardSSEDataReceived extends DashboardEvent {
  final Map<String, dynamic> data;

  const DashboardSSEDataReceived({required this.data});

  @override
  List<Object?> get props => [data];
}

/// SSE连接状态变化
class DashboardSSEConnectionChanged extends DashboardEvent {
  final bool isConnected;

  const DashboardSSEConnectionChanged({required this.isConnected});

  @override
  List<Object?> get props => [isConnected];
}

/// 时间范围变化
class DashboardTimeRangeChanged extends DashboardEvent {
  final String range; // 'day', 'week', 'month'

  const DashboardTimeRangeChanged({required this.range});

  @override
  List<Object?> get props => [range];
}
