import 'package:flutter/material.dart';

import 'package:inv_app/core/theme/csergy_assets.dart';

enum ConnectionMode { remote, local }

class NavItem {
  final String path;
  final String label;
  final String iconAsset;
  final String activeIconAsset;
  final IconData fallbackIcon;
  final IconData activeFallbackIcon;

  const NavItem({
    required this.path,
    required this.label,
    required this.iconAsset,
    required this.activeIconAsset,
    this.fallbackIcon = Icons.home_outlined,
    this.activeFallbackIcon = Icons.home,
  });
}

class RoleService {
  /// Default permission code constants for the new organization-based system.
  /// Codes mirror the backend `permission_grants.permission_code` values
  /// (see business-api `role_default_grants.go` / `ListAllPermissionCodes`).
  static const String permDevicesView = 'devices:view';
  static const String permDevicesManage = 'devices:manage';
  static const String permDeviceControl = 'device_control:basic';
  static const String permOtaView = 'ota:view';
  static const String permStatisticsView = 'dashboard:view';
  static const String permAlarmsView = 'alerts:view';
  static const String permAdminManage = 'admin:manage';

  static List<NavItem> getNavItems(
    bool isSystemAdmin, {
    List<String>? permissions,
    List<String>? labels,
  }) {
    const defaultLabels = ['Home', 'Overview', 'Device', 'Alarm', 'Profile'];

    String labelAt(int index) {
      final candidate = labels != null && index < labels.length
          ? labels[index].trim()
          : '';
      return candidate.isEmpty ? defaultLabels[index] : candidate;
    }

    final perms = permissions ?? const <String>[];
    // 权限列表为空（迁移期/未配置）时保留全部导航项，避免用户导航消失；
    // 有权限码时按角色导航矩阵过滤。
    final hasNavGrants = perms.isNotEmpty;
    final canViewStatistics =
        !hasNavGrants || hasPermission(isSystemAdmin, perms, permStatisticsView);
    final canViewDevices =
        !hasNavGrants || hasPermission(isSystemAdmin, perms, permDevicesView);
    final canViewAlarms =
        !hasNavGrants || hasPermission(isSystemAdmin, perms, permAlarmsView);

    return [
      NavItem(
        path: '/home',
        label: labelAt(0),
        iconAsset: CsergyAssets.home.normalAsset,
        activeIconAsset: CsergyAssets.home.activeAsset,
        fallbackIcon: CsergyAssets.home.normalFallbackIcon,
        activeFallbackIcon: CsergyAssets.home.activeFallbackIcon,
      ),
      if (canViewStatistics)
        NavItem(
          path: '/statistics',
          label: labelAt(1),
          iconAsset: CsergyAssets.statistics.normalAsset,
          activeIconAsset: CsergyAssets.statistics.activeAsset,
          fallbackIcon: CsergyAssets.statistics.normalFallbackIcon,
          activeFallbackIcon: CsergyAssets.statistics.activeFallbackIcon,
        ),
      if (canViewDevices)
        NavItem(
          path: '/devices',
          label: labelAt(2),
          iconAsset: CsergyAssets.devices.normalAsset,
          activeIconAsset: CsergyAssets.devices.activeAsset,
          fallbackIcon: CsergyAssets.devices.normalFallbackIcon,
          activeFallbackIcon: CsergyAssets.devices.activeFallbackIcon,
        ),
      if (canViewAlarms)
        NavItem(
          path: '/alarms',
          label: labelAt(3),
          iconAsset: CsergyAssets.alarms.normalAsset,
          activeIconAsset: CsergyAssets.alarms.activeAsset,
          fallbackIcon: CsergyAssets.alarms.normalFallbackIcon,
          activeFallbackIcon: CsergyAssets.alarms.activeFallbackIcon,
        ),
      NavItem(
        path: '/profile',
        label: labelAt(4),
        iconAsset: CsergyAssets.profile.normalAsset,
        activeIconAsset: CsergyAssets.profile.activeAsset,
        fallbackIcon: CsergyAssets.profile.normalFallbackIcon,
        activeFallbackIcon: CsergyAssets.profile.activeFallbackIcon,
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
    return hasPermission(isSystemAdmin, permissions, permOtaView) ||
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
