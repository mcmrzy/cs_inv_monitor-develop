import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';

class AuthGuard {
  static final List<String> _publicRoutes = [
    '/splash',
    '/login',
    '/register',
    '/forgot-password',
  ];

  static Future<String?> redirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final currentPath = state.matchedLocation;

    if (_publicRoutes.contains(currentPath)) {
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
