import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/notification/presentation/models/notification_feed_item.dart';

void main() {
  group('mergeNotificationFeedItems', () {
    test('merges alarms and system notifications in descending time order', () {
      final alarm = <String, dynamic>{
        'id': 7,
        'occurred_at': '2026-08-30T08:00:00.000Z',
      };
      final notification = SystemNotification(
        id: 9,
        type: SystemNotificationType.deviceOnline,
        title: 'Device online',
        subtitle: '',
        timestamp: DateTime.utc(2026, 8, 30, 9),
      );

      final result = mergeNotificationFeedItems(
        alarms: [alarm],
        systemNotifications: [notification],
      );

      expect(
        result.map((item) => item.type),
        [NotificationFeedItemType.system, NotificationFeedItemType.alarm],
      );
      expect(result.first.data, same(notification));
      expect(result.last.data, same(alarm));
    });

    test('uses the supplied fallback clock for an invalid alarm timestamp', () {
      final fallback = DateTime.utc(2026, 8, 30, 10);

      final result = mergeNotificationFeedItems(
        alarms: [
          <String, dynamic>{'id': 3, 'occurred_at': 'not-a-date'},
        ],
        systemNotifications: const [],
        now: () => fallback,
      );

      expect(result.single.timestamp, fallback);
    });

    test('prefixes stable keys so alarm and notification ids cannot collide', () {
      final alarmItem = NotificationFeedItem.alarm(
        alarm: <String, dynamic>{'id': 12},
        timestamp: DateTime.utc(2026),
      );
      final notificationItem = NotificationFeedItem.system(
        notification: SystemNotification(
          id: 12,
          type: SystemNotificationType.deviceOffline,
          title: '',
          subtitle: '',
          timestamp: DateTime.utc(2026),
        ),
      );

      expect(alarmItem.stableKey, 'alarm:12');
      expect(notificationItem.stableKey, 'notif:12');
    });
  });
}
