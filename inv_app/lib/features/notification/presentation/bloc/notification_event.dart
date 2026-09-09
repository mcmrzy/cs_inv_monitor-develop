part of 'notification_bloc.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class SystemNotificationsRequested extends NotificationEvent {
  /// 是否用户手动刷新（下拉/点击刷新按钮）：
  /// 手动刷新与首载一样需要检查 App 更新；SSE/推送等自动刷新跳过
  final bool manual;

  const SystemNotificationsRequested({this.manual = false});

  @override
  List<Object?> get props => [manual];
}

/// 加载更多系统通知（分页）：基于当前 SystemNotificationsLoaded 的页码取下一页，
/// 后端条目追加到现有列表；无更多（hasMore=false）时 handler 直接忽略
class SystemNotificationsLoadMoreRequested extends NotificationEvent {
  const SystemNotificationsLoadMoreRequested();
}

/// 删除单条系统通知：后端通知走 DELETE /notifications/:id，本地通知直接删存储
class SystemNotificationDeleteRequested extends NotificationEvent {
  final SystemNotification notification;

  const SystemNotificationDeleteRequested({required this.notification});

  @override
  List<Object?> get props => [
        notification.id,
        notification.title,
        notification.timestamp,
      ];
}

/// 清空全部系统通知：后端走 DELETE /notifications/clear-all，本地通知直接清存储
class SystemNotificationsClearRequested extends NotificationEvent {
  const SystemNotificationsClearRequested();
}

class _MqttStatusUpdate extends NotificationEvent {
  final String deviceSn;
  final bool isOnline;

  const _MqttStatusUpdate({required this.deviceSn, required this.isOnline});

  @override
  List<Object?> get props => [deviceSn, isOnline];
}

/// JPush 推送消息到达（前台展示）
class JPushNotificationReceived extends NotificationEvent {
  final String notifyType;
  final String? deviceSn;
  final String title;
  final String content;

  const JPushNotificationReceived({
    required this.notifyType,
    this.deviceSn,
    this.title = '',
    this.content = '',
  });

  @override
  List<Object?> get props => [notifyType, deviceSn, title, content];
}

/// 用户点击推送通知
class JPushNotificationTapped extends NotificationEvent {
  final String notifyType;
  final String? deviceSn;

  const JPushNotificationTapped({
    required this.notifyType,
    this.deviceSn,
  });

  @override
  List<Object?> get props => [notifyType, deviceSn];
}
