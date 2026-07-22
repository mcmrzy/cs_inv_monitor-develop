import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// JWT Token 拦截器
/// 自动处理 Token 刷新和添加认证头
class JwtInterceptor extends Interceptor {
  final StorageService storageService;
  final void Function()? onTokenExpired;

  JwtInterceptor({
    required this.storageService,
    this.onTokenExpired,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 获取 Token
    final token = await storageService.getToken();

    // 如果不是 GET 请求且没有自定义 Authorization header，则添加 Token
    if (token != null && !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';

      // 调试日志（生产环境应该移除或降低级别）
      if (options.path.contains('/api/v1/organizations') ||
          options.path.contains('/api/v1/invitations') ||
          options.path.contains('/api/v1/devices/transfers')) {
        debugPrint('[JWT] Adding auth token to ${options.path}');
      }
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final originalRequest = err.requestOptions;

    // 如果错误是 401 Unauthorized 且尚未重试
    if (err.response?.statusCode == 401 && !originalRequest.retry) {
      try {
        // 尝试刷新 Token
        final refreshToken = await storageService.getRefreshToken();

        if (refreshToken != null) {
          // 调用后端刷新接口
          final newTokenResponse = await _refreshToken(refreshToken);

          if (newTokenResponse != null) {
            final newToken = newTokenResponse['token'];
            final newRefreshToken = newTokenResponse['refresh_token'];

            // 保存新 Token
            if (newToken != null) {
              await storageService.saveToken(newToken);
            }
            if (newRefreshToken != null) {
              await storageService.saveRefreshToken(newRefreshToken);
            }

            // 重试原始请求
            originalRequest.headers['Authorization'] = 'Bearer $newToken';
            originalRequest.retry = true;

            final freshResponse = await Dio().fetch(originalRequest);
            return handler.resolve(freshResponse);
          }
        }
      } catch (e) {
        debugPrint('[JWT] Token refresh failed: $e');
        // Token 刷新失败，触发退出登录逻辑
        onTokenExpired?.call();
      }
    }

    handler.next(err);
  }

  /// 调用后端刷新 Token 接口
  Future<Map<String, dynamic>?> _refreshToken(String refreshToken) async {
    try {
      final dio = Dio();
      final response = await dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data);
      }
    } catch (e) {
      debugPrint('[JWT] Refresh error: $e');
    }
    return null;
  }
}

/// 用于标记已经重试的请求
extension RequestOptionsExtension on RequestOptions {
  bool get retry => extra['retry'] as bool? ?? false;
  set retry(bool value) => extra['retry'] = value;
}
