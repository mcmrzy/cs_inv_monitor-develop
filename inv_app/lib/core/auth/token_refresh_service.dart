import 'package:dio/dio.dart';
import 'package:inv_app/core/network/retry_request_options.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// Shared by API requests and SSE so refresh-token rotation happens once.
class TokenRefreshService {
  final Dio _dio;
  final StorageService _storage;
  final void Function() _onSessionExpired;
  Future<bool>? _pending;

  TokenRefreshService(this._dio, this._storage, this._onSessionExpired);

  Future<bool> refresh() =>
      _pending ??= _refresh().whenComplete(() => _pending = null);

  Future<bool> _refresh() async {
    try {
      final refreshToken =
          normalizeTokenValue(await _storage.getRefreshToken());
      if (refreshToken == null) {
        _onSessionExpired();
        return false;
      }

      final response = await _dio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) return false;

      // Older servers return authentication errors inside HTTP 200 envelopes.
      if (body['code'] == 401 || body['code'] == 403) {
        _onSessionExpired();
        return false;
      }
      if (body.containsKey('code') && body['code'] != 0) return false;

      final data = body['code'] == 0 ? body['data'] : body;
      if (data is! Map<String, dynamic>) return false;
      final accessToken = normalizeTokenValue(
        (data['access_token'] ?? data['token'] ?? data['accessToken'])
            as String?,
      );
      final nextRefreshToken = normalizeTokenValue(
        (data['refresh_token'] ?? data['refreshToken']) as String?,
      );
      if (accessToken == null) return false;

      await _storage.saveToken(accessToken);
      if (nextRefreshToken != null) {
        await _storage.saveRefreshToken(nextRefreshToken);
      }
      return true;
    } on DioException catch (error) {
      // Restart downtime, timeouts and 5xx responses must retain the session.
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        _onSessionExpired();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _dio.close(force: true);
}
