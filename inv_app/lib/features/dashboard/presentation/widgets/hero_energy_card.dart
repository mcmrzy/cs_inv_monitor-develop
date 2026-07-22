import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// Hero 能量卡片 - 渐变蓝底，展示今日发电 / 累计发电 / 设备总数
/// 支持趋势指示器和数字滚动动画
class HeroEnergyCard extends StatelessWidget {
  final double todayEnergy;
  final double totalEnergy;
  final int deviceCount;
  final double? yesterdayEnergy;
  final double? lastMonthEnergy;
  final int? yesterdayDeviceCount;

  const HeroEnergyCard({
    super.key,
    required this.todayEnergy,
    required this.totalEnergy,
    required this.deviceCount,
    this.yesterdayEnergy,
    this.lastMonthEnergy,
    this.yesterdayDeviceCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1565C0),
            Color(0xFF1976D2),
            Color(0xFF2196F3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _bannerItem(
                todayEnergy,
                'kWh',
                l10n.todayGeneration,
                previousValue: yesterdayEnergy,
              ),
              Container(width: 1, height: 50.h, color: Colors.white24),
              _bannerItem(
                totalEnergy,
                'kWh',
                l10n.totalGeneration,
                previousValue: lastMonthEnergy,
              ),
              Container(width: 1, height: 50.h, color: Colors.white24),
              _bannerItem(
                deviceCount.toDouble(),
                l10n.unitDevices,
                l10n.totalDevices,
                previousValue: yesterdayDeviceCount?.toDouble(),
                isDeviceCount: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerItem(
    double value,
    String unit,
    String label, {
    IconData? icon,
    double? previousValue,
    bool isDeviceCount = false,
  }) {
    final trend = previousValue != null && previousValue > 0
        ? ((value - previousValue) / previousValue * 100)
        : 0.0;

    final isPositive = trend > 0;
    final isNeutral = trend == 0;

    Color trendColor;
    IconData trendIcon;

    if (isNeutral) {
      trendColor = Colors.white60;
      trendIcon = Icons.trending_flat;
    } else if (isPositive) {
      trendColor = const Color(0xFF81C784);
      trendIcon = Icons.trending_up;
    } else {
      trendColor = const Color(0xFFEF9A9A);
      trendIcon = Icons.trending_down;
    }

    return Column(
      children: [
        // 图标
        if (icon != null) ...[
          Icon(icon, size: 20.w, color: Colors.white70),
          SizedBox(height: 6.h),
        ],
        // 数字和单位
        _AnimatedEnergyValue(
          value: value,
          unit: unit,
          isDeviceCount: isDeviceCount,
        ),
        SizedBox(height: 4.h),
        // 标签
        Text(
          label,
          style: TextStyle(fontSize: 11.sp, color: Colors.white60),
        ),
        // 趋势指示器
        if (previousValue != null) ...[
          SizedBox(height: 4.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trendIcon,
                  size: 10.w,
                  color: trendColor,
                ),
                SizedBox(width: 2.w),
                Text(
                  '${isPositive ? '+' : ''}${trend.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 9.sp,
                    color: trendColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 能量值动画组件
class _AnimatedEnergyValue extends StatefulWidget {
  final double value;
  final String unit;
  final bool isDeviceCount;

  const _AnimatedEnergyValue({
    required this.value,
    required this.unit,
    this.isDeviceCount = false,
  });

  @override
  State<_AnimatedEnergyValue> createState() => _AnimatedEnergyValueState();
}

class _AnimatedEnergyValueState extends State<_AnimatedEnergyValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.value,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _controller.forward();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(_AnimatedEnergyValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
      _animation = Tween<double>(
        begin: _previousValue,
        end: widget.value,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
      );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: _formatEnergy(
                  widget.isDeviceCount
                      ? _animation.value.roundToDouble()
                      : _animation.value,
                  l10n.wan,
                ),
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              if (widget.unit.isNotEmpty)
                TextSpan(
                  text: ' ${widget.unit}',
                  style: TextStyle(fontSize: 12.sp, color: Colors.white70),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatEnergy(double value, String wanLabel) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}$wanLabel';
    }
    if (value >= 1000) {
      return value.toStringAsFixed(0);
    }
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
