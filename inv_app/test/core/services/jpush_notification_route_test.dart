import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/services/jpush_service.dart';

void main() {
  group('resolveTargetRoute 通知点击路由', () {
    test('device_offline 带 SN → 设备详情页（push 可返回）', () {
      final target = resolveTargetRoute(
        const JPushNotification(
          notifyType: 'device_offline',
          deviceSn: 'CSINV1234567890',
        ),
      );
      expect(target.location, '/device/CSINV1234567890');
      expect(target.push, isTrue);
    });

    test('device_online 带 SN → 设备详情页（push 可返回）', () {
      final target = resolveTargetRoute(
        const JPushNotification(
          notifyType: 'device_online',
          deviceSn: 'CSINV9876543210',
        ),
      );
      expect(target.location, '/device/CSINV9876543210');
      expect(target.push, isTrue);
    });

    test('device_offline 缺 SN → 消息中心兜底', () {
      for (final sn in [null, '']) {
        final target = resolveTargetRoute(
          JPushNotification(notifyType: 'device_offline', deviceSn: sn),
        );
        expect(target.location, '/alarms');
        expect(target.push, isFalse);
      }
    });

    test('device_ota → OTA 管理页（修复原先误兜底消息中心）', () {
      final target = resolveTargetRoute(
        const JPushNotification(notifyType: 'device_ota'),
      );
      expect(target.location, '/ota');
      expect(target.push, isFalse);
    });

    test('ota_available → OTA 管理页', () {
      final target = resolveTargetRoute(
        const JPushNotification(notifyType: 'ota_available'),
      );
      expect(target.location, '/ota');
    });

    test('app_update → 关于页并自动检查更新（push 可返回）', () {
      final target = resolveTargetRoute(
        const JPushNotification(notifyType: 'app_update'),
      );
      expect(target.location, '/about?check=1');
      expect(target.push, isTrue);
    });

    test('daily_report → 统计概览', () {
      final target = resolveTargetRoute(
        const JPushNotification(notifyType: 'daily_report'),
      );
      expect(target.location, '/statistics');
      expect(target.push, isFalse);
    });

    test('device_alarm 带 alarmId → 告警详情页（push 可返回）', () {
      final target = resolveTargetRoute(
        const JPushNotification(
          notifyType: 'device_alarm',
          deviceSn: 'CSINV1234567890',
          alarmId: 123,
        ),
      );
      expect(target.location, '/alarm/123');
      expect(target.push, isTrue);
    });

    test('alarm_cleared 带 alarmId → 告警详情页（push 可返回）', () {
      final target = resolveTargetRoute(
        const JPushNotification(notifyType: 'alarm_cleared', alarmId: 456),
      );
      expect(target.location, '/alarm/456');
      expect(target.push, isTrue);
    });

    test('device_alarm / alarm_cleared 缺 alarmId → 消息中心兜底', () {
      for (final notifyType in ['device_alarm', 'alarm_cleared']) {
        final target = resolveTargetRoute(
          JPushNotification(
            notifyType: notifyType,
            deviceSn: 'CSINV1234567890',
            alarmId: null,
          ),
        );
        expect(target.location, '/alarms', reason: 'notifyType: $notifyType');
        expect(target.push, isFalse, reason: 'notifyType: $notifyType');
      }
    });

    test('公告/未知类型 → 消息中心兜底', () {
      for (final notifyType in [
        'system_announcement',
        'unknown_type',
        '',
      ]) {
        final target = resolveTargetRoute(
          JPushNotification(notifyType: notifyType, deviceSn: 'system'),
        );
        expect(target.location, '/alarms', reason: 'notifyType: $notifyType');
        expect(target.push, isFalse, reason: 'notifyType: $notifyType');
      }
    });
  });
}
