import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:go_router/go_router.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:inv_app/core/config/app_config.dart';

import 'package:inv_app/core/services/app_update_service.dart';

import 'package:inv_app/core/services/role_service.dart';

import 'package:inv_app/core/theme/app_theme.dart';

import 'package:inv_app/core/theme/csergy_assets.dart';

import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';

import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';

import 'package:inv_app/l10n/app_localizations.dart';

import 'package:inv_app/features/auth/presentation/pages/splash_page.dart';

import 'package:inv_app/features/auth/presentation/pages/auth_page.dart';

import 'package:inv_app/features/auth/presentation/pages/jverify_auth_page.dart';

import 'package:inv_app/features/auth/presentation/pages/forgot_password_page.dart';

import 'package:inv_app/features/station/presentation/pages/home_page.dart';

import 'package:inv_app/features/station/presentation/pages/station_detail_page.dart';

import 'package:inv_app/features/station/presentation/pages/create_station_page.dart';

import 'package:inv_app/features/station/presentation/pages/edit_station_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_realtime_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_op_logs_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_qr_bind_page.dart';

import 'package:inv_app/features/device_protocol/presentation/pages/device_protocol_page.dart';

import 'package:inv_app/features/device/presentation/pages/wifi_config_page.dart';

import 'package:inv_app/features/device/presentation/pages/add_device_page.dart';

import 'package:inv_app/features/dashboard/presentation/pages/dashboard_overview_page.dart';

import 'package:inv_app/features/alarm/presentation/pages/alarm_detail_page.dart';

import 'package:inv_app/features/notification/presentation/pages/notification_center_page.dart';

import 'package:inv_app/features/profile/presentation/pages/profile_page.dart';

import 'package:inv_app/features/profile/presentation/pages/settings_page.dart';

import 'package:inv_app/features/profile/presentation/pages/change_password_page.dart';

import 'package:inv_app/features/profile/presentation/pages/edit_profile_page.dart';

import 'package:inv_app/features/profile/presentation/pages/about_page.dart';

import 'package:inv_app/features/profile/presentation/pages/notify_settings_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_edit_page.dart';

import 'package:inv_app/features/device/presentation/pages/history_chart_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_settings_page.dart';

import 'package:inv_app/features/device/presentation/pages/local_mode_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_detail_page.dart';

import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_tab_page.dart';

import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';

import 'package:inv_app/core/router/guards/auth_guard.dart';

import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';

import 'package:inv_app/features/profile/presentation/widgets/profile_setup_dialog.dart';

import 'package:inv_app/core/services/service_locator.dart';

import 'package:inv_app/core/widgets/device_list_view.dart';

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(begin: const Offset(0.06, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));

      return SlideTransition(
        position: animation.drive(tween),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => _fadePage(state, const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            _fadePage(state, const AuthPage(initialMode: AuthMode.login)),
      ),
      GoRoute(
        path: '/jverify-login',
        name: 'jverifyAuth',
        pageBuilder: (context, state) =>
            _fadePage(state, const JVerifyAuthPage()),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) =>
            _fadePage(state, const AuthPage(initialMode: AuthMode.register)),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        pageBuilder: (context, state) =>
            _slidePage(state, const ForgotPasswordPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/statistics',
            name: 'statistics',
            builder: (context, state) => const DashboardOverviewPage(),
          ),
          GoRoute(
            path: '/alarms',
            name: 'alarms',
            builder: (context, state) => const NotificationCenterPage(),
          ),
          GoRoute(
            path: '/devices',
            name: 'devices',
            builder: (context, state) => const DeviceListPage(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      GoRoute(
        path: '/ota',
        name: 'otaTab',
        pageBuilder: (context, state) => _slidePage(state, const OtaTabPage()),
      ),
      GoRoute(
        path: '/station/create',
        name: 'createStation',
        pageBuilder: (context, state) =>
            _slidePage(state, const CreateStationPage()),
      ),
      GoRoute(
        path: '/station/:id',
        name: 'stationDetail',
        pageBuilder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);

          return _slidePage(state, StationDetailPage(stationId: id));
        },
      ),
      GoRoute(
        path: '/station/:id/edit',
        name: 'editStation',
        pageBuilder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);

          return _slidePage(state, EditStationPage(stationId: id));
        },
      ),
      GoRoute(
        path: '/device/:sn',
        name: 'deviceRealtime',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceRealtimePage(sn: sn, type: 'inv'));
        },
      ),
      GoRoute(
        path: '/device/:sn/control',
        name: 'deviceControl',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceControlPageWrapper(deviceSN: sn));
        },
      ),
      GoRoute(
        path: '/device/:sn/protocol',
        name: 'deviceProtocol',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceProtocolPage(sn: sn));
        },
      ),
      GoRoute(
        path: '/device/:sn/history',
        name: 'deviceHistory',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, HistoryChartPage(deviceSN: sn));
        },
      ),
      GoRoute(
        path: '/device/:sn/settings',
        name: 'deviceSettings',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceSettingsPage(sn: sn));
        },
      ),
      GoRoute(
        path: '/device/op-logs/:sn',
        name: 'deviceOpLogs',
        pageBuilder: (context, state) => _slidePage(
          state,
          DeviceOpLogsPage(sn: state.pathParameters['sn']!),
        ),
      ),
      GoRoute(
        path: '/device/qr-bind',
        name: 'deviceQrBind',
        pageBuilder: (context, state) => _slidePage(
          state,
          DeviceQrBindPage(
            sn: state.uri.queryParameters['sn'] ?? '',
            pin: state.uri.queryParameters['pin'] ?? '',
            stationId: int.tryParse(state.uri.queryParameters['station_id'] ?? ''),
          ),
        ),
      ),
      GoRoute(
        path: '/device/:sn/edit',
        name: 'deviceEdit',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;
          // extra 传设备快照与电站上下文；深链接无 extra 时回退最小快照
          final extra = state.extra as Map<String, dynamic>?;
          final device =
              (extra?['device'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{'sn': sn};
          final stationId = extra?['stationId'] as int?;
          final onEnterSortMode = extra?['onEnterSortMode'] as void Function()?;

          return _slidePage(
            state,
            DeviceEditPage(
              sn: sn,
              device: device,
              stationId: stationId,
              onEnterSortMode: onEnterSortMode,
            ),
          );
        },
      ),
      GoRoute(
        path: '/wifi-config',
        name: 'wifiConfig',
        pageBuilder: (context, state) =>
            _slidePage(state, const WifiConfigPage()),
      ),
      GoRoute(
        path: '/local-mode',
        name: 'localMode',
        pageBuilder: (context, state) =>
            _slidePage(state, const LocalModePage()),
      ),
      GoRoute(
        path: '/local-ota',
        name: 'localOta',
        pageBuilder: (context, state) {
          final sn = state.uri.queryParameters['sn'] ?? '';
          final ip = state.uri.queryParameters['ip'] ?? '';
          return _slidePage(
            state,
            LocalOTAPage(deviceSN: sn, deviceIP: ip),
          );
        },
      ),
      GoRoute(
        path: '/add-device',
        name: 'addDevice',
        pageBuilder: (context, state) {
          final stationId = state.uri.queryParameters['station_id'];

          return _slidePage(
            state,
            AddDevicePage(
              stationId: stationId != null ? int.parse(stationId) : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/alarm/:id',
        name: 'alarmDetail',
        pageBuilder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);

          return _slidePage(state, AlarmDetailPage(alarmId: id));
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) =>
            _slidePage(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/change-password',
        name: 'changePassword',
        pageBuilder: (context, state) =>
            _slidePage(state, const ChangePasswordPage()),
      ),
      GoRoute(
        path: '/edit-profile',
        name: 'editProfile',
        pageBuilder: (context, state) =>
            _slidePage(state, const EditProfilePage()),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        pageBuilder: (context, state) => _slidePage(state, const AboutPage()),
      ),
      GoRoute(
        path: '/notify-settings',
        name: 'notifySettings',
        pageBuilder: (context, state) =>
            _slidePage(state, const NotifySettingsPage()),
      ),
      GoRoute(
        path: '/ota/:sn',
        name: 'ota',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(
            state,
            BlocProvider(
              create: (_) => getIt<OtaBloc>(),
              child: OTAPage(deviceSN: sn),
            ),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/detail',
        name: 'otaDetail',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          final taskId = int.parse(state.uri.queryParameters['task_id'] ?? '0');

          return _slidePage(
            state,
            BlocProvider(
              create: (_) => getIt<OtaBloc>(),
              child: OTADetailPage(deviceSN: sn, taskId: taskId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/local',
        name: 'otaLocal',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          final deviceIP = state.uri.queryParameters['ip'] ?? '192.168.4.1';

          final firmwareId = state.uri.queryParameters['firmware_id'] != null
              ? int.tryParse(state.uri.queryParameters['firmware_id']!)
              : null;

          final firmwareUrl = state.uri.queryParameters['firmware_url'];

          final firmwareFileName =
              state.uri.queryParameters['firmware_file_name'];

          final targetChip = state.uri.queryParameters['target_chip'];
          final firmwareVersion = state.uri.queryParameters['firmware_version'];
          final fileSha256 = state.uri.queryParameters['file_sha256'];
          final securityVersion =
              int.tryParse(state.uri.queryParameters['security_version'] ?? '');
          final releaseSignature =
              state.uri.queryParameters['release_signature'];

          return _slidePage(
            state,
            LocalOTAPage(
              deviceSN: sn,
              deviceIP: deviceIP,
              firmwareId: firmwareId,
              firmwareUrl: firmwareUrl,
              firmwareFileName: firmwareFileName,
              targetChip: targetChip,
              firmwareVersion: firmwareVersion,
              fileSha256: fileSha256,
              securityVersion: securityVersion,
              releaseSignature: releaseSignature,
            ),
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          '${AppLocalizations.of(context)!.pageNotFound}: ${state.error}',
        ),
      ),
    ),
    redirect: (context, state) async {
      return await AuthGuard.redirect(context, state);
    },
  );
}

class MainShell extends StatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static bool _hasCheckedUpdate = false;

  // 完善个人信息弹窗：本次启动仅提示一次（跳过或已设置后不再弹）
  static bool _hasShownProfilePrompt = false;
  
  // 等待 profile 刷新完成后再判断是否弹出完善资料弹窗的订阅
  StreamSubscription<AuthState>? _profileSetupSubscription;

  bool _downloading = false;

  double _downloadProgress = 0;

  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();

    // 未设置昵称的一键登录新用户：进入主框架后弹出完善个人信息弹窗
    if (!_hasShownProfilePrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowProfileSetup();
      });
    }

    if (!_hasCheckedUpdate) {
      _hasCheckedUpdate = true;

      // 延迟检查更新，避免阻塞页面加载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _autoCheckUpdate();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _profileSetupSubscription?.cancel();
    _cancelToken?.cancel();

    super.dispose();
  }

  /// 一键登录自动注册用户（昵称为空）首次进入时弹出完善个人信息弹窗
  void _maybeShowProfileSetup() {
    if (_hasShownProfilePrompt) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // 乐观进入时 user 尚未加载（后台刷新中），等待刷新完成后再判断，
    // 避免资料已存在却因未加载完成而重复弹出完善资料弹窗
    if (authState.user == null) {
      _profileSetupSubscription?.cancel();
      _profileSetupSubscription = context.read<AuthBloc>().stream.listen((state) {
        if (state is AuthAuthenticated && state.user != null) {
          _profileSetupSubscription?.cancel();
          _profileSetupSubscription = null;
          if (mounted) _maybeShowProfileSetup();
        }
      });
      return;
    }

    final nickname = authState.nickname?.trim() ?? '';
    if (nickname.isNotEmpty) return;
    _hasShownProfilePrompt = true;
    ProfileSetupDialog.show(context);
  }

  Future<void> _autoCheckUpdate() async {
    try {
      final updateService = getIt<AppUpdateService>();

      final info = await updateService.checkUpdate(AppConfig.versionCode);

      if (!mounted || !info.hasUpdate) return;

      _showUpdateDialog(info);
    } catch (_) {}
  }

  void _showUpdateDialog(AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.shouldForceUpdate,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;

        return PopScope(
          canPop: !info.shouldForceUpdate,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.system_update, color: AppColors.primary),
                  SizedBox(width: 8.w),
                  Text(l10n.newVersionFound),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.str(
                        'latest_version_label',
                        {'version': info.latestVersionName},
                      ),
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      l10n.str(
                        'current_version_label',
                        {'version': AppConfig.version},
                      ),
                      style:
                          TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                    if (info.changelog.isNotEmpty) ...[
                      SizedBox(height: 12.h),
                      Text(
                        l10n.updateContent,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        info.changelog,
                        style: TextStyle(
                          fontSize: 12.sp,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (_downloading) ...[
                      SizedBox(height: 16.h),
                      LinearProgressIndicator(value: _downloadProgress),
                      SizedBox(height: 4.h),
                      Text(
                        '${l10n.downloadProgress} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!info.shouldForceUpdate)
                  TextButton(
                    onPressed: _downloading
                        ? null
                        : () {
                            _cancelToken?.cancel();

                            Navigator.pop(ctx);
                          },
                    child: Text(l10n.updateLater),
                  ),
                FilledButton(
                  onPressed: _downloading
                      ? null
                      : () => _handleUpdate(info, ctx, setDialogState),
                  child: Text(
                    Platform.isIOS
                        ? l10n.goToUpdate
                        : (_downloading
                            ? l10n.downloadProgress
                            : l10n.updateNow),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleUpdate(
    AppUpdateInfo info,
    BuildContext ctx,
    void Function(void Function()) setDialogState,
  ) async {
    if (Platform.isIOS) {
      if (info.downloadUrl.isNotEmpty) {
        final uri = Uri.parse(info.downloadUrl);

        if (await canLaunchUrl(uri)) {
          if (!mounted) return;

          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      return;
    }

    setState(() => _downloading = true);

    setDialogState(() {});

    _cancelToken = CancelToken();

    try {
      final updateService = getIt<AppUpdateService>();

      final fileName = 'app-${info.latestVersionName}.apk';

      await updateService.downloadAndInstall(
        info.downloadUrl,
        fileName,
        cancelToken: _cancelToken,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress);

          setDialogState(() {});
        },
      );

      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) {
        if (e is WebPageUrlException) {
          Navigator.pop(ctx);

          _showBrowserDownloadDialog(info);
        } else if (e is! DioException) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(ctx)!
                    .str('download_failed', {'error': e.toString()}),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;

          _downloadProgress = 0;
        });
      }
    }
  }

  void _showBrowserDownloadDialog(AppUpdateInfo info) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.open_in_browser, color: AppColors.primary),
            SizedBox(width: 8.w),
            Text(l10n.str('browser_download_title', {})),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.str(
                'browser_download_desc',
                {'version': info.latestVersionName},
              ),
              style: TextStyle(fontSize: 14.sp, height: 1.5),
            ),
            SizedBox(height: 8.h),
            Text(
              info.downloadUrl,
              style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);

              final uri = Uri.parse(info.downloadUrl);

              canLaunchUrl(uri).then((ok) {
                if (ok) launchUrl(uri, mode: LaunchMode.externalApplication);
              });
            },
            child: Text(l10n.str('open_in_browser', {})),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        layoutBuilder: (currentChild, previousChildren) {
          // 完全丢弃 previousChildren，避免新旧页面同时存在于 widget 树导致 GlobalKey 冲突

          // 注意：不能通过 allChildren 列表包含 previousChildren，否则它们仍会被构建

          return currentChild ?? const SizedBox.shrink();
        },
        child: KeyedSubtree(
          key: ValueKey(currentPath),
          child: widget.child,
        ),
      ),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({super.key});

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  bool _assetsPreloaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsPreloaded) {
      _assetsPreloaded = true;
      // 预加载全部导航图标资产：切换 tab 时资产校验命中缓存同步完成，避免闪现 fallback 图标
      _CsergyNavigationIconState.preloadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;

    final isSystemAdmin = authState is AuthAuthenticated
        ? authState.isSystemAdmin
        : false;
    final permissions = authState is AuthAuthenticated
        ? authState.permissions
        : <String>[];

    final l10n = AppLocalizations.of(context)!;

    final navItems = RoleService.getNavItems(
      isSystemAdmin,
      permissions: permissions,
      labels: [
        l10n.navHome,
        l10n.navOverview,
        l10n.navDevice,
        l10n.navAlarm,
        l10n.navProfile,
      ],
    );

    final currentPath = GoRouterState.of(context).matchedLocation;

    final currentIndex = _selectedNavIndex(currentPath, navItems);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;
    final unselectedColor = colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            if (index >= 0 && index < navItems.length) {
              context.go(navItems[index].path);
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: colorScheme.surface,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
          elevation: 0,
          items: navItems.map((item) {
            final label = _translateNavLabel(context, item.label);
            return BottomNavigationBarItem(
              icon: _CsergyNavigationIcon(
                item: item,
                label: label,
                selected: false,
                color: unselectedColor,
              ),
              activeIcon: _CsergyNavigationIcon(
                item: item,
                label: label,
                selected: true,
                color: selectedColor,
              ),
              label: label,
              tooltip: label,
            );
          }).toList(),
        ),
      ),
    );
  }

  int _selectedNavIndex(String currentPath, List<NavItem> navItems) {
    for (int i = 0; i < navItems.length; i++) {
      final path = navItems[i].path;
      if (currentPath == path || currentPath.startsWith('$path/')) {
        return i;
      }
    }

    return 0;
  }
  String _translateNavLabel(BuildContext context, String label) {
    final l10n = AppLocalizations.of(context);

    if (l10n == null) return label;

    switch (label) {
      case 'Home':
        return l10n.navHome;

      case 'Overview':
        return l10n.navOverview;

      case 'Device':
        return l10n.navDevice;

      case 'Alarm':
        return l10n.navAlarm;

      case 'Profile':
        return l10n.navProfile;

      default:
        return label;
    }
  }
}

class _CsergyNavigationIcon extends StatefulWidget {
  final NavItem item;
  final String label;
  final bool selected;
  final Color color;

  const _CsergyNavigationIcon({
    required this.item,
    required this.label,
    required this.selected,
    required this.color,
  });

  String get asset => selected ? item.activeIconAsset : item.iconAsset;

  IconData get fallbackIcon =>
      selected ? item.activeFallbackIcon : item.fallbackIcon;

  @override
  State<_CsergyNavigationIcon> createState() => _CsergyNavigationIconState();
}

class _CsergyNavigationIconState extends State<_CsergyNavigationIcon> {
  /// 全局 SVG 解析缓存：asset → PictureInfo。
  /// 命中缓存后 build 走同步绘制路径，切换 tab（normal/active 资产互换）时
  /// 不再经过 FutureBuilder 等待帧，彻底消除 fallback 图标闪现。
  static final Map<String, PictureInfo> _pictureCache = <String, PictureInfo>{};

  /// 预加载全部导航图标资产并解析为 Picture（fire-and-forget）。
  /// 解析失败的资产不缓存，由 FutureBuilder 回退 fallback 图标兜底。
  static Future<void> preloadAll() async {
    for (final nav in CsergyAssets.navAssets) {
      await _loadPicture(nav.normalAsset);
      await _loadPicture(nav.activeAsset);
    }
  }

  static Future<PictureInfo> _loadPicture(String asset) async {
    final cached = _pictureCache[asset];
    if (cached != null) return cached;
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    _pictureCache[asset] = info;
    return info;
  }

  @override
  Widget build(BuildContext context) {
    final cached = _pictureCache[widget.asset];
    if (cached != null) {
      // 缓存命中：同步绘制，无异步等待帧
      return _buildAccessibleIcon(_buildPicture(cached));
    }
    // 首次加载（或预加载失败）：FutureBuilder 兜底，完成后同样走同步绘制
    return FutureBuilder<PictureInfo>(
      future: _loadPicture(widget.asset),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _buildAccessibleIcon(_buildPicture(snapshot.data!));
        }
        return _buildAccessibleIcon(_buildFallbackIcon());
      },
    );
  }

  Widget _buildPicture(PictureInfo info) {
    return CustomPaint(
      size: const Size.square(CsergyAssets.navigationIconSize),
      painter: _NavSvgPainter(info, widget.color),
    );
  }

  Widget _buildAccessibleIcon(Widget child) {
    return Semantics(
      label: widget.label,
      image: true,
      child: child,
    );
  }

  Widget _buildFallbackIcon() {
    return Icon(
      widget.fallbackIcon,
      size: CsergyAssets.navigationIconSize,
      color: widget.color,
      semanticLabel: widget.label,
    );
  }
}

/// 同步绘制缓存 SVG Picture 的 painter（ColorFilter.srcIn 统一着色）。
/// 替代 SvgPicture.asset 的异步解析路径，避免导航切换时闪现 fallback 图标。
class _NavSvgPainter extends CustomPainter {
  _NavSvgPainter(this.info, this.color);

  final PictureInfo info;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final srcSize = info.size;
    if (srcSize.isEmpty || size.isEmpty) return;

    canvas.save();
    // 图层 + srcIn 着色，与 SvgPicture.colorFilter 效果一致
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
    // 等比缩放居中（保持 SvgPicture fit: contain 的行为）
    final scale =
        math.min(size.width / srcSize.width, size.height / srcSize.height);
    canvas.translate(
      (size.width - srcSize.width * scale) / 2,
      (size.height - srcSize.height * scale) / 2,
    );
    canvas.scale(scale, scale);
    canvas.drawPicture(info.picture);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavSvgPainter oldDelegate) =>
      oldDelegate.info != info || oldDelegate.color != color;
}

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  // 全局设备拖动排序模式：由 AppBar 排序图标开启
  bool _sortMode = false;
  // 缓存最后一次列表数据：排序/更新产生其他状态时保持页面不闪 loading
  DeviceListLoaded? _cachedList;

  @override
  void initState() {
    super.initState();

    context.read<DeviceBloc>().add(const DeviceListRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColor.surface(context),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(
            l10n.deviceManagement,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: AppColor.surfaceContainer(context),
          foregroundColor: AppColor.textPrimary(context),
          actions: [
            if (_sortMode)
              TextButton(
                onPressed: () => setState(() => _sortMode = false),
                child: Text(
                  l10n.finishSorting,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.swap_vert_rounded, size: 22),
                tooltip: l10n.sortDevices,
                onPressed: () => setState(() => _sortMode = true),
              ),
          ],
        ),
      ),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          // 设备编辑页保存别名/备注后刷新列表
          if (state is DeviceUpdateSuccess) {
            context.read<DeviceBloc>().add(const DeviceListRequested());
          }
        },
        builder: (context, state) {
          if (state is DeviceListLoaded) _cachedList = state;
          final ds = _cachedList;

          if (state is DeviceError && ds == null) {
            // 小烁展示设备插画：加载失败/断网态（美术路由 C3/offline）
            return XiaoshuoStatePanel(
              asset: CsergyAssets.xiaoshuoDevice,
              title: l10n.translateError(state.message),
              message: l10n.loadFailed,
              size: 176,
              action: OutlinedButton(
                onPressed: () => context
                    .read<DeviceBloc>()
                    .add(const DeviceListRequested()),
                child: Text(l10n.retry),
              ),
            );
          }

          if (ds == null) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 3),
            );
          }

          // 全局设备列表页：长按弹编辑页（无电站上下文，不显示排序入口项）
          return DeviceListView(
            devices: ds.devices,
            whiteHeader: true,
            sortMode: _sortMode,
            onDeviceChanged: (order) {
              // 拖动即持久化全局设备顺序
              context
                  .read<DeviceBloc>()
                  .add(DeviceGlobalReorderRequested(deviceOrder: order));
            },
            onLongPressDevice: (sn) {
              final device = ds.devices.firstWhere(
                (d) => (d['sn'] ?? '').toString() == sn,
                orElse: () => <String, dynamic>{'sn': sn},
              );
              context.push('/device/$sn/edit', extra: {'device': device});
            },
          );
        },
      ),
    );
  }
}

class DeviceControlPageWrapper extends StatelessWidget {
  final String deviceSN;

  const DeviceControlPageWrapper({super.key, required this.deviceSN});

  @override
  Widget build(BuildContext context) {
    return DeviceControlPage(deviceSN: deviceSN);
  }
}
