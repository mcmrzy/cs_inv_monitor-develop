import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 通用分页栏：上一页 / 第 X 页 / 共 Y 页 / 下一页。
///
/// - [currentPage] 为 1-based 页码
/// - 禁用态按钮为灰色 [AppColors.textHint]，可用态为 [AppColors.primary]
/// - totalPages <= 1 时返回 SizedBox.shrink()（组件自身兜底，
///   调用方也可自行判断 totalPages > 1 再决定是否渲染）
class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final canPrev = currentPage > 1;
    final canNext = currentPage < totalPages;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            icon: Icons.chevron_left_rounded,
            enabled: canPrev,
            onTap: canPrev ? () => onPageChanged(currentPage - 1) : null,
          ),
          SizedBox(width: 14.w),
          Text(
            AppLocalizations.of(context)!
                .paginationInfo(currentPage, totalPages),
            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          ),
          SizedBox(width: 14.w),
          _PageButton(
            icon: Icons.chevron_right_rounded,
            enabled: canNext,
            onTap: canNext ? () => onPageChanged(currentPage + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _PageButton({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : AppColors.textHint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.w,
        height: 32.w,
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, size: 20.sp, color: color),
      ),
    );
  }
}
