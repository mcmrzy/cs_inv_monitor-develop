import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/notification_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/offline_cache_service.dart';
import 'package:inv_app/core/services/offline_sync_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/jpush_service.dart';
import 'package:inv_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:inv_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:inv_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:inv_app/features/auth/domain/usecases/login.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/station/data/datasources/station_remote_data_source.dart';
import 'package:inv_app/features/station/data/repositories/station_repository_impl.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/device/data/datasources/device_remote_data_source.dart';
import 'package:inv_app/features/device/data/repositories/device_repository_impl.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/device_protocol/data/datasources/device_protocol_remote_data_source.dart';
import 'package:inv_app/features/device_protocol/data/repositories/device_protocol_repository_impl.dart';
import 'package:inv_app/features/device_protocol/domain/repositories/device_protocol_repository.dart';
import 'package:inv_app/features/alarm/data/datasources/alarm_remote_data_source.dart';
import 'package:inv_app/features/alarm/data/repositories/alarm_repository_impl.dart';
import 'package:inv_app/features/alarm/domain/repositories/alarm_repository.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/data/datasources/notification_remote_data_source.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_remote_data_source.dart';
import 'package:inv_app/features/dashboard/data/datasources/dashboard_sse_data_source.dart';
import 'package:inv_app/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:inv_app/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/features/ota/data/datasources/ota_remote_data_source.dart';
import 'package:inv_app/features/ota/data/repositories/ota_repository_impl.dart';
import 'package:inv_app/features/ota/domain/repositories/ota_repository.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

final getIt = GetIt.instance;

class ServiceLocator {
  static Future<void> init() async {
    await _initExternalDependencies();
    _initCoreServices();
    _initDataSources();
    _initRepositories();
    _initUseCases();
    _initBloc();
  }

  static Future<void> _initExternalDependencies() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    getIt.registerLazySingleton<SharedPreferences>(() => sharedPreferences);

    // 启动时清理可能存在的破旧 serverUrl，确保 Dio 始终使用最新的 AppConfig.apiBaseUrl
    final savedUrl = sharedPreferences.getString('server_url');
    if (savedUrl != null && savedUrl != AppConfig.apiBaseUrl) {
      // 清除与 AppConfig 不同的破旧值（如缺少端口的旧 URL）
      // 用户如果需要自定义 URL，可以在设置页重新设置
      await sharedPreferences.remove('server_url');
    }

    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    getIt.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
        sendTimeout: const Duration(milliseconds: AppConfig.sendTimeout),
      ),
    );

    // 拦截器1：Token 注入 + 自动刷新
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getIt<StorageService>().getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            if (error.requestOptions.path == '/auth/refresh') {
              getIt<AuthBloc>().add(AuthLogoutRequested());
              return handler.next(error);
            }

            if (error.requestOptions.path == '/auth/logout') {
              return handler.next(error);
            }

            if (_tokenRefreshLock) {
              return _waitForRefresh(error, handler);
            }

            _tokenRefreshLock = true;
            try {
              final storageService = getIt<StorageService>();
              final refreshToken = await storageService.getRefreshToken();

              if (refreshToken == null) {
                _tokenRefreshLock = false;
                _refreshCompleter?.complete(false);
                _refreshCompleter = null;
                getIt<AuthBloc>().add(AuthLogoutRequested());
                return handler.next(error);
              }

              final refreshDio = Dio(
                BaseOptions(
                  baseUrl: AppConfig.apiBaseUrl,
                  connectTimeout:
                      const Duration(milliseconds: AppConfig.connectTimeout),
                  receiveTimeout:
                      const Duration(milliseconds: AppConfig.receiveTimeout),
                ),
              );

              final refreshResponse = await refreshDio.post(
                '/auth/refresh',
                data: {'refresh_token': refreshToken},
              );

              final responseData = refreshResponse.data;
              String? newToken;
              String? newRefreshToken;

              if (responseData is Map<String, dynamic>) {
                if (responseData['code'] == 0 && responseData['data'] != null) {
                  final data = responseData['data'] as Map<String, dynamic>;
                  newToken = (data['access_token'] ??
                      data['token'] ??
                      data['accessToken']) as String?;
                  newRefreshToken = (data['refresh_token'] ??
                      data['refreshToken']) as String?;
                } else if (responseData['access_token'] != null ||
                    responseData['token'] != null) {
                  newToken = (responseData['access_token'] ??
                      responseData['token'] ??
                      responseData['accessToken']) as String?;
                  newRefreshToken = (responseData['refresh_token'] ??
                      responseData['refreshToken']) as String?;
                }
              }

              if (newToken != null) {
                await storageService.saveToken(newToken);
                if (newRefreshToken != null) {
                  await storageService.saveRefreshToken(newRefreshToken);
                }

                _tokenRefreshLock = false;
                _refreshCompleter?.complete(true);
                _refreshCompleter = null;

                final opts = Options(
                  method: error.requestOptions.method,
                  headers: {
                    ...error.requestOptions.headers,
                    'Authorization': 'Bearer $newToken',
                  },
                );

                final retryResponse = await dio.fetch(
                  RequestOptions(
                    path: error.requestOptions.path,
                    data: error.requestOptions.data,
                    queryParameters: error.requestOptions.queryParameters,
                    headers: opts.headers,
                    method: opts.method,
                    baseUrl: error.requestOptions.baseUrl,
                    connectTimeout: error.requestOptions.connectTimeout,
                    receiveTimeout: error.requestOptions.receiveTimeout,
                    sendTimeout: error.requestOptions.sendTimeout,
                  ),
                );
                return handler.resolve(retryResponse);
              } else {
                _tokenRefreshLock = false;
                _refreshCompleter?.complete(false);
                _refreshCompleter = null;
                getIt<AuthBloc>().add(AuthLogoutRequested());
                return handler.next(error);
              }
            } catch (e) {
              _tokenRefreshLock = false;
              _refreshCompleter?.complete(false);
              _refreshCompleter = null;
              getIt<AuthBloc>().add(AuthLogoutRequested());
              return handler.next(error);
            }
          }
          return handler.next(error);
        },
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
        ),
      );
    }

    getIt.registerLazySingleton<Dio>(() => dio);
  }

  static bool _tokenRefreshLock = false;
  static Completer<bool>? _refreshCompleter;

  static Future<void> _waitForRefresh(
      DioException error, ErrorInterceptorHandler handler) async {
    _refreshCompleter ??= Completer<bool>();
    final success = await _refreshCompleter!.future;
    if (success) {
      final storageService = getIt<StorageService>();
      final newToken = await storageService.getToken();
      final opts = Options(
        method: error.requestOptions.method,
        headers: {
          ...error.requestOptions.headers,
          'Authorization': 'Bearer $newToken',
        },
      );
      try {
        final retryResponse = await getIt<Dio>().fetch(
          RequestOptions(
            path: error.requestOptions.path,
            data: error.requestOptions.data,
            queryParameters: error.requestOptions.queryParameters,
            headers: opts.headers,
            method: opts.method,
            baseUrl: error.requestOptions.baseUrl,
            connectTimeout: error.requestOptions.connectTimeout,
            receiveTimeout: error.requestOptions.receiveTimeout,
            sendTimeout: error.requestOptions.sendTimeout,
          ),
        );
        return handler.resolve(retryResponse);
      } catch (e) {
        return handler.next(error);
      }
    } else {
      return handler.next(error);
    }
  }

  static void _initCoreServices() {
    getIt.registerLazySingleton<StorageService>(
      () => StorageServiceImpl(getIt(), getIt()),
    );

    getIt.registerLazySingleton<ApiService>(
      () => ApiServiceImpl(getIt()),
    );

    getIt.registerLazySingleton<MQTTService>(
      () => MQTTServiceImpl(),
      dispose: (service) => (service as MQTTServiceImpl).dispose(),
    );

    getIt.registerLazySingleton<NotificationService>(
      () => NotificationService(),
    );

    getIt.registerLazySingleton<LocalCommunicationService>(
      () => LocalCommunicationService(),
    );

    getIt.registerLazySingleton<ConnectionModeService>(
      () => ConnectionModeService(getIt()),
    );

    getIt.registerLazySingleton<OfflineCacheService>(
      () => OfflineCacheService(getIt()),
    );

    getIt.registerLazySingleton<DataCacheService>(
      () => DataCacheService(getIt()),
    );

    getIt.registerLazySingleton<OfflineSyncService>(
      () => OfflineSyncService(
        cacheService: getIt(),
        apiService: getIt(),
        connectivity: Connectivity(),
      ),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<LocaleService>(
      () => LocaleService(getIt()),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<AppUpdateService>(
      () => AppUpdateService(getIt()),
    );

    getIt.registerLazySingleton<JPushService>(
      () => JPushService(),
    );
  }

  static void _initDataSources() {
    getIt.registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<StationRemoteDataSource>(
      () => StationRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<DeviceRemoteDataSource>(
      () => DeviceRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<DeviceProtocolRemoteDataSource>(
      () => DeviceProtocolRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<AlarmRemoteDataSource>(
      () => AlarmRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSource(getIt()),
    );

    getIt.registerLazySingleton<DashboardRemoteDataSource>(
      () => DashboardRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<DashboardSSEDataSource>(
      () => DashboardSSEDataSource(getIt()),
    );

    getIt.registerLazySingleton<OtaRemoteDataSource>(
      () => OtaRemoteDataSourceImpl(getIt()),
    );
  }

  static void _initRepositories() {
    getIt.registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(getIt(), getIt()),
    );

    getIt.registerLazySingleton<StationRepository>(
      () => StationRepositoryImpl(getIt()),
    );

    getIt.registerLazySingleton<DeviceRepository>(
      () => DeviceRepositoryImpl(getIt(), getIt()),
    );

    getIt.registerLazySingleton<DeviceProtocolRepository>(
      () => DeviceProtocolRepositoryImpl(getIt(), getIt()),
    );

    getIt.registerLazySingleton<AlarmRepository>(
      () => AlarmRepositoryImpl(getIt()),
    );

    getIt.registerLazySingleton<DashboardRepository>(
      () => DashboardRepositoryImpl(getIt()),
    );

    getIt.registerLazySingleton<OtaRepository>(
      () => OtaRepositoryImpl(getIt()),
    );
  }

  static void _initUseCases() {
    getIt.registerLazySingleton(() => LoginUseCase(getIt()));
    getIt.registerLazySingleton(() => RegisterUseCase(getIt()));
    getIt.registerLazySingleton(() => LogoutUseCase(getIt()));
    getIt.registerLazySingleton(() => SendCodeUseCase(getIt()));
    getIt.registerLazySingleton(() => ResetPasswordUseCase(getIt()));
    getIt.registerLazySingleton(() => ChangePasswordUseCase(getIt()));
    getIt.registerLazySingleton(() => GetProfileUseCase(getIt()));
    getIt.registerLazySingleton(() => UpdateProfileUseCase(getIt()));
    getIt.registerLazySingleton(() => EmailLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => EmailRegisterUseCase(getIt()));
    getIt.registerLazySingleton(() => SendEmailCodeUseCase(getIt()));
    getIt.registerLazySingleton(() => RefreshTokenUseCase(getIt()));
    getIt.registerLazySingleton(() => WechatLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => GoogleLoginUseCase(getIt()));
  }

  static void _initBloc() {
    getIt.registerFactory(
      () => AuthBloc(
        loginUseCase: getIt(),
        registerUseCase: getIt(),
        logoutUseCase: getIt(),
        sendCodeUseCase: getIt(),
        resetPasswordUseCase: getIt(),
        changePasswordUseCase: getIt(),
        getProfileUseCase: getIt(),
        updateProfileUseCase: getIt(),
        emailLoginUseCase: getIt(),
        emailRegisterUseCase: getIt(),
        sendEmailCodeUseCase: getIt(),
        refreshTokenUseCase: getIt(),
        wechatLoginUseCase: getIt(),
        googleLoginUseCase: getIt(),
        storageService: getIt(),
        mqttService: getIt(),
        jpushService: getIt(),
      ),
    );

    getIt.registerFactory(
      () => StationBloc(
          repository: getIt(),
          storageService: getIt(),
          dataCacheService: getIt()),
    );

    getIt.registerFactory(
      () => DeviceBloc(
        repository: getIt(),
        mqttService: getIt(),
        localCommunicationService: getIt(),
        connectionModeService: getIt(),
        offlineCacheService: getIt(),
        dataCacheService: getIt(),
      ),
    );

    getIt.registerFactory(
      () => AlarmBloc(
          repository: getIt(), dataCacheService: getIt(), mqttService: getIt()),
    );

    getIt.registerFactory(
      () => NotificationBloc(
          deviceRepository: getIt(),
          mqttService: getIt(),
          notificationDataSource: getIt()),
    );

    getIt.registerFactory(
      () => DashboardBloc(
        repository: getIt(),
        dataCacheService: getIt(),
        sseDataSource: getIt(),
      ),
    );

    getIt.registerFactory(
      () => OtaBloc(repository: getIt()),
    );
  }
}
