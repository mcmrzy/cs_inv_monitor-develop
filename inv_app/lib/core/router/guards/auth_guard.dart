import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

class AuthGuard {
  /// 公开路由 - 无需认证即可访问
  static final List<String> _publicRoutes = [
    '/splash',
    '/onboarding',
    '/login',
    '/jverify-login',
    '/register',
    '/forgot-password',
  ];

  /// 离线可用路由 - 无需网络连接/登录即可使用的本地功能
  /// 包括：主页、设备列表、本地配网、本地OTA、WiFi配置等
  /// （Q4/Q7：登录页"本地模式"guest 入口与已登录用户断网自动切换本地
  /// 均复用这些路由，因此未登录也放行）
  static final List<String> _offlineRoutes = [
    '/home',
    '/devices',
    '/profile',
    '/wifi-config',
    '/local-mode',
    '/local-ota',
    // 设备绑定深链入口（csinv://bind）；实际绑定仍需登录态，
    // 未登录时由页面引导登录
    '/device/qr-bind',
    // 操作日志页（本地 op-log 存储，离线可用）
    '/device/op-logs/',
  ];

  /// 设备详情子路由离线白名单（guest/离线豁免复核结论）：
  /// 逐路由显式放行而非 '/device/' 前缀匹配，新增设备路由不会被
  /// 隐式暴露给 guest。control/settings 为本地直连链路的产品能力
  /// （guest 本地模式免登录控制设备）；云端变更类操作无 token 时
  /// 后端仍会拒绝，豁免仅保障本地直连与离线展示。
  static final RegExp _offlineDeviceRoutePattern = RegExp(
    r'^/device/[^/]+(/(control|protocol|history|settings|edit))?$',
  );

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

    // 设备详情子路由白名单放行（逐路由显式枚举，见上方复核结论）
    if (_offlineDeviceRoutePattern.hasMatch(currentPath)) {
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
