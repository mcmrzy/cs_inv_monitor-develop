// 幽灵 bloc 回归测试。
//
// 背景：service_locator.dart 中 AuthBloc 曾注册为 registerFactory，
// Dio 拦截器 / ServiceLocator.refreshAccessToken 在 401 时通过
// getIt<AuthBloc>().add(AuthLogoutRequested) 派发登出，而 main.dart 的
// BlocProvider(create: (_) => getIt<AuthBloc>()) + BlocListener 监听的是
// 另一个全新实例（幽灵 bloc）——token 已清但页面永远不跳登录页。
//
// 修复后 AuthBloc 注册为 registerLazySingleton，拦截器与 UI 共享同一实例。
//
// 无法在单测中直接调用 ServiceLocator.init()（依赖 SharedPreferences /
// secure storage / 平台插件），这里按 _initBloc 完全相同的注册方式
// （registerLazySingleton + 全量依赖注入）复刻最小注册链验证：
//   1. getIt 解析 AuthBloc 恒为同一实例（若回退为 registerFactory 此断言失败）；
//   2. 通过 getIt 解析引用派发 AuthLogoutRequested（模拟拦截器），
//      独立监听者（模拟 main.dart BlocListener）能收到 AuthUnauthenticated。

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/jpush_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mock_providers.dart';

void main() {
  late MockStorageService storageService;
  late MockJPushService jpushService;
  late MockLogoutUseCase logoutUseCase;
  final closedBlocs = <AuthBloc>[];

  AuthBloc buildAuthBloc() {
    final bloc = AuthBloc(
      loginUseCase: MockLoginUseCase(),
      registerUseCase: MockRegisterUseCase(),
      logoutUseCase: logoutUseCase,
      sendCodeUseCase: MockSendCodeUseCase(),
      resetPasswordUseCase: MockResetPasswordUseCase(),
      changePasswordUseCase: MockChangePasswordUseCase(),
      getProfileUseCase: MockGetProfileUseCase(),
      updateProfileUseCase: MockUpdateProfileUseCase(),
      emailLoginUseCase: MockEmailLoginUseCase(),
      phoneCodeLoginUseCase: MockPhoneCodeLoginUseCase(),
      emailCodeLoginUseCase: MockEmailCodeLoginUseCase(),
      emailRegisterUseCase: MockEmailRegisterUseCase(),
      sendEmailCodeUseCase: MockSendEmailCodeUseCase(),
      refreshTokenUseCase: MockRefreshTokenUseCase(),
      wechatLoginUseCase: MockWechatLoginUseCase(),
      googleLoginUseCase: MockGoogleLoginUseCase(),
      jverifyLoginUseCase: MockJVerifyLoginUseCase(),
      storageService: storageService,
      jpushService: jpushService,
    );
    closedBlocs.add(bloc);
    return bloc;
  }

  setUp(() async {
    // 登出处理链中 AuthBloc 还会触达其他 getIt 服务（本地快照/BLE 等），
    // 未注册时抛出的异常都被 handler 内 try/catch 吞掉，无需真实注册
    await getIt.reset();
    storageService = MockStorageService();
    jpushService = MockJPushService();
    logoutUseCase = MockLogoutUseCase();

    // 依赖注册方式与 ServiceLocator._initCoreServices 中对应项一致
    getIt.registerLazySingleton<StorageService>(() => storageService);
    getIt.registerLazySingleton<JPushService>(() => jpushService);

    // 与 ServiceLocator._initBloc 相同：registerLazySingleton 注册 AuthBloc
    getIt.registerLazySingleton<AuthBloc>(buildAuthBloc);
  });

  tearDown(() async {
    for (final bloc in closedBlocs) {
      await bloc.close();
    }
    closedBlocs.clear();
    await getIt.reset();
  });

  test('getIt resolves AuthBloc to the same instance on every lookup', () {
    final viaFirstLookup = getIt<AuthBloc>();
    final viaSecondLookup = getIt<AuthBloc>();

    // 拦截器（getIt<AuthBloc>()）与 main.dart BlocProvider create 必须
    // 拿到同一个实例，否则登出事件落入无人监听的幽灵 bloc
    expect(identical(viaFirstLookup, viaSecondLookup), isTrue);
  });

  test(
    'logout dispatched via getIt-resolved instance is observed by a listener '
    'of the same instance (interceptor -> shared bloc -> UI)',
    () async {
      // 登出链路 stub：云端登出成功 + 本地存储清理
      when(() => logoutUseCase())
          .thenAnswer((_) async => right<Failure, void>(null));
      when(() => storageService.deleteToken()).thenAnswer((_) async {});
      when(() => storageService.deleteRefreshToken()).thenAnswer((_) async {});
      when(() => storageService.deleteUserId()).thenAnswer((_) async {});
      when(() => storageService.deleteUserPhone()).thenAnswer((_) async {});
      when(() => storageService.deleteIsSystemAdmin())
          .thenAnswer((_) async {});
      when(() => storageService.deletePermissions()).thenAnswer((_) async {});
      when(() => storageService.saveString(any(), any()))
          .thenAnswer((_) async {});
      when(() => storageService.deleteActiveOrgId()).thenAnswer((_) async {});
      when(() => storageService.deleteActiveOrgName())
          .thenAnswer((_) async {});
      when(() => storageService.deleteStationCache()).thenAnswer((_) async {});
      when(() => jpushService.unbindUser()).thenAnswer((_) async {});

      // UI 侧监听：模拟 main.dart BlocListener 持有的订阅
      final uiBloc = getIt<AuthBloc>();
      final unauthenticatedVisible = uiBloc.stream
          .firstWhere((state) => state is AuthUnauthenticated);

      // 拦截器侧派发：通过 getIt 解析（不持有 UI 引用），与
      // refreshAccessToken / Dio onError 中的写法一致
      getIt<AuthBloc>().add(AuthLogoutRequested());

      // 状态流转对 UI 可见：AuthUnauthenticated 触发跳转登录页
      await unauthenticatedVisible.timeout(const Duration(seconds: 5));
      expect(identical(getIt<AuthBloc>(), uiBloc), isTrue);
    },
  );
}
