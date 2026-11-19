import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DeviceSectionNavigation extends StatelessWidget {
  const DeviceSectionNavigation({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<(IconData, String)> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
        padding: EdgeInsets.all(5.w),
        decoration: BoxDecoration(
          color: AppColor.surfaceContainer(context),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: AppColor.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 18,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(child: _item(context, i, tabs[i].$1, tabs[i].$2)),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData icon,
    String label,
  ) {
    final selected = index == selectedIndex;
    final ink =
        selected ? AppColor.primary(context) : AppColor.textSecondary(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(16.r),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: selected ? AppColor.primarySoft(context) : null,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17.sp,
                color: ink,
              ),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
