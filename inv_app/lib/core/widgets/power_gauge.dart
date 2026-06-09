import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PowerGauge extends StatefulWidget {
  final double power;
  final double maxPower;
  final double size;
  final Color? textColor;
  final Color? subtextColor;

  const PowerGauge({
    super.key,
    required this.power,
    this.maxPower = 50,
    this.size = 220,
    this.textColor,
    this.subtextColor,
  });

  @override
  State<PowerGauge> createState() => _PowerGaugeState();
}

class _PowerGaugeState extends State<PowerGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant PowerGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.power != widget.power ||
        oldWidget.maxPower != widget.maxPower) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getGaugeColor(double ratio) {
    if (ratio < 0.5) {
      return Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFFC107),
        ratio * 2,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFFC107),
        const Color(0xFFF44336),
        (ratio - 0.5) * 2,
      )!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = (widget.power / widget.maxPower).clamp(0.0, 1.0);
    final gaugeColor = _getGaugeColor(ratio);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size.w,
          height: widget.size.h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: widget.size.h * 0.02,
                child: Container(
                  width: widget.size.w * 0.88,
                  height: widget.size.w * 0.88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: gaugeColor.withValues(alpha: 0.15),
                        blurRadius: 20.r,
                        spreadRadius: 2.r,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: widget.size.w * 0.88,
                height: widget.size.w * 0.88,
                child: CustomPaint(
                  painter: _GaugePainter(
                    ratio: ratio * _animation.value,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: gaugeColor,
                    strokeWidth: 14.w,
                    startAngle: 135 * math.pi / 180,
                    sweepAngle: 270 * math.pi / 180,
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (widget.power * _animation.value).toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 36.sp,
                      fontWeight: FontWeight.bold,
                      color: widget.textColor ?? theme.colorScheme.onSurface,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'kW',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: widget.subtextColor ?? theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: widget.size.h * 0.06,
                child: Text(
                  '额定 ${widget.maxPower.toStringAsFixed(0)}kW',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: widget.subtextColor ?? theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double ratio;
  final Color backgroundColor;
  final Color foregroundColor;
  final double strokeWidth;
  final double startAngle;
  final double sweepAngle;

  _GaugePainter({
    required this.ratio,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.strokeWidth,
    required this.startAngle,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    final fgPaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * ratio,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.foregroundColor != foregroundColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
