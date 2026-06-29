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
