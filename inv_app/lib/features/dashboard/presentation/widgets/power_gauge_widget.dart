import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

/// 发电功率仪表盘 - 大圆形进度环显示实时发电功率
class PowerGaugeWidget extends StatefulWidget {
  final double currentPower; // 当前功率 (kW)
  final double maxPower; // 最大功率 (kW)
  final double todayEnergy; // 今日发电量 (kWh)
  final double todayRevenue; // 今日收益 (元)
  final String? trendText; // 趋势文本，如 "+5.2%"

  const PowerGaugeWidget({
    super.key,
    required this.currentPower,
    required this.maxPower,
    required this.todayEnergy,
    required this.todayRevenue,
    this.trendText,
  });

  @override
  State<PowerGaugeWidget> createState() => _PowerGaugeWidgetState();
}

class _PowerGaugeWidgetState extends State<PowerGaugeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousPower = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.currentPower,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ),);
    _controller.forward();
    _previousPower = widget.currentPower;
  }

  @override
  void didUpdateWidget(PowerGaugeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPower != widget.currentPower) {
      _previousPower = oldWidget.currentPower;
      _animation = Tween<double>(
        begin: _previousPower,
        end: widget.currentPower,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),);
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
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.wb_sunny_rounded, size: 20.w, color: Colors.white70),
              SizedBox(width: 8.w),
              Text(
                '光伏发电功率',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              if (widget.trendText != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    widget.trendText!,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 24.h),
          // 功率仪表盘
          SizedBox(
            width: 180.w,
            height: 180.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 背景圆环
                SizedBox(
                  width: 180.w,
                  height: 180.w,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 12.w,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                // 进度圆环
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final progress = widget.maxPower > 0
                        ? (_animation.value / widget.maxPower).clamp(0.0, 1.0)
                        : 0.0;
                    return SizedBox(
                      width: 180.w,
                      height: 180.w,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12.w,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeCap: StrokeCap.round,
                      ),
                    );
                  },
                ),
                // 中心内容
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return Text(
                          _animation.value.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 36.sp,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    Text(
                      'kW',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '实时功率',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          // 底部数据
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomItem(
                '今日发电',
                '${widget.todayEnergy.toStringAsFixed(1)} kWh',
              ),
              Container(
                width: 1,
                height: 40.h,
                color: Colors.white24,
              ),
              _buildBottomItem(
                '今日收益',
                '¥${widget.todayRevenue.toStringAsFixed(0)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: Colors.white60,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
