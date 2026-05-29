import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/entities/inverter_data.dart';
import 'package:inv_app/core/services/mqtt_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/core/widgets/styled_refresh_indicator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/device_list_view.dart';

class StationDetailPage extends StatefulWidget {
  final int stationId;

  const StationDetailPage({super.key, required this.stationId});

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> with TickerProviderStateMixin {
  StationDetailLoaded? _cachedState;
  int _activeTabIndex = 0;
  late AnimationController _anim;
  String _weatherIcon = '\u2600';
  String? _weatherTemp;

  String _statsPeriod = 'day';
  DateTime _statsDate = DateTime.now();
  List<Map<String, dynamic>> _statsData = [];
  bool _statsLoading = false;
  double _statsProduce = 0;
  double _statsConsume = 0;
  bool _statsInitialized = false;

  final Set<String> _mqttSubscribed = {};
  StreamSubscription<InverterRealtime>? _mqttSub;
  double _mqttPvW = 0;
  double _mqttLoadW = 0;
  double _mqttBattW = 0;
  double _mqttSoc = 0;
  bool _mqttActive = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _cachedState = null;
    _activeTabIndex = 0;
    _weatherIcon = '\u2600';
    _weatherTemp = null;
    _mqttSub?.cancel();
    _mqttSub = null;
    _mqttSubscribed.clear();
    _mqttActive = false;
    context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId));
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/stations/${widget.stationId}/weather');
      if (res.statusCode == 200) {
        final data = (res.data is Map) ? (res.data['data'] ?? res.data) as Map<String, dynamic> : res.data as Map<String, dynamic>;
        if (data['temp_min'] != null || data['temp_max'] != null) {
          setState(() {
            _weatherIcon = data['icon'] as String? ?? '\u2600';
            final tempMin = (data['temp_min'] as num?)?.toStringAsFixed(0) ?? '--';
            final tempMax = (data['temp_max'] as num?)?.toStringAsFixed(0) ?? '--';
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
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=Asia%2FShanghai';
      final openMeteoDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final res = await openMeteoDio.get(url);
      if (res.statusCode != 200) return;

      final data = res.data as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      final daily = data['daily'] as Map<String, dynamic>?;

      final code = (current?['weather_code'] as num?)?.toInt() ?? 0;
      final tempMinList = (daily?['temperature_2m_min'] as List?)?.cast<num>();
      final tempMaxList = (daily?['temperature_2m_max'] as List?)?.cast<num>();

      setState(() {
        _weatherIcon = _weatherIconFromCode(code);
        final tMin = tempMinList != null && tempMinList.isNotEmpty ? tempMinList[0].toStringAsFixed(0) : '--';
        final tMax = tempMaxList != null && tempMaxList.isNotEmpty ? tempMaxList[0].toStringAsFixed(0) : '--';
        _weatherTemp = '$tMin~$tMax℃';
      });
    } catch (_) {}
  }

  String _weatherIconFromCode(int code) {
    if (code <= 1) return '\u2600';
    if (code <= 3) return '\u26C5';
    if (code <= 48) return '\u2601';
    if (code <= 57) return '\uD83C\uDF27';
    if (code <= 67) return '\uD83C\uDF28';
    if (code <= 77) return '\u2744';
    if (code <= 82) return '\uD83C\uDF27';
    return '\u26C8';
  }

  @override
  void dispose() {
    _anim.dispose();
    _mqttSub?.cancel();
    final mqtt = getIt<MQTTService>();
    for (final sn in _mqttSubscribed) {
      mqtt.unsubscribeDeviceTopics(sn);
    }
    super.dispose();
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

    final mqtt = getIt<MQTTService>();
    for (final d in devices) {
      final sn = d['sn'] as String?;
      if (sn == null || sn.isEmpty || _mqttSubscribed.contains(sn)) continue;
      _mqttSubscribed.add(sn);
      mqtt.subscribeDeviceTopics(sn);
    }

    _mqttSub = mqtt.realtimeDataStream.listen(_onMQTTData);
  }

  void _onMQTTData(InverterRealtime data) {
    if (!_mqttSubscribed.contains(data.deviceSN)) return;

    var pvSum = 0.0;
    var loadSum = 0.0;
    var battWSum = 0.0;
    var socSum = 0.0;
    var socCount = 0;
    var hasPv = false;
    var hasAc = false;
    var hasBatt = false;

    final mqtt = getIt<MQTTService>();
    for (final sn in _mqttSubscribed) {
      final rt = mqtt.getLatestData(sn);
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
        if (state is StationDetailLoaded) {
          if (state.stationId == widget.stationId) {
            _cachedState = state;
            _initMQTTRealtime(state);
          }
        }
        final ds = _cachedState;
        if (ds == null) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            bottomNavigationBar: _bottomBar(),
          );
        }

        final station = ds.station;
        if (station == null) {
          return const Scaffold(body: Center(child: Text('电站不存在')));
        }

        return Scaffold(
          body: IndexedStack(
            index: _activeTabIndex,
            children: [
              _buildOverviewBody(station),
              _buildStatisticsBody(station),
              _buildDevicesBody(ds),
            ],
          ),
          bottomNavigationBar: _bottomBar(),
        );
      },
    );
  }

  Widget _buildOverviewBody(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';
    final status = station['status'] ?? 1;
    final online = status == 1;

    final pvW = (station['pv_power'] as num?)?.toDouble() ?? 0;
    final loadW = (station['load_power'] as num?)?.toDouble() ?? 0;
    final battW = (station['batt_power'] as num?)?.toDouble() ?? 0;
    final soc = (station['batt_soc'] as num?)?.toDouble() ?? 0;

    final displayPvW = _mqttActive ? _mqttPvW : pvW;
    final displayLoadW = _mqttActive ? _mqttLoadW : loadW;
    final displayBattW = _mqttActive ? _mqttBattW : battW;
    final displaySoc = _mqttActive ? _mqttSoc : soc;
    final displayGridW = 0.0;
    final todayKwh = (station['today_energy'] ?? 0.0).toDouble();
    final totalKwh = (station['total_energy'] ?? 0.0).toDouble();
    final monthKwh = (station['month_energy'] ?? 0.0).toDouble();
    final yearKwh = (station['year_energy'] ?? 0.0).toDouble();
    final totalPowerW = (station['total_power'] as num?)?.toDouble() ?? 0;
    final coal = (totalKwh * 0.33).toStringAsFixed(1);
    final co2 = (totalKwh * 0.997).toStringAsFixed(1);
    final trees = (totalKwh * 0.05).toStringAsFixed(0);
    final flows = _computeFlows(displayPvW, displayBattW, displayGridW, displayLoadW);

    return Stack(
      children: [
        Positioned.fill(
          top: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF87CEEB), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.5],
              ),
            ),
          ),
        ),
        StyledRefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            context.read<StationBloc>().add(StationDetailRequested(stationId: widget.stationId));
            _fetchWeather();
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
              _topBar(name, online),
              SizedBox(height: 8.h),
              _flowArea(displayPvW, displayLoadW, displayBattW, displayGridW, displaySoc, flows),
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ),
              Expanded(
                child: Text(name, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: online ? const Color(0xFFECFDF5) : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6.r),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: online ? AppColors.successLight : AppColors.textHint, shape: BoxShape.circle)),
                    SizedBox(width: 4.w),
                    Text(online ? '在线' : '离线', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, color: online ? AppColors.successLight : AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Row(
            children: [
              Text(_weatherIcon, style: TextStyle(fontSize: 16.sp)),
              SizedBox(width: 6.w),
              Text(_weatherTemp ?? '--~--℃', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flowArea(double pv, double load, double batt, double grid, double soc, List<FlowEdge> flows) {
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
                painter: _EnergyFlowPainter(flows: flows, animValue: _anim.value),
              ),
            ),
            _energyNode('光伏', pvW, Icons.wb_sunny, const Color(0xFFF59E0B), const Alignment(0, -0.75), true, active: pv > 0),
            _energyNode('负载', loadW, Icons.home_rounded, const Color(0xFF3B82F6), const Alignment(0, 0.75), false, active: load > 0),
            _energyNodeBatt('储能', battW, soc, Icons.battery_charging_full, AppColors.successLight, const Alignment(-0.75, 0), active: batt.abs() > 0),
            _energyNode('电网', gridW, Icons.electrical_services, AppColors.textSecondary, const Alignment(0.75, 0), true, active: grid.abs() > 0),
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
                  colors: [color.withOpacity(op1), color.withOpacity(op1 * 0.2), color.withOpacity(0)],
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
                  colors: [color.withOpacity(op2), color.withOpacity(0)],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _energyNode(String label, String val, IconData icon, Color color, Alignment align, bool labelAbove, {bool active = false}) {
    final labelWidget = Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
    final circle = Container(
      width: 80.w, height: 80.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 2.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Center(
        child: Container(
          width: 62.w, height: 62.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 1)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16.sp, color: color),
              SizedBox(height: 1.h),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(val, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: color, height: 1)))),
              Text('W', style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.w600, color: color)),
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
          if (active) Stack(alignment: Alignment.center, children: [_buildGlow(color), circle]) else circle,
          if (!labelAbove) SizedBox(height: 4.h),
          if (!labelAbove) labelWidget,
        ],
      ),
    );
  }

  Widget _energyNodeBatt(String label, String val, double soc, IconData icon, Color color, Alignment align, {bool active = false}) {
    final circle = Container(
      width: 80.w, height: 80.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45), width: 2.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Center(
        child: Container(
          width: 62.w, height: 62.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 1)),
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
                  Text('${soc.toStringAsFixed(0)}%', style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
              SizedBox(height: 1.h),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(val, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: color, height: 1)))),
              Text('W', style: TextStyle(fontSize: 8.sp, fontWeight: FontWeight.w600, color: color)),
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
          Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 4.h),
          if (active) Stack(alignment: Alignment.center, children: [_buildGlow(color), circle]) else circle,
        ],
      ),
    );
  }

  List<FlowEdge> _computeFlows(double pv, double batt, double grid, double load) {
    final flows = <FlowEdge>[];
    const threshold = 0.0;

    // PV → Load (main trunk)
    if (pv > threshold && load > threshold) {
      flows.add(FlowEdge(
        from: NodePosition.top, to: NodePosition.bottom,
        fromColor: const Color(0xFFF59E0B), toColor: const Color(0xFF3B82F6),
      ));
    }

    // PV → Battery (left branch)
    if (pv > threshold && batt > threshold) {
      flows.add(FlowEdge(
        from: NodePosition.top, to: NodePosition.left,
        fromColor: const Color(0xFFF59E0B), toColor: AppColors.successLight,
      ));
    }

    // Battery → Load (left branch, discharging)
    if (batt < -threshold) {
      flows.add(FlowEdge(
        from: NodePosition.left, to: NodePosition.bottom,
        fromColor: AppColors.successLight, toColor: const Color(0xFF3B82F6),
      ));
    }

    // Grid → Load (right branch, importing)
    if (grid > threshold) {
      flows.add(FlowEdge(
        from: NodePosition.right, to: NodePosition.bottom,
        fromColor: AppColors.textSecondary, toColor: const Color(0xFF3B82F6),
      ));
    }

    // Load → Grid (right branch, exporting to grid)
    if (grid < -threshold) {
      flows.add(FlowEdge(
        from: NodePosition.bottom, to: NodePosition.right,
        fromColor: const Color(0xFF3B82F6), toColor: AppColors.textSecondary,
      ));
    }

    return flows;
  }

  Widget _twoCards(double pvW, double totalPowerW, double todayKwh) {
    final w = pvW.toStringAsFixed(0);
    final kwh = todayKwh.toStringAsFixed(1);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(child: _crd(Icons.wb_sunny_outlined, w, 'W', '当前功率', const Color(0xFFF59E0B))),
          SizedBox(width: 10.w),
          Expanded(child: _crd(Icons.bolt_rounded, kwh, 'kWh', '今日发电', AppColors.successLight)),
        ],
      ),
    );
  }

  Widget _crd(IconData icon, String val, String unit, String label, Color accent) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14.r), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(
        children: [
          Container(
            width: 36.w, height: 36.w,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10.r)),
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
                    Text(val, style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1)),
                    SizedBox(width: 4.w),
                    Padding(padding: EdgeInsets.only(bottom: 2.h), child: Text(unit, style: TextStyle(fontSize: 11.sp, color: AppColors.textHint))),
                  ],
                ),
                SizedBox(height: 2.h),
                Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(double month, double year, double total) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14.r), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(
          children: [
            _sItem('${month.toStringAsFixed(0)}', 'kWh', '当月发电量'),
            _sItem('${year.toStringAsFixed(0)}', 'kWh', '当年发电量'),
            _sItem('${total.toStringAsFixed(0)}', 'kWh', '累计发电量'),
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
              Text(val, style: TextStyle(fontSize: 19.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1)),
              SizedBox(width: 3.w),
              Padding(padding: EdgeInsets.only(bottom: 2.h), child: Text(unit, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint))),
            ],
          ),
          SizedBox(height: 4.h),
          Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _ecoRow(String coal, String co2, String trees) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14.r), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('社会贡献', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            SizedBox(height: 10.h),
            Row(
              children: [
                _ecoCard('$coal kg', '节约标准煤', Icons.factory_outlined, const Color(0xFF06B6D4)),
                SizedBox(width: 8.w),
                _ecoCard('$co2 kg', 'CO₂减排量', Icons.cloud_outlined, AppColors.successLight),
                SizedBox(width: 8.w),
                _ecoCard('$trees 棵', '等效植树量', Icons.park_outlined, const Color(0xFF84CC16)),
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
            Text(val, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color)),
            SizedBox(height: 2.h),
            Text(label, style: TextStyle(fontSize: 9.sp, color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsBody(dynamic station) {
    final name = station['station_name'] ?? station['name'] ?? '';

    if (!_statsInitialized) {
      _statsInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchStatistics());
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFFF5F7FA)),
        ),
        Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
            _statsTopBar(name),
            SizedBox(height: 0.h),
            Expanded(child: _buildStatsContent()),
          ],
        ),
      ],
    );
  }

  Widget _statsTopBar(String name) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            _buildPeriodSelector(),
            SizedBox(height: 12.h),
            _buildDateNavigator(),
            SizedBox(height: 14.h),
            _buildEnergyCard(),
            SizedBox(height: 14.h),
            _buildChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          _periodBtn('day', '日'),
          _periodBtn('month', '月'),
          _periodBtn('year', '年'),
        ],
      ),
    );
  }

  Widget _periodBtn(String period, String label) {
    final active = _statsPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_statsPeriod == period) return;
          setState(() {
            _statsPeriod = period;
            _statsDate = DateTime.now();
          });
          _fetchStatistics();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateNavigator() {
    String dateText;
    switch (_statsPeriod) {
      case 'day':
        dateText = DateFormat('yyyy/M/d').format(_statsDate);
        break;
      case 'month':
        dateText = DateFormat('yyyy/M').format(_statsDate);
        break;
      default:
        dateText = DateFormat('yyyy').format(_statsDate);
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                switch (_statsPeriod) {
                  case 'day': _statsDate = _statsDate.subtract(const Duration(days: 1)); break;
                  case 'month': _statsDate = DateTime(_statsDate.year, _statsDate.month - 1, 1); break;
                  default: _statsDate = DateTime(_statsDate.year - 1, 1, 1); break;
                }
              });
              _fetchStatistics();
            },
            child: const Icon(Icons.chevron_left, size: 22, color: AppColors.textSecondary),
          ),
          GestureDetector(
            onTap: () => _showDatePickerSheet(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dateText, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(width: 2.w),
                const Icon(Icons.arrow_drop_down, size: 24, color: AppColors.textPrimary),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                switch (_statsPeriod) {
                  case 'day': _statsDate = _statsDate.add(const Duration(days: 1)); break;
                  case 'month': _statsDate = DateTime(_statsDate.year, _statsDate.month + 1, 1); break;
                  default: _statsDate = DateTime(_statsDate.year + 1, 1, 1); break;
                }
              });
              _fetchStatistics();
            },
            child: const Icon(Icons.chevron_right, size: 22, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showDatePickerSheet() {
    int selectedYear = _statsDate.year;
    int selectedMonth = _statsDate.month;
    int selectedDay = _statsDate.day;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final yearWidget = SizedBox(
              width: 100.w,
              child: ListWheelScrollView.useDelegate(
                itemExtent: 44.h,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                controller: FixedExtentScrollController(initialItem: selectedYear - 1900),
                onSelectedItemChanged: (i) => setSheetState(() => selectedYear = 1900 + i),
                childDelegate: ListWheelChildBuilderDelegate(
                  builder: (context, i) {
                    final y = 1900 + i;
                    return Center(child: Text('$y', style: TextStyle(fontSize: y == selectedYear ? 18.sp : 14.sp, fontWeight: y == selectedYear ? FontWeight.w700 : FontWeight.w400, color: y == selectedYear ? AppColors.primary : AppColors.textHint)));
                  },
                  childCount: 200,
                ),
              ),
            );

            final monthWidget = _statsPeriod != 'year'
                ? SizedBox(
                    width: 70.w,
                    child: ListWheelScrollView.useDelegate(
                      itemExtent: 44.h,
                      diameterRatio: 1.5,
                      physics: const FixedExtentScrollPhysics(),
                      controller: FixedExtentScrollController(initialItem: selectedMonth - 1),
                      onSelectedItemChanged: (i) {
                        setSheetState(() {
                          selectedMonth = i + 1;
                          final maxDay = DateUtils.getDaysInMonth(selectedYear, selectedMonth);
                          if (selectedDay > maxDay) selectedDay = maxDay;
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, i) {
                          final m = i + 1;
                          return Center(child: Text('$m月', style: TextStyle(fontSize: m == selectedMonth ? 18.sp : 14.sp, fontWeight: m == selectedMonth ? FontWeight.w700 : FontWeight.w400, color: m == selectedMonth ? AppColors.primary : AppColors.textHint)));
                        },
                        childCount: 12,
                      ),
                    ),
                  )
                : const SizedBox.shrink();

            final dayWidget = _statsPeriod == 'day'
                ? SizedBox(
                    width: 70.w,
                    child: ListWheelScrollView.useDelegate(
                      itemExtent: 44.h,
                      diameterRatio: 1.5,
                      physics: const FixedExtentScrollPhysics(),
                      controller: FixedExtentScrollController(initialItem: selectedDay - 1),
                      onSelectedItemChanged: (i) => setSheetState(() => selectedDay = i + 1),
                      childDelegate: ListWheelChildBuilderDelegate(
                        builder: (context, i) {
                          final d = i + 1;
                          final maxDay = DateUtils.getDaysInMonth(selectedYear, selectedMonth);
                          final valid = d <= maxDay;
                          return Center(child: Text('$d日', style: TextStyle(fontSize: d == selectedDay ? 18.sp : 14.sp, fontWeight: d == selectedDay ? FontWeight.w700 : FontWeight.w400, color: d == selectedDay ? AppColors.primary : valid ? AppColors.textHint : AppColors.textHint)));
                        },
                        childCount: 31,
                      ),
                    ),
                  )
                : const SizedBox.shrink();

            return Container(
              height: 260.h,
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('取消', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                      ),
                      Text('选择日期', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final maxDay = DateUtils.getDaysInMonth(selectedYear, selectedMonth);
                          if (_statsPeriod == 'year') {
                            selectedMonth = 1;
                            selectedDay = 1;
                          } else if (_statsPeriod == 'month') {
                            selectedDay = 1;
                          }
                          if (selectedDay > maxDay) selectedDay = maxDay;
                          setState(() {
                            _statsDate = DateTime(selectedYear, selectedMonth, selectedDay);
                          });
                          _fetchStatistics();
                        },
                        child: Text('确定', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_statsPeriod == 'day') ...[
                          yearWidget,
                          monthWidget,
                          dayWidget,
                        ] else if (_statsPeriod == 'month') ...[
                          yearWidget,
                          SizedBox(width: 20.w),
                          monthWidget,
                        ] else ...[
                          yearWidget,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEnergyCard() {
    if (_statsLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20.h),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
      );
    }

    String periodLabel;
    switch (_statsPeriod) {
      case 'day': periodLabel = '当日'; break;
      case 'month': periodLabel = '当月'; break;
      default: periodLabel = '当年'; break;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${periodLabel}发电量', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                SizedBox(height: 4.h),
                Text('${_statsProduce.toStringAsFixed(2)} kWh', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: AppColors.successLight)),
              ],
            ),
          ),
          Container(width: 1, height: 40.h, color: const Color(0xFFE5E7EB)),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${periodLabel}用电量', style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
                SizedBox(height: 4.h),
                Text('${_statsConsume.toStringAsFixed(2)} kWh', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: AppColors.errorLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_statsLoading) {
      return SizedBox(
        height: 260.h,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
      );
    }

    if (_statsData.isEmpty) {
      return SizedBox(
        height: 260.h,
        child: const Center(child: Text('暂无数据', style: TextStyle(fontSize: 14, color: AppColors.textHint))),
      );
    }

    final produceSpots = <FlSpot>[];
    final consumeSpots = <FlSpot>[];
    
    final isDayView = _statsPeriod == 'day';

    for (int i = 0; i < _statsData.length; i++) {
      final item = _statsData[i];
      final produce = (item['energy_produce'] as num?)?.toDouble() ?? 0;
      final consume = (item['energy_consume'] as num?)?.toDouble() ?? 0;
      produceSpots.add(FlSpot(i.toDouble(), produce));
      consumeSpots.add(FlSpot(i.toDouble(), consume));
    }

    final maxY = [_statsProduce, _statsConsume, ...produceSpots.map((s) => s.y), ...consumeSpots.map((s) => s.y)].reduce((a, b) => a > b ? a : b);
    final yMax = maxY > 0 ? maxY * 1.2 : 10.0;
    
    String yUnit;
    String chartTitle;
    if (isDayView) {
      yUnit = 'W';
      chartTitle = '功率趋势';
    } else {
      yUnit = 'kWh';
      chartTitle = '发电/用电趋势';
    }

    return SizedBox(
      height: 280.h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chartTitle, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 4.h),
          Row(
            children: [
              _legendDot(const Color(0xFFF59E0B)),
              SizedBox(width: 4.w),
              Text(isDayView ? '光伏功率' : '发电', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
              SizedBox(width: 16.w),
              _legendDot(const Color(0xFF8B5CF6)),
              SizedBox(width: 4.w),
              Text(isDayView ? '负载功率' : '用电', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
            ],
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: yMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yMax > 0 ? (yMax / 4).clamp(1.0, double.infinity) : 1,
                  getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFE5E7EB), strokeWidth: 0.8),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40.w,
                      getTitlesWidget: (value, meta) {
                        return Text('${value.toStringAsFixed(0)}', style: TextStyle(fontSize: 9.sp, color: AppColors.textHint));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28.h,
                      interval: (_statsData.length / 5).ceilToDouble().clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _statsData.length) return const SizedBox.shrink();
                        final time = _statsData[idx]['time']?.toString() ?? '';
                        String label;
                        switch (_statsPeriod) {
                          case 'day':
                            label = time.length >= 16 ? time.substring(11, 16) : time;
                            break;
                          case 'month':
                            label = time.length >= 10 ? time.substring(8, 10) : time;
                            break;
                          default:
                            label = time.length >= 7 ? time.substring(5, 7) : time;
                        }
                        return Padding(
                          padding: EdgeInsets.only(top: 6.h),
                          child: Text(label, style: TextStyle(fontSize: 9.sp, color: AppColors.textHint)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final isProduce = spot.barIndex == 0;
                        final unit = isDayView ? 'W' : 'kWh';
                        final label = isDayView 
                          ? (isProduce ? "光伏功率" : "负载功率")
                          : (isProduce ? "发电" : "用电");
                        return LineTooltipItem(
                          '$label: ${spot.y.toStringAsFixed(1)} $unit',
                          TextStyle(fontSize: 11.sp, color: Colors.white),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: produceSpots,
                    isCurved: true,
                    color: const Color(0xFFF59E0B),
                    barWidth: 2.5,
                    dotData: FlDotData(show: _statsData.length <= 31),
                    belowBarData: BarAreaData(show: true, color: const Color(0xFFF59E0B).withValues(alpha: 0.08)),
                  ),
                  LineChartBarData(
                    spots: consumeSpots,
                    isCurved: true,
                    color: const Color(0xFF8B5CF6),
                    barWidth: 2.5,
                    dotData: FlDotData(show: _statsData.length <= 31),
                    belowBarData: BarAreaData(show: true, color: const Color(0xFF8B5CF6).withValues(alpha: 0.08)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }

  Future<void> _fetchStatistics() async {
    setState(() => _statsLoading = true);
    try {
      final dio = getIt<Dio>();
      String startDate;
      String endDate;
      String period;

      switch (_statsPeriod) {
        case 'day':
          final d = _statsDate;
          startDate = DateFormat('yyyy-MM-dd').format(d);
          endDate = startDate;
          period = 'hour';
          break;
        case 'month':
          final y = _statsDate.year;
          final m = _statsDate.month;
          startDate = '$y-${m.toString().padLeft(2, '0')}-01';
          final lastDay = DateUtils.getDaysInMonth(y, m);
          endDate = '$y-${m.toString().padLeft(2, '0')}-$lastDay';
          period = 'day';
          break;
        default:
          final y = _statsDate.year;
          startDate = '$y-01-01';
          endDate = '$y-12-31';
          period = 'month';
      }

      final res = await dio.get('/stations/${widget.stationId}/statistics', queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
        'period': period,
      });

      if (res.statusCode == 200) {
        final body = res.data;
        List<dynamic> rawList;
        if (body is Map && body.containsKey('data')) {
          rawList = body['data'] as List<dynamic>? ?? [];
        } else if (body is List) {
          rawList = body;
        } else {
          rawList = [];
        }

        final list = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        
        double produceValue = 0;
        double consumeValue = 0;
        
        if (_statsPeriod == 'day') {
          // 按日视图：找最大的daily_pv作为当日发电量
          double maxDailyPv = 0;
          double maxAcPower = 0;
          for (final item in list) {
            final dailyPv = (item['daily_pv'] as num?)?.toDouble() ?? 0;
            final acPower = (item['energy_consume'] as num?)?.toDouble() ?? 0;
            if (dailyPv > maxDailyPv) maxDailyPv = dailyPv;
            if (acPower > maxAcPower) maxAcPower = acPower;
          }
          produceValue = maxDailyPv;
          consumeValue = maxAcPower;
        } else {
          // 按月/年视图：累加每天的发电量
          for (final item in list) {
            produceValue += (item['energy_produce'] as num?)?.toDouble() ?? 0;
            consumeValue += (item['energy_consume'] as num?)?.toDouble() ?? 0;
          }
        }

        setState(() {
          _statsData = list;
          _statsProduce = produceValue;
          _statsConsume = consumeValue;
          _statsLoading = false;
        });
      } else {
        setState(() => _statsLoading = false);
      }
    } catch (e) {
      debugPrint('[Statistics] _fetchStatistics error: $e');
      setState(() {
        _statsData = [];
        _statsProduce = 0;
        _statsConsume = 0;
        _statsLoading = false;
      });
    }
  }

  Widget _bottomBar() {
    return Container(
      height: 56.h + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, -1))]),
      child: Row(
        children: [
          _tab(0, Icons.info_outline, '电站概况'),
          _tab(1, Icons.show_chart_rounded, '统计数据'),
          _tab(2, Icons.dns_outlined, '关联设备'),
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
              Icon(icon, size: 20.sp, color: active ? AppColors.primary : AppColors.textHint),
              SizedBox(height: 2.h),
              Text(label, style: TextStyle(fontSize: 10.sp, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? AppColors.primary : AppColors.textHint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesBody(dynamic ds) {
    final station = ds.station;
    final name = station != null ? (station['station_name'] ?? station['name'] ?? '') : '';

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFFF5F7FA)),
        ),
        Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
            _devicesTopBar(name),
            SizedBox(height: 0.h),
            Expanded(
              child: DeviceListView(
                devices: (ds.devices as List?) ?? [],
                showSearch: false,
                whiteHeader: true,
                bottomPadding: 100,
              ),
            ),
          ],
        ),
      ],
    );
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
                child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppColors.textPrimary),
              ),
            ),
          ),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
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

  static const arcR = 40.0;
  static const nodeR = 40.0;

  _EnergyFlowPainter({required this.flows, required this.animValue});

  bool _match(FlowEdge f, NodePosition a, NodePosition b) =>
      (f.from == a && f.to == b) || (f.from == b && f.to == a);

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

  bool hasEdge(NodePosition a, NodePosition b) =>
      flows.any((f) => (f.from == a && f.to == b) || (f.from == b && f.to == a));

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
    final pvToBatt = flows.any((f) => f.from == NodePosition.top && f.to == NodePosition.left);

    // pvToBatt=true：PV→储能，粒子reverse=true，从pv到batt移动 → 颜色顺序也要反过来
    final lineStartColor = pvToBatt ? pvColor : battColor;
    final lineEndColor = pvToBatt ? battColor : pvColor;
    
    _solidLine(canvas, battRight, Offset(cx - offset - r, bY), lineEndColor);
    
    _curvedArcOnly(canvas, 
      Offset(cx - offset - r, bY), 
      Offset(cx - offset, bY), 
      Offset(cx - offset, bY - r), 
      lineEndColor, lineStartColor,
      reverse: !pvToBatt);
    
    _solidLine(canvas, Offset(cx - offset, bY - r), pvTarget, lineStartColor);

    _curvedParticlesV(canvas, battRight, Offset(cx - offset - r, bY), Offset(cx - offset, bY), Offset(cx - offset, bY - r), pvTarget, battColor, pvColor,
      reverse: pvToBatt);
    if (pvToBatt) {
      _drawArrow(canvas, battRight.dx - 12, bY, battColor, pointingLeft: true);
    } else {
      _drawArrow(canvas, pvTarget.dx, pvTarget.dy - 12, pvColor, pointingUp: true);
    }
  }

  // ── 储能 ↔ 负载：向右 → 拐弯 → 走 cx-offset 竖线 → 到负载中心左侧 ──
  if (hasEdge(NodePosition.left, NodePosition.bottom)) {
    final battRight = Offset(battC.dx + nodeR, battC.dy);
    final loadTarget = Offset(loadC.dx - offset, loadC.dy - nodeR);
    final bY = battC.dy;

    _solidLine(canvas, battRight, Offset(cx - offset - r, bY), battColor);
    
    _curvedArcOnly(canvas,
      Offset(cx - offset - r, bY),
      Offset(cx - offset, bY),
      Offset(cx - offset, bY + r),
      battColor, loadColor);
    
    _solidLine(canvas, Offset(cx - offset, bY + r), loadTarget, loadColor);

    _curvedParticlesV(canvas, battRight, Offset(cx - offset - r, bY), Offset(cx - offset, bY), Offset(cx - offset, bY + r), loadTarget, battColor, loadColor);
    _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
  }

  // ── 电网 ↔ 光伏：向左 → 拐弯 → 走 cx+offset 竖线 → 到光伏中心右侧 ──
  if (hasEdge(NodePosition.right, NodePosition.top)) {
    final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
    final pvTarget = Offset(pvC.dx + offset, pvC.dy + nodeR);
    final gY = gridC.dy;
    final pvToGrid = flows.any((f) => f.from == NodePosition.top && f.to == NodePosition.right);

    final lineStartColor = pvToGrid ? pvColor : gridColor;
    final lineEndColor = pvToGrid ? gridColor : pvColor;
    
    _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);
    
    _curvedArcOnly(canvas,
      Offset(cx + offset + r, gY),
      Offset(cx + offset, gY),
      Offset(cx + offset, gY - r),
      lineEndColor, lineStartColor,
      reverse: !pvToGrid);
    
    _solidLine(canvas, Offset(cx + offset, gY - r), pvTarget, lineStartColor);

    _curvedParticlesV(canvas, gridLeft, Offset(cx + offset + r, gY), Offset(cx + offset, gY), Offset(cx + offset, gY - r), pvTarget, gridColor, pvColor,
      reverse: pvToGrid);
    if (pvToGrid) {
      _drawArrow(canvas, gridLeft.dx + 12, gY, gridColor, pointingLeft: false);
    } else {
      _drawArrow(canvas, pvTarget.dx, pvTarget.dy - 12, pvColor, pointingUp: true);
    }
  }

  // ── 电网 ↔ 负载：向左 → 拐弯 → 走 cx+offset 竖线 → 到负载中心右侧 ──
  if (hasEdge(NodePosition.right, NodePosition.bottom)) {
    final gridLeft = Offset(gridC.dx - nodeR, gridC.dy);
    final loadTarget = Offset(loadC.dx + offset, loadC.dy - nodeR);
    final gY = gridC.dy;
    final loadToGrid = flows.any((f) => f.from == NodePosition.bottom && f.to == NodePosition.right);

    final lineStartColor = loadToGrid ? loadColor : gridColor;
    final lineEndColor = loadToGrid ? gridColor : loadColor;
    
    _solidLine(canvas, gridLeft, Offset(cx + offset + r, gY), lineEndColor);
    
    _curvedArcOnly(canvas,
      Offset(cx + offset + r, gY),
      Offset(cx + offset, gY),
      Offset(cx + offset, gY + r),
      lineEndColor, lineStartColor,
      reverse: !loadToGrid);
    
    _solidLine(canvas, Offset(cx + offset, gY + r), loadTarget, lineStartColor);

    _curvedParticlesV(canvas, gridLeft, Offset(cx + offset + r, gY), Offset(cx + offset, gY), Offset(cx + offset, gY + r), loadTarget, gridColor, loadColor,
      reverse: loadToGrid);
    if (loadToGrid) {
      _drawArrow(canvas, gridLeft.dx + 12, gY, gridColor, pointingLeft: false);
    } else {
      _drawArrow(canvas, loadTarget.dx, loadTarget.dy - 12, loadColor);
    }
  }
}

  void _drawArrow(Canvas canvas, double x, double y, Color c, {bool pointingLeft = false, bool pointingUp = false}) {
    final s = 6.0;
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
    canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.fill);
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
        [0.0, 1.0]
      );
      
      canvas.drawLine(
        Offset(x1, y1), 
        Offset(x2, y2), 
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..shader = shader
      );
    }
  }

  void _solidLine(Canvas canvas, Offset a, Offset b, Color color) {
    canvas.drawLine(a, b, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..color = color);
  }

  void _curvedArcOnly(Canvas canvas, Offset cornerStart, Offset control, Offset cornerEnd, Color ca, Color cb, {bool reverse = false}) {
    final path = Path();
    path.moveTo(cornerStart.dx, cornerStart.dy);
    path.quadraticBezierTo(control.dx, control.dy, cornerEnd.dx, cornerEnd.dy);
    
    final shader = ui.Gradient.linear(cornerStart, cornerEnd, [reverse ? cb : ca, reverse ? ca : cb], [0.0, 1.0]);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = shader);
  }

  void _curvedLine(Canvas canvas, Offset cornerStart, Offset control, Offset cornerEnd, Offset end, Color ca, Color cb) {
    final s1 = (cornerStart - cornerStart).distance;
    final bChord = (cornerEnd - cornerStart).distance;
    final bCtrl1 = (control - cornerStart).distance;
    final bCtrl2 = (cornerEnd - control).distance;
    final s2 = (bChord + bCtrl1 + bCtrl2) / 2;
    final s3 = (end - cornerEnd).distance;
    final total = s1 + s2 + s3;
    if (total < 1) return;

    const segments = 40;
    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;
      
      final d1 = t1 * total;
      final d2 = t2 * total;
      
      double x1, y1, x2, y2;
      
      if (d1 < s1) {
        x1 = cornerStart.dx;
        y1 = cornerStart.dy;
      } else if (d1 < s1 + s2) {
        final bt = (d1 - s1) / s2;
        final tInv = 1 - bt;
        x1 = tInv * tInv * cornerStart.dx + 2 * tInv * bt * control.dx + bt * bt * cornerEnd.dx;
        y1 = tInv * tInv * cornerStart.dy + 2 * tInv * bt * control.dy + bt * bt * cornerEnd.dy;
      } else {
        final lt = (d1 - s1 - s2) / s3;
        x1 = cornerEnd.dx + (end.dx - cornerEnd.dx) * lt;
        y1 = cornerEnd.dy + (end.dy - cornerEnd.dy) * lt;
      }
      
      if (d2 < s1) {
        x2 = cornerStart.dx;
        y2 = cornerStart.dy;
      } else if (d2 < s1 + s2) {
        final bt = (d2 - s1) / s2;
        final tInv = 1 - bt;
        x2 = tInv * tInv * cornerStart.dx + 2 * tInv * bt * control.dx + bt * bt * cornerEnd.dx;
        y2 = tInv * tInv * cornerStart.dy + 2 * tInv * bt * control.dy + bt * bt * cornerEnd.dy;
      } else {
        final lt = (d2 - s1 - s2) / s3;
        x2 = cornerEnd.dx + (end.dx - cornerEnd.dx) * lt;
        y2 = cornerEnd.dy + (end.dy - cornerEnd.dy) * lt;
      }
      
      final color1 = _lerp3(ca, cb, t1);
      final color2 = _lerp3(ca, cb, t2);
      
      final shader = ui.Gradient.linear(
        Offset(x1, y1), 
        Offset(x2, y2), 
        [color1, color2], 
        [0.0, 1.0]
      );
      
      canvas.drawLine(
        Offset(x1, y1), 
        Offset(x2, y2), 
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..shader = shader
      );
    }
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

  void _curvedParticlesV(Canvas canvas, Offset start, Offset cornerStart, Offset control, Offset cornerEnd, Offset end, Color ca, Color cb, {bool reverse = false}) {
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
        px = tInv * tInv * cornerStart.dx + 2 * tInv * bt * control.dx + bt * bt * cornerEnd.dx;
        py = tInv * tInv * cornerStart.dy + 2 * tInv * bt * control.dy + bt * bt * cornerEnd.dy;
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

  void _dot(Canvas canvas, double x, double y, double angle, double alpha, Color c) {
    canvas.drawCircle(Offset(x, y), 5.0, Paint()
      ..color = c.withOpacity(alpha * 0.5)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(x, y), 3.0, Paint()
      ..color = c.withOpacity(alpha)
      ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter old) =>
      flows.length != old.flows.length || animValue != old.animValue;
}
