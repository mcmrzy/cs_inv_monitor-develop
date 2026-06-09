import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';

class HistoryChartPage extends StatefulWidget {
  final String deviceSN;

  const HistoryChartPage({super.key, required this.deviceSN});

  @override
  State<HistoryChartPage> createState() => _HistoryChartPageState();
}

class _HistoryChartPageState extends State<HistoryChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedMetricIndex = 0;
  DateTime _selectedDate = DateTime.now();

  static const _metrics = [
    ('发电量', 'pv', Colors.orange),
    ('充电量', 'charge', AppColors.success),
    ('放电量', 'discharge', Colors.blue),
    ('负载电量', 'load', Colors.purple),
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

  String get _currentMetric => _metrics[_selectedMetricIndex].$2;

  void _requestData() {
    final now = _selectedDate;
    String startDate;
    String endDate;

    switch (_currentPeriod) {
      case 'day':
        startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        endDate = startDate;
        break;
      case 'month':
        startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        endDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${DateUtils.getDaysInMonth(now.year, now.month).toString().padLeft(2, '0')}';
        break;
      case 'year':
        startDate = '${now.year}-01-01';
        endDate = '${now.year}-12-31';
        break;
      default:
        startDate = '2020-01-01';
        endDate = '${DateTime.now().year}-12-31';
    }

    context.read<DeviceBloc>().add(DeviceHistoryRequested(
          sn: widget.deviceSN,
          period: _currentPeriod,
          startDate: startDate,
          endDate: endDate,
          metric: _currentMetric,
        ));
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

  String get _dateLabel {
    switch (_currentPeriod) {
      case 'day':
        return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      case 'month':
        return '${_selectedDate.year}年${_selectedDate.month}月';
      case 'year':
        return '${_selectedDate.year}年';
      default:
        return '全部';
    }
  }

  List<FlSpot> _convertToFlSpots(List<Map<String, dynamic>> data) {
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final x = (item['x'] as num?)?.toDouble() ?? i.toDouble();
      final y = (item['y'] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(x, y));
    }
    if (spots.isEmpty) {
      spots.add(const FlSpot(0, 0));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('历史曲线 - ${widget.deviceSN}'),
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textHint,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: '日'),
                Tab(text: '月'),
                Tab(text: '年'),
                Tab(text: '总'),
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
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 16.sp, color: AppColors.primary),
                        SizedBox(width: 6.w),
                        Text(
                          _dateLabel,
                          style: TextStyle(fontSize: 13.sp, color: AppColors.primary, fontWeight: FontWeight.w600),
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
              children: List.generate(_metrics.length, (index) {
                final metric = _metrics[index];
                final selected = _selectedMetricIndex == index;
                return FilterChip(
                  label: Text(metric.$1),
                  selected: selected,
                  selectedColor: metric.$3.withValues(alpha: 0.15),
                  checkmarkColor: metric.$3,
                  labelStyle: TextStyle(
                    color: selected ? metric.$3 : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12.sp,
                  ),
                  side: BorderSide(
                    color: selected ? metric.$3.withValues(alpha: 0.4) : AppColors.divider,
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
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is DeviceError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 40.sp, color: AppColors.error),
                        SizedBox(height: 8.h),
                        Text(state.message, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                }
                if (state is DeviceHistoryLoaded) {
                  final spots = _convertToFlSpots(state.data);
                  final metricColor = _metrics[_selectedMetricIndex].$3;
                  return _buildChart(spots, metricColor);
                }
                return Center(
                  child: Text('暂无数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _buildChart(List<FlSpot> spots, Color color) {
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

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: maxY > 5 ? (maxY / 5) : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.divider.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: AppColors.divider.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _calculateBottomInterval(spots),
                getTitlesWidget: (value, meta) => _buildBottomTitle(value, meta, spots),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                interval: (maxY - minY) > 5 ? (maxY - minY) / 5 : 1,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: AppColors.divider),
              left: BorderSide(color: AppColors.divider),
            ),
          ),
          minX: spots.first.x,
          maxX: spots.last.x,
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
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
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
              tooltipBgColor: Colors.grey.shade800,
              tooltipRoundedRadius: 8,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(2)} kWh',
                    TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w600),
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

  Widget _buildBottomTitle(double value, TitleMeta meta, List<FlSpot> spots) {
    final period = _currentPeriod;
    String text;
    if (period == 'day') {
      text = '${value.toInt()}h';
    } else if (period == 'month') {
      text = '${value.toInt()}日';
    } else if (period == 'year') {
      text = '${value.toInt()}月';
    } else {
      text = '${value.toInt()}';
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(
        text,
        style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
      ),
    );
  }
}
