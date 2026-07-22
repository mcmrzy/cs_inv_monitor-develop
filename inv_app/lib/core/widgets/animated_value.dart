import 'package:flutter/material.dart';

/// Displays a value that smoothly animates when it changes.
///
/// Uses [AnimatedSwitcher] with a vertical slide + fade transition.
/// The [value] string is compared by identity; pass a new string each
/// time the data changes to trigger the animation.
class AnimatedValue extends StatelessWidget {
  final String value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedValue({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) {
        final isForward = child.key == ValueKey(value);
        final offsetAnimation = Tween<Offset>(
          begin: isForward ? const Offset(0, 0.3) : const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: Text(
        value,
        key: ValueKey(value),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
