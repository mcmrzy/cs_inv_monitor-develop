import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 快捷状态行 - 在线 / 离线 / 故障 3 个状态芯片
/// 支持变化指示和点击交互
class QuickStatsRow extends StatelessWidget {
  final int onlineCount;
  final int offlineCount;
  final int faultCount;
  final int? previousOnlineCount;
  final int? previousOfflineCount;
  final int? previousFaultCount;
  final VoidCallback? onOnlineTap;
  final VoidCallback? onOfflineTap;
  final VoidCallback? onFaultTap;

  const QuickStatsRow({
    super.key,
    required this.onlineCount,
    required this.offlineCount,
    required this.faultCount,
    this.previousOnlineCount,
    this.previousOfflineCount,
    this.previousFaultCount,
    this.onOnlineTap,
    this.onOfflineTap,
    this.onFaultTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.check_circle_rounded,
              label: l10n.statusOnline,
              count: onlineCount,
              color: AppColors.online,
              previousCount: previousOnlineCount,
              onTap: onOnlineTap,
              positiveIsGood: true,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _StatChip(
              icon: Icons.pause_circle_rounded,
              label: l10n.statusOffline,
              count: offlineCount,
              color: AppColors.offline,
              previousCount: previousOfflineCount,
              onTap: onOfflineTap,
              positiveIsGood: false,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _StatChip(
              icon: Icons.error_rounded,
              label: l10n.statusFault,
              count: faultCount,
              color: AppColors.fault,
              previousCount: previousFaultCount,
              onTap: onFaultTap,
              positiveIsGood: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final int? previousCount;
  final VoidCallback? onTap;
  final bool positiveIsGood;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.previousCount,
    this.onTap,
    this.positiveIsGood = true,
  });

  @override
  State<_StatChip> createState() => _StatChipState();
}

class _StatChipState extends State<_StatChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ),);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final change = widget.previousCount != null ? widget.count - widget.previousCount! : 0;
    final isPositive = change > 0;
    final isNeutral = change == 0;

    Color changeColor;
    IconData changeIcon;

    if (isNeutral) {
      changeColor = AppColors.textHint;
      changeIcon = Icons.remove;
    } else if (isPositive) {
      changeColor = widget.positiveIsGood ? AppColors.success : AppColors.error;
      changeIcon = Icons.arrow_upward;
    } else {
      changeColor = widget.positiveIsGood ? AppColors.error : AppColors.success;
      changeIcon = Icons.arrow_downward;
    }

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: widget.color.withValues(alpha: 0.15), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 图标带背景
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, size: 20.w, color: widget.color),
                  ),
                  SizedBox(height: 8.h),
                  // 数字动画
                  _AnimatedCount(
                    count: widget.count,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    widget.label,
                    style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                  ),
                  // 变化指示器
                  if (widget.previousCount != null) ...[
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            changeIcon,
                            size: 10.w,
                            color: changeColor,
                          ),
                          SizedBox(width: 2.w),
                          Text(
                            '${isPositive ? '+' : ''}$change',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: changeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 数字动画组件
class _AnimatedCount extends StatefulWidget {
  final int count;
  final TextStyle style;

  const _AnimatedCount({
    required this.count,
    required this.style,
  });

  @override
  State<_AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<_AnimatedCount>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.count.toDouble(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ),);
    _controller.forward();
    _previousCount = widget.count;
  }

  @override
  void didUpdateWidget(_AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _previousCount = oldWidget.count;
      _animation = Tween<double>(
        begin: _previousCount.toDouble(),
        end: widget.count.toDouble(),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          _animation.value.round().toString(),
          style: widget.style,
        );
      },
    );
  }
}
