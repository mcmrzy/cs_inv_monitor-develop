import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/captcha_service.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_binding_service.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/ble/ble_polling_service.dart';
import 'package:inv_app/core/network/api_client.dart';
import 'package:inv_app/core/network/retry_request_options.dart';
import 'package:inv_app/core/auth/organization_context_session_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/data/local_cache_database.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/notification_service.dart';
import 'package:inv_app/features/profile/data/notify_prefs_service.dart';
import 'package:inv_app/core/services/firmware_download_service.dart';
import 'package:inv_app/core/services/local_communication_service.dart';
import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/offline/offline_log_api.dart';
import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/offline/offline_op_log_store.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/deep_link_service.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/services/theme_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/jpush_service.dart';
import 'package:inv_app/core/services/jverify_service.dart';
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
import 'package:inv_app/features/ota/data/datasources/local_ota_result_sync_queue.dart';
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
          final token = normalizeTokenValue(
            await getIt<StorageService>().getToken(),
          );
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            if (isTokenRefreshRetry(error.requestOptions)) {
              return handler.next(error);
            }

            // 未携带 token 的请求（如离网 guest 模式误碰云端接口）必然 401：
            // 直接透传错误由业务层展示离线态，不触发刷新/登出链路
            // （登出会连带退出 guest 本地模式，导致用户被踢回登录页）
            if (!error.requestOptions.headers.containsKey('Authorization')) {
              return handler.next(error);
            }
            if (error.requestOptions.path == '/auth/refresh') {
              getIt<AuthBloc>().add(AuthLogoutRequested());
              return handler.next(error);
            }

            // 上下文切换请求自身携带 refresh token，并由事务服务负责处理；
            // 401 时不能触发通用刷新，否则会额外轮换旧上下文令牌。
            if (error.requestOptions.path == '/auth/context') {
              return handler.next(error);
            }

            if (error.requestOptions.path == '/auth/logout') {
              return handler.next(error);
            }

            // 刷新 access token（内部处理并发锁；失败时已触发登出）
            final refreshed = await refreshAccessToken();
            if (!refreshed) {
              return handler.next(error);
            }

            final storageService = getIt<StorageService>();
            final newToken = normalizeTokenValue(
              await storageService.getToken(),
            );
            if (newToken == null) {
              return handler.next(error);
            }

            final retryOptions = buildTokenRefreshRetryOptions(
              error.requestOptions,
              accessToken: newToken,
            );

            try {
              final retryResponse = await dio.fetch(retryOptions);
              return handler.resolve(retryResponse);
            } catch (e) {
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
          requestHeader: false,
          requestBody: false,
          responseBody: false,
          responseHeader: false,
          error: false,
          compact: true,
        ),
      );
    }

    getIt.registerLazySingleton<Dio>(() => dio);
  }

  static bool _tokenRefreshLock = false;
  static Completer<bool>? _refreshCompleter;

  /// 刷新 access token（Dio 拦截器与 SSE 等非 Dio 请求共用）。
  /// 返回 true 表示刷新成功且新 token 已保存；false 表示刷新失败（已触发登出）。
  static Future<bool> refreshAccessToken() async {
    if (_tokenRefreshLock) {
      _refreshCompleter ??= Completer<bool>();
      return _refreshCompleter!.future;
    }

    _tokenRefreshLock = true;
    _refreshCompleter ??= Completer<bool>();
    try {
      final storageService = getIt<StorageService>();
      final refreshToken = normalizeTokenValue(
        await storageService.getRefreshToken(),
      );

      if (refreshToken == null) {
        _finishTokenRefresh(false);
        getIt<AuthBloc>().add(AuthLogoutRequested());
        return false;
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

      final normalizedNewToken = normalizeTokenValue(newToken);
      final normalizedNewRefreshToken = normalizeTokenValue(newRefreshToken);
      if (normalizedNewToken != null) {
        await storageService.saveToken(normalizedNewToken);
        if (normalizedNewRefreshToken != null) {
          await storageService.saveRefreshToken(normalizedNewRefreshToken);
        }
        _finishTokenRefresh(true);
        return true;
      }

      _finishTokenRefresh(false);
      getIt<AuthBloc>().add(AuthLogoutRequested());
      return false;
    } catch (e) {
      _finishTokenRefresh(false);
      getIt<AuthBloc>().add(AuthLogoutRequested());
      return false;
    }
  }

  static void _finishTokenRefresh(bool success) {
    _tokenRefreshLock = false;
    _refreshCompleter?.complete(success);
    _refreshCompleter = null;
  }

  static void _initCoreServices() {
    getIt.registerLazySingleton<StorageService>(
      () => StorageServiceImpl(getIt(), getIt()),
    );

    getIt.registerLazySingleton<ApiService>(
      () => ApiService(getIt()),
    );

    getIt.registerLazySingleton<CaptchaService>(
      () => CaptchaService(getIt()),
    );

    getIt.registerLazySingleton<ApiClient>(
      () => ApiClient(getIt()),
    );

    // RealtimeDataService: 通过 API 轮询获取实时数据（App 不直连 MQTT）
    getIt.registerLazySingleton<RealtimeDataService>(
      () => RealtimeDataServiceImpl(),
      dispose: (service) => (service as RealtimeDataServiceImpl).dispose(),
    );

    getIt.registerLazySingleton<NotificationService>(
      () => NotificationService(),
    );

getIt.registerLazySingleton<NotifyPrefsService>(
      () => NotifyPrefsService(getIt(), getIt()),
    );

    getIt.registerLazySingleton<LocalCommunicationService>(
      () => LocalCommunicationService(),
    );

    getIt.registerLazySingleton<ConnectionModeService>(
      () => ConnectionModeService(
        getIt(),
        networkStatusService: getIt<NetworkStatusService>(),
      ),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<LocalCacheDatabase>(
      () => LocalCacheDatabase(),
    );

    getIt.registerLazySingleton<NetworkStatusService>(
      () => NetworkStatusService(connectivity: Connectivity()),
      dispose: (service) => service.dispose(),
    );

    // ---- BLE 直连设备模式：基础设施（适配器 / key 存储 / 设备管理器）----
    getIt.registerLazySingleton<BleDeviceKeyStore>(
      () => SecureStorageBleDeviceKeyStore(getIt<FlutterSecureStorage>()),
    );

    getIt.registerLazySingleton<BleAdapter>(() => FlutterBlueUltraAdapter());

    // 注意：BleDeviceManager 实际无 dispose() 方法，注册不带 dispose 回调；
    // 会话清理由 BleDirectService.dispose → manager.disconnectAll() 负责。
    getIt.registerLazySingleton<BleDeviceManager>(
      () => BleDeviceManager(
        adapter: getIt<BleAdapter>(),
        keyStore: getIt<BleDeviceKeyStore>(),
      ),
    );

    // ---- BLE 直连设备模式：离线操作日志（存储 / API / 同步）----
    getIt.registerLazySingleton<OfflineOpLogStore>(
      () => OfflineOpLogStore(),
    );

    getIt.registerLazySingleton<OfflineLogApi>(
      () => DioOfflineLogApi(getIt<Dio>()),
    );

    getIt.registerLazySingleton<OfflineLogSyncService>(
      () => OfflineLogSyncService(
        store: getIt<OfflineOpLogStore>(),
        api: getIt<OfflineLogApi>(),
        networkStatus: getIt<NetworkStatusService>(),
      ),
      dispose: (service) => service.dispose(),
    );

    // ---- BLE 直连设备模式：绑定 / 轮询 / 直连总开关 ----
    getIt.registerLazySingleton<BleBindingService>(
      () => BleBindingService(
        manager: getIt<BleDeviceManager>(),
        dio: getIt<Dio>(),
        keyStore: getIt<BleDeviceKeyStore>(),
        logStore: getIt<OfflineOpLogStore>(),
      ),
    );

    getIt.registerLazySingleton<BlePollingService>(
      () => BlePollingService(manager: getIt<BleDeviceManager>()),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<BleDirectService>(
      () => BleDirectService(
        adapter: getIt<BleAdapter>(),
        manager: getIt<BleDeviceManager>(),
        polling: getIt<BlePollingService>(),
        storage: getIt<StorageService>(),
      ),
    );

    getIt.registerLazySingleton<DataCacheService>(
      () => DataCacheService(getIt()),
    );

    getIt.registerLazySingleton<LocaleService>(
      () => LocaleService(getIt()),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<ThemeService>(
      () => ThemeService(getIt()),
      dispose: (service) => service.dispose(),
    );

    getIt.registerLazySingleton<AppUpdateService>(
      () => AppUpdateService(getIt()),
    );

    getIt.registerLazySingleton<JPushService>(
      () => JPushService(),
    );

    getIt.registerLazySingleton<JVerifyService>(
      () => JVerifyService(),
    );

    getIt.registerLazySingleton<DeepLinkService>(
      () => DeepLinkService(),
    );

    // 固件下载：应用级单例（并发守卫/进度流需跨页面共享，
    // 页面各自实例化会让守卫形同虚设）
    getIt.registerLazySingleton<FirmwareDownloadService>(
      () => FirmwareDownloadService(getIt<Dio>(), getIt()),
      dispose: (service) => service.dispose(),
    );

    // 本地 OTA 升级结果的云端同步队列（失败重试，跨启动持久化）
    getIt.registerLazySingleton<LocalOtaResultSyncQueue>(
      () => LocalOtaResultSyncQueue(
        repository: getIt<OtaRepository>(),
        sharedPreferences: getIt(),
        networkStatus: getIt<NetworkStatusService>(),
      ),
      dispose: (service) => service.dispose(),
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
      () => DeviceRepositoryImpl(getIt()),
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
    getIt.registerLazySingleton<OrganizationContextSessionService>(
      () => OrganizationContextSessionService(getIt(), getIt()),
    );
    getIt.registerLazySingleton(() => LoginUseCase(getIt()));
    getIt.registerLazySingleton(() => RegisterUseCase(getIt()));
    getIt.registerLazySingleton(() => LogoutUseCase(getIt()));
    getIt.registerLazySingleton(() => SendCodeUseCase(getIt()));
    getIt.registerLazySingleton(() => ResetPasswordUseCase(getIt()));
    getIt.registerLazySingleton(() => ChangePasswordUseCase(getIt()));
    getIt.registerLazySingleton(() => GetProfileUseCase(getIt()));
    getIt.registerLazySingleton(() => UpdateProfileUseCase(getIt()));
    getIt.registerLazySingleton(() => EmailLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => PhoneCodeLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => EmailCodeLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => EmailRegisterUseCase(getIt()));
    getIt.registerLazySingleton(() => SendEmailCodeUseCase(getIt()));
    getIt.registerLazySingleton(() => RefreshTokenUseCase(getIt()));
    getIt.registerLazySingleton(() => WechatLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => GoogleLoginUseCase(getIt()));
    getIt.registerLazySingleton(() => JVerifyLoginUseCase(getIt()));
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
        phoneCodeLoginUseCase: getIt(),
        emailCodeLoginUseCase: getIt(),
        emailRegisterUseCase: getIt(),
        sendEmailCodeUseCase: getIt(),
        refreshTokenUseCase: getIt(),
        wechatLoginUseCase: getIt(),
        googleLoginUseCase: getIt(),
        jverifyLoginUseCase: getIt(),
        storageService: getIt(),
        jpushService: getIt(),
        organizationContextSessionService: getIt(),
      ),
    );

    getIt.registerFactory(
      () => StationBloc(
        repository: getIt(),
        storageService: getIt(),
        dataCacheService: getIt(),
        connectionModeService: getIt(),
        localCache: getIt(),
      ),
    );

    getIt.registerFactory(
      () => DeviceBloc(
        repository: getIt(),
        realtimeDataService: getIt(),
        localCommunicationService: getIt(),
        connectionModeService: getIt(),
        dataCacheService: getIt(),
        localCache: getIt(),
      ),
    );

    getIt.registerFactory(
      () => AlarmBloc(
        repository: getIt(),
        dataCacheService: getIt(),
        realtimeDataService: getIt(),
      ),
    );

    getIt.registerFactory(
      () => NotificationBloc(
        deviceRepository: getIt(),
        realtimeDataService: getIt(),
        notificationDataSource: getIt(),
      ),
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
