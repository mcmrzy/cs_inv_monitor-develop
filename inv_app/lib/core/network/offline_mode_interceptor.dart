import 'package:dio/dio.dart';
import 'package:inv_app/core/services/storage_service.dart';

/// Stops cloud API requests while the user explicitly selects offline mode.
class OfflineModeInterceptor extends Interceptor {
  OfflineModeInterceptor(this.storage);
  final StorageService storage;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      if (await storage.getIsOfflineMode()) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'OFFLINE_MODE',
            message: 'Offline mode is active. Use a local device connection.',
          ),
        );
        return;
      }
      handler.next(options);
    } catch (error) {
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }
}
