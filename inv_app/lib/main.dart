import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/services/offline/offline_log_sync_service.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/core/router/app_router.dart';
import 'package:inv_app/core/services/jpush_service.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/deep_link_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/data/china_regions.dart';
import 'package:inv_app/core/data/regions_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await ServiceLocator.init();
  
  // 初始化地区数据
  initChinaRegions();
  initGlobalRegions();

  // 提前创建 NotificationBloc 实例，用于接收 JPush 事件
  final notificationBloc = getIt<NotificationBloc>();
  getIt<JPushService>().onNotificationReceived = (notification) {
    notificationBloc.add(
      JPushNotificationReceived(
        notifyType: notification.notifyType,
        deviceSn: notification.deviceSn,
        title: notification.title,
        content: notification.content,
      ),
    );
  };
  getIt<JPushService>().onNotificationOpened = (notification) {
    notificationBloc.add(
      JPushNotificationTapped(
        notifyType: notification.notifyType,
        deviceSn: notification.deviceSn,
      ),
    );
  };

  runApp(InvApp(notificationBloc: notificationBloc));

  // 网络状态服务初始化：默认乐观在线，启动瞬间不误判离线
  unawaited(getIt<NetworkStatusService>().initialize());

  // 极光推送/认证 SDK 初始化改为首帧渲染后异步执行，
  // 不阻塞冷启动（一键登录的完整性由 SplashPage 的轮询兑底保证）
  unawaited(_initPushSdks());

  // BLE 直连恢复 + 离线日志同步（首帧渲染后异步执行，不阻塞冷启动）
  unawaited(_restoreBleServices());

  // 智能链接 Deep Link：冷启动 + 热启动接收 csinv://bind
  unawaited(_initDeepLinks());
}

Future<void> _restoreBleServices() async {
  try {
    // 恢复 BLE 直连模式（设置开关为开时）
    final storage = getIt<StorageService>();
    if (await storage.getIsBleDirectEnabled()) {
      await getIt<BleDirectService>().restore();
    }
    // 启动离线操作日志同步（监听网络状态，自动退避重试）
    await getIt<OfflineLogSyncService>().start();
  } catch (e) {
    debugPrint('BLE restore failed: $e');
  }
}

/// 最近一次已处理的绑定链接去重键（app_links 冷启动/热启动可能重复投递同一链接）
String? _lastHandledLinkKey;

Future<void> _initDeepLinks() async {
  final service = getIt<DeepLinkService>();

  void handle(BindLink? link) {
    if (link == null) return;
    // 同一链接（sn|pin）只触发一次跳转，避免冷启动/热启动重复 push
    if (_lastHandledLinkKey == link.dedupeKey) return;
    _lastHandledLinkKey = link.dedupeKey;
    AppRouter.router.push('/device/qr-bind?sn=${link.sn}&pin=${link.pin}');
  }

  // 冷启动：等首帧后再跳转，避免路由未就绪
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    handle(await service.getInitialLink());
  });

  // 热启动：运行中收到链接立即处理
  service.linkStream.listen(handle);
}

Future<void> _initPushSdks() async {
  // 初始化极光推送（在依赖注入完成后）
  try {
    await getIt<JPushService>().init();
  } catch (e) {
    debugPrint('JPush init failed: $e');
  }

  // 初始化极光认证（一键登录）
  try {
    await getIt<JVerifyService>().init();
  } catch (e) {
    debugPrint('JVerify init failed: $e');
  }
}

class InvApp extends StatefulWidget {
  final NotificationBloc notificationBloc;

  const InvApp({super.key, required this.notificationBloc});

  @override
  State<InvApp> createState() => _InvAppState();
}

class _InvAppState extends State<InvApp> {
  Locale _currentLocale = const Locale('zh', 'CN');
  StreamSubscription<Locale>? _localeSubscription;

  @override
  void initState() {
    super.initState();
    _currentLocale = getIt<LocaleService>().currentLocale;
    _localeSubscription = getIt<LocaleService>().localeStream.listen((locale) {
      if (mounted) {
        setState(() {
          _currentLocale = locale;
        });
      }
    });
  }

  @override
  void dispose() {
    _localeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // AuthBloc 立即创建（登录状态检查由 SplashPage 触发，避免重复检查）
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>(),
        ),
        // 以下 Bloc 使用懒加载，只在首次访问时创建
        BlocProvider<StationBloc>(
          lazy: true,
          create: (_) => getIt<StationBloc>(),
        ),
        BlocProvider<DeviceBloc>(
          lazy: true,
          create: (_) => getIt<DeviceBloc>(),
        ),
        BlocProvider<AlarmBloc>(
          lazy: true,
          create: (_) => getIt<AlarmBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          lazy: true,
          create: (_) => widget.notificationBloc,
        ),
        BlocProvider<DashboardBloc>(
          lazy: true,
          create: (_) => getIt<DashboardBloc>(),
        ),
      ],
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUnauthenticated) {
            // Splash 页自行处理未登录分流（一键登录/登录页）；
            // 此处仅兜底登出/Token 过期等场景
            final currentPath = GoRouterState.of(context).matchedLocation;
            if (currentPath != '/splash' &&
                currentPath != '/jverify-login' &&
                currentPath != '/login') {
              AppRouter.router.go('/login');
            }
          }
        },
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) {
            return MaterialApp.router(
              onGenerateTitle: (context) =>
                  AppLocalizations.of(context)?.brandName ?? AppConfig.appName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.system,
              routerConfig: AppRouter.router,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              locale: _currentLocale,
              builder: (context, widget) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: widget!,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
