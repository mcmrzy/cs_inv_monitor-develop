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
import 'package:inv_app/features/device/presentation/pages/history_chart_page.dart';
import 'package:inv_app/features/device/presentation/pages/local_mode_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';
import 'package:inv_app/features/ota/presentation/pages/ota_detail_page.dart';
import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';
import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';
import 'package:inv_app/core/router/guards/auth_guard.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/core/services/service_locator.dart';

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
        path: '/device/:sn/history',
        name: 'deviceHistory',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return HistoryChartPage(deviceSN: sn);
        },
      ),
      GoRoute(
        path: '/wifi-config',
        name: 'wifiConfig',
        builder: (context, state) => const WifiConfigPage(),
      ),
      GoRoute(
        path: '/local-mode',
        name: 'localMode',
        builder: (context, state) => const LocalModePage(),
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
      GoRoute(
        path: '/ota/:sn',
        name: 'ota',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          return BlocProvider(
            create: (_) => getIt<OtaBloc>(),
            child: OTAPage(deviceSN: sn),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/detail',
        name: 'otaDetail',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          final taskId = int.parse(state.uri.queryParameters['task_id'] ?? '0');
          return BlocProvider(
            create: (_) => getIt<OtaBloc>(),
            child: OTADetailPage(deviceSN: sn, taskId: taskId),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/local',
        name: 'otaLocal',
        builder: (context, state) {
          final sn = state.pathParameters['sn']!;
          final deviceIP = state.uri.queryParameters['ip'] ?? '192.168.4.1';
          final firmwareId = state.uri.queryParameters['firmware_id'] != null
              ? int.tryParse(state.uri.queryParameters['firmware_id']!)
              : null;
          final firmwareUrl = state.uri.queryParameters['firmware_url'];
          final firmwareFileName = state.uri.queryParameters['firmware_file_name'];
          return LocalOTAPage(
            deviceSN: sn,
            deviceIP: deviceIP,
            firmwareId: firmwareId,
            firmwareUrl: firmwareUrl,
            firmwareFileName: firmwareFileName,
          );
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

    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        if (index < navItems.length) {
          context.go(navItems[index].path);
        }
      },
      type: BottomNavigationBarType.fixed,
      items: navItems.map((item) => BottomNavigationBarItem(
        icon: Icon(item.icon),
        activeIcon: Icon(item.activeIcon),
        label: item.label,
      )).toList(),
    );
  }
}

class OtaTabPage extends StatelessWidget {
  const OtaTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(50.h),
        child: AppBar(
          title: const Text('OTA升级', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.system_update_outlined, size: 64.sp, color: AppColors.textHint),
            SizedBox(height: 16.h),
            Text('OTA升级功能开发中', style: TextStyle(fontSize: 16.sp, color: AppColors.textSecondary)),
          ],
        ),
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
                        hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textHint),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint), onPressed: () { _searchController.clear(); setState(() {}); })
                            : null,
                        filled: true, fillColor: AppColors.surfaceHover,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: AppColors.primary, width: 1)),
                      ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Row(
                    children: [
                      _buildChip('全部', -1, AppColors.primary),
                      SizedBox(width: 8.w),
                      _buildChip('在线', 1, AppColors.successLight),
                      SizedBox(width: 8.w),
                      _buildChip('离线', 0, AppColors.textHint),
                      SizedBox(width: 8.w),
                      _buildChip('故障', 2, AppColors.errorLight),
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
                            final accentColor = isOnline ? AppColors.primary : (isFault ? AppColors.errorLight : AppColors.textHint);

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
                                          child: Icon(Icons.solar_power_rounded, size: 20.sp, color: AppColors.primary),
                                        ),
                                        SizedBox(width: 12.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(sn, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                              SizedBox(height: 2.h),
                                              Text(model.isNotEmpty ? model : '未知型号', style: TextStyle(fontSize: 11.sp, color: AppColors.textHint), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                          decoration: BoxDecoration(
                                            color: isOnline ? const Color(0xFFECFDF5) : (isFault ? const Color(0xFFFEF2F2) : AppColors.surfaceHover),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(isOnline ? '在线' : (isFault ? '故障' : '离线'), style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: isOnline ? AppColors.successLight : (isFault ? AppColors.errorLight : AppColors.textHint))),
                                        ),
                                        SizedBox(width: 4.w),
                                        Icon(Icons.chevron_right_rounded, size: 16.sp, color: AppColors.textHint),
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
          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
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
          color: selected ? color.withValues(alpha: 0.1) : AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(19.r),
          border: Border.all(color: selected ? color.withValues(alpha: 0.3) : const Color(0xFFE5E7EB), width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: selected ? color : AppColors.textSecondary)),
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

class _DeviceDetailWrapper extends StatefulWidget {
  final String deviceSN;

  const _DeviceDetailWrapper({required this.deviceSN});

  @override
  State<_DeviceDetailWrapper> createState() => _DeviceDetailWrapperState();
}

class _DeviceDetailWrapperState extends State<_DeviceDetailWrapper> {
  Map<String, dynamic>? _cachedDevice;
  InverterRealtime? _cachedRealtime;

  @override
  void initState() {
    super.initState();
    context.read<DeviceBloc>().add(DeviceDetailRequested(sn: widget.deviceSN));
  }

  @override
  void dispose() {
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
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: '解绑设备',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('解绑设备'),
                  content: Text('确定要解绑设备 ${widget.deviceSN} 吗？解绑后将无法查看该设备数据。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        context.read<DeviceBloc>().add(DeviceUnbindRequested(sn: widget.deviceSN));
                      },
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('解绑'),
                    ),
                  ],
                ),
              );
            },
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
          if (state is DeviceUnbindSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('设备已解绑'), backgroundColor: AppColors.success),
            );
            context.pop();
          }
          if (state is DeviceControlSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message ?? '命令已发送'), backgroundColor: AppColors.success),
            );
          }
        },
        builder: (context, state) {
          if (state is DeviceDetailLoaded) {
            _cachedDevice = state.device;
            _cachedRealtime = state.realtimeData;
          }
          if (_cachedDevice != null) {
            final mqttOnline = _cachedRealtime?.onlineStatus?.online;
            final online = mqttOnline ?? (_cachedDevice?['status'] == 1);
            return DeviceDetailPage(
              data: _cachedRealtime,
              device: _cachedDevice,
              isOnline: online,
              onRefresh: () => context.read<DeviceBloc>().add(DeviceDetailRequested(sn: widget.deviceSN)),
              onNavigateControl: () => context.push('/device/${widget.deviceSN}/control'),
              onUnbind: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('解绑设备'),
                    content: Text('确定要解绑设备 ${widget.deviceSN} 吗？解绑后将无法查看该设备数据。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.read<DeviceBloc>().add(DeviceUnbindRequested(sn: widget.deviceSN));
                        },
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('解绑'),
                      ),
                    ],
                  ),
                );
              },
            );
          }
          if (state is DeviceLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
