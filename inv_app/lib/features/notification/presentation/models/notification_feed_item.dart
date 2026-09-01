import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';

enum NotificationFeedItemType { alarm, system }

/// A typed presentation item used by the notification center's merged feed.
///
/// Alarm and system notification identifiers live in separate namespaces, so
/// [stableKey] includes the source prefix to avoid collisions in selection and
/// removal animations.
class NotificationFeedItem {
  final NotificationFeedItemType type;
  final DateTime timestamp;
  final Object data;

  const NotificationFeedItem._({
    required this.type,
    required this.timestamp,
    required this.data,
  });

  factory NotificationFeedItem.alarm({
    required Map<String, dynamic> alarm,
    required DateTime timestamp,
  }) {
    return NotificationFeedItem._(
      type: NotificationFeedItemType.alarm,
      timestamp: timestamp,
      data: alarm,
    );
  }

  factory NotificationFeedItem.system({
    required SystemNotification notification,
  }) {
    return NotificationFeedItem._(
      type: NotificationFeedItemType.system,
      timestamp: notification.timestamp,
      data: notification,
    );
  }

  Map<String, dynamic> get alarm => data as Map<String, dynamic>;

  SystemNotification get notification => data as SystemNotification;

  String get stableKey => switch (type) {
        NotificationFeedItemType.alarm => 'alarm:${alarm['id']}',
        NotificationFeedItemType.system => 'notif:${notification.id}',
      };
}

/// Merges the two notification-center sources and preserves the existing
/// newest-first ordering and invalid-alarm-timestamp fallback semantics.
List<NotificationFeedItem> mergeNotificationFeedItems({
  required Iterable<dynamic> alarms,
  required Iterable<SystemNotification> systemNotifications,
  DateTime Function()? now,
}) {
  final fallbackClock = now ?? DateTime.now;
  final items = <NotificationFeedItem>[];

  for (final rawAlarm in alarms) {
    final alarm = rawAlarm as Map<String, dynamic>;
    final occurredAt = alarm['occurred_at'] as String? ?? '';
    final timestamp = DateTime.tryParse(occurredAt) ?? fallbackClock();
    items.add(
      NotificationFeedItem.alarm(alarm: alarm, timestamp: timestamp),
    );
  }

  for (final notification in systemNotifications) {
    items.add(NotificationFeedItem.system(notification: notification));
  }

  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return items;
}
