import 'package:flutter/material.dart';

enum ConnectionMode { remote, local }

class NavItem {
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class RoleService {
  /// Default permission code constants for the new organization-based system.
  static const String permDevicesView = 'devices:view';
  static const String permDevicesManage = 'devices:manage';
  static const String permDeviceControl = 'device_control:basic';
  static const String permOtaManage = 'ota:manage';
  static const String permStatisticsView = 'statistics:view';
  static const String permAlarmsView = 'alarms:view';
  static const String permAdminManage = 'admin:manage';

  static List<NavItem> getNavItems(
    bool isSystemAdmin, {
    List<String>? permissions,
    List<String>? labels,
  }) {
    final l =
        labels ?? const ['Home', 'Overview', 'Device', 'Alarm', 'Profile'];
    return [
      NavItem(
        path: '/home',
        label: l[0],
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
      ),
      NavItem(
        path: '/statistics',
        label: l[1],
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
      ),
      NavItem(
        path: '/devices',
        label: l[2],
        icon: Icons.devices_outlined,
        activeIcon: Icons.devices,
      ),
      NavItem(
        path: '/alarms',
        label: l[3],
        icon: Icons.notifications_outlined,
        activeIcon: Icons.notifications,
      ),
      NavItem(
        path: '/profile',
        label: l[4],
        icon: Icons.person_outline,
        activeIcon: Icons.person,
      ),
    ];
  }

  static bool hasPermission(
    bool isSystemAdmin,
    List<String> permissions,
    String code,
  ) {
    if (isSystemAdmin) return true;
    return permissions.contains(code);
  }

  static bool hasOtaAccess(bool isSystemAdmin, List<String> permissions) {
    return hasPermission(isSystemAdmin, permissions, permOtaManage) ||
        hasPermission(isSystemAdmin, permissions, permDevicesManage);
  }

  static bool hasStatisticsAccess(bool isSystemAdmin, List<String> permissions) {
    return hasPermission(isSystemAdmin, permissions, permStatisticsView);
  }

  static bool canManageDevices(bool isSystemAdmin, List<String> permissions) {
    return hasPermission(isSystemAdmin, permissions, permDevicesManage);
  }

  static bool canControlDevices(bool isSystemAdmin, List<String> permissions) {
    return hasPermission(isSystemAdmin, permissions, permDeviceControl);
  }

  static String getRoleName(bool isSystemAdmin, [List<String>? permissions]) {
    if (isSystemAdmin) return 'System Admin';
    if (permissions != null && permissions.contains(permAdminManage)) {
      return 'Org Admin';
    }
    return 'Member';
  }
}
