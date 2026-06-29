import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/app_update_service.dart';
import 'package:inv_app/core/services/role_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/features/auth/presentation/pages/splash_page.dart';
import 'package:inv_app/features/auth/presentation/pages/login_page.dart';
import 'package:inv_app/features/auth/presentation/pages/register_page.dart';
import 'package:inv_app/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:inv_app/features/station/presentation/pages/home_page.dart';
import 'package:inv_app/features/station/presentation/pages/station_detail_page.dart';
import 'package:inv_app/features/station/presentation/pages/create_station_page.dart';
import 'package:inv_app/features/station/presentation/pages/edit_station_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_realtime_page.dart';
import 'package:inv_app/features/device/presentation/pages/wifi_config_page.dart';
import 'package:inv_app/features/device/presentation/pages/add_device_page.dart';
import 'package:inv_app/features/dashboard/presentation/pages/dashboard_overview_page.dart';
import 'package:inv_app/features/alarm/presentation/pages/alarm_page.dart';
import 'package:inv_app/features/alarm/presentation/pages/alarm_detail_page.dart';
import 'package:inv_app/features/notification/presentation/pages/notification_center_page.dart';
import 'package:inv_app/features/profile/presentation/pages/profile_page.dart';
import 'package:inv_app/features/profile/presentation/pages/settings_page.dart';
import 'package:inv_app/features/profile/presentation/pages/change_password_page.dart';
import 'package:inv_app/features/profile/presentation/pages/about_page.dart';
import 'package:inv_app/features/profile/presentation/pages/notify_settings_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';
import 'package:inv_app/features/device/presentation/pages/history_chart_page.dart';
import 'package:inv_app/features/device/presentation/pages/local_mode_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_detail_page.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_tab_page.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/core/router/guards/auth_guard.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
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
        pageBuilder: (context, state) => _fadePage(state, const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) => _slidePage(state, const RegisterPage()),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        pageBuilder: (context, state) => _slidePage(state, const ForgotPasswordPage()),
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
        pageBuilder: (context, state) => _slidePage(state, const CreateStationPage()),
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
        path: '/device/:sn/history',
        name: 'deviceHistory',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return _slidePage(state, HistoryChartPage(deviceSN: sn));
        },
      ),
      GoRoute(
        path: '/wifi-config',
        name: 'wifiConfig',
        pageBuilder: (context, state) => _slidePage(state, const WifiConfigPage()),
      ),
      GoRoute(
        path: '/local-mode',
        name: 'localMode',
        pageBuilder: (context, state) => _slidePage(state, const LocalModePage()),
      ),
      GoRoute(
        path: '/add-device',
        name: 'addDevice',
        pageBuilder: (context, state) {
          final stationId = state.uri.queryParameters['station_id'];
          return _slidePage(state, AddDevicePage(stationId: stationId != null ? int.parse(stationId) : null));
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
        pageBuilder: (context, state) => _slidePage(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/change-password',
        name: 'changePassword',
        pageBuilder: (context, state) => _slidePage(state, const ChangePasswordPage()),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        pageBuilder: (context, state) => _slidePage(state, const AboutPage()),
      ),
      GoRoute(
        path: '/notify-settings',
        name: 'notifySettings',
        pageBuilder: (context, state) => _slidePage(state, const NotifySettingsPage()),
      ),
      GoRoute(
        path: '/ota/:sn',
        name: 'ota',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return _slidePage(state, BlocProvider(
            create: (_) => getIt<OtaBloc>(),
            child: OTAPage(deviceSN: sn),
          ));
        },
      ),
      GoRoute(
        path: '/ota/:sn/detail',
        name: 'otaDetail',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;
          final taskId = int.parse(state.uri.queryParameters['task_id'] ?? '0');
          return _slidePage(state, BlocProvider(
            create: (_) => getIt<OtaBloc>(),
            child: OTADetailPage(deviceSN: sn, taskId: taskId),
          ));
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
          final firmwareFileName = state.uri.queryParameters['firmware_file_name'];
          return _slidePage(state, LocalOTAPage(
            deviceSN: sn,
            deviceIP: deviceIP,
            firmwareId: firmwareId,
            firmwareUrl: firmwareUrl,
            firmwareFileName: firmwareFileName,
          ));
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('${AppLocalizations.of(context)!.pageNotFound}: ${state.error}'),
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
  bool _downloading = false;
  double _downloadProgress = 0;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    if (!_hasCheckedUpdate) {
      _hasCheckedUpdate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoCheckUpdate();
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
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
                  Icon(Icons.system_update, color: AppColors.primary),
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
                      l10n.str('latest_version_label', {'version': info.latestVersionName}),
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      l10n.str('current_version_label', {'version': AppConfig.version}),
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                    if (info.changelog.isNotEmpty) ...[
                      SizedBox(height: 12.h),
                      Text(l10n.updateContent, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
                      SizedBox(height: 4.h),
                      Text(info.changelog, style: TextStyle(fontSize: 12.sp, height: 1.5, color: AppColors.textSecondary)),
                    ],
                    if (_downloading) ...[
                      SizedBox(height: 16.h),
                      LinearProgressIndicator(value: _downloadProgress),
                      SizedBox(height: 4.h),
                      Text(
                        '${l10n.downloadProgress} ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!info.shouldForceUpdate)
                  TextButton(
                    onPressed: _downloading ? null : () {
                      _cancelToken?.cancel();
                      Navigator.pop(ctx);
                    },
                    child: Text(l10n.updateLater),
                  ),
                FilledButton(
                  onPressed: _downloading ? null : () => _handleUpdate(info, ctx, setDialogState),
                  child: Text(Platform.isIOS ? l10n.goToUpdate : (_downloading ? l10n.downloadProgress : l10n.updateNow)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleUpdate(AppUpdateInfo info, BuildContext ctx, void Function(void Function()) setDialogState) async {
    if (Platform.isIOS) {
      if (info.downloadUrl.isNotEmpty) {
        final uri = Uri.parse(info.downloadUrl);
        if (await canLaunchUrl(uri)) {
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

      if (mounted) Navigator.pop(ctx);
    } catch (e) {
      if (mounted) {
        if (e is WebPageUrlException) {
          Navigator.pop(ctx);
          _showBrowserDownloadDialog(info);
        } else if (e is! DioException) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.str('download_failed', {'error': e.toString()}))),
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
            Icon(Icons.open_in_browser, color: AppColors.primary),
            SizedBox(width: 8.w),
            Text(l10n.str('browser_download_title', {})),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.str('browser_download_desc', {'version': info.latestVersionName}),
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
        child: KeyedSubtree(
          key: ValueKey(currentPath),
          child: widget.child,
        ),
      ),
      bottomNavigationBar: BottomNavBar(child: widget.child),
    );
  }
}

String _dash(dynamic val) {
  if (val == null) return '-';
  final s = val.toString().trim();
  if (s.isEmpty || s == '0' || s == '0.0' || s == '0.00') return '-';
  return s;
}

class BottomNavBar extends StatelessWidget {
  final Widget child;

  const BottomNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final role = authState is AuthAuthenticated ? authState.role : RoleService.roleEndUser;
    final l10n = AppLocalizations.of(context)!;
    final navItems = RoleService.getNavItems(role, labels: [
      l10n.navHome, l10n.navOverview, l10n.navDevice, l10n.navAlarm, l10n.navProfile,
    ]);
    final currentPath = GoRouterState.of(context).matchedLocation;

    int currentIndex = 0;
    for (int i = 0; i < navItems.length; i++) {
      if (currentPath == navItems[i].path) {
        currentIndex = i;
        break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index < navItems.length) {
            context.go(navItems[index].path);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
        elevation: 0,
        items: navItems.map((item) => BottomNavigationBarItem(
          icon: Icon(item.icon, size: 22),
          activeIcon: Icon(item.activeIcon, size: 22),
          label: _translateNavLabel(context, item.label),
        )).toList(),
      ),
    );
  }

  String _translateNavLabel(BuildContext context, String label) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return label;
    switch (label) {
      case 'Home': return l10n.navHome;
      case 'Overview': return l10n.navOverview;
      case 'Device': return l10n.navDevice;
      case 'Alarm': return l10n.navAlarm;
      case 'Profile': return l10n.navProfile;
      default: return label;
    }
  }
}

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: Text(AppLocalizations.of(context)!.deviceManagement, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state is DeviceLoading) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (state is DeviceError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(padding: EdgeInsets.all(20.w), decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), shape: BoxShape.circle), child: Icon(Icons.error_outline_rounded, size: 40.sp, color: AppColors.error)),
                  SizedBox(height: 12.h),
                  Text(AppLocalizations.of(context)!.translateError(state.message), style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 16.h),
                  OutlinedButton(onPressed: () => context.read<DeviceBloc>().add(const DeviceListRequested()), child: Text(AppLocalizations.of(context)!.retry)),
                ],
              ),
            );
          }
          if (state is DeviceListLoaded) {
            return DeviceListView(
              devices: state.devices,
              whiteHeader: true,
              onDeviceChanged: () {
                context.read<DeviceBloc>().add(const DeviceListRequested());
              },
            );
          }
          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
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


