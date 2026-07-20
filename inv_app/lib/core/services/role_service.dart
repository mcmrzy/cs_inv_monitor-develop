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
  static const int roleSuperAdmin = 0;
  static const int roleGeneralAgent = 1;
  static const int roleAgent = 2;
  static const int roleDealer = 3;
  static const int roleInstaller = 4;
  static const int roleEndUser = 5;

  static List<NavItem> getNavItems(int role, {List<String>? labels}) {
    final l = labels ?? const ['Home', 'Overview', 'Device', 'Alarm', 'Profile'];
    return [
      NavItem(path: '/home', label: l[0], icon: Icons.home_outlined, activeIcon: Icons.home),
      NavItem(path: '/statistics', label: l[1], icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard),
      NavItem(path: '/devices', label: l[2], icon: Icons.devices_outlined, activeIcon: Icons.devices),
      NavItem(path: '/alarms', label: l[3], icon: Icons.notifications_outlined, activeIcon: Icons.notifications),
      NavItem(path: '/profile', label: l[4], icon: Icons.person_outline, activeIcon: Icons.person),
    ];
  }

  static bool hasOtaAccess(int role) {
    return role >= roleSuperAdmin && role <= roleEndUser;
  }

  static bool hasStatisticsAccess(int role) {
    return role >= roleSuperAdmin && role <= roleEndUser;
  }

  static bool canManageDevices(int role) {
    return role >= roleSuperAdmin && role <= roleEndUser;
  }

  static bool isInstaller(int role) {
    return role == roleInstaller;
  }

  static bool isAgent(int role) {
    return role >= roleGeneralAgent && role <= roleDealer;
  }

  static bool isEndUser(int role) {
    return role == roleEndUser;
  }

  static String getRoleName(int role) {
    switch (role) {
      case roleSuperAdmin:
        return 'Admin';
      case roleGeneralAgent:
        return 'General Agent';
      case roleAgent:
        return 'Agent';
      case roleDealer:
        return 'Dealer';
      case roleInstaller:
        return 'Installer';
      case roleEndUser:
        return 'User';
      default:
        return 'User';
    }
  }
}
