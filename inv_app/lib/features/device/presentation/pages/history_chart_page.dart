import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/core/widgets/xiaoshuo_state_panel.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

class HistoryChartPage extends StatefulWidget {
  final String deviceSN;

  const HistoryChartPage({super.key, required this.deviceSN});

  @override
  State<HistoryChartPage> createState() => _HistoryChartPageState();
}

/// 单个图表点：后端行解析出的时间 + 按指标映射出的 y 值
class _ChartPoint {
  final DateTime time;
  final double value;
  const _ChartPoint(this.time, this.value);
}

class _HistoryChartPageState extends State<HistoryChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedMetricIndex = 0;
  DateTime _selectedDate = DateTime.now();

  // 指标 chip：设备维度历史接口（GET /devices/by-sn/:sn/history）仅返回
  // time/avg_power/max_power/energy_produce/avg_temperature/run_minutes，
  // 没有电池充/放电字段（battery_charge/discharge 只存在于电站级接口），
  // 故充电/放电 chip 移除——不映射相似字段伪造数据（审计 P0 ④的取舍）。
  List<(String, String, Color)> _getMetrics(AppLocalizations l10n) => [
        (l10n.powerGeneration, 'pv', Colors.orange),
        (l10n.load, 'load', Colors.purple),
      ];

  static const _periods = ['day', 'month', 'year', 'total'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _requestData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _requestData();
    }
  }

  String get _currentPeriod => _periods[_tabController.index];

  static const _metricKeys = ['pv', 'load'];
  static const _metricColors = [
    Colors.orange,
    Colors.purple,
  ];

  String get _currentMetric =>
      _metricKeys[_selectedMetricIndex.clamp(0, _metricKeys.length - 1)];

  /// UI 周期 → 后端 period。
  /// day 档改走小时表（后端 period='hour' → device_telemetry_hour），
  /// 拿到整天 24 个小时桶；此前发 period='day' 且 start==end，
  /// 落到日表只回 1 行（审计 P0 ②）。
  /// month/year/total 走日表（device_energy_day）逐日聚合（审计 P0 ③）。
  String get _apiPeriod => _currentPeriod == 'day' ? 'hour' : _currentPeriod;

  void _requestData() {
    final now = _selectedDate;
    String startDate;
    String endDate;

    switch (_currentPeriod) {
      case 'day':
        startDate =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        endDate = startDate;
        break;
      case 'month':
        startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        endDate =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${DateUtils.getDaysInMonth(now.year, now.month).toString().padLeft(2, '0')}';
        break;
      case 'year':
        startDate = '${now.year}-01-01';
        endDate = '${now.year}-12-31';
        break;
      default:
        startDate = '2020-01-01';
        endDate = '${DateTime.now().year}-12-31';
    }

    context.read<DeviceBloc>().add(
          DeviceHistoryRequested(
            sn: widget.deviceSN,
            period: _apiPeriod,
            startDate: startDate,
            endDate: endDate,
            metric: _currentMetric,
          ),
        );
  }

  Future<void> _pickDate() async {
    if (_currentPeriod == 'total') return;

    DateTime? picked;
    if (_currentPeriod == 'day') {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
    } else if (_currentPeriod == 'month') {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        picked = DateTime(picked.year, picked.month, 1);
      }
    } else if (_currentPeriod == 'year') {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        picked = DateTime(picked.year, 1, 1);
      }
    }

    if (picked != null) {
      setState(() {
        _selectedDate = picked!;
      });
      _requestData();
    }
  }

  String _getDateLabel(AppLocalizations l10n) {
    switch (_currentPeriod) {
      case 'day':
        return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      case 'month':
        return '${_selectedDate.year}${l10n.year}${_selectedDate.month}${l10n.month}';
      case 'year':
        return '${_selectedDate.year}${l10n.year}';
      default:
        return l10n.total;
    }
  }

  double? _asDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  /// 后端 `time` 字段（Go time.Time → RFC3339 字符串）解析为本地时间做 x 轴。
  /// 此前页面读不存在的 `item['x']/item['y']`，恒回退 0（审计 P0 ①）。
  DateTime? _parseTime(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  /// 按当前指标从后端行数据映射 y 值：
  /// - 发电 pv → energy_produce（小时表=daily_pv_energy，日表=pv_energy）
  /// - 负载 load → avg_power（小时表=avg_ac_power 平均交流输出功率）；
  ///   日表无负载/平均功率字段（avg_power 恒为 NULL→0），
  ///   退化为 max_power（max_ac_power 当日峰值，最接近的可用字段）
  double? _yForItem(Map<String, dynamic> item) {
    switch (_currentMetric) {
      case 'pv':
        return _asDouble(item['energy_produce']);
      case 'load':
        final raw =
            _currentPeriod == 'day' ? item['avg_power'] : item['max_power'];
        return _asDouble(raw);
      default:
        return null;
    }
  }

  /// 后端行 → 图表点。time 无法解析或 y 字段缺失的行跳过，
  /// 宁可展示空态也不画 0 平线（审计 P0 ⑤）。
  List<_ChartPoint> _mapToChartPoints(List<Map<String, dynamic>> data) {
    final points = <_ChartPoint>[];
    for (final item in data) {
      final time = _parseTime(item['time']);
      final y = _yForItem(item);
      if (time == null || y == null) continue;
      points.add(_ChartPoint(time, y));
    }
    return points;
  }

  /// x 值：day=小时(含分钟小数)、month=日、year=月；total 用索引均分
  double _xOf(_ChartPoint point, int index) {
    switch (_currentPeriod) {
      case 'day':
        return point.time.hour + point.time.minute / 60.0;
      case 'month':
        return point.time.day.toDouble();
      case 'year':
        return point.time.month.toDouble();
      default:
        return index.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final metrics = _getMetrics(l10n);
    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.historyCurve} - ${widget.deviceSN}'),
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColor.textHint(context),
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: l10n.day),
                Tab(text: l10n.month),
                Tab(text: l10n.year),
                Tab(text: l10n.total),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16.sp,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          _getDateLabel(l10n),
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Wrap(
              spacing: 8.w,
              children: List.generate(metrics.length, (index) {
                final metric = metrics[index];
                final selected = _selectedMetricIndex == index;
                return FilterChip(
                  label: Text(metric.$1),
                  selected: selected,
                  selectedColor: metric.$3.withValues(alpha: 0.15),
                  checkmarkColor: metric.$3,
                  labelStyle: TextStyle(
                    color: selected ? metric.$3 : AppColor.textSecondary(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12.sp,
                  ),
                  side: BorderSide(
                    color: selected
                        ? metric.$3.withValues(alpha: 0.4)
                        : AppColor.divider(context),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedMetricIndex = index;
                    });
                    _requestData();
                  },
                );
              }),
            ),
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: BlocBuilder<DeviceBloc, DeviceState>(
              builder: (context, state) {
                if (state is DeviceLoading) {
                  return const PageSkeleton();
                }
                if (state is DeviceError) {
                  // 小烁离线动作插画：历史数据加载失败（美术路由 C4/offline）
                  return XiaoshuoStatePanel(
                    asset: CsergyAssets.xiaoshuoOffline,
                    title: AppLocalizations.of(context)!
                        .translateError(state.message),
                    message: l10n.loadFailed,
                    size: 168,
                    action: OutlinedButton(
                      onPressed: _requestData,
                      child: Text(l10n.retry),
                    ),
                  );
                }
                if (state is DeviceHistoryLoaded) {
                  final points = _mapToChartPoints(state.data);
                  if (points.isEmpty) {
                    // 后端无该档数据：展示空态而不是画 0 平线（审计 P0 ⑤）
                    return XiaoshuoStatePanel(
                      asset: CsergyAssets.emptyRecord,
                      title: l10n.noData,
                      size: 160,
                    );
                  }
                  final spots = <FlSpot>[
                    for (var i = 0; i < points.length; i++)
                      FlSpot(_xOf(points[i], i), points[i].value),
                  ];
                  final metricColor = _metricColors[
                      _selectedMetricIndex.clamp(0, _metricColors.length - 1)];
                  return _buildChart(spots, points, metricColor);
                }
                // 小烁查询空态插画：历史数据为空（美术路由 S4/empty-record）
                return XiaoshuoStatePanel(
                  asset: CsergyAssets.emptyRecord,
                  title: l10n.noData,
                  size: 160,
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _buildChart(
    List<FlSpot> spots,
    List<_ChartPoint> points,
    Color color,
  ) {
    double minY = 0;
    double maxY = 1;
    if (spots.isNotEmpty) {
      final values = spots.map((s) => s.y).toList();
      minY = values.reduce((a, b) => a < b ? a : b);
      maxY = values.reduce((a, b) => a > b ? a : b);
      if (minY == maxY) {
        minY = minY - 1;
        maxY = maxY + 1;
      }
      final padding = (maxY - minY) * 0.1;
      minY = (minY - padding).clamp(0, double.infinity);
      maxY = maxY + padding;
    }

    // 单点数据：minX==maxX 时扩出可视区间，只渲染数据点
    double minX = spots.first.x;
    double maxX = spots.last.x;
    if (minX == maxX) {
      minX = minX - 0.5;
      maxX = maxX + 0.5;
    }

    // 负载是功率（kW），发电是电量（kWh），tooltip 单位随指标
    final unit = _currentMetric == 'load' ? 'kW' : 'kWh';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: maxY > 5 ? (maxY / 5) : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColor.divider(context).withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: AppColor.divider(context).withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _calculateBottomInterval(spots),
                getTitlesWidget: (value, meta) =>
                    _buildBottomTitle(value, meta, points),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                interval: (maxY - minY) > 5 ? (maxY - minY) / 5 : 1,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10.sp, color: AppColor.textHint(context)),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: AppColor.divider(context)),
              left: BorderSide(color: AppColor.divider(context)),
            ),
          ),
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(
                show: spots.length <= 30,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.08),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              // tooltip 保持深色底白字；暗色用浮层语义色
              getTooltipColor: (spot) =>
                  Theme.of(context).brightness == Brightness.dark
                      ? AppColor.surfaceContainer(context)
                      : AppColor.textPrimary(context),
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(2)} $unit',
                    TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  double? _calculateBottomInterval(List<FlSpot> spots) {
    if (spots.length <= 1) return null;
    final range = spots.last.x - spots.first.x;
    if (range <= 0) return null;
    final interval = range / 5;
    return interval;
  }

  Widget _buildBottomTitle(
    double value,
    TitleMeta meta,
    List<_ChartPoint> points,
  ) {
    final period = _currentPeriod;
    final l10n = AppLocalizations.of(context)!;
    String text;
    if (period == 'day') {
      text = '${value.toInt()}h';
    } else if (period == 'month') {
      text = '${value.toInt()}${l10n.day}';
    } else if (period == 'year') {
      text = '${value.toInt()}${l10n.month}';
    } else {
      // total 档 x 是索引：用对应点的月-日做标签（点按时间升序）
      final index = value.toInt().clamp(0, points.length - 1);
      final t = points[index].time;
      text =
          '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    return SideTitleWidget(
      meta: meta,
      child: Text(
        text,
        style: TextStyle(fontSize: 10.sp, color: AppColor.textHint(context)),
      ),
    );
  }
}
