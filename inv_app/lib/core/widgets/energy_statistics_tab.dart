import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/core/entities/energy_data_point.dart';
import 'package:dio/dio.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 图表视图类型
enum ChartViewType { line, bar, table }

/// 发电统计 Tab - 可复用组件
/// 支持 stationId 参数：null = 全部电站，非null = 筛选该电站
/// 用于数据统计页和电站详情页
class EnergyStatisticsTab extends StatefulWidget {
  final int? stationId; // null 表示全部电站

  const EnergyStatisticsTab({super.key, this.stationId});

  @override
  State<EnergyStatisticsTab> createState() => _EnergyStatisticsTabState();
}

class _EnergyStatisticsTabState extends State<EnergyStatisticsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _period = 'day'; // day / month / year
  DateTime _selectedDate = DateTime.now();
  bool _loading = false;
  List<EnergyDataPoint> _dataPoints = [];
  EnergySummary _summary = const EnergySummary();
  late AppLocalizations _l10n;
  
  // 通知数据
  List<Map<String, dynamic>> _alarms = [];
  bool _alarmsLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _fetchAlarms();
  }

  @override
  void didUpdateWidget(EnergyStatisticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stationId != widget.stationId) {
      _fetchData();
      _fetchAlarms();
    }
  }

  Future<void> _fetchAlarms() async {
    if (widget.stationId == null) {
      if (mounted) setState(() => _alarmsLoading = false);
      return;
    }
    setState(() => _alarmsLoading = true);
    try {
      final dio = getIt<Dio>();
      final response = await dio.get('/alarms', queryParameters: {
        'station_id': widget.stationId,
        'page': 1,
        'page_size': 5,
      },);
      if (response.statusCode == 200 && mounted) {
        final body = response.data;
        if (body is Map<String, dynamic> && body['code'] == 0) {
          final data = body['data'];
          if (data is Map<String, dynamic> && data['list'] is List) {
            setState(() {
              _alarms = List<Map<String, dynamic>>.from(data['list']);
              _alarmsLoading = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _alarmsLoading = false);
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);

    try {
      // 使用全局认证 Dio 实例，而不是创建裸 Dio
      final dio = getIt<Dio>();

      // 计算日期范围
      String startDate, endDate, period;
      switch (_period) {
        case 'day':
          startDate = _formatDate(_selectedDate);
          endDate = startDate;
          period = 'hour';
          break;
        case 'month':
          startDate = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-01';
          final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
          endDate = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-$lastDay';
          period = 'day';
          break;
        case 'year':
          startDate = '${_selectedDate.year}-01-01';
          endDate = '${_selectedDate.year}-12-31';
          period = 'month';
          break;
        default:
          startDate = _formatDate(_selectedDate);
          endDate = startDate;
          period = 'hour';
      }

      // 构建请求路径
      String path;
      if (widget.stationId != null) {
        path = '/stations/${widget.stationId}/statistics';
      } else {
        // 全部电站 - 使用 summary 端点或汇总
        path = '/stations/summary/statistics';
      }

      final response = await dio.get(path, queryParameters: {
        'start_date': startDate,
        'end_date': endDate,
        'period': period,
      },);

      if (response.statusCode == 200) {
        final body = response.data;
        List<dynamic> rawList = [];

        if (body is Map<String, dynamic>) {
          if (body['code'] == 0) {
            final data = body['data'];
            if (data is List) {
              rawList = data;
            } else if (data is Map<String, dynamic> && data['list'] is List) {
              rawList = data['list'] as List;
            }
          }
        } else if (body is List) {
          rawList = body;
        }

        final points = rawList
            .map((e) => EnergyDataPoint.fromStationStats(e as Map<String, dynamic>))
            .toList();

        if (mounted) {
          setState(() {
            _dataPoints = points;
            _summary = EnergySummary.fromDataPointsWithPeriod(points, _period);
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 格式化时间标签：hour -> "HH:00", day -> "MM-DD", month -> "M月"
  ///
  /// 后端返回 RFC3339 格式时间字符串（如 "2025-06-29T00:00:00Z"），
  /// 存储的是 UTC 时间，需通过 toLocal() 转换为设备本地时间。
  String _formatTimeLabel(String rawTime) {
    try {
      final dt = DateTime.parse(rawTime).toLocal();
      switch (_period) {
        case 'day': // hour 模式 → "Xh"
          return '${dt.hour}h';
        case 'month': // day 模式 → "MM-DD"
          return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        case 'year': // month 模式 → "M月"
          return '${dt.month}M';
        default:
          return rawTime;
      }
    } catch (_) {
      // 解析失败时回退到字符串截取
      final tIndex = rawTime.indexOf('T');
      switch (_period) {
        case 'day':
          if (tIndex >= 0 && rawTime.length > tIndex + 2) {
            return '${int.tryParse(rawTime.substring(tIndex + 1, tIndex + 3)) ?? rawTime.substring(tIndex + 1, tIndex + 3)}h';
          }
          break;
        case 'month':
          if (rawTime.length >= 10) return rawTime.substring(5, 10);
          break;
      }
      return rawTime;
    }
  }

  String _formatDateDisplay() {
    switch (_period) {
      case 'day':
        return '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';
      case 'month':
        return '${_selectedDate.year}/${_selectedDate.month}';
      case 'year':
        return '${_selectedDate.year}';
      default:
        return '';
    }
  }

  void _navigateDate(int offset) {
    setState(() {
      switch (_period) {
        case 'day':
          _selectedDate = _selectedDate.add(Duration(days: offset));
          break;
        case 'month':
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + offset, 1);
          break;
        case 'year':
          _selectedDate = DateTime(_selectedDate.year + offset, 1, 1);
          break;
      }
    });
    _fetchData();
  }

  void _changePeriod(String newPeriod) {
    if (_period == newPeriod) return;
    setState(() {
      _period = newPeriod;
      _selectedDate = DateTime.now();
    });
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    _l10n = l10n;

    return Column(
      children: [
        // 时间选择器（用于电量概览）
        _buildTimeSelector(l10n),
        SizedBox(height: 12.h),
        // 内容区
        Expanded(
          child: _loading
              ? _buildSkeleton()
              : RefreshIndicator(
                  onRefresh: () async {
                    await _fetchData();
                    await _fetchAlarms();
                  },
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    children: [
                      _buildEnergyCards(l10n),
                      SizedBox(height: 16.h),
                      // 功率趋势（只在日模式下显示）
                      if (_period == 'day') ...[
                        _buildPowerChartSection(l10n),
                        SizedBox(height: 16.h),
                      ],
                      // 电量概览（可切换日月年）
                      _buildEnergyChartSection(l10n),
                      SizedBox(height: 16.h),
                      // 通知信息
                      _buildAlarmSection(l10n),
                      SizedBox(height: 80.h),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 时间选择器 - 日/月/年 + 日期导航
  Widget _buildTimeSelector(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      color: AppColor.surface(context),
      child: Column(
        children: [
          // 周期切换
          Row(
            children: [
              _buildPeriodChip(l10n.day, 'day'),
              SizedBox(width: 8.w),
              _buildPeriodChip(l10n.month, 'month'),
              SizedBox(width: 8.w),
              _buildPeriodChip(l10n.year, 'year'),
            ],
          ),
          SizedBox(height: 8.h),
          // 日期导航
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _navigateDate(-1),
                icon: Icon(Icons.chevron_left, size: 24.sp, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.w),
              ),
              GestureDetector(
                onTap: _showDatePicker,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDateDisplay(),
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Icon(Icons.keyboard_arrow_down, size: 18.sp, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _navigateDate(1),
                icon: Icon(Icons.chevron_right, size: 24.sp, color: AppColors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.w),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, String value) {
    final isActive = _period == value;
    return GestureDetector(
      onTap: () => _changePeriod(value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// 4 宫格能源概览卡片
  Widget _buildEnergyCards(AppLocalizations l10n) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12.h,
      crossAxisSpacing: 12.w,
      childAspectRatio: 1.6,
      children: [
        _buildMetricCard(
          l10n.pvGeneration,
          _summary.pvTotal,
          'kWh',
          Icons.wb_sunny_rounded,
          AppColors.orange,
          _summary.pvChange,
        ),
        _buildMetricCard(
          l10n.batteryCharge,
          _summary.batteryChargeTotal,
          'kWh',
          Icons.battery_charging_full_rounded,
          AppColors.successLight,
          _summary.batteryChargeChange,
        ),
        _buildMetricCard(
          l10n.batteryDischarge,
          _summary.batteryDischargeTotal,
          'kWh',
          Icons.battery_std_rounded,
          AppColors.blue,
          _summary.batteryDischargeChange,
        ),
        _buildMetricCard(
          l10n.inverterOutput,
          _summary.inverterOutputTotal,
          'kWh',
          Icons.electric_bolt_rounded,
          AppColors.purple,
          _summary.inverterOutputChange,
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, double value, String unit, IconData icon, Color color, double? change) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColor.surface(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(icon, size: 16.sp, color: color),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value >= 1000 ? (value / 1000).toStringAsFixed(1) : value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      TextSpan(
                        text: ' ${value >= 1000 ? 'MWh' : unit}',
                        style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
                      ),
                    ],
                  ),
                ),
              ),
              if (change != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: (change >= 0 ? AppColors.successLight : AppColors.errorLight).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 10.sp,
                        color: change >= 0 ? AppColors.successLight : AppColors.errorLight,
                      ),
                      Text(
                        '${change.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                          color: change >= 0 ? AppColors.successLight : AppColors.errorLight,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 图表展示区
  /// 功率折线图区域
  Widget _buildPowerChartSection(AppLocalizations l10n) {
    if (_dataPoints.isEmpty) {
      return Container(
        height: 260.h,
        decoration: AppColor.card(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 48.sp, color: AppColors.textHint),
              SizedBox(height: 8.h),
              Text(l10n.noData, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.powerTrend,
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          SizedBox(height: 16.h),
          _buildLineChart(),
          SizedBox(height: 12.h),
          _buildPowerLegend(),
        ],
      ),
    );
  }

  /// 能量柱状图区域
  Widget _buildEnergyChartSection(AppLocalizations l10n) {
    if (_dataPoints.isEmpty) {
      return Container(
        height: 260.h,
        decoration: AppColor.card(context),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 48.sp, color: AppColors.textHint),
              SizedBox(height: 8.h),
              Text(l10n.noData, style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.energyTrend,
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          SizedBox(height: 16.h),
          _buildBarChart(),
          SizedBox(height: 12.h),
          _buildEnergyLegend(),
        ],
      ),
    );
  }

  /// 功率图例
  Widget _buildPowerLegend() {
    final items = [
      {'label': '${_l10n.pvGeneration}↑', 'color': AppColors.orange},
      {'label': '${_l10n.batteryCharge}↑', 'color': AppColors.successLight},
      {'label': '${_l10n.batteryDischarge}↓', 'color': AppColors.blue},
      {'label': '${_l10n.inverterOutput}↓', 'color': AppColors.purple},
    ];

    return Wrap(
      spacing: 16.w,
      runSpacing: 8.h,
      children: items.map((item) {
        final color = item['color'] as Color;
        final label = item['label'] as String;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10.w,
              height: 10.w,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 4.w),
            Text(label, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          ],
        );
      }).toList(),
    );
  }

  /// 能量图例
  Widget _buildEnergyLegend() {
    final items = [
      {'label': _l10n.pvGeneration, 'color': AppColors.orange},
      {'label': _l10n.batteryCharge, 'color': AppColors.successLight},
      {'label': _l10n.batteryDischarge, 'color': AppColors.blue},
      {'label': _l10n.inverterOutput, 'color': AppColors.purple},
    ];

    return Wrap(
      spacing: 16.w,
      runSpacing: 8.h,
      children: items.map((item) {
        final color = item['color'] as Color;
        final label = item['label'] as String;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10.w,
              height: 10.w,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 4.w),
            Text(label, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          ],
        );
      }).toList(),
    );
  }

  /// 通知信息区域
  Widget _buildAlarmSection(AppLocalizations l10n) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: AppColor.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_outlined, size: 18.sp, color: AppColors.orange),
              SizedBox(width: 8.w),
              Text(
                l10n.recentAlarms,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _alarmsLoading
              ? Center(child: Padding(
                  padding: EdgeInsets.all(20.w),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),)
              : _alarms.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.w),
                        child: Text(l10n.noAlarms, style: TextStyle(fontSize: 13.sp, color: AppColors.textHint)),
                      ),
                    )
                  : Column(
                      children: _alarms.map((alarm) => _buildAlarmItem(alarm)).toList(),
                    ),
        ],
      ),
    );
  }

  Widget _buildAlarmItem(Map<String, dynamic> alarm) {
    final level = (alarm['alarm_level'] as num?)?.toInt() ?? 0;
    final message = alarm['fault_message'] as String? ?? _l10n.unknownAlarm;
    final deviceSn = alarm['device_sn'] as String? ?? '';
    final occurredAt = alarm['occurred_at'] as String? ?? '';

    // 优先使用 fault_code 映射实际严重级别
    final faultCode = alarm['fault_code'];
    int parsedCode = -1;
    if (faultCode is int) {
      parsedCode = faultCode;
    } else if (faultCode != null) {
      final str = faultCode.toString();
      if (str.startsWith('0x') || str.startsWith('0X')) {
        parsedCode = int.tryParse(str.substring(2), radix: 16) ?? -1;
      } else {
        parsedCode = int.tryParse(str) ?? -1;
      }
    }
    final alarmEntry = parsedCode >= 0 ? AlarmCodeMapping.getEntry(parsedCode) : null;
    final severity = alarmEntry?.severity ?? _levelToSeverity(level);

    Color levelColor;
    String levelText;
    switch (severity) {
      case 'fault':
        levelColor = AppColors.errorLight;
        levelText = _l10n.severe;
        break;
      case 'warning':
        levelColor = AppColors.warning;
        levelText = _l10n.warningLevel;
        break;
      case 'info':
        levelColor = AppColors.blue;
        levelText = _l10n.infoLevel;
        break;
      case 'normal':
        levelColor = AppColors.success;
        levelText = _l10n.normal;
        break;
      default:
        levelColor = AppColors.textHint;
        levelText = _l10n.general;
    }

    String timeStr = '';
    if (occurredAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(occurredAt).toLocal();
        timeStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        timeStr = occurredAt;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.3), width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Text(levelText, style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w600, color: levelColor)),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
                SizedBox(height: 2.h),
                Text(deviceSn, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
              ],
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(timeStr, style: TextStyle(fontSize: 10.sp, color: AppColors.textHint)),
        ],
      ),
    );
  }

  String _levelToSeverity(int level) {
    switch (level) {
      case 3:
        return 'fault';
      case 2:
        return 'warning';
      case 1:
        return 'info';
      default:
        return 'normal'; // code=0
    }
  }

  /// 折线图 - 实时功率（所有值 >= 0，Y轴从0开始）
  Widget _buildLineChart() {
    // 功率折线图使用 *Power 字段（单位 W），负值截断为 0
    final pvData = _dataPoints.map((e) => e.pvPower < 0 ? 0.0 : e.pvPower).toList();
    final battChargeData = _dataPoints.map((e) => e.batteryChargePower < 0 ? 0.0 : e.batteryChargePower).toList();
    final battDischargeData = _dataPoints.map((e) => e.batteryDischargePower < 0 ? 0.0 : e.batteryDischargePower).toList();
    final inverterData = _dataPoints.map((e) => e.gridPower < 0 ? 0.0 : e.gridPower).toList();

    // 计算Y轴最大值（所有正值中的最大）
    double maxVal = 0;
    for (final p in _dataPoints) {
      if (p.pvPower > maxVal) maxVal = p.pvPower;
      if (p.batteryChargePower > maxVal) maxVal = p.batteryChargePower;
      if (p.batteryDischargePower > maxVal) maxVal = p.batteryDischargePower;
      if (p.gridPower > maxVal) maxVal = p.gridPower;
    }
    final double yMax = maxVal > 0 ? maxVal * 1.2 : 100.0;
    final yInterval = yMax / 4;

    // X轴固定 0-23，横向滚动 2 倍屏宽保证间距
    final currentHour = DateTime.now().hour;
    final screenWidth = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: screenWidth * 2,
        height: 220.h,
        child: LineChart(
          LineChartData(
            minX: 0.0,
            maxX: 23.0,
            minY: 0.0,
            maxY: yMax,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yInterval,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppColors.divider.withValues(alpha: 0.3),
                strokeWidth: 0.5,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40.w,
                  interval: yInterval,
                  getTitlesWidget: (value, meta) {
                    if (value < 0) return const SizedBox.shrink();
                    return Text(
                      value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0),
                      style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20.h,
                  interval: 1.0,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index > 23) return const SizedBox.shrink();
                    // 每3小时显示标签 + 始终显示当前小时
                    if (index % 3 != 0 && index != currentHour) return const SizedBox.shrink();
                    return Text(
                      '${index}h',
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: index == currentHour ? AppColors.primary : AppColors.textHint,
                        fontWeight: index == currentHour ? FontWeight.w600 : FontWeight.normal,
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              _buildLineData(pvData, AppColors.orange),
              _buildLineData(battChargeData, AppColors.successLight),
              _buildLineData(battDischargeData, AppColors.blue),
              _buildLineData(inverterData, AppColors.purple),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((spot) {
                  final labels = [_l10n.pvGeneration, _l10n.batteryCharge, _l10n.batteryDischarge, _l10n.inverterOutput];
                  final val = spot.y < 0 ? 0.0 : spot.y;
                  return LineTooltipItem(
                    '${labels[spot.barIndex]}: ${val.toStringAsFixed(0)} W\n',
                    TextStyle(fontSize: 11.sp, color: Colors.white, fontWeight: FontWeight.w500),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildLineData(List<double> data, Color color) {
    return LineChartBarData(
      spots: data.asMap().entries.map((e) {
        final v = e.value < 0 ? 0.0 : e.value;
        return FlSpot(e.key.toDouble(), v);
      }).toList(),
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: FlDotData(show: data.length <= 31),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }

  /// 柱状图
  Widget _buildBarChart() {
    final maxY = _getMaxY();
    return SizedBox(
      height: 220.h,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY * 1.15 : 10,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final labels = [_l10n.pvGeneration, _l10n.batteryCharge, _l10n.batteryDischarge, _l10n.inverterOutput];
                return BarTooltipItem(
                  '${labels[rodIndex]}: ${rod.toY.toStringAsFixed(1)} kWh\n',
                  TextStyle(fontSize: 11.sp, color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40.w,
                interval: maxY > 0 ? maxY / 4 : 1,
                getTitlesWidget: (value, meta) => Text(
                  value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0),
                  style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24.h,
                interval: _period == 'day' ? 3.0 : null,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= _dataPoints.length) return const SizedBox.shrink();
                  if (_period == 'day') {
                    if (index % 3 != 0) return const SizedBox.shrink();
                  } else {
                    const maxLabels = 5;
                    final step = (_dataPoints.length / maxLabels).ceil().clamp(1, _dataPoints.length);
                    if (index % step != 0) return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: EdgeInsets.only(top: 4.h),
                    child: Text(
                      _formatTimeLabel(_dataPoints[index].time),
                      style: TextStyle(fontSize: 9.sp, color: AppColors.textHint),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.divider.withValues(alpha: 0.4),
              strokeWidth: 0.5,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: _buildBarGroups(),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    // 根据数据点数量决定柱子宽度
    final barWidth = _dataPoints.length <= 7 ? 6.w : 
                     _dataPoints.length <= 15 ? 4.w : 3.w;
    final barsSpace = _dataPoints.length <= 7 ? 2.w : 1.w;
    
    return _dataPoints.asMap().entries.map((entry) {
      final i = entry.key;
      final point = entry.value;
      return BarChartGroupData(
        x: i,
        barsSpace: barsSpace,
        barRods: [
          BarChartRodData(
            toY: point.pvEnergy,
            color: AppColors.orange,
            width: barWidth,
            borderRadius: BorderRadius.vertical(top: Radius.circular(2.r)),
          ),
          BarChartRodData(
            toY: point.batteryCharge,
            color: AppColors.successLight,
            width: barWidth,
            borderRadius: BorderRadius.vertical(top: Radius.circular(2.r)),
          ),
          BarChartRodData(
            toY: point.batteryDischarge,
            color: AppColors.blue,
            width: barWidth,
            borderRadius: BorderRadius.vertical(top: Radius.circular(2.r)),
          ),
          BarChartRodData(
            toY: point.inverterOutput,
            color: AppColors.purple,
            width: barWidth,
            borderRadius: BorderRadius.vertical(top: Radius.circular(2.r)),
          ),
        ],
      );
    }).toList();
  }

  double _getMaxY() {
    if (_dataPoints.isEmpty) return 0;
    double max = 0;
    for (final p in _dataPoints) {
      if (p.pvEnergy > max) max = p.pvEnergy;
      if (p.batteryCharge > max) max = p.batteryCharge;
      if (p.batteryDischarge > max) max = p.batteryDischarge;
      if (p.inverterOutput > max) max = p.inverterOutput;
    }
    return max;
  }

  /// 日期选择弹窗
  void _showDatePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColor.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        int selectedYear = _selectedDate.year;
        int selectedMonth = _selectedDate.month;
        int selectedDay = _selectedDate.day;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.all(20.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_l10n.selectDate, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  SizedBox(height: 16.h),
                  if (_period == 'day') ...[
                    SizedBox(
                      height: 150.h,
                      child: Row(
                        children: [
                          Expanded(child: _buildYearWheel(selectedYear, (v) => setSheetState(() => selectedYear = v))),
                          Expanded(child: _buildMonthWheel(selectedMonth, (v) => setSheetState(() => selectedMonth = v))),
                          Expanded(child: _buildDayWheel(selectedDay, selectedYear, selectedMonth, (v) => setSheetState(() => selectedDay = v))),
                        ],
                      ),
                    ),
                  ] else if (_period == 'month') ...[
                    SizedBox(
                      height: 150.h,
                      child: Row(
                        children: [
                          Expanded(child: _buildYearWheel(selectedYear, (v) => setSheetState(() => selectedYear = v))),
                          Expanded(child: _buildMonthWheel(selectedMonth, (v) => setSheetState(() => selectedMonth = v))),
                        ],
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      height: 150.h,
                      child: _buildYearWheel(selectedYear, (v) => setSheetState(() => selectedYear = v)),
                    ),
                  ],
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _selectedDate = DateTime(selectedYear, selectedMonth, selectedDay);
                        });
                        Navigator.pop(ctx);
                        _fetchData();
                      },
                      child: Text(_l10n.confirm),
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

  Widget _buildYearWheel(int selected, ValueChanged<int> onChanged) {
    return ListWheelScrollView.useDelegate(
      itemExtent: 40.h,
      controller: FixedExtentScrollController(initialItem: selected - 2020),
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) => onChanged(2020 + index),
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          final year = 2020 + index;
          return Center(
            child: Text('$year', style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
          );
        },
        childCount: 20,
      ),
    );
  }

  Widget _buildMonthWheel(int selected, ValueChanged<int> onChanged) {
    return ListWheelScrollView.useDelegate(
      itemExtent: 40.h,
      controller: FixedExtentScrollController(initialItem: selected - 1),
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) => onChanged(index + 1),
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          return Center(
            child: Text('${index + 1}', style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
          );
        },
        childCount: 12,
      ),
    );
  }

  Widget _buildDayWheel(int selected, int year, int month, ValueChanged<int> onChanged) {
    final maxDay = DateTime(year, month + 1, 0).day;
    return ListWheelScrollView.useDelegate(
      itemExtent: 40.h,
      controller: FixedExtentScrollController(initialItem: selected - 1),
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) => onChanged(index + 1),
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          return Center(
            child: Text('${index + 1}', style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
          );
        },
        childCount: maxDay,
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        const SkeletonCard(height: 130),
        SizedBox(height: 16.h),
        const SkeletonCard(height: 260),
        SizedBox(height: 80.h),
      ],
    );
  }
}
