import 'package:flutter/material.dart';

/// 排序/批量模式的错相位持续抖动动画（iOS 编辑模式 jiggle 风格）：
/// `active` 变为 true 时卡片持续做小幅 scale/rotate 往复抖动；
/// 每张卡片按 `index` 偏移 0.15s 错峰播放（与 _AnimatedMenuSheet 的 Interval 错峰一致）。
/// 拖动/勾选等后续交互不会重复触发；退出模式立即停止并复位。
class JiggleOnce extends StatefulWidget {
  final bool active;
  final int index;
  final Widget child;

  const JiggleOnce({
    super.key,
    required this.active,
    required this.index,
    required this.child,
  });

  @override
  State<JiggleOnce> createState() => _JiggleOnceState();
}

class _JiggleOnceState extends State<JiggleOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _rotation;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // 控制器 1000ms：index * 0.15 直接对应 150ms 相位偏移；
    // 起始延迟限幅，保证每张卡片都有足够的摇晃时长
    final start = (widget.index * 0.15).clamp(0.0, 0.5);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _ctl,
      curve: Interval(start, end, curve: Curves.easeInOut),
    );
    _rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.017), weight: 33),
      TweenSequenceItem(tween: Tween(begin: -0.017, end: 0.017), weight: 34),
      TweenSequenceItem(tween: Tween(begin: 0.017, end: 0.0), weight: 33),
    ]).animate(animation);
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.995), weight: 33),
      TweenSequenceItem(tween: Tween(begin: 0.995, end: 1.005), weight: 34),
      TweenSequenceItem(tween: Tween(begin: 1.005, end: 1.0), weight: 33),
    ]).animate(animation);
    if (widget.active) _play();
  }

  @override
  void didUpdateWidget(JiggleOnce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _play();
    } else if (!widget.active && oldWidget.active) {
      // 退出排序/批量模式：立即停止，帧末复位（避免 build 期间触发监听）
      _ctl.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.active) _ctl.value = 0;
      });
    }
  }

  void _play() {
    // 延迟一帧再启动，确保元素在树中稳定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _ctl.repeat();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotation.value,
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
