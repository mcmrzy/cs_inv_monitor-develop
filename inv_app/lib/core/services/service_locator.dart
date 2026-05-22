import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
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
import 'package:inv_app/features/alarm/data/datasources/alarm_remote_data_source.dart';
import 'package:inv_app/features/alarm/data/repositories/alarm_repository_impl.dart';
import 'package:inv_app/features/alarm/domain/repositories/alarm_repository.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/statistics/data/datasources/statistics_remote_data_source.dart';
import 'package:inv_app/features/statistics/data/repositories/statistics_repository_impl.dart';
import 'package:inv_app/features/statistics/domain/repositories/statistics_repository.dart';
import 'package:inv_app/features/statistics/presentation/bloc/statistics_bloc.dart';
import 'package:get_it/get_it.dart';

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

    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    getIt.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);

    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
      sendTimeout: const Duration(milliseconds: AppConfig.sendTimeout),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getIt<StorageService>().getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          getIt<AuthBloc>().add(AuthLogoutRequested());
        }
        return handler.next(error);
      },
    ));

    dio.interceptors.add(PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      error: true,
      compact: true,
    ));

    getIt.registerLazySingleton<Dio>(() => dio);
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

    getIt.registerLazySingleton<AlarmRemoteDataSource>(
      () => AlarmRemoteDataSourceImpl(getIt()),
    );

    getIt.registerLazySingleton<StatisticsRemoteDataSource>(
      () => StatisticsRemoteDataSourceImpl(getIt()),
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

    getIt.registerLazySingleton<AlarmRepository>(
      () => AlarmRepositoryImpl(getIt()),
    );

    getIt.registerLazySingleton<StatisticsRepository>(
      () => StatisticsRepositoryImpl(getIt()),
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
        storageService: getIt(),
        mqttService: getIt(),
      ),
    );

    getIt.registerFactory(
      () => StationBloc(repository: getIt()),
    );

    getIt.registerFactory(
      () => DeviceBloc(repository: getIt(), mqttService: getIt()),
    );

    getIt.registerFactory(
      () => AlarmBloc(repository: getIt()),
    );

    getIt.registerFactory(
      () => StatisticsBloc(repository: getIt()),
    );
  }
}
