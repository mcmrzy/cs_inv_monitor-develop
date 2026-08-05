import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

class AuthGuard {
  /// 公开路由 - 无需认证即可访问
  static final List<String> _publicRoutes = [
    '/splash',
    '/login',
    '/jverify-login',
    '/register',
    '/forgot-password',
  ];

  /// 离线可用路由 - 无需网络连接即可使用的本地功能
  /// 包括：主页、设备列表、本地配网、本地OTA、WiFi配置等
  static final List<String> _offlineRoutes = [
    '/home',
    '/devices',
    '/profile',
    '/wifi-config',
    '/local-mode',
    '/local-ota',
    '/device/',
  ];

  static Future<String?> redirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final currentPath = state.matchedLocation;

    // 公开路由直接放行
    if (_publicRoutes.contains(currentPath)) {
      return null;
    }

    // 离线可用路由放行 - 支持断网/未登录情况下仍可访问主页面和本地功能
    if (_offlineRoutes.any(
      (route) => currentPath == route || currentPath.startsWith(route),
    )) {
      return null;
    }

    final storageService = getIt<StorageService>();
    final token = await storageService.getToken();
    if (!context.mounted) return null;

    if (token == null || token.isEmpty) {
      return '/login';
    }

    if (currentPath == '/splash') {
      return '/home';
    }

    return null;
  }

  static Future<bool> isAuthenticated() async {
    final storageService = getIt<StorageService>();
    final token = await storageService.getToken();
    return token != null && token.isNotEmpty;
  }
}
