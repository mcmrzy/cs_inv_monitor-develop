part of 'notification_bloc.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class SystemNotificationsRequested extends NotificationEvent {
  const SystemNotificationsRequested();
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
part of 'notification_bloc.dart';

abstract class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

class SystemNotificationsRequested extends NotificationEvent {
  const SystemNotificationsRequested();
}

class _MqttStatusUpdate extends NotificationEvent {
  final String deviceSn;
  final bool isOnline;

  const _MqttStatusUpdate({required this.deviceSn, required this.isOnline});

  @override
  List<Object?> get props => [deviceSn, isOnline];
}
