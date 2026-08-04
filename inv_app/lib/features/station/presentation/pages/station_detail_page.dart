import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/realtime_data_service.dart';
import 'package:inv_app/core/services/network_status_service.dart';
import 'package:inv_app/core/services/data_cache_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/utils/timezone_utils.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/widgets/energy_statistics_tab.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class StationDetailPage extends StatefulWidget {
  final int stationId;

  const StationDetailPage({super.key, required this.stationId});

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage>
    with TickerProviderStateMixin {
  StationDetailLoaded? _cachedState;
  int _activeTabIndex = 0;
  late AnimationController _anim;
  String _weatherIcon = '\uD83C\uDF1E';
  String? _weatherTemp;

  // 统计数据已移至 EnergyStatisticsTab 组件

  final Set<String> _mqttSubscribed = {};
  StreamSubscription<InverterRealtime>? _mqttSub;
  StreamSubscription<dynamic>? _statusSub;
  StreamSubscription<dynamic>? _alarmSub;
  double _mqttPvW = 0;
  double _mqttLoadW = 0;
  double _mqttBattW = 0;
  double _mqttSoc = 0;
  bool _mqttActive = false;
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
    _activeTabIndex = 0;
    _weatherIcon = '\uD83C\uDF1E';
    _weatherTemp = null;
    _mqttSub?.cancel();
    _mqttSub = null;
    _mqttSubscribed.clear();
    _mqttActive = false;
    context
        .read<StationBloc>()
        .add(StationDetailRequested(stationId: widget.stationId));
    final realtimeService = getIt<RealtimeDataService>();
    _statusSub = realtimeService.statusStream.listen((_) {
      if (!mounted) return;
      context
          .read<StationBloc>()
          .add(StationDetailRequested(stationId: widget.stationId));
    });
    _alarmSub = realtimeService.alarmStream.listen((_) {
      if (!mounted) return;
      context
          .read<StationBloc>()
          .add(StationDetailRequested(stationId: widget.stationId));
    });
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
    _statusSub?.cancel();
    _alarmSub?.cancel();
    _anim.dispose();
    _mqttSub?.cancel();
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

  void _initMQTTRealtime(StationDetailLoaded ds) {
    if (_mqttSub != null) return;
    final devices = (ds.devices as List?) ?? [];
    if (devices.isEmpty) return;

    final station = ds.station;
    if (station != null) {
      _mqttPvW = (station['pv_power'] as num?)?.toDouble() ?? 0;
      _mqttLoadW = (station['load_power'] as num?)?.toDouble() ?? 0;
      _mqttBattW = (station['batt_power'] as num?)?.toDouble() ?? 0;
      _mqttSoc = (station['batt_soc'] as num?)?.toDouble() ?? 0;
    }
    _mqttActive = true;

    final realtimeService = getIt<RealtimeDataService>();
    for (final d in devices) {
      final sn = d['sn'] as String?;
      if (sn == null || sn.isEmpty || _mqttSubscribed.contains(sn)) continue;
      _mqttSubscribed.add(sn);
      realtimeService.startPolling(sn);
    }

    _mqttSub = realtimeService.realtimeDataStream.listen(_onMQTTData);
  }

  void _onMQTTData(InverterRealtime data) {
    if (!_mqttSubscribed.contains(data.deviceSN)) return;
    _recalcMqttAggregation();
  }

  /// 根据 _selectedDeviceSn 重新聚合 MQTT 数据
  void _recalcMqttAggregation() {
    var pvSum = 0.0;
    var loadSum = 0.0;
    var battWSum = 0.0;
    var socSum = 0.0;
    var socCount = 0;
    var hasPv = false;
    var hasAc = false;
    var hasBatt = false;

    final realtimeService = getIt<RealtimeDataService>();
    final targetSNs =
        _selectedDeviceSn == 'all' ? _mqttSubscribed : {_selectedDeviceSn};
    for (final sn in targetSNs) {
      final rt = realtimeService.getLatestData(sn);
      if (rt == null) continue;
      if (rt.pv != null) {
        pvSum += rt.pv!.pvPower;
        hasPv = true;
      }
      if (rt.ac != null) {
        loadSum += rt.ac!.power;
        hasAc = true;
      }
      if (rt.battery != null) {
        battWSum += rt.battery!.voltage * rt.battery!.current;
        socSum += rt.battery!.soc;
        socCount++;
        hasBatt = true;
      }
    }

    setState(() {
      _mqttActive = true;
      if (hasPv) _mqttPvW = pvSum;
      if (hasAc) _mqttLoadW = loadSum;
      if (hasBatt) _mqttBattW = battWSum;
      _mqttSoc = socCount > 0 ? socSum / socCount : _mqttSoc;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StationBloc, StationState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        if (state is StationDetailLoaded) {
          if (state.stationId == widget.stationId) {
            _cachedState = state;
            _initMQTTRealtime(state);
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
            if (state is StationDeleteSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.str('station_deleted', {})),
                ),
              );
              context.pop();
            } else if (state is DeviceUnbindSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${l10n.str('device_unbound', {})} - ${state.sn}',
                  ),
                ),
              );
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceDeleteSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${l10n.str('device_deleted', {})} - ${state.sn}',
                  ),
                ),
              );
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceRebindSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${l10n.str('device_rebound', {})} - ${state.sn}',
                  ),
                ),
              );
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceBindSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${l10n.str('device_bound', {})} - ${state.sn}',
                  ),
                ),
              );
              context.read<StationBloc>().add(
                StationDetailRequested(stationId: widget.stationId),
              );
            } else if (state is DeviceReorderSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.str('device_order_saved', {}),
                  ),
                ),
              );
            } else if (state is StationError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.translateError(state.message)),
                ),
              );
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
                      _buildStatisticsBody(station),
                      _buildDevicesBody(ds),
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
    final status = station['status'] ?? 1;
    final deviceCount = (station['device_count'] as num?)?.toInt() ?? 0;
    final online = status == 1 && deviceCount > 0;

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
    final displayPvW = online ? (_mqttActive ? _mqttPvW : pvW) : 0.0;
    final displayLoadW = online ? (_mqttActive ? _mqttLoadW : loadW) : 0.0;
    final displayBattW = online ? (_mqttActive ? _mqttBattW : battW) : 0.0;
    final displaySoc = online ? (_mqttActive ? _mqttSoc : soc) : 0.0;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.pop(),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.all(8.w),
                    child: const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 编辑电站入口（原三点菜单移除后的落点）
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      context.push('/station/${widget.stationId}/edit'),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.all(6.w),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              // 右上角：在线状态徽标（保持最右）
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: online
                      ? AppColors.badgeNormalBg
                      : Colors.white.withValues(alpha: 0.8),
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
                            : AppColors.textHint,
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
                            : AppColors.textHint,
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
                  color: AppColors.textSecondary,
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
      return device['sn'] as String? ?? l10n.allDevices;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColor.surface(context),
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
            Icon(Icons.devices_other, size: 16.sp, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(
              getSelectedDeviceName(),
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.arrow_drop_down,
              size: 18.sp,
              color: AppColors.textSecondary,
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
    _recalcMqttAggregation();
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
                painter:
                    _EnergyFlowPainter(flows: flows, animValue: _anim.value),
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
              AppColors.textSecondary,
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
        color: AppColors.textPrimary,
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
            color: Colors.white,
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
            color: Colors.white,
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
              color: AppColors.textPrimary,
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
        const FlowEdge(
          from: NodePosition.right,
          to: NodePosition.bottom,
          fromColor: AppColors.textSecondary,
          toColor: AppColors.blue,
        ),
      );
    }

    // Load → Grid (right branch, exporting to grid)
    if (grid < -threshold) {
      flows.add(
        const FlowEdge(
          from: NodePosition.bottom,
          to: NodePosition.right,
          fromColor: AppColors.blue,
          toColor: AppColors.textSecondary,
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
              const Color(0xFFF59E0B),
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
        color: Colors.white,
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
                        color: AppColors.textPrimary,
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
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                Text(
                  label,
                  style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
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
          color: Colors.white,
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
                  color: AppColors.textPrimary,
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
                    color: AppColors.textHint,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
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
          color: Colors.white,
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
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                _ecoCard(
                  '$coal kg',
                  l10n.coalSaved,
                  Icons.factory_outlined,
                  const Color(0xFF06B6D4),
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
                  const Color(0xFF84CC16),
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
              style: TextStyle(fontSize: 9.sp, color: AppColors.textHint),
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
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
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
                color: AppColors.textPrimary,
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
        color: Colors.white,
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
              setState(() => _activeTabIndex = i);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20.sp,
                color: active ? AppColors.primary : AppColors.textHint,
              ),
              SizedBox(height: 2.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.primary : AppColors.textHint,
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
                      color: AppColors.textHint,
                    ),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        l10n.sortModeHint,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
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
                      .add(DeviceReorderRequested(
                        stationId: widget.stationId,
                        deviceOrder: order,
                      ));
                },
                onLongPressDevice: (sn) {
                  // 长按卡片弹出设备编辑页（携带电站上下文与排序入口回调）
                  final device = devices.firstWhere(
                    (d) => (d['sn'] ?? '').toString() == sn,
                    orElse: () => <String, dynamic>{'sn': sn},
                  );
                  context.push('/device/$sn/edit', extra: {
                    'device': device,
                    'stationId': widget.stationId,
                    'onEnterSortMode': () {
                      if (mounted) {
                        setState(() => _deviceSortMode = true);
                      }
                    },
                  }).then((_) {
                    // 编辑页返回后刷新设备列表（别名/备注可能已变更）
                    if (mounted) {
                      context.read<StationBloc>().add(
                            StationDetailRequested(
                                stationId: widget.stationId),
                          );
                    }
                  });
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
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
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

class _EnergyFlowPainter extends CustomPainter {
  final List<FlowEdge> flows;
  final double animValue;

  _EnergyFlowPainter({required this.flows, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 动态计算：80.w / 2 = 40 * size.width / 375
    final nodeR = 40.0 * size.width / 375.0;
    // 标签12.sp + 间距4.h 导致圆心偏移 = (12.w/375 + 4.h/812) / 2
    // gapH = 4 * size.height / 400 = size.height / 100 (因为 400.h = size.height)
    // labelH ≈ 12 * size.width / 375
    final labelOff = (12.0 * size.width / 375.0 + size.height / 100.0) / 2.0;

    // Align 坐标 → 圆的实际中心（含标签偏移）
    // labelAbove=true 的节点（光伏、电网、储能）：圆心下移 labelOff
    // labelAbove=false 的节点（负载）：圆心在 Align 锚点上方 labelOff
    final pvC = Offset(cx, size.height * 0.125 + labelOff);
    final loadC = Offset(cx, size.height * 0.875 - labelOff);
    final battC = Offset(size.width * 0.125, cy + labelOff);
    final gridC = Offset(size.width * 0.875, cy + labelOff);

    const pvColor = Color(0xFFF59E0B);
    const loadColor = Color(0xFF3B82F6);
    const battColor = AppColors.successLight;
    const gridColor = AppColors.textSecondary;
    const r = 16.0;
    const offset = 8.0;

    bool hasEdge(NodePosition a, NodePosition b) => flows
        .any((f) => (f.from == a && f.to == b) || (f.from == b && f.to == a));

    // ── 光伏 ↔ 负载：中心竖直线（完全保留，走cx） ──
    if (hasEdge(NodePosition.top, NodePosition.bottom)) {
      final a = Offset(pvC.dx, pvC.dy + nodeR);
      final b = Offset(loadC.dx, loadC.dy - nodeR);
      _line(canvas, a, b, pvColor, loadColor);
      _particles(canvas, a, b, pvColor, loadColor);
      _drawArrow(canvas, b.dx, b.dy + 12, loadColor);
    }

    // ── 储能 ↔ 光伏：向右 → 拐弯 → 走 cx-offset 竖线 → 到光伏中心左侧 ──
    if (hasEdge(NodePosition.left, NodePosition.top)) {
      final battRight = Offset(battC.dx + nodeR, battC.dy);
      final pvTarget = Offset(pvC.dx - offset, pvC.dy + nodeR);
      final bY = battC.dy;
      final pvToBatt = flows
          .any((f) => f.from == NodePosition.top && f.to == NodePosition.left);

      // pvToBatt=true：PV→储能，粒子reverse=true，从pv到batt移动 → 颜色顺序也要反过来
      final lineStartColor = pvToBatt ? pvColor : battColor;
      final lineEndColor = pvToBatt ? battColor : pvColor;

      _solidLine(canvas, battRight, Offset(cx - offset - r, bY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY - r),
        lineEndColor,
        lineStartColor,
        reverse: !pvToBatt,
      );

      _solidLine(canvas, Offset(cx - offset, bY - r), pvTarget, lineStartColor);

      _curvedParticlesV(
        canvas,
        battRight,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY - r),
        pvTarget,
        battColor,
        pvColor,
        reverse: pvToBatt,
      );
      if (pvToBatt) {
        _drawArrow(
          canvas,
          battRight.dx - 12,
          bY,
          battColor,
          pointingLeft: true,
        );
      } else {
        _drawArrow(
          canvas,
          pvTarget.dx,
          pvTarget.dy - 12,
          pvColor,
          pointingUp: true,
        );
      }
    }

    // ── 储能 ↔ 负载：向右 → 拐弯 → 走 cx-offset 竖线 → 到负载中心左侧 ──
    if (hasEdge(NodePosition.left, NodePosition.bottom)) {
      final battRight = Offset(battC.dx + nodeR, battC.dy);
      final loadTarget = Offset(loadC.dx - offset, loadC.dy - nodeR);
      final bY = battC.dy;

      _solidLine(canvas, battRight, Offset(cx - offset - r, bY), battColor);

      _curvedArcOnly(
        canvas,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY + r),
        battColor,
        loadColor,
      );

      _solidLine(canvas, Offset(cx - offset, bY + r), loadTarget, loadColor);

      _curvedParticlesV(
        canvas,
        battRight,
        Offset(cx - offset - r, bY),
        Offset(cx - offset, bY),
        Offset(cx - offset, bY + r),
        loadTarget,
        battColor,
        loadColor,
      );
      _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
    }

    // ── 电网 ↔ 光伏：向左 → 拐弯 → 走 cx+offset 竖线 → 到光伏中心右侧 ──
    if (hasEdge(NodePosition.right, NodePosition.top)) {
      final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
      final pvTarget = Offset(pvC.dx + offset, pvC.dy + nodeR);
      final gY = gridC.dy;
      final pvToGrid = flows
          .any((f) => f.from == NodePosition.top && f.to == NodePosition.right);

      final lineStartColor = pvToGrid ? pvColor : gridColor;
      final lineEndColor = pvToGrid ? gridColor : pvColor;

      _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY - r),
        lineEndColor,
        lineStartColor,
        reverse: !pvToGrid,
      );

      _solidLine(canvas, Offset(cx + offset, gY - r), pvTarget, lineStartColor);

      _curvedParticlesV(
        canvas,
        gridLeft,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY - r),
        pvTarget,
        gridColor,
        pvColor,
        reverse: pvToGrid,
      );
      if (pvToGrid) {
        _drawArrow(
          canvas,
          gridLeft.dx + 12,
          gY,
          gridColor,
          pointingLeft: false,
        );
      } else {
        _drawArrow(
          canvas,
          pvTarget.dx,
          pvTarget.dy - 12,
          pvColor,
          pointingUp: true,
        );
      }
    }

    // ── 电网 ↔ 负载：向左 → 拐弯 → 走 cx+offset 竖线 → 到负载中心右侧 ──
    if (hasEdge(NodePosition.right, NodePosition.bottom)) {
      final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
      final loadTarget = Offset(loadC.dx + offset, loadC.dy - nodeR);
      final gY = gridC.dy;
      final loadToGrid = flows.any(
        (f) => f.from == NodePosition.bottom && f.to == NodePosition.right,
      );

      final lineStartColor = loadToGrid ? loadColor : gridColor;
      final lineEndColor = loadToGrid ? gridColor : loadColor;

      _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);

      _curvedArcOnly(
        canvas,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY + r),
        lineEndColor,
        lineStartColor,
        reverse: !loadToGrid,
      );

      _solidLine(
        canvas,
        Offset(cx + offset, gY + r),
        loadTarget,
        lineStartColor,
      );

      _curvedParticlesV(
        canvas,
        gridLeft,
        Offset(cx + offset + r, gY),
        Offset(cx + offset, gY),
        Offset(cx + offset, gY + r),
        loadTarget,
        gridColor,
        loadColor,
        reverse: loadToGrid,
      );
      if (loadToGrid) {
        _drawArrow(
          canvas,
          gridLeft.dx + 12,
          gY,
          gridColor,
          pointingLeft: false,
        );
      } else {
        _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
      }
    }
  }

  void _drawArrow(
    Canvas canvas,
    double x,
    double y,
    Color c, {
    bool pointingLeft = false,
    bool pointingUp = false,
  }) {
    const s = 6.0;
    final path = Path();
    if (pointingUp) {
      path.moveTo(x, y - s);
      path.lineTo(x - s, y + s);
      path.lineTo(x + s, y + s);
    } else if (pointingLeft) {
      path.moveTo(x - s, y);
      path.lineTo(x + s, y - s);
      path.lineTo(x + s, y + s);
    } else {
      path.moveTo(x, y + s);
      path.lineTo(x - s, y - s);
      path.lineTo(x + s, y - s);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.fill,
    );
  }

  void _line(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    const segments = 20;

    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;

      final x1 = a.dx + dx * t1;
      final y1 = a.dy + dy * t1;
      final x2 = a.dx + dx * t2;
      final y2 = a.dy + dy * t2;

      final color1 = _lerp3(ca, cb, t1);
      final color2 = _lerp3(ca, cb, t2);

      final shader = ui.Gradient.linear(
        Offset(x1, y1),
        Offset(x2, y2),
        [color1, color2],
        [0.0, 1.0],
      );

      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }
  }

  void _solidLine(Canvas canvas, Offset a, Offset b, Color color) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _curvedArcOnly(
    Canvas canvas,
    Offset cornerStart,
    Offset control,
    Offset cornerEnd,
    Color ca,
    Color cb, {
    bool reverse = false,
  }) {
    final path = Path();
    path.moveTo(cornerStart.dx, cornerStart.dy);
    path.quadraticBezierTo(control.dx, control.dy, cornerEnd.dx, cornerEnd.dy);

    final shader = ui.Gradient.linear(
      cornerStart,
      cornerEnd,
      [reverse ? cb : ca, reverse ? ca : cb],
      [0.0, 1.0],
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  void _particles(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    const n = 8;
    for (int i = 0; i < n; i++) {
      final t = ((i / n) + animValue) % 1.0;
      final px = a.dx + dx * t, py = a.dy + dy * t;
      final alpha = (sin(t * pi) * 0.7).clamp(0.0, 0.8);
      _dot(canvas, px, py, 0, alpha, _lerp3(ca, cb, t));
    }
  }

  void _curvedParticlesV(
    Canvas canvas,
    Offset start,
    Offset cornerStart,
    Offset control,
    Offset cornerEnd,
    Offset end,
    Color ca,
    Color cb, {
    bool reverse = false,
  }) {
    final s1 = (cornerStart - start).distance;
    final bChord = (cornerEnd - cornerStart).distance;
    final bCtrl1 = (control - cornerStart).distance;
    final bCtrl2 = (cornerEnd - control).distance;
    final s2 = (bChord + bCtrl1 + bCtrl2) / 2;
    final s3 = (end - cornerEnd).distance;
    final total = s1 + s2 + s3;
    if (total < 1) return;

    const n = 8;
    for (int i = 0; i < n; i++) {
      final t = ((i / n) + animValue) % 1.0;
      final tp = reverse ? 1.0 - t : t;
      final alpha = (sin(tp * pi) * 0.7).clamp(0.0, 0.8);
      final d = tp * total;
      double px, py;
      if (d < s1) {
        final lt = d / s1;
        px = start.dx + (cornerStart.dx - start.dx) * lt;
        py = start.dy + (cornerStart.dy - start.dy) * lt;
      } else if (d < s1 + s2) {
        final bt = (d - s1) / s2;
        final tInv = 1 - bt;
        px = tInv * tInv * cornerStart.dx +
            2 * tInv * bt * control.dx +
            bt * bt * cornerEnd.dx;
        py = tInv * tInv * cornerStart.dy +
            2 * tInv * bt * control.dy +
            bt * bt * cornerEnd.dy;
      } else {
        final lt = (d - s1 - s2) / s3;
        px = cornerEnd.dx + (end.dx - cornerEnd.dx) * lt;
        py = cornerEnd.dy + (end.dy - cornerEnd.dy) * lt;
      }
      _dot(canvas, px, py, 0, alpha, _lerp3(ca, cb, tp));
    }
  }

  Color _lerp3(Color ca, Color cb, double t) {
    if (t < 0.33) return ca;
    if (t < 0.67) return Color.lerp(ca, cb, (t - 0.33) / 0.34)!;
    return cb;
  }

  void _dot(
    Canvas canvas,
    double x,
    double y,
    double angle,
    double alpha,
    Color c,
  ) {
    canvas.drawCircle(
      Offset(x, y),
      5.0,
      Paint()
        ..color = c.withValues(alpha: alpha * 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(x, y),
      3.0,
      Paint()
        ..color = c.withValues(alpha: alpha)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter old) =>
      flows.length != old.flows.length || animValue != old.animValue;
}

// 选择设备弹窗：白色圆角面板 + 设备列表（选中态高亮、逐项入场动画）
class _DeviceSelectSheet extends StatefulWidget {
  final List<dynamic> devices;
  final String selectedSn;
  final ValueChanged<String> onSelected;

  const _DeviceSelectSheet({
    required this.devices,
    required this.selectedSn,
    required this.onSelected,
  });

  @override
  State<_DeviceSelectSheet> createState() => _DeviceSelectSheetState();
}

class _DeviceSelectSheetState extends State<_DeviceSelectSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  // 逐项入场动画（淡入 + 上移），间隔 0.12
  Widget _animatedItem(int i, Widget child) {
    final start = i * 0.12;
    final end = (start + 0.7).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  // 设备状态颜色：1=在线、2=故障、其他=离线
  Color _statusColor(int status) {
    if (status == 2) return AppColors.fault;
    if (status == 1) return AppColors.online;
    return AppColors.offline;
  }

  // 设备状态文案 key
  String _statusKey(int status) {
    if (status == 2) return 'fault';
    if (status == 1) return 'online';
    return 'offline';
  }

  Widget _buildOption({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _animatedItem(
      index,
      Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color:
                        (selected ? AppColors.primary : color)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    size: 20.sp,
                    color: selected ? AppColors.primary : color,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textHint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20.sp,
                    color: AppColors.primary,
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18.sp,
                    color: AppColors.textHint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = <Widget>[
      _buildOption(
        index: 0,
        icon: Icons.devices,
        title: l10n.allDevices,
        subtitle: l10n.summaryHint,
        color: AppColors.primary,
        selected: widget.selectedSn == 'all',
        onTap: () => widget.onSelected('all'),
      ),
    ];
    var index = 1;
    for (final raw in widget.devices) {
      final d = raw as Map<String, dynamic>;
      final sn = d['sn'] as String? ?? '';
      final status = (d['status'] as num?)?.toInt() ?? 0;
      options.add(
        _buildOption(
          index: index++,
          icon: Icons.memory,
          title: sn,
          subtitle: l10n.str(_statusKey(status), {}),
          color: _statusColor(status),
          selected: widget.selectedSn == sn,
          onTap: () => widget.onSelected(sn),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题头：渐变图标 + 标题 + 设备数量
              Row(
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14.r),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.primary.withValues(alpha: 0.18),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      Icons.devices_other,
                      size: 22.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.selectDevice,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          l10n.deviceCountHint('${widget.devices.length}'),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              const Divider(height: 1, color: AppColors.divider),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: options,
                ),
              ),
              SizedBox(height: 14.h),
              _animatedItem(
                options.length,
                Material(
                  color:
                      isDark ? const Color(0xFF252830) : AppColors.surfaceHover,
                  borderRadius: BorderRadius.circular(14.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
