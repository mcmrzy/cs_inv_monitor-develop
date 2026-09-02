import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

enum WifiProvisionMode { softAp, ble }

class WifiProvisionModeSwitch extends StatelessWidget {
  final WifiProvisionMode selectedMode;
  final String bleLabel;
  final String softApLabel;
  final ValueChanged<WifiProvisionMode> onSelected;

  const WifiProvisionModeSwitch({
    super.key,
    required this.selectedMode,
    required this.bleLabel,
    required this.softApLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeOption(
              icon: Icons.bluetooth,
              label: bleLabel,
              selected: selectedMode == WifiProvisionMode.ble,
              onTap: () => onSelected(WifiProvisionMode.ble),
            ),
          ),
          Expanded(
            child: _ModeOption(
              icon: Icons.router,
              label: softApLabel,
              selected: selectedMode == WifiProvisionMode.softAp,
              onTap: () => onSelected(WifiProvisionMode.softAp),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18.sp,
                  color: selected
                      ? Colors.white
                      : AppColor.textSecondary(context),
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : AppColor.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WifiProvisionStepData {
  final String label;
  final bool isCompleted;
  final bool isCurrent;

  const WifiProvisionStepData({
    required this.label,
    this.isCompleted = false,
    this.isCurrent = false,
  });
}

class WifiProvisionStepIndicator extends StatelessWidget {
  final List<WifiProvisionStepData> steps;

  const WifiProvisionStepIndicator({
    super.key,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final stepColor = step.isCompleted
              ? AppColors.successLight
              : step.isCurrent
                  ? AppColors.primary
                  : AppColor.textHint(context);

          return Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    label: step.label,
                    selected: step.isCurrent,
                    checked: step.isCompleted,
                    child: ExcludeSemantics(
                      child: Column(
                        children: [
                          Container(
                            width: 28.w,
                            height: 28.w,
                            decoration: BoxDecoration(
                              color: stepColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: stepColor, width: 2),
                            ),
                            child: step.isCompleted
                                ? Icon(
                                    Icons.check,
                                    size: 14.sp,
                                    color: stepColor,
                                  )
                                : Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        color: stepColor,
                                      ),
                                    ),
                                  ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            step.label,
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: step.isCurrent || step.isCompleted
                                  ? AppColor.textPrimary(context)
                                  : AppColor.textHint(context),
                              fontWeight: step.isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (index < steps.length - 1)
                  Padding(
                    padding: EdgeInsets.only(top: 13.w),
                    child: Container(
                      width: 16.w,
                      height: 2,
                      color: step.isCompleted
                          ? AppColors.successLight
                          : AppColor.border(context),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
