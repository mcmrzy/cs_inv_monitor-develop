import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/command_result.dart';
import 'package:inv_app/core/services/role_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
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
import 'package:inv_app/features/statistics/presentation/pages/statistics_page.dart';
import 'package:inv_app/features/alarm/presentation/pages/alarm_page.dart';
import 'package:inv_app/features/alarm/presentation/pages/alarm_detail_page.dart';
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
            builder: (context, state) => const StatisticsPage(),
          ),
          GoRoute(
            path: '/alarms',
            name: 'alarms',
            builder: (context, state) => const AlarmPage(),
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
          GoRoute(
            path: '/ota',
            name: 'otaTab',
            builder: (context, state) => const OtaTabPage(),
          ),
        ],
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
        child: Text('Page not found: ${state.error}'),
      ),
    ),
    redirect: (context, state) async {
      return await AuthGuard.redirect(context, state);
    },
  );
}

class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

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
          child: child,
        ),
      ),
      bottomNavigationBar: BottomNavBar(child: child),
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
    final navItems = RoleService.getNavItems(role);
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
          label: item.label,
        )).toList(),
      ),
    );
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
          title: const Text('设备管理', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
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
                  Text(state.message, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                  SizedBox(height: 16.h),
                  OutlinedButton(onPressed: () => context.read<DeviceBloc>().add(const DeviceListRequested()), child: const Text('重试')),
                ],
              ),
            );
          }
          if (state is DeviceListLoaded) {
            return DeviceListView(devices: state.devices, whiteHeader: true);
          }
          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
        },
      ),
    );
  }
}

class DeviceControlPageWrapper extends StatefulWidget {
  final String deviceSN;

  const DeviceControlPageWrapper({super.key, required this.deviceSN});

  @override
  State<DeviceControlPageWrapper> createState() => _DeviceControlPageWrapperState();
}

class _DeviceControlPageWrapperState extends State<DeviceControlPageWrapper> {
  InverterRealtime? _cachedData;
  bool _cachedOnline = false;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(DeviceDetailRequested(sn: widget.deviceSN));
  }

  Future<CommandResult?> _sendCommand(String command, Map<String, dynamic>? params) async {
    try {
      context.read<DeviceBloc>().add(DeviceControlRequested(
        sn: widget.deviceSN,
        cmdType: command,
        params: params ?? {},
      ));
      return CommandResult(status: 'success', message: '命令已发送', timestamp: 0, deviceSn: widget.deviceSN);
    } catch (e) {
      return CommandResult(status: 'error', message: e.toString(), timestamp: 0, deviceSn: widget.deviceSN);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('逆变器控制 - ${widget.deviceSN}')),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceControlSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message ?? '命令执行成功'), backgroundColor: AppColors.success),
            );
          }
        },
        builder: (context, state) {
          if (state is DeviceDetailLoaded) {
            _cachedData = state.realtimeData;
            final device = state.device;
            final mqttOnline = state.realtimeData?.onlineStatus?.online;
            _cachedOnline = mqttOnline ?? (device?['status'] == 1);
          }
          return DeviceControlPage(
            data: _cachedData,
            isOnline: _cachedOnline,
            onSendCommand: _sendCommand,
          );
        },
      ),
    );
  }
}


