import 'dart:math';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'package:inv_app/core/widgets/device_action_sheet.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/energy_statistics_tab.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

part 'station_detail_widgets.dart';

class StationDetailPage extends StatefulWidget {
  final int stationId;
  /// 初始 Tab（0 总览 / 1 统计 / 2 设备），支持路由直达设备管理
  final int initialTab;

  const StationDetailPage({
    super.key,
    required this.stationId,
    this.initialTab = 0,
  });

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage>
    with TickerProviderStateMixin {
  StationDetailLoaded? _cachedState;
  int _activeTabIndex = 0;
  // IndexedStack 懒加载：已访问过的 tab 索引集合（初始仅总览 tab 0）
  final Set<int> _visitedTabs = {0};
  late AnimationController _anim;
  String _weatherIcon = '\uD83C\uDF1E';
  String? _weatherTemp;

  // 统计数据已移至 EnergyStatisticsTab 组件

  String _selectedDeviceSn = 'all';
  // 设备拖动排序模式：由设备编辑页“设备排序”入口开启
  bool _deviceSortMode = false;

  @override
  void initState() {
    super.initState();
    _anim =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
    _cachedState = null;
    _loadCachedDetailIfAvailable();
    _activeTabIndex = widget.initialTab;
    // 路由直达统计/设备 tab 时也标记为已访问，避免懒加载下首帧空白
    _visitedTabs.add(widget.initialTab);
    _weatherIcon = '\uD83C\uDF1E';
    _weatherTemp = null;
    context
        .read<StationBloc>()
        .add(StationDetailRequested(stationId: widget.stationId));
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/stations/${widget.stationId}/weather');
      if (res.statusCode == 200) {
        final data = (res.data is Map)
            ? (res.data['data'] ?? res.data) as Map<String, dynamic>
            : res.data as Map<String, dynamic>;
        if (data['temp_min'] != null || data['temp_max'] != null) {
          if (!mounted) return;
          setState(() {
            _weatherIcon = data['icon'] as String? ?? '\uD83C\uDF1E';
            final tempMin =
                (data['temp_min'] as num?)?.toStringAsFixed(0) ?? '--';
            final tempMax =
                (data['temp_max'] as num?)?.toStringAsFixed(0) ?? '--';
            _weatherTemp = '$tempMin~$tempMax℃';
          });
          return;
        }
      }
    } catch (_) {}

    await _fetchWeatherDirect();
  }

  Future<void> _fetchWeatherDirect() async {
    var ds = _cachedState;
    if (ds == null) {
      await Future.delayed(const Duration(seconds: 3));
      ds = _cachedState;
    }
    if (ds == null) return;

    final station = ds.station;
    if (station == null) return;

    final lat = (station['latitude'] as num?)?.toDouble();
    final lng = (station['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return;

    try {
      final tz = TimezoneUtils.getTimezoneFromStation(station);
      final encodedTz = TimezoneUtils.encodeTimezoneForUrl(tz);
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=$encodedTz';
      final openMeteoDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final res = await openMeteoDio.get(url);
      if (res.statusCode != 200) return;

      final data = res.data as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      final daily = data['daily'] as Map<String, dynamic>?;

      final code = (current?['weather_code'] as num?)?.toInt() ?? 0;
      final tempMinList = (daily?['temperature_2m_min'] as List?)?.cast<num>();
      final tempMaxList = (daily?['temperature_2m_max'] as List?)?.cast<num>();

      if (!mounted) return;
      setState(() {
        _weatherIcon = _weatherIconFromCode(code);
        final tMin = tempMinList != null && tempMinList.isNotEmpty
            ? tempMinList[0].toStringAsFixed(0)
            : '--';
        final tMax = tempMaxList != null && tempMaxList.isNotEmpty
            ? tempMaxList[0].toStringAsFixed(0)
            : '--';
        _weatherTemp = '$tMin~$tMax℃';
      });
    } catch (_) {}
  }

  String _weatherIconFromCode(int code) {
    if (code <= 1) return '\uD83C\uDF1E';
    if (code <= 3) return '\uD83C\uDF24';
    if (code <= 48) return '\uD83C\uDF25';
    if (code <= 57) return '\uD83C\uDF27';
    if (code <= 67) return '\uD83C\uDF28';
    if (code <= 77) return '\uD83C\uDF28';
    if (code <= 82) return '\uD83C\uDF27';
    return '\uD83C\uDF29';
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _loadCachedDetailIfAvailable() {
    try {
      final dataCacheService = getIt<DataCacheService>();
      final cached = dataCacheService.load(DataCacheService.stationDetail(widget.stationId));
      if (cached != null && cached is Map<String, dynamic>) {
        final station = cached['station'] as Map<String, dynamic>?;
        final devices = (cached['devices'] as List?) ?? [];
        if (station != null) {
          _cachedState = StationDetailLoaded(
            stationId: widget.stationId,
            station: station,
            devices: devices,
            // 缓存仅用于快速渲染；只有当前已知离线时才提示“无网络，
            // 显示缓存数据”，网络正常时等实时数据返回后自然覆盖
            isFromCache: getIt<NetworkStatusService>().isOffline,
          );
        }
      }
    } catch (_) {
      // Cache service not available, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StationBloc, StationState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        if (state is StationDetailLoaded) {
          if (state.stationId == widget.stationId) {
            _cachedState = state;
          }
        }
        final ds = _cachedState;
        if (ds == null) {
          return const Scaffold(
            body: SkeletonStationDetail(),
            bottomNavigationBar: null,
          );
        }

        final station = ds.station;
        if (station == null) {
          return Scaffold(body: Center(child: Text(l10n.stationNotFound)));
        }

        return BlocListener<StationBloc, StationState>(
          listener: (context, state) {
            if (state is DeviceUnbindSuccess) {
              AppToast.show(context, '${l10n.str('device_unbound', {})} - ${state.sn}', type: ToastType.success);
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceDeleteSuccess) {
              AppToast.show(context, '${l10n.str('device_deleted', {})} - ${state.sn}', type: ToastType.success);
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceRebindSuccess) {
              AppToast.show(context, '${l10n.str('device_rebound', {})} - ${state.sn}', type: ToastType.success);
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceBindSuccess) {
              AppToast.show(context, '${l10n.str('device_bound', {})} - ${state.sn}', type: ToastType.success);
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceReorderSuccess) {
              AppToast.show(context, l10n.str('device_order_saved', {}), type: ToastType.success);
            } else if (state is StationError &&
                state is! StationActionError) {
              AppToast.show(context, l10n.translateError(state.message), type: ToastType.error);
            }
          },
          child: Scaffold(
            body: Column(
              children: [
                if (ds.isFromCache)
                  SafeArea(
                    bottom: false,
                    child: OfflineDataBanner(
                      onRetry: () => context.read<StationBloc>().add(
                            StationDetailRequested(stationId: widget.stationId),
                          ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _activeTabIndex,
                    children: [
                      _buildOverviewBody(station),
                      // 懒加载：仅已访问过的 tab 才构建，避免未点开的统计/设备 tab 提前拉数据
                      _visitedTabs.contains(1)
                          ? _buildStatisticsBody(station)
                          : const SizedBox.shrink(),
                      _visitedTabs.contains(2)
                          ? _buildDevicesBody(ds)
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _bottomBar(),
          ),
        );
      },
    );
  }

  Widget _buildOverviewBody(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';
    // 在线口径与首页电站卡片统一：以 online_count 为准（status 由后端 SyncStationStatus 联动设备维护，避免两端不一致）
    final online = ((station['online_count'] as num?)?.toInt() ?? 0) > 0;

    double pvW, loadW, battW, soc;
    if (_selectedDeviceSn != 'all') {
      // 单设备模式：从 RealtimeDataService 获取该设备数据
      final rt = getIt<RealtimeDataService>().getLatestData(_selectedDeviceSn);
      pvW = rt?.pv?.pvPower ?? 0;
      loadW = rt?.ac?.power ?? 0;
      if (rt?.battery != null) {
        battW = rt!.battery!.voltage * rt.battery!.current;
        soc = rt.battery!.soc;
      } else {
        battW = 0;
        soc = 0;
      }
    } else {
      pvW = (station['pv_power'] as num?)?.toDouble() ?? 0;
      loadW = (station['load_power'] as num?)?.toDouble() ?? 0;
      battW = (station['batt_power'] as num?)?.toDouble() ?? 0;
      soc = (station['batt_soc'] as num?)?.toDouble() ?? 0;
    }

    // 离线时功率/SOC 清零：能量流全零，动画自然停止
    final displayPvW = online ? pvW : 0.0;
    final displayLoadW = online ? loadW : 0.0;
    final displayBattW = online ? battW : 0.0;
    final displaySoc = online ? soc : 0.0;
    const displayGridW = 0.0;
    final todayKwh = (station['today_energy'] ?? 0.0).toDouble();
    final totalKwh = (station['total_energy'] ?? 0.0).toDouble();
    final monthKwh = (station['month_energy'] ?? 0.0).toDouble();
    final yearKwh = (station['year_energy'] ?? 0.0).toDouble();
    final totalPowerW = (station['total_power'] as num?)?.toDouble() ?? 0;
    final coal = (totalKwh * 0.33).toStringAsFixed(1);
    final co2 = (totalKwh * 0.997).toStringAsFixed(1);
    final trees = (totalKwh * 0.05).toStringAsFixed(0);
    final flows =
        _computeFlows(displayPvW, displayBattW, displayGridW, displayLoadW);

    return Stack(
      children: [
        Positioned.fill(
          top: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // 浅色：天蓝渐变；暗色：深蓝灰渐变
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [const Color(0xFF1B2A3A), AppColor.surface(context)]
                    : const [Color(0xFF87CEEB), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5],
              ),
            ),
          ),
        ),
        StyledRefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            context
                .read<StationBloc>()
                .add(StationDetailRequested(stationId: widget.stationId));
            _fetchWeather();
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
              _topBar(name, online),
              SizedBox(height: 8.h),
              _flowArea(
                displayPvW,
                displayLoadW,
                displayBattW,
                displayGridW,
                displaySoc,
                flows,
              ),
              SizedBox(height: 10.h),
              _twoCards(displayPvW, totalPowerW, todayKwh),
              SizedBox(height: 10.h),
              _statsRow(monthKwh, yearKwh, totalKwh),
              SizedBox(height: 10.h),
              _ecoRow(coal, co2, trees),
              SizedBox(height: 100.h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(String name, bool online) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.pop(),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.all(8.w),
                    child: Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 18,
                      color: AppColor.textPrimary(context),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColor.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 右上角：在线状态徽标（保持最右；编辑入口已移除，首页长按菜单可编辑）
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: online
                      ? AppColors.badgeNormalBg
                      : AppColor.surfaceContainer(
                          context,
                        ).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: online
                            ? AppColors.successLight
                            : AppColor.textHint(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      online ? l10n.online : l10n.offline,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w500,
                        color: online
                            ? AppColors.successLight
                            : AppColor.textHint(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          // 天气和设备选择器在同一行，一左一右
          Row(
            children: [
              // 天气信息
              Text(_weatherIcon, style: TextStyle(fontSize: 16.sp)),
              SizedBox(width: 6.w),
              Text(
                _weatherTemp ?? '--~--℃',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: AppColor.textSecondary(context),
                ),
              ),
              const Spacer(),
              // 设备选择器（仅在多个设备时显示）
              if ((_cachedState?.devices ?? []).length > 1) 
                _buildDeviceSelector(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector() {
    final l10n = AppLocalizations.of(context)!;
    final devices = _cachedState?.devices ?? [];
    
    // 获取当前选中的设备名称
    String getSelectedDeviceName() {
      if (_selectedDeviceSn == 'all') {
        return l10n.allDevices;
      }
      final device = devices.firstWhere(
        (d) => d['sn'] == _selectedDeviceSn,
        orElse: () => {'sn': l10n.allDevices},
      );
      // 优先自定义别名，回退 SN
      final alias = (device['alias'] ?? '').toString();
      if (alias.isNotEmpty) return alias;
      return device['sn'] as String? ?? l10n.allDevices;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () => _showDeviceSelectSheet(devices),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 16.sp, color: AppColor.textSecondary(context)),
            SizedBox(width: 6.w),
            Text(
              getSelectedDeviceName(),
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: AppColor.textPrimary(context),
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.arrow_drop_down,
              size: 18.sp,
              color: AppColor.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  // 弹出设备选择面板（白色圆角 BottomSheet，替代系统默认灰色 PopupMenu）
  Future<void> _showDeviceSelectSheet(List<dynamic> devices) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _DeviceSelectSheet(
        devices: devices,
        selectedSn: _selectedDeviceSn,
        onSelected: (val) => Navigator.pop(ctx, val),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedDeviceSn = selected);
  }

  Widget _flowArea(
    double pv,
    double load,
    double batt,
    double grid,
    double soc,
    List<FlowEdge> flows,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final pvW = pv.toStringAsFixed(0);
    final loadW = load.toStringAsFixed(0);
    final gridW = grid.abs().toStringAsFixed(0);
    final battW = batt.abs().toStringAsFixed(0);

    return SizedBox(
      height: 400.h,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, child) => Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EnergyFlowPainter(
                  flows: flows,
                  animValue: _anim.value,
                  gridColor: AppColor.textSecondary(context),
                ),
              ),
            ),
            _energyNode(
              l10n.pv,
              pvW,
              Icons.wb_sunny,
              AppColors.orange,
              const Alignment(0, -0.75),
              true,
              active: pv > 0,
            ),
            _energyNode(
              l10n.load,
              loadW,
              Icons.home_rounded,
              AppColors.blue,
              const Alignment(0, 0.75),
              false,
              active: load > 0,
            ),
            _energyNodeBatt(
              l10n.battery,
              battW,
              soc,
              Icons.battery_charging_full,
              AppColors.successLight,
              const Alignment(-0.75, 0),
              active: batt.abs() > 0,
            ),
            _energyNode(
              l10n.grid,
              gridW,
              Icons.electrical_services,
              AppColor.textSecondary(context),
              const Alignment(0.75, 0),
              true,
              active: grid.abs() > 0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlow(Color color) {
    final t = _anim.value;
    final pulse1 = sin(t * 2 * pi);
    final pulse2 = sin(t * 2 * pi + pi);
    final op1 = 0.14 + 0.14 * (pulse1 * 0.5 + 0.5);
    final op2 = 0.06 + 0.06 * (pulse2 * 0.5 + 0.5);
    return IgnorePointer(
      child: SizedBox(
        width: 110.w,
        height: 110.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100.w,
              height: 100.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: op1),
                    color.withValues(alpha: op1 * 0.2),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0.5, 0.8, 1.0],
                ),
              ),
            ),
            Container(
              width: 90.w,
              height: 90.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: op2),
                    color.withValues(alpha: 0),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _energyNode(
    String label,
    String val,
    IconData icon,
    Color color,
    Alignment align,
    bool labelAbove, {
    bool active = false,
  }) {
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        color: AppColor.textPrimary(context),
      ),
    );
    final circle = Container(
      width: 80.w,
      height: 80.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 62.w,
          height: 62.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColor.surfaceContainer(context),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16.sp, color: color),
              SizedBox(height: 1.h),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    val,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Text(
                'W',
                style: TextStyle(
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (labelAbove) labelWidget,
          if (labelAbove) SizedBox(height: 4.h),
          if (active)
            Stack(
              alignment: Alignment.center,
              children: [_buildGlow(color), circle],
            )
          else
            circle,
          if (!labelAbove) SizedBox(height: 4.h),
          if (!labelAbove) labelWidget,
        ],
      ),
    );
  }

  Widget _energyNodeBatt(
    String label,
    String val,
    double soc,
    IconData icon,
    Color color,
    Alignment align, {
    bool active = false,
  }) {
    final circle = Container(
      width: 80.w,
      height: 80.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 62.w,
          height: 62.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColor.surfaceContainer(context),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15.sp, color: color),
                  SizedBox(width: 2.w),
                  Text(
                    '${soc.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 1.h),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    val,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Text(
                'W',
                style: TextStyle(
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 4.h),
          if (active)
            Stack(
              alignment: Alignment.center,
              children: [_buildGlow(color), circle],
            )
          else
            circle,
        ],
      ),
    );
  }

  List<FlowEdge> _computeFlows(
    double pv,
    double batt,
    double grid,
    double load,
  ) {
    final flows = <FlowEdge>[];
    const threshold = 0.0;

    // PV → Load (main trunk)
    if (pv > threshold && load > threshold) {
      flows.add(
        const FlowEdge(
          from: NodePosition.top,
          to: NodePosition.bottom,
          fromColor: AppColors.orange,
          toColor: AppColors.blue,
        ),
      );
    }

    // PV → Battery (left branch)
    if (pv > threshold && batt > threshold) {
      flows.add(
        const FlowEdge(
          from: NodePosition.top,
          to: NodePosition.left,
          fromColor: AppColors.orange,
          toColor: AppColors.successLight,
        ),
      );
    }

    // Battery → Load (left branch, discharging)
    if (batt < -threshold) {
      flows.add(
        const FlowEdge(
          from: NodePosition.left,
          to: NodePosition.bottom,
          fromColor: AppColors.successLight,
          toColor: AppColors.blue,
        ),
      );
    }

    // Grid → Load (right branch, importing)
    if (grid > threshold) {
      flows.add(
        FlowEdge(
          from: NodePosition.right,
          to: NodePosition.bottom,
          fromColor: AppColor.textSecondary(context),
          toColor: AppColors.blue,
        ),
      );
    }

    // Load → Grid (right branch, exporting to grid)
    if (grid < -threshold) {
      flows.add(
        FlowEdge(
          from: NodePosition.bottom,
          to: NodePosition.right,
          fromColor: AppColors.blue,
          toColor: AppColor.textSecondary(context),
        ),
      );
    }

    return flows;
  }

  Widget _twoCards(double pvW, double totalPowerW, double todayKwh) {
    final l10n = AppLocalizations.of(context)!;
    final w = pvW.toStringAsFixed(0);
    final kwh = todayKwh.toStringAsFixed(1);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            child: _crd(
              Icons.wb_sunny_outlined,
              w,
              'W',
              l10n.currentPower,
              AppColors.orange,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _crd(
              Icons.bolt_rounded,
              kwh,
              'kWh',
              l10n.todayGeneration,
              AppColors.successLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _crd(
    IconData icon,
    String val,
    String unit,
    String label,
    Color accent,
  ) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 18.sp, color: accent),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      val,
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColor.textPrimary(context),
                        height: 1,
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Padding(
                      padding: EdgeInsets.only(bottom: 2.h),
                      child: Text(
                        unit,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                Text(
                  label,
                  style: TextStyle(fontSize: 10.sp, color: AppColor.textHint(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(double month, double year, double total) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColor.surfaceContainer(context),
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _sItem(month.toStringAsFixed(0), 'kWh', l10n.monthlyGeneration),
            _sItem(year.toStringAsFixed(0), 'kWh', l10n.yearlyGeneration),
            _sItem(total.toStringAsFixed(0), 'kWh', l10n.totalGenerationAll),
          ],
        ),
      ),
    );
  }

  Widget _sItem(String val, String unit, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                val,
                style: TextStyle(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColor.textPrimary(context),
                  height: 1,
                ),
              ),
              SizedBox(width: 3.w),
              Padding(
                padding: EdgeInsets.only(bottom: 2.h),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(fontSize: 10.sp, color: AppColor.textHint(context)),
          ),
        ],
      ),
    );
  }

  Widget _ecoRow(String coal, String co2, String trees) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: AppColor.surfaceContainer(context),
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.socialContribution,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColor.textPrimary(context),
              ),
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                _ecoCard(
                  '$coal kg',
                  l10n.coalSaved,
                  Icons.factory_outlined,
                  AppColors.cyan,
                ),
                SizedBox(width: 8.w),
                _ecoCard(
                  '$co2 kg',
                  l10n.co2Reduction,
                  Icons.cloud_outlined,
                  AppColors.successLight,
                ),
                SizedBox(width: 8.w),
                _ecoCard(
                  l10n.str('tree_count', {'count': trees}),
                  l10n.treeEquivalent,
                  Icons.park_outlined,
                  AppColors.lime,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ecoCard(String val, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20.sp, color: color),
            SizedBox(height: 6.h),
            Text(
              val,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(fontSize: 9.sp, color: AppColor.textHint(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsBody(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
        _buildSimpleTopBar(name),
        SizedBox(height: 8.h),
        Expanded(
          child: EnergyStatisticsTab(stationId: widget.stationId),
        ),
      ],
    );
  }

  Widget _buildSimpleTopBar(String name) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.pop(),
              borderRadius: BorderRadius.circular(8.r),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColor.textPrimary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 56.h + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          _tab(0, Icons.info_outline, l10n.stationOverview),
          _tab(1, Icons.show_chart_rounded, l10n.stationStatistics),
          _tab(2, Icons.dns_outlined, l10n.stationDevices),
        ],
      ),
    );
  }

  Widget _tab(int i, IconData icon, String label) {
    final active = i == _activeTabIndex;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (i != _activeTabIndex) {
              setState(() {
                _activeTabIndex = i;
                // 切换前先标记 visited，避免 IndexedStack 下一帧才渲染
                _visitedTabs.add(i);
              });
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20.sp,
                color: active ? AppColors.primary : AppColor.textHint(context),
              ),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.primary : AppColor.textHint(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesBody(dynamic ds) {
    final l10n = AppLocalizations.of(context)!;
    final station = ds.station;
    final name = station != null
        ? (station['station_name'] ?? station['name'] ?? '')
        : '';
    final devices = _mergeFaultStatus((ds.devices as List?) ?? []);

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: AppColor.surface(context)),
        ),
        Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
            _devicesTopBar(name),
            // 排序模式横条：拖动提示 + 完成按钮
            if (_deviceSortMode)
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 2.h),
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 13.sp,
                      color: AppColor.textHint(context),
                    ),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        l10n.sortModeHint,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _deviceSortMode = false),
                      child: Text(
                        l10n.finishSorting,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: DeviceListView(
                devices: devices,
                showSearch: false,
                whiteHeader: true,
                bottomPadding: 100,
                sortMode: _deviceSortMode,
                onDeviceChanged: (order) {
                  // 保存新的排序顺序到数据库（order 为拖动后的 SN 顺序）
                  context
                      .read<StationBloc>()
                      .add(
                        DeviceReorderRequested(
                          stationId: widget.stationId,
                          deviceOrder: order,
                        ),
                      );
                },
                onLongPressDevice: (sn) {
                  // 长按卡片弹出设备操作菜单（编辑/排序/解绑/删除，携带电站上下文）
                  final device = devices.firstWhere(
                    (d) => (d['sn'] ?? '').toString() == sn,
                    orElse: () => <String, dynamic>{'sn': sn},
                  );
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => DeviceActionSheet(
                      device: device,
                      stationId: widget.stationId,
                      onEnterSortMode: () {
                        if (mounted) {
                          setState(() => _deviceSortMode = true);
                        }
                      },
                      onEditClosed: () {
                        // 编辑页返回后刷新设备列表（别名/备注可能已变更）
                        if (mounted) {
                          context.read<StationBloc>().add(
                                StationDetailRequested(
                                  stationId: widget.stationId,
                                ),
                              );
                        }
                      },
                    ),
                  );
                },
                // 下拉刷新：重新拉取电站详情（含设备列表）
                onRefresh: () async {
                  context.read<StationBloc>().add(
                        StationDetailRequested(stationId: widget.stationId),
                      );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 将轮询实时数据中的故障状态合并到设备列表中，
  /// 确保即使 API 数据尚未更新，UI 也能立即反映故障状态。
  List<Map<String, dynamic>> _mergeFaultStatus(List<dynamic> devices) {
    final realtimeService = getIt<RealtimeDataService>();
    return devices.map((d) {
      final Map<String, dynamic> device = Map<String, dynamic>.from(d as Map);
      final sn = device['sn'] as String?;
      if (sn == null || sn.isEmpty) return device;
      final rt = realtimeService.getLatestData(sn);
      if (rt == null) return device;
      final sys = rt.sysStatus;
      if (sys != null && (sys.hasFault || sys.state == 'fault')) {
        device['status'] = 2;
        if (sys.faultCode != 0) {
          device['fault_code'] = sys.faultCode;
        }
        if (sys.alarmCode != 0) {
          device['alarm_code'] = sys.alarmCode;
        }
      }
      return device;
    }).toList();
  }

  Widget _devicesTopBar(String name) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.pop(),
              borderRadius: BorderRadius.circular(8.r),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ),
          ),
          // 与统计 tab 保持一致：返回按钮与标题文字间距 4.w
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColor.textPrimary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum NodePosition { top, bottom, left, right }

class FlowEdge {
  final NodePosition from;
  final NodePosition to;
  final Color fromColor;
  final Color toColor;

  const FlowEdge({
    required this.from,
    required this.to,
    required this.fromColor,
    required this.toColor,
  });
}
