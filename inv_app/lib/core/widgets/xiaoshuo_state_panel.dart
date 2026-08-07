import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 小烁/插画状态面板：插画 + 标题 + 副文案 + 可选操作按钮
///
/// 对应美术路由文档组件契约 `XiaoshuoStatePanel` / `CsergyStatusEmptyState`，
/// 任何插画资源（小烁动作、空状态图）均可传入，用于空态、错误、
/// 离线、引导等场景。
class XiaoshuoStatePanel extends StatelessWidget {
  final String asset;
  final String title;
  final String? message;
  final Widget? action;
  final double size;
  final EdgeInsetsGeometry padding;

  const XiaoshuoStatePanel({
    super.key,
    required this.asset,
    required this.title,
    this.message,
    this.action,
    this.size = 200,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              asset,
              width: size.w,
              height: size.w,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.image_not_supported_outlined,
                size: (size * 0.4).w,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (message != null) ...[
              SizedBox(height: 8.h),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: 20.h),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
