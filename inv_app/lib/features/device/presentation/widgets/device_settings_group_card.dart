import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';

class DeviceSettingsGroupCard extends StatelessWidget {
  const DeviceSettingsGroupCard({
    super.key,
    required this.title,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.expanded,
    required this.onToggle,
    required this.content,
    this.badge,
    this.compact = false,
  });

  final String title;
  final String summary;
  final IconData icon;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget content;
  final Widget? badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 仅标题行可点击切换展开，避免展开区内误触收起
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14.w,
              vertical: compact ? 10.h : 14.h,
            ),
            child: Row(
              children: [
                if (compact)
                  Icon(icon, size: 20.sp, color: AppColor.primary(context))
                else
                  SettingsIconContainer(icon: icon, accent: accent),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        SizedBox(height: 3.h),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColor.textSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge != null) ...[badge!, SizedBox(width: 6.w)],
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 22.sp,
                    color: AppColor.textHint(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 展开区：分类描述 + 参数控件（AnimatedSize 平滑伸缩）
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded ? content : const SizedBox(width: double.infinity),
        ),
      ],
    );
    if (compact) return body;
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 10.h),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(
          color: AppColor.border(context),
          width: 0.6,
        ),
      ),
      color: AppColor.surfaceContainer(context),
      child: body,
    );
  }
}
