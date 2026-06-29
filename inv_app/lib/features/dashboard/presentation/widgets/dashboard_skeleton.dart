import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

/// 仪表盘骨架屏 - 全页加载态
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: ListView(
        padding: EdgeInsets.all(16.w),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Hero 卡片
          const SkeletonStatisticsHeader(),
          SizedBox(height: 16.h),
          // 状态行
          Row(
            children: List.generate(
              3,
              (_) => Expanded(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 4.w),
                  height: 80.h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          // 趋势图
          SkeletonCard(height: 230),
          SizedBox(height: 16.h),
          // 设备分布
          SkeletonCard(height: 160),
          SizedBox(height: 16.h),
          // 电站排行
          SkeletonCard(height: 220),
          SizedBox(height: 16.h),
          // 最近告警
          SkeletonCard(height: 180),
          SizedBox(height: 100.h),
        ],
      ),
    );
  }
}
