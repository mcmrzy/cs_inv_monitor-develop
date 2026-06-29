import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/dashboard/domain/entities/trend_data_point.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 能量趋势图 - 7 日发电用电趋势折线图
class EnergyTrendChart extends StatefulWidget {
  final List<TrendDataPoint> data;

  const EnergyTrendChart({
    super.key,
    required this.data,
  });

  @override
  State<EnergyTrendChart> createState() => _EnergyTrendChartState();
}

class _EnergyTrendChartState extends State<EnergyTrendChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final hasLoadData = widget.data.any((e) => e.load > 0);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.show_chart_rounded, size: 18.w, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Text(
                l10n.recent7DayTrend,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // 图例
              _buildLegendItem(AppColors.primary, l10n.powerGeneration),
              if (hasLoadData) ...[
                SizedBox(width: 12.w),
                _buildLegendItem(const Color(0xFFF5A623), l10n.powerConsumption),
              ],
            ],
          ),
          SizedBox(height: 20.h),
          // 图表
          SizedBox(
            height: 200.h,
            child: LineChart(
              _buildChartData(context, hasLoadData),
              duration: const Duration(milliseconds: 250),
            ),
          ),
          // 数据点详情
          if (_touchedIndex != null && _touchedIndex! < widget.data.length)
            _buildDataPointDetails(widget.data[_touchedIndex!], hasLoadData),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16.w,
          height: 4.h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.r),
          ),
        ),
        SizedBox(width: 6.w),
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDataPointDetails(TrendDataPoint point, bool hasLoadData) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: EdgeInsets.only(top: 16.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded, size: 16.w, color: AppColors.primary),
          SizedBox(width: 8.w),
          Text(
            point.date,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _buildDetailChip(l10n.powerGeneration, '${point.energy.toStringAsFixed(1)} kWh', AppColors.primary),
          if (hasLoadData && point.load > 0) ...[
            SizedBox(width: 8.w),
            _buildDetailChip(l10n.powerConsumption, '${point.load.toStringAsFixed(1)} kWh', const Color(0xFFF5A623)),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData(BuildContext context, bool hasLoadData) {
    final energySpots = widget.data.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.energy);
    }).toList();

    final allValues = energySpots.map((e) => e.y).toList();
    if (hasLoadData) {
      allValues.addAll(widget.data.map((e) => e.load));
    }
    final maxY = allValues.isEmpty
        ? 10.0
        : allValues.reduce((a, b) => a > b ? a : b) * 1.2;

    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: energySpots,
        isCurved: true,
        curveSmoothness: 0.45,
        preventCurveOverShooting: true,
        barWidth: 3,
        color: AppColors.primary,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: _touchedIndex == index ? 6 : 4,
            color: _touchedIndex == index ? AppColors.primary : Colors.white,
            strokeWidth: _touchedIndex == index ? 3 : 2,
            strokeColor: AppColors.primary,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.2),
              AppColors.primary.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ];

    if (hasLoadData) {
      final loadSpots = widget.data.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(), entry.value.load);
      }).toList();

      lineBars.add(LineChartBarData(
        spots: loadSpots,
        isCurved: true,
        curveSmoothness: 0.45,
        preventCurveOverShooting: true,
        barWidth: 3,
        color: const Color(0xFFF5A623),
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: _touchedIndex == index ? 6 : 4,
            color: _touchedIndex == index ? const Color(0xFFF5A623) : Colors.white,
            strokeWidth: _touchedIndex == index ? 3 : 2,
            strokeColor: const Color(0xFFF5A623),
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF5A623).withValues(alpha: 0.15),
              const Color(0xFFF5A623).withValues(alpha: 0.0),
            ],
          ),
        ),
      ));
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
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
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(0),
                style: TextStyle(fontSize: 10.sp, color: AppColors.textHint),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28.h,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= widget.data.length) {
                return const SizedBox.shrink();
              }
              final shouldShow = index == 0 ||
                  index == widget.data.length - 1 ||
                  (widget.data.length > 4 && index % 2 == 0);
              if (!shouldShow) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                  _formatDate(widget.data[index].date),
                  style: TextStyle(fontSize: 9.sp, color: AppColors.textHint),
                ),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: widget.data.length > 1 ? (widget.data.length - 1).toDouble() : 1.0,
      minY: 0,
      maxY: maxY > 0 ? maxY : 10,
      lineBarsData: lineBars,
      lineTouchData: LineTouchData(
        enabled: true,
        touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
          if (event is FlTapUpEvent && touchResponse != null) {
            final spotIndex = touchResponse.lineBarSpots?.first.x.toInt();
            if (spotIndex != null && spotIndex >= 0 && spotIndex < widget.data.length) {
              setState(() {
                _touchedIndex = spotIndex;
              });
            }
          }
        },
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: AppColors.primary,
          tooltipRoundedRadius: 10.r,
          getTooltipItems: (spots) {
            if (spots.isEmpty) return [];
            return spots.map((spot) {
              final index = spot.x.toInt();
              if (index >= 0 && index < widget.data.length) {
                final point = widget.data[index];
                final isFirst = spot.barIndex == 0;
                final label = isFirst
                    ? '${point.date}\n${AppLocalizations.of(context)?.generation ?? "Gen"}: ${point.energy.toStringAsFixed(1)} kWh'
                    : '${point.date}\n${AppLocalizations.of(context)?.consumption ?? "Usage"}: ${point.load.toStringAsFixed(1)} kWh';
                return LineTooltipItem(
                  label,
                  TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }
              return null;
            }).toList();
          },
        ),
        handleBuiltInTouches: true,
      ),
    );
  }

  String _formatDate(String date) {
    if (date.length >= 5) {
      final last5 = date.substring(date.length - 5);
      final parts = last5.split(RegExp(r'[-/]'));
      if (parts.length >= 2) {
        return '${int.parse(parts[0])}/${int.parse(parts[1])}';
      }
      return last5;
    }
    return date;
  }
}
