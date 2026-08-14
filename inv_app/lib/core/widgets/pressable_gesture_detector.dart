import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 支持自定义长按时长的点击/长按手势组件。
///
/// Flutter 3.44+ 的 [GestureDetector] 已移除 `longPressDuration` 参数，
/// 本组件基于 [RawGestureDetector] + [TapGestureRecognizer] +
/// [LongPressGestureRecognizer] 复刻 [GestureDetector] 的点击/长按手势
/// （手势竞技场行为一致，回调签名与 [GestureDetector] 相同），
/// 默认长按 300ms，与电站/设备/通知卡片统一手感。
///
/// 与 [GestureDetector] 一致：仅当对应回调非空时才注册该手势，
/// 避免空回调抢占手势竞技场（例如排序模式下长按由 ReorderableListView 接管）。
class PressableGestureDetector extends StatelessWidget {
  const PressableGestureDetector({
    super.key,
    required this.child,
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onLongPress,
    this.onLongPressCancel,
    this.onLongPressUp,
    this.longPressDuration = const Duration(milliseconds: 300),
  });

  final Widget child;

  /// 手指按下（与 [GestureDetector.onTapDown] 一致）
  final GestureTapDownCallback? onTapDown;

  /// 手指抬起（与 [GestureDetector.onTapUp] 一致）
  final GestureTapUpCallback? onTapUp;

  /// 点击完成（与 [GestureDetector.onTap] 一致）
  final VoidCallback? onTap;

  /// 点击取消（与 [GestureDetector.onTapCancel] 一致）
  final GestureTapCancelCallback? onTapCancel;

  /// 长按达成（与 [GestureDetector.onLongPress] 一致）
  final GestureLongPressCallback? onLongPress;

  /// 长按取消（与 [GestureDetector.onLongPressCancel] 一致）
  final GestureLongPressCancelCallback? onLongPressCancel;

  /// 长按抬起（与 [GestureDetector.onLongPressUp] 一致）
  final GestureLongPressUpCallback? onLongPressUp;

  /// 长按触发时长，默认 300ms（比系统默认 500ms 更灵敏）
  final Duration longPressDuration;

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    if (onTapDown != null ||
        onTapUp != null ||
        onTap != null ||
        onTapCancel != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(),
        (instance) {
          instance
            ..onTapDown = onTapDown
            ..onTapUp = onTapUp
            ..onTap = onTap
            ..onTapCancel = onTapCancel;
        },
      );
    }

    if (onLongPress != null ||
        onLongPressCancel != null ||
        onLongPressUp != null) {
      gestures[LongPressGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: longPressDuration),
        (instance) {
          instance
            ..onLongPress = onLongPress
            ..onLongPressCancel = onLongPressCancel
            ..onLongPressUp = onLongPressUp;
        },
      );
    }

    return RawGestureDetector(
      gestures: gestures,
      child: child,
    );
  }
}
