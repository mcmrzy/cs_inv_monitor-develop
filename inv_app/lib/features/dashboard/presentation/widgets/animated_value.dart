import 'package:flutter/material.dart';

/// 数字滚动动画组件
/// 支持数字变化时的平滑过渡动画
class AnimatedValue extends StatefulWidget {
  final double value;
  final String unit;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final Duration duration;
  final String Function(double)? formatter;

  const AnimatedValue({
    super.key,
    required this.value,
    this.unit = '',
    this.valueStyle,
    this.unitStyle,
    this.duration = const Duration(milliseconds: 300),
    this.formatter,
  });

  @override
  State<AnimatedValue> createState() => _AnimatedValueState();
}

class _AnimatedValueState extends State<AnimatedValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.value,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ),);
    _controller.forward();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(AnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
      _animation = Tween<double>(
        begin: _previousValue,
        end: widget.value,
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final displayValue = widget.formatter != null
            ? widget.formatter!(_animation.value)
            : _formatValue(_animation.value);
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              displayValue,
              style: widget.valueStyle ?? 
                const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
            ),
            if (widget.unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                widget.unit,
                style: widget.unitStyle ?? 
                  const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _formatValue(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    if (value >= 1000) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

/// 带趋势指示器的数值组件
class TrendValue extends StatelessWidget {
  final double value;
  final double? previousValue;
  final String unit;
  final TextStyle? valueStyle;
  final bool showTrend;
  final bool isPositiveGood;

  const TrendValue({
    super.key,
    required this.value,
    this.previousValue,
    this.unit = '',
    this.valueStyle,
    this.showTrend = true,
    this.isPositiveGood = true,
  });

  @override
  Widget build(BuildContext context) {
    final trend = previousValue != null && previousValue! > 0
        ? ((value - previousValue!) / previousValue! * 100)
        : 0.0;
    
    final isPositive = trend > 0;
    final isNeutral = trend == 0;
    
    Color trendColor;
    IconData trendIcon;
    
    if (isNeutral) {
      trendColor = Colors.grey;
      trendIcon = Icons.trending_flat;
    } else if (isPositive) {
      trendColor = isPositiveGood ? Colors.green : Colors.red;
      trendIcon = Icons.trending_up;
    } else {
      trendColor = isPositiveGood ? Colors.red : Colors.green;
      trendIcon = Icons.trending_down;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedValue(
          value: value,
          unit: unit,
          valueStyle: valueStyle,
        ),
        if (showTrend && previousValue != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                trendIcon,
                size: 14,
                color: trendColor,
              ),
              const SizedBox(width: 4),
              Text(
                '${isPositive ? '+' : ''}${trend.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  color: trendColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}