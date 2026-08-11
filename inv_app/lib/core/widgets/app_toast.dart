import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Toast 提示类型：成功 / 失败 / 信息
enum ToastType { success, error, info }

/// 统一 Toast 提示工具：基于 ScaffoldMessenger 的浮动 SnackBar 封装，
/// 带语义图标与语义背景色（成功绿 / 失败红 / 信息深灰蓝），
/// 替代裸 SnackBar 的"蓝黑一坨"观感。
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
  }) {
    final (icon, background) = switch (type) {
      ToastType.success => (
          Icons.check_circle_rounded,
          const Color(0xFF16A34A),
        ),
      ToastType.error => (
          Icons.error_rounded,
          const Color(0xFFDC2626),
        ),
      ToastType.info => (
          Icons.info_rounded,
          const Color(0xFF374151),
        ),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: background,
          // 轻投影：悬浮于页面之上
          elevation: 4,
          // 圆角浮层 + 内边距
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          duration: Duration(
            milliseconds: type == ToastType.error ? 2500 : 2000,
          ),
        ),
      );
  }
}
