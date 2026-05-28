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

class StationDetailPage extends StatefulWidget {
  final int stationId;

  const StationDetailPage({super.key, required this.stationId});

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> with TickerProviderStateMixin {
  StationDetailLoaded? _cachedState;
  String _activeTab = 'overview';
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

  int _deviceFilter = 0;
  static const _deviceFilters = ['全部', '逆变器', '采集器', '储能'];

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
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    debugPrint('[StationDetail] initState, stationId=${widget.stationId}, dispatching StationDetailRequested');
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
    return Scaffold(
      body: BlocBuilder<StationBloc, StationState>(
        builder: (context, state) {
          if (state is StationDetailLoaded) {
            debugPrint('[StationDetail] StationDetailLoaded received, pv=${state.station?['pv_power']}, load=${state.station?['load_power']}');
            _cachedState = state;
            _initMQTTRealtime(state);
          }
          if (state is StationError) {
            debugPrint('[StationDetail] StationError: ${state.message}');
          }
          final ds = _cachedState;
          if (ds == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary));

          final station = ds.station;
          if (station == null) return const Center(child: Text('电站不存在'));

          if (_activeTab == 'statistics') {
            return _buildStatisticsBody(station);
          }
          if (_activeTab == 'devices') {
            return _buildDevicesBody(ds);
          }

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
        },
      ),
      bottomNavigationBar: _bottomBar(),
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
          if (_weatherTemp != null)
            Row(
              children: [
                Text(_weatherIcon, style: TextStyle(fontSize: 16.sp)),
                SizedBox(width: 6.w),
                Text(_weatherTemp!, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
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
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, child) => CustomPaint(
                painter: _EnergyFlowPainter(flows: flows, animValue: _anim.value),
              ),
            ),
          ),
          _energyNode('光伏', pvW, Icons.wb_sunny, const Color(0xFFF59E0B), Alignment.topCenter, true),
          _energyNode('负载', loadW, Icons.home_rounded, const Color(0xFF3B82F6), Alignment.bottomCenter, false),
          _energyNodeBatt('储能', battW, soc, Icons.battery_charging_full, AppColors.successLight, const Alignment(-0.75, 0)),
          _energyNode('电网', gridW, Icons.electrical_services, AppColors.textSecondary, const Alignment(0.75, 0), true),
        ],
      ),
    );
  }

  Widget _energyNode(String label, String val, IconData icon, Color color, Alignment align, bool labelAbove) {
    final labelWidget = Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (labelAbove) labelWidget,
          if (labelAbove) SizedBox(height: 4.h),
          Container(
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
          ),
          if (!labelAbove) SizedBox(height: 4.h),
          if (!labelAbove) labelWidget,
        ],
      ),
    );
  }

  Widget _energyNodeBatt(String label, String val, double soc, IconData icon, Color color, Alignment align) {
    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          SizedBox(height: 4.h),
          Container(
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
          ),
        ],
      ),
    );
  }

  List<FlowEdge> _computeFlows(double pv, double batt, double grid, double load) {
    final flows = <FlowEdge>[];
    const threshold = 0.0;

    if (pv > threshold) {
      if (load > threshold) {
        flows.add(FlowEdge(
          from: NodePosition.top, to: NodePosition.bottom,
          fromColor: const Color(0xFFF59E0B), toColor: const Color(0xFF3B82F6),
        ));
      }
      if (batt > threshold) {
        flows.add(FlowEdge(
          from: NodePosition.top, to: NodePosition.left,
          fromColor: const Color(0xFFF59E0B), toColor: AppColors.successLight,
        ));
      }
    }
    if (batt < -threshold) {
      flows.add(FlowEdge(
        from: NodePosition.left, to: NodePosition.bottom,
        fromColor: AppColors.successLight, toColor: const Color(0xFF3B82F6),
      ));
    }
    return flows;
  }

  Widget _twoCards(double pvW, double totalPowerW, double todayKwh) {
    final w = totalPowerW > 0 ? totalPowerW.toStringAsFixed(0) : pvW.toStringAsFixed(0);
    final kwh = todayKwh.toStringAsFixed(1);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(child: _crd(Icons.bolt_rounded, w, 'W', '当前功率', const Color(0xFFF59E0B))),
          SizedBox(width: 10.w),
          Expanded(child: _crd(Icons.wb_sunny_outlined, kwh, 'kWh', '今日发电', AppColors.successLight)),
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
    final active = (i == 0 && _activeTab == 'overview') || (i == 1 && _activeTab == 'statistics') || (i == 2 && _activeTab == 'devices');
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = i == 0 ? 'overview' : i == 1 ? 'statistics' : 'devices'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20.sp, color: active ? AppColors.primary : AppColors.textHint),
            SizedBox(height: 2.h),
            Text(label, style: TextStyle(fontSize: 10.sp, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? AppColors.primary : AppColors.textHint)),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesBody(dynamic ds) {
    final devices = (ds.devices as List?) ?? [];
    final filtered = _filterDevices(devices);

    final name = ds.station['station_name'] ?? ds.station['name'] ?? '';

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFFF5F7FA)),
        ),
        Column(
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top + 6.h),
            _statsTopBar(name),
            _buildDeviceFilterBar(),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('暂无设备', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 100.h),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _buildDeviceCard(filtered[i]),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  List<dynamic> _filterDevices(List<dynamic> devices) {
    if (_deviceFilter == 0) return devices;
    return devices.where((d) {
      final t = _deviceType(d);
      switch (_deviceFilter) {
        case 1: return t == 'inv';
        case 2: return t == 'collector';
        case 3: return t == 'battery';
        default: return true;
      }
    }).toList();
  }

  String _deviceType(dynamic d) {
    final model = (d['model'] ?? '').toString().toLowerCase();
    final sn = (d['sn'] ?? '').toString().toLowerCase();
    if (model.contains('battery') || model.contains('bms') || model.contains('储能') || sn.contains('batt')) return 'battery';
    if (model.contains('collect') || model.contains('采集') || model.contains('daq') || sn.contains('col')) return 'collector';
    return 'inv';
  }

  Widget _buildDeviceFilterBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 10.h),
      child: Row(
        children: List.generate(4, (i) {
          final active = _deviceFilter == i;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 3.w),
              child: GestureDetector(
                onTap: () => setState(() => _deviceFilter = i),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary.withValues(alpha: 0.1) : const Color(0xFFF8FAFB),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: active ? AppColors.primary.withValues(alpha: 0.4) : AppColors.surfaceHover,
                    ),
                  ),
                  child: Center(
                    child: Text(_deviceFilters[i],
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: active ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device) {
    final sn = device['sn'] ?? '';
    final model = device['model'] ?? '--';
    final firmware = device['firmware_version'] ?? '--';
    final hardware = device['hardware_version'] ?? '--';
    final ratedPower = (device['rated_power'] as num?)?.toDouble() ?? 0;
    final type = _deviceType(device);
    final status = device['status'] ?? 0;
    final isOnline = status == 1;

    return GestureDetector(
      onTap: () {
        _showDeviceDetail(device);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8.w, height: 8.w,
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.successLight : AppColors.textHint,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(sn, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                Text(_deviceTypeLabel(type), style: TextStyle(fontSize: 11.sp, color: AppColors.textHint)),
              ],
            ),
            SizedBox(height: 10.h),
            _deviceInfoRow('SN 号', sn),
            _deviceInfoRow('设备类型', _deviceTypeLabel(type)),
            _deviceInfoRow('型号名称', model),
            Row(
              children: [
                Expanded(child: _deviceInfoCell('固件版本', firmware)),
                GestureDetector(
                  onTap: () => context.push('/firmware-history/$sn'),
                  child: Padding(
                    padding: EdgeInsets.only(left: 4.w),
                    child: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textHint),
                  ),
                ),
              ],
            ),
            if (ratedPower > 0) _deviceInfoRow('额定功率', '${ratedPower.toStringAsFixed(0)} W'),
            if (hardware.isNotEmpty && hardware != '--') _deviceInfoRow('硬件版本', hardware),
            if (type == 'battery') ..._buildBatteryExtras(device),
            if (type == 'inv') ..._buildInverterExtras(device),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBatteryExtras(dynamic device) {
    return [
      const Divider(height: 20, color: AppColors.surfaceHover),
      _deviceInfoRow('电池 SOC', '--%'),
      _deviceInfoRow('电池健康度', '--%'),
      _deviceInfoRow('当日充电量', '-- kWh'),
      _deviceInfoRow('当日放电量', '-- kWh'),
    ];
  }

  List<Widget> _buildInverterExtras(dynamic device) {
    return [
      const Divider(height: 20, color: AppColors.surfaceHover),
      _deviceInfoRow('运行模式', '--'),
      _deviceInfoRow('当前功率', '-- kW'),
      _deviceInfoRow('当日发电量', '-- kWh'),
    ];
  }

  Widget _deviceInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _deviceInfoCell(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textHint)),
          SizedBox(width: 8.w),
          Text(value, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  String _deviceTypeLabel(String type) {
    switch (type) {
      case 'inv': return '逆变器';
      case 'collector': return '采集器';
      case 'battery': return '储能设备';
      default: return '未知';
    }
  }

  void _showDeviceDetail(dynamic device) {
    final sn = device['sn'] ?? '';
    final type = _deviceType(device);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceDetailSheet(sn: sn, type: type),
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
    if (flows.isEmpty) return;

    final margin = 70.0;
    final cx = size.width / 2;
    final cy = size.height / 2;

    Offset centerOf(NodePosition pos) {
      switch (pos) {
        case NodePosition.top:    return Offset(cx, margin + nodeR + 16);
        case NodePosition.bottom: return Offset(cx, size.height - margin - nodeR);
        case NodePosition.left:   return Offset(size.width * 0.18, cy);
        case NodePosition.right:  return Offset(size.width * 0.82, cy);
      }
    }

    for (final flow in flows) {
      final src = centerOf(flow.from);
      final dst = centerOf(flow.to);

      if (_match(flow, NodePosition.top, NodePosition.bottom)) {
        _drawStraight(canvas, src, dst, flow.fromColor, flow.toColor);
      } else if (_match(flow, NodePosition.top, NodePosition.left)) {
        _drawArcTL(canvas, src, dst, cx, cy, flow.fromColor, flow.toColor);
      } else if (_match(flow, NodePosition.left, NodePosition.bottom)) {
        _drawArcLB(canvas, src, dst, cx, cy, flow.fromColor, flow.toColor);
      }
    }
  }

  void _drawStraight(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final shader = ui.Gradient.linear(a, b, [ca, cb]);
    canvas.drawLine(a, b, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.8..strokeCap = StrokeCap.round..shader = shader);
    _particles(canvas, a, b, ca);
  }

  void _drawArcTL(Canvas canvas, Offset src, Offset dst, double cx, double cy, Color ca, Color cb) {
    // PV → Battery: vertical down from PV center, horizontal left at cornerY, arc to battery right edge center
    // Corner at (dst.dx + nodeR, dst.dy) - battery's right edge center
    // Arc center at corner, arc sweeps from top(270°) to left(180°)
    final cornerX = dst.dx + nodeR;
    final cornerY = dst.dy;
    // Arc center at corner
    final arcCx = cornerX;
    final arcCy = cornerY;
    // Arc: from top (arcCx, arcCy - arcR) to left (arcCx - arcR, arcCy) = horizontal line end
    final pArcStart = Offset(arcCx, arcCy - arcR);
    final pArcEnd = Offset(arcCx - arcR, arcCy);
    // Vertical line: from PV bottom center down to cornerY
    final pTop = Offset(cx, src.dy + nodeR);
    final pCorner = Offset(cx, cornerY);
    final mid = Color.lerp(ca, cb, 0.5)!;
    _line(canvas, pTop, pCorner, ca, mid);
    // Horizontal line: from corner left to arc top
    _line(canvas, pCorner, pArcStart, mid, mid);
    _arc(canvas, arcCx, arcCy, arcR, pArcStart, pArcEnd, mid);
    final total = (pTop - pCorner).distance + (pCorner - pArcStart).distance + pi * arcR / 2;
    final a1 = atan2(pArcStart.dy - arcCy, pArcStart.dx - arcCx);
    final a2 = atan2(pArcEnd.dy - arcCy, pArcEnd.dx - arcCx);
    double sweep = a2 - a1;
    while (sweep > pi) sweep -= 2 * pi;
    while (sweep < -pi) sweep += 2 * pi;
    _arcParticles(canvas, pTop, pCorner, pArcEnd, pArcEnd, arcCx, arcCy, arcR, a1, sweep, total, ca);
  }

  void _drawArcLB(Canvas canvas, Offset src, Offset dst, double cx, double cy, Color ca, Color cb) {
    // Battery → Load: horizontal right from battery right edge, arc down to load center
    // Corner at (load center X, battery center Y)
    // Arc center at corner, arc sweeps from left(180°) to bottom(270°)
    final cornerX = cx; // Load center X
    final cornerY = src.dy; // Battery center Y
    // Arc center at corner
    final arcCx = cornerX;
    final arcCy = cornerY;
    // Arc: from left (arcCx - arcR, arcCy) to bottom (arcCx, arcCy + arcR)
    final pArcStart = Offset(arcCx - arcR, arcCy);
    final pArcEnd = Offset(arcCx, arcCy + arcR);
    // Horizontal line: from battery right edge to arc left
    final battEdge = Offset(src.dx + nodeR, cornerY);
    final mid = Color.lerp(ca, cb, 0.5)!;
    _line(canvas, battEdge, pArcStart, ca, mid);
    _arc(canvas, arcCx, arcCy, arcR, pArcStart, pArcEnd, mid);
    _line(canvas, pArcEnd, dst, mid, cb);
    final total = (battEdge - pArcStart).distance + pi * arcR / 2 + (pArcEnd - dst).distance;
    final a1 = atan2(pArcStart.dy - arcCy, pArcStart.dx - arcCx);
    final a2 = atan2(pArcEnd.dy - arcCy, pArcEnd.dx - arcCx);
    double sweep = a2 - a1;
    while (sweep > pi) sweep -= 2 * pi;
    while (sweep < -pi) sweep += 2 * pi;
    _arcParticles(canvas, battEdge, pArcStart, pArcEnd, dst, arcCx, arcCy, arcR, a1, sweep, total, ca);
  }

  void _line(Canvas canvas, Offset a, Offset b, Color ca, Color cb) {
    final shader = ui.Gradient.linear(a, b, [ca, cb]);
    canvas.drawLine(a, b, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.8..strokeCap = StrokeCap.round..shader = shader);
  }

  void _arc(Canvas canvas, double cx, double cy, double r, Offset from, Offset to, Color c) {
    final a1 = atan2(from.dy - cy, from.dx - cx);
    final a2 = atan2(to.dy - cy, to.dx - cx);
    double sweep = a2 - a1;
    while (sweep > pi) sweep -= 2 * pi;
    while (sweep < -pi) sweep += 2 * pi;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), a1, sweep, false,
      Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.8..strokeCap = StrokeCap.round);
  }

  void _particles(Canvas canvas, Offset a, Offset b, Color c) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final angle = atan2(dy, dx);
    for (int i = 0; i < 8; i++) {
      final t = (i / 8.0 + animValue * 0.45) % 1.0;
      final px = a.dx + dx * t, py = a.dy + dy * t;
      final alpha = 0.3 + 0.5 * (1.0 - (t - animValue * 0.45).abs() * 3.0).clamp(0.0, 1.0);
      _dot(canvas, px, py, angle, alpha, c);
    }
  }

  void _arcParticles(Canvas canvas, Offset src, Offset p1, Offset p4, Offset dst,
      double cx, double cy, double r, double a1, double sweep, double total, Color c) {
    final s1 = (src - p1).distance, aLen = pi * r / 2, s2 = (p4 - dst).distance;
    final aDir1 = atan2(p1.dy - src.dy, p1.dx - src.dx);
    final aDir2 = atan2(dst.dy - p4.dy, dst.dx - p4.dx);
    for (int i = 0; i < 8; i++) {
      final t = (i / 8.0 + animValue * 0.45) % 1.0;
      final alpha = 0.3 + 0.5 * (1.0 - (t - animValue * 0.45).abs() * 3.0).clamp(0.0, 1.0);
      final d = t * total;
      double px, py, angle;
      if (d < s1) {
        final lt = d / s1;
        px = src.dx + (p1.dx - src.dx) * lt;
        py = src.dy + (p1.dy - src.dy) * lt;
        angle = aDir1;
      } else if (d < s1 + aLen) {
        final a = a1 + sweep * (d - s1) / aLen;
        px = cx + r * cos(a);
        py = cy + r * sin(a);
        angle = a + pi / 2 * sweep.sign;
      } else {
        final lt = (d - s1 - aLen) / s2;
        px = p4.dx + (dst.dx - p4.dx) * lt;
        py = p4.dy + (dst.dy - p4.dy) * lt;
        angle = aDir2;
      }
      _dot(canvas, px, py, angle, alpha, c);
    }
  }

  void _dot(Canvas canvas, double x, double y, double angle, double alpha, Color c) {
    canvas.drawCircle(Offset(x, y), 5.0, Paint()
      ..color = c.withValues(alpha: alpha * 0.5)..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(x, y), 3.0, Paint()
      ..color = c.withValues(alpha: alpha)..style = PaintingStyle.fill);
    final s = 7.0;
    canvas.drawLine(Offset(x - cos(angle)*s, y - sin(angle)*s),
                    Offset(x + cos(angle)*s, y + sin(angle)*s),
      Paint()..color = c.withValues(alpha: alpha*0.7)..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _EnergyFlowPainter old) =>
      flows.length != old.flows.length || animValue != old.animValue;
}

class _DeviceDetailSheet extends StatefulWidget {
  final String sn;
  final String type;

  const _DeviceDetailSheet({required this.sn, required this.type});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> with TickerProviderStateMixin {
  Map<String, dynamic>? _realtime;
  bool _loading = true;
  late AnimationController _pulseAnim;

  static const _topicGroups = [
    {
      'title': '交流输出',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFF8B5CF6),
      'keys': {
        '电压 (V)': 'ac_voltage',
        '电流 (A)': 'ac_current',
        '功率 (W)': 'ac_power',
        '频率 (Hz)': 'ac_frequency',
        '负载率 (%)': 'ac_load_percent',
      },
    },
    {
      'title': '电池状态',
      'icon': Icons.battery_charging_full,
      'color': AppColors.successLight,
      'keys': {
        'SOC (%)': 'batt_soc',
        'SOH (%)': 'batt_soh',
        '电压 (V)': 'batt_voltage',
        '电流 (A)': 'batt_current',
        '充电状态': 'batt_charge_state',
      },
    },
    {
      'title': '光伏 MPPT',
      'icon': Icons.wb_sunny_outlined,
      'color': Color(0xFFF59E0B),
      'keys': {
        'PV 电压 (V)': 'pv_voltage',
        'PV 电流 (A)': 'pv_current',
        'PV 功率 (W)': 'pv_power',
        'MPPT 状态': 'mppt_state',
      },
    },
    {
      'title': '系统状态',
      'icon': Icons.info_outline_rounded,
      'color': Color(0xFF06B6D4),
      'keys': {
        '工作状态': 'state',
        '故障码': 'fault_code',
        '告警码': 'alarm_code',
        '逆变器温度 (℃)': 'temp_inv',
        'MOS温度 (℃)': 'temp_mos',
        '效率 (%)': 'efficiency',
      },
    },
    {
      'title': '能量统计',
      'icon': Icons.show_chart_rounded,
      'color': AppColors.primary,
      'keys': {
        '当日发电量 (kWh)': 'daily_pv',
        '累计发电量 (kWh)': 'total_pv',
        '运行时间 (h)': 'runtime_hours',
      },
    },
    {
      'title': '设备信息',
      'icon': Icons.devices_rounded,
      'color': Color(0xFF8B5CF6),
      'keys': {
        'SN': 'sn',
        '型号': 'model',
        '厂商': 'manufacturer',
        'ARM固件': 'firmware_arm',
        'ESP固件': 'firmware_esp',
        '类型': 'type',
        '额定功率 (W)': 'rated_power',
        '额定电压 (V)': 'rated_voltage',
        '额定频率 (Hz)': 'rated_freq',
        '电池电压 (V)': 'battery_voltage',
        '电池类型': 'battery_type',
        '电池串数': 'cell_count',
      },
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _fetchRealtime();
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    super.dispose();
  }

  Future<void> _fetchRealtime() async {
    try {
      final dio = getIt<Dio>();
      final res = await dio.get('/devices/${widget.sn}/realtime');
      if (res.statusCode == 200) {
        final outer = (res.data is Map) ? res.data as Map<String, dynamic> : {};
        final wrapper = (outer['data'] as Map<String, dynamic>?) ?? {};
        final realtime = (wrapper['realtime'] as Map<String, dynamic>?) ?? wrapper;
        
        final merged = <String, dynamic>{};
        
        final info = realtime['info'] as Map<String, dynamic>?;
        if (info != null) merged.addAll(info);
        
        final ac = realtime['ac'] as Map<String, dynamic>?;
        if (ac != null) merged.addAll({
          'ac_voltage': ac['voltage'],
          'ac_current': ac['current'],
          'ac_power': ac['power'],
          'ac_frequency': ac['frequency'],
          'ac_load_percent': ac['load_percent'],
        });
        
        final battery = realtime['battery'] as Map<String, dynamic>?;
        if (battery != null) merged.addAll({
          'batt_soc': battery['soc'],
          'batt_soh': battery['soh'],
          'batt_voltage': battery['voltage'],
          'batt_current': battery['current'],
          'batt_charge_state': battery['charge_state'],
        });
        
        final pv = realtime['pv'] as Map<String, dynamic>?;
        if (pv != null) merged.addAll({
          'pv_voltage': pv['pv_voltage'],
          'pv_current': pv['pv_current'],
          'pv_power': pv['pv_power'],
          'mppt_state': pv['mppt_state'],
        });
        
        final status = realtime['status'] as Map<String, dynamic>?;
        if (status != null) merged.addAll({
          'state': status['state'],
          'fault_code': status['fault_code'],
          'alarm_code': status['alarm_code'],
          'temp_inv': status['temp_inv'],
          'temp_mos': status['temp_mos'],
          'efficiency': status['efficiency'],
        });
        
        final energy = realtime['energy'] as Map<String, dynamic>?;
        if (energy != null) merged.addAll({
          'daily_pv': energy['daily_pv'],
          'total_pv': energy['total_pv'],
          'runtime_hours': energy['runtime_hours'],
        });
        
        debugPrint('[DeviceDetail] realtime loaded, merged keys: ${merged.keys.length}');
        if (mounted) setState(() { _realtime = merged; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('[DeviceDetail] _fetchRealtime error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic val, [String unit = '']) {
    if (val == null) return '--';
    if (val is List) {
      if (val.isEmpty) return '--';
      final n = val.first;
      if (n is num) return n.toStringAsFixed(1);
      return n.toString();
    }
    if (val is double) {
      final s = val % 1 == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
      return unit.isEmpty ? s : '$s $unit';
    }
    if (val is int) return unit.isEmpty ? '$val' : '$val $unit';
    return unit.isEmpty ? '$val' : '$val $unit';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: EdgeInsets.symmetric(vertical: 10.h),
                width: 40.w, height: 4.h,
                decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
              ),
              Row(
                children: [
                  SizedBox(width: 16.w),
                  Text('设备实时数据', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(widget.sn, style: TextStyle(fontSize: 11.sp, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(width: 16.w),
                ],
              ),
              SizedBox(height: 8.h),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : _realtime == null
                        ? Center(child: Text('暂无实时数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)))
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _fetchRealtime,
                            child: ListView.builder(
                              controller: scrollController,
                              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 60.h),
                              itemCount: _topicGroups.length,
                              itemBuilder: (_, i) => _buildTopicCard(_topicGroups[i]),
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopicCard(Map<String, dynamic> group) {
    final title = group['title'] as String;
    final icon = group['icon'] as IconData;
    final color = group['color'] as Color;
    final keysRaw = group['keys'] as Map;
    final keys = keysRaw.map((k, v) => MapEntry(k.toString(), v.toString()));

    final items = <Widget>[];
    var first = true;
    keys.forEach((label, key) {
      if (!first) {
        items.add(const Divider(height: 1, color: AppColors.surfaceHover));
      }
      first = false;
      items.add(_dataItem(label, _realtime?[key]));
    });

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(title, icon, color),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(String title, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Container(
              width: 6.w, height: 6.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3 + _pulseAnim.value * 0.5),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4)],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Icon(icon, size: 18.sp, color: color),
          SizedBox(width: 6.w),
          Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _dataItem(String label, dynamic value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ),
          Text(
            _fmt(value),
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: value != null ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
