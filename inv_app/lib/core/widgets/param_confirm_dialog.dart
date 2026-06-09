import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class ParamConfirmDialog extends StatelessWidget {
  final Map<String, MapEntry<dynamic, dynamic>> changes;
  final Set<String> dangerousKeys;

  const ParamConfirmDialog({
    super.key,
    required this.changes,
    required this.dangerousKeys,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, MapEntry<dynamic, dynamic>> changes,
    required Set<String> dangerousKeys,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ParamConfirmDialog(
        changes: changes,
        dangerousKeys: dangerousKeys,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDangerous = changes.keys.any((k) => dangerousKeys.contains(k));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      title: Row(
        children: [
          Icon(Icons.edit_note, size: 24.sp, color: theme.colorScheme.primary),
          SizedBox(width: 8.w),
          const Text('确认参数修改'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasDangerous) ...[
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        '包含危险参数，修改可能影响设备安全运行',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
            ],
            ...changes.entries.map((entry) {
              final isDangerous = dangerousKeys.contains(entry.key);
              return _buildChangeItem(
                context,
                label: entry.key,
                oldValue: entry.value.key,
                newValue: entry.value.value,
                isDangerous: isDangerous,
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: hasDangerous
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: Text(hasDangerous ? '确认修改(危险)' : '确认修改'),
        ),
      ],
    );
  }

  Widget _buildChangeItem(
    BuildContext context, {
    required String label,
    required dynamic oldValue,
    required dynamic newValue,
    required bool isDangerous,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: isDangerous
            ? AppColors.error.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.r),
        border: isDangerous
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          if (isDangerous)
            Padding(
              padding: EdgeInsets.only(right: 6.w),
              child: Icon(Icons.warning_amber, color: AppColors.error, size: 16.sp),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: isDangerous ? AppColors.error : theme.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Text(
                      '${oldValue ?? '-'}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6.w),
                      child: Icon(Icons.arrow_forward, size: 14.sp, color: theme.colorScheme.primary),
                    ),
                    Text(
                      '${newValue ?? '-'}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: isDangerous ? AppColors.error : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
