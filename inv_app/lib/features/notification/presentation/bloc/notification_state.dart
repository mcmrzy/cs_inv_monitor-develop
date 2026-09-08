part of 'notification_bloc.dart';

abstract class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

class NotificationInitial extends NotificationState {}

class SystemNotificationsLoaded extends NotificationState {
  final List<SystemNotification> notifications;

  /// 已加载的后端通知页码（1-based，仅 SystemNotificationsRequested 会重置为 1）
  final int page;

  /// 后端是否还有更早的通知（total > 已加载条数）
  final bool hasMore;

  const SystemNotificationsLoaded({
    required this.notifications,
    this.page = 1,
    this.hasMore = false,
  });

  @override
  List<Object?> get props => [notifications, page, hasMore];
}

class NotificationError extends NotificationState {
  final String message;

  const NotificationError({required this.message});

  @override
  List<Object?> get props => [message];
}
