import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/entities/command_result.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/pages/splash_page.dart';
import 'package:inv_app/features/auth/presentation/pages/login_page.dart';
import 'package:inv_app/features/auth/presentation/pages/register_page.dart';
import 'package:inv_app/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:inv_app/features/station/presentation/pages/home_page.dart';
import 'package:inv_app/features/station/presentation/pages/station_detail_page.dart';
import 'package:inv_app/features/station/presentation/pages/create_station_page.dart';
import 'package:inv_app/features/station/presentation/pages/edit_station_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_detail_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_params_page.dart';
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
import 'package:inv_app/features/profile/presentation/pages/device_share_page.dart';
import 'package:inv_app/features/device/presentation/pages/device_control_page.dart';
import 'package:inv_app/core/router/guards/auth_guard.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        builder: (context, state) => const ForgotPasswordPage(),
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
        ],
      ),
      GoRoute(
        path: '/station/create',
        name: 'createStation',
        builder: (context, state) => const CreateStationPage(),
      ),
      GoRoute(
        path: '/station/:id',
        name: 'stationDetail',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return StationDetailPage(stationId: id);
        },
      ),
      GoRoute(
        path: '/station/:id/edit',
        name: 'editStation',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return EditStationPage(stationId: id);
        },
      ),
      GoRoute(
        path: '/device/:sn',
        name: 'deviceDetail',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return _DeviceDetailWrapper(deviceSN: sn);
        },
      ),
      GoRoute(
        path: '/device/:sn/control',
        name: 'deviceControl',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return DeviceControlPageWrapper(deviceSN: sn);
        },
      ),
      GoRoute(
        path: '/device/:sn/params',
        name: 'deviceParams',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return DeviceParamsPage(deviceSN: sn);
        },
      ),
      GoRoute(
        path: '/wifi-config',
        name: 'wifiConfig',
        builder: (context, state) => const WifiConfigPage(),
      ),
      GoRoute(
        path: '/add-device',
        name: 'addDevice',
        builder: (context, state) {
          final stationId = state.uri.queryParameters['station_id'];
          return AddDevicePage(stationId: stationId != null ? int.parse(stationId) : null);
        },
      ),
      GoRoute(
        path: '/alarm/:id',
        name: 'alarmDetail',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return AlarmDetailPage(alarmId: id);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/change-password',
        name: 'changePassword',
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: '/notify-settings',
        name: 'notifySettings',
        builder: (context, state) => const NotifySettingsPage(),
      ),
      GoRoute(
        path: '/device/:sn/share',
        name: 'deviceShare',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return DeviceSharePage(deviceSN: sn);
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
    return Scaffold(
      body: child,
      bottomNavigationBar: const BottomNavBar(),
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
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).matchedLocation;

    int currentIndex = 0;
    if (currentPath == '/home') {
      currentIndex = 0;
    } else if (currentPath == '/statistics') {
      currentIndex = 1;
    } else if (currentPath == '/alarms') {
      currentIndex = 2;
    } else if (currentPath == '/devices') {
      currentIndex = 3;
    } else if (currentPath == '/profile') {
      currentIndex = 4;
    }

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/home');
            break;
          case 1:
            context.go('/statistics');
            break;
          case 2:
            context.go('/alarms');
            break;
          case 3:
            context.go('/devices');
            break;
          case 4:
            context.go('/profile');
            break;
        }
      },
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: '首页',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_outlined),
          activeIcon: Icon(Icons.bar_chart),
          label: '统计',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications_outlined),
          activeIcon: Icon(Icons.notifications),
          label: '告警',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.devices_outlined),
          activeIcon: Icon(Icons.devices),
          label: '设备',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: '我的',
        ),
      ],
    );
  }
}

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  final TextEditingController _searchController = TextEditingController();
  int _statusFilter = -1;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(const DeviceListRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<dynamic> _filter(List<dynamic> devices) {
    final query = _searchController.text.trim().toLowerCase();
    var list = devices;

    if (query.isNotEmpty) {
      list = list.where((d) {
        final sn = (d['sn'] ?? '').toString().toLowerCase();
        final model = (d['model'] ?? '').toString().toLowerCase();
        return sn.contains(query) || model.contains(query);
      }).toList();
    }

    if (_statusFilter >= 0) {
      list = list.where((d) => (d['status'] ?? 0) == _statusFilter).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: const Text('设备管理', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F2937),
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
                ],
              ),
            );
          }
          if (state is DeviceListLoaded) {
            final filtered = _filter(state.devices);
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    cursorColor: AppColors.primary,
                    style: TextStyle(fontSize: 15.sp),
                    decoration: InputDecoration(
                        hintText: '搜索序列号或型号',
                        hintStyle: TextStyle(fontSize: 14.sp, color: const Color(0xFFD1D5DB)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF9CA3AF)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF9CA3AF)), onPressed: () { _searchController.clear(); setState(() {}); })
                            : null,
                        filled: true, fillColor: const Color(0xFFF3F4F6),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Color(0xFF5B9BD5), width: 1)),
                      ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Row(
                    children: [
                      _buildChip('全部', -1, const Color(0xFF5B9BD5)),
                      SizedBox(width: 8.w),
                      _buildChip('在线', 1, const Color(0xFF10B981)),
                      SizedBox(width: 8.w),
                      _buildChip('离线', 0, const Color(0xFF9CA3AF)),
                      SizedBox(width: 8.w),
                      _buildChip('故障', 2, const Color(0xFFEF4444)),
                    ],
                  ),
                ),
                SizedBox(height: 4.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Row(
                    children: [
                      Text('共 ${filtered.length} 台设备', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const Spacer(),
                      if (_statusFilter >= 0)
                        GestureDetector(
                          onTap: () => setState(() => _statusFilter = -1),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12.r)),
                            child: Text('清除', style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(child: Text('暂无设备', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)))
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final device = filtered[index];
                            final sn = device['sn'] ?? '-';
                            final model = device['model'] ?? '';
                            final status = device['status'] ?? 0;
                            final isOnline = status == 1;
                            final isFault = status == 2;
                            final accentColor = isOnline ? const Color(0xFF5B9BD5) : (isFault ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF));

                            return Padding(
                              padding: EdgeInsets.only(bottom: 8.h),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14.r),
                                elevation: 0,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14.r),
                                  onTap: () => context.push('/device/$sn'),
                                  child: Padding(
                                    padding: EdgeInsets.all(14.w),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40.w, height: 40.w,
                                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10.r)),
                                          child: Icon(Icons.solar_power_rounded, size: 20.sp, color: const Color(0xFF5B9BD5)),
                                        ),
                                        SizedBox(width: 12.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(sn, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937))),
                                              SizedBox(height: 2.h),
                                              Text(model.isNotEmpty ? model : '未知型号', style: TextStyle(fontSize: 11.sp, color: const Color(0xFF9CA3AF)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                          decoration: BoxDecoration(
                                            color: isOnline ? const Color(0xFFECFDF5) : (isFault ? const Color(0xFFFEF2F2) : const Color(0xFFF3F4F6)),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(isOnline ? '在线' : (isFault ? '故障' : '离线'), style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: isOnline ? const Color(0xFF10B981) : (isFault ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF)))),
                                        ),
                                        SizedBox(width: 4.w),
                                        Icon(Icons.chevron_right_rounded, size: 16.sp, color: const Color(0xFFD1D5DB)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }
          return const Center(child: Text('加载中...'));
        },
      ),
    );
  }

  Widget _buildChip(String label, int statusValue, Color color) {
    final selected = _statusFilter == statusValue;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = selected ? -1 : statusValue),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(19.r),
          border: Border.all(color: selected ? color.withValues(alpha: 0.3) : const Color(0xFFE5E7EB), width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: selected ? color : const Color(0xFF6B7280))),
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
          InverterRealtime? data;
          bool online = false;
          if (state is DeviceDetailLoaded) {
            data = state.realtimeData;
            final device = state.device;
            online = device?['status'] == 1;
          }
          return DeviceControlPage(
            data: data,
            isOnline: online,
            onSendCommand: _sendCommand,
          );
        },
      ),
    );
  }
}

class _DeviceDetailWrapper extends StatefulWidget {
  final String deviceSN;

  const _DeviceDetailWrapper({required this.deviceSN});

  @override
  State<_DeviceDetailWrapper> createState() => _DeviceDetailWrapperState();
}

class _DeviceDetailWrapperState extends State<_DeviceDetailWrapper> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(DeviceDetailRequested(sn: widget.deviceSN));
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        context.read<DeviceBloc>().add(DeviceRealtimeRefresh(sn: widget.deviceSN));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    try {
      context.read<DeviceBloc>().add(const DeviceUnsubscribeRealtime());
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('设备 ${widget.deviceSN}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_remote),
            tooltip: '设备控制',
            onPressed: () => context.push('/device/${widget.deviceSN}/control'),
          ),
        ],
      ),
      body: BlocConsumer<DeviceBloc, DeviceState>(
        listener: (context, state) {
          if (state is DeviceError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          if (state is DeviceDetailLoaded) {
            final device = state.device;
            final online = device?['status'] == 1;
            return DeviceDetailPage(
              data: state.realtimeData,
              isOnline: online,
              onRefresh: () => context.read<DeviceBloc>().add(DeviceRealtimeRefresh(sn: widget.deviceSN)),
              onNavigateControl: () => context.push('/device/${widget.deviceSN}/control'),
            );
          }
          if (state is DeviceLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(child: Text('加载中...'));
        },
      ),
    );
  }
}
