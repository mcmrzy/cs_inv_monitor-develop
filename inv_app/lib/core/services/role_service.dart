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
  static const int roleAgent = 1;
  static const int roleInstaller = 2;
  static const int roleEndUser = 3;

  static List<NavItem> getNavItems(int role) {
    return const [
      NavItem(path: '/home', label: '首页', icon: Icons.home_outlined, activeIcon: Icons.home),
      NavItem(path: '/statistics', label: '统计', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart),
      NavItem(path: '/devices', label: '设备', icon: Icons.devices_outlined, activeIcon: Icons.devices),
      NavItem(path: '/alarms', label: '告警', icon: Icons.notifications_outlined, activeIcon: Icons.notifications),
      NavItem(path: '/profile', label: '我的', icon: Icons.person_outline, activeIcon: Icons.person),
    ];
  }

  static bool hasOtaAccess(int role) {
    return role == roleSuperAdmin;
  }

  static bool hasStatisticsAccess(int role) {
    return role == roleSuperAdmin || role == roleAgent || role == roleInstaller;
  }

  static bool canManageDevices(int role) {
    return role == roleSuperAdmin || role == roleAgent || role == roleInstaller;
  }

  static bool isInstaller(int role) {
    return role == roleInstaller;
  }

  static bool isAgent(int role) {
    return role == roleAgent;
  }

  static bool isEndUser(int role) {
    return role == roleEndUser;
  }

  static String getRoleName(int role) {
    switch (role) {
      case roleSuperAdmin:
        return '超级管理员';
      case roleAgent:
        return '代理商';
      case roleInstaller:
        return '安装商';
      case roleEndUser:
        return '用户';
      default:
        return '用户';
    }
  }
}
