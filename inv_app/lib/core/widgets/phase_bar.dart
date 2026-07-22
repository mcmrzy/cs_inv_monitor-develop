import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PhaseBar extends StatelessWidget {
  final double phaseA;
  final double phaseB;
  final double phaseC;
  final String label;
  final double maxValue;

  const PhaseBar({
    super.key,
    required this.phaseA,
    required this.phaseB,
    required this.phaseC,
    required this.label,
    required this.maxValue,
  });

  static const Color _colorA = Color(0xFF2196F3);
  static const Color _colorB = Color(0xFF4CAF50);
  static const Color _colorC = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phases = [
      _PhaseData('A', phaseA, _colorA),
      _PhaseData('B', phaseB, _colorB),
      _PhaseData('C', phaseC, _colorC),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: 200.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 10.h),
          ...phases.map(
            (phase) => _PhaseRow(
              phase: phase,
              maxValue: maxValue,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseData {
  final String label;
  final double value;
  final Color color;

  const _PhaseData(this.label, this.value, this.color);
}

class _PhaseRow extends StatelessWidget {
  final _PhaseData phase;
  final double maxValue;
  final ThemeData theme;

  const _PhaseRow({
    required this.phase,
    required this.maxValue,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (phase.value / maxValue).clamp(0.0, 1.0);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: [
          SizedBox(
            width: 18.w,
            child: Text(
              phase.label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: phase.color,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth * ratio;
                return Stack(
                  children: [
                    Container(
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      height: 14.h,
                      width: barWidth,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            phase.color.withValues(alpha: 0.7),
                            phase.color,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: 8.w),
          SizedBox(
            width: 52.w,
            child: Text(
              phase.value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
