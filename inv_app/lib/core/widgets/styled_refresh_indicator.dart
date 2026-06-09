import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class StyledRefreshIndicator extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;

  const StyledRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: color ?? AppColors.primary,
      displacement: 60,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
