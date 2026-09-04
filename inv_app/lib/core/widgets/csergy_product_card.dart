import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// CSERGY 产品卡片：产品图 + 名称，白底圆角卡片（浅色底可读）
///
/// 对应美术路由文档组件契约 `CsergyProductCard` / `CsergyProductHero`：
/// 列表卡片 80–112dp，Hero 220–320dp。
class CsergyProductCard extends StatelessWidget {
  final String asset;
  final String name;
  final double size;
  final double? width;
  final double? height;

  const CsergyProductCard({
    super.key,
    required this.asset,
    required this.name,
    this.size = 96,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width ?? size.w,
      height: height ?? size.w,
      padding: EdgeInsets.all((size * 0.08).w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.solar_power_outlined,
                size: (size * 0.35).w,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
