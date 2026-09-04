import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/role_service.dart';

void main() {
  group('RoleService permission constants', () {
    test('permission code constants are defined correctly', () {
      expect(RoleService.permDevicesView, 'devices:view');
      expect(RoleService.permDevicesManage, 'devices:manage');
      expect(RoleService.permDeviceControl, 'device_control:basic');
      expect(RoleService.permOtaView, 'ota:view');
      expect(RoleService.permStatisticsView, 'dashboard:view');
      expect(RoleService.permAlarmsView, 'alerts:view');
      expect(RoleService.permAdminManage, 'admin:manage');
    });
  });

  group('RoleService.hasPermission', () {
    test('system admin always has permission', () {
      expect(
        RoleService.hasPermission(true, [], 'devices:view'),
        isTrue,
      );
      expect(
        RoleService.hasPermission(true, [], 'admin:manage'),
        isTrue,
      );
    });

    test('non-admin checks permissions list', () {
      final perms = ['devices:view', 'devices:manage'];
      expect(
        RoleService.hasPermission(false, perms, 'devices:view'),
        isTrue,
      );
      expect(
        RoleService.hasPermission(false, perms, 'admin:manage'),
        isFalse,
      );
    });

    test('empty permissions denies all for non-admin', () {
      expect(
        RoleService.hasPermission(false, [], 'devices:view'),
        isFalse,
      );
    });
  });

  group('RoleService.getRoleName', () {
    test('system admin returns System Admin', () {
      expect(RoleService.getRoleName(true), 'System Admin');
    });

    test('org admin with admin:manage returns Org Admin', () {
      expect(
        RoleService.getRoleName(false, ['admin:manage', 'devices:view']),
        'Org Admin',
      );
    });

    test('regular member returns Member', () {
      expect(
        RoleService.getRoleName(false, ['devices:view']),
        'Member',
      );
      expect(RoleService.getRoleName(false, []), 'Member');
    });
  });

  group('RoleService convenience methods', () {
    test('hasOtaAccess checks ota:view or devices:manage', () {
      expect(
        RoleService.hasOtaAccess(true, []),
        isTrue,
      );
      expect(
        RoleService.hasOtaAccess(false, ['ota:view']),
        isTrue,
      );
      expect(
        RoleService.hasOtaAccess(false, ['devices:manage']),
        isTrue,
      );
      expect(
        RoleService.hasOtaAccess(false, ['devices:view']),
        isFalse,
      );
    });

    test('hasStatisticsAccess checks dashboard:view', () {
      expect(
        RoleService.hasStatisticsAccess(true, []),
        isTrue,
      );
      expect(
        RoleService.hasStatisticsAccess(false, ['dashboard:view']),
        isTrue,
      );
      expect(
        RoleService.hasStatisticsAccess(false, []),
        isFalse,
      );
    });

    test('canManageDevices checks devices:manage', () {
      expect(
        RoleService.canManageDevices(true, []),
        isTrue,
      );
      expect(
        RoleService.canManageDevices(false, ['devices:manage']),
        isTrue,
      );
      expect(
        RoleService.canManageDevices(false, ['devices:view']),
        isFalse,
      );
    });

    test('canControlDevices checks device_control:basic', () {
      expect(
        RoleService.canControlDevices(true, []),
        isTrue,
      );
      expect(
        RoleService.canControlDevices(false, ['device_control:basic']),
        isTrue,
      );
      expect(
        RoleService.canControlDevices(false, []),
        isFalse,
      );
    });
  });

  group('RoleService.getNavItems', () {
    test('returns 5 nav items for all users', () {
      final items = RoleService.getNavItems(false, permissions: []);
      expect(items.length, 5);
      expect(items[0].path, '/home');
      expect(items[1].path, '/statistics');
      expect(items[2].path, '/devices');
      expect(items[3].path, '/alarms');
      expect(items[4].path, '/profile');
    });

    test('accepts custom labels', () {
      final items = RoleService.getNavItems(
        true,
        labels: ['首页', '概览', '设备', '告警', '我的'],
      );
      expect(items[0].label, '首页');
      expect(items[4].label, '我的');
    });

    test('filters nav items by permission grants', () {
      final items = RoleService.getNavItems(
        false,
        permissions: ['devices:view', 'alerts:view'],
      );
      expect(items.map((e) => e.path).toList(), [
        '/home',
        '/devices',
        '/alarms',
        '/profile',
      ]);
    });

    test('system admin always sees all nav items', () {
      final items = RoleService.getNavItems(true, permissions: []);
      expect(items.length, 5);
      expect(items[1].path, '/statistics');
    });
  });
}
