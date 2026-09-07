import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/auth/permission_codes.dart';

void main() {
  group('PermissionCodes backend contract', () {
    test('organization management uses the backend plural resource', () {
      expect(PermissionCodes.organizationsManage, 'organizations:manage');
      expect(PermissionCodes.organizationsInvite, 'organizations:invite');
      expect(
        PermissionCodes.organizationsManageMembers,
        'organizations:manage_members',
      );
    });

    test('legacy singular resources map through the explicit whitelist', () {
      expect(PermissionCodes.build('device', 'view'), 'devices:view');
      expect(
        PermissionCodes.build('organization', 'manage'),
        'organizations:manage',
      );
      expect(PermissionCodes.build('alert', 'view'), 'alerts:view');
      expect(PermissionCodes.build('user', 'manage'), 'users:manage');
    });

    test('unknown and already canonical resources remain unchanged', () {
      expect(PermissionCodes.build('firmware', 'view'), 'firmware:view');
      expect(PermissionCodes.build('devices', 'view'), 'devices:view');
    });

    test('permission gate shortcuts use backend permission codes', () {
      expect(PermissionCodes.devicesView, 'devices:view');
      expect(PermissionCodes.devicesControl, 'devices:control');
      expect(PermissionCodes.devicesManage, 'devices:manage');
      expect(PermissionCodes.organizationsManage, 'organizations:manage');
      expect(PermissionCodes.alertsView, 'alerts:view');
      expect(PermissionCodes.usersManage, 'users:manage');
      expect(PermissionCodes.adminManage, 'admin:manage');
    });
  });
}
