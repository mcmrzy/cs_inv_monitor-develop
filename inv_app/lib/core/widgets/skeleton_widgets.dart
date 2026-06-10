import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerSkeleton extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerSkeleton({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: baseColor ?? (isDark ? const Color(0xFF2A2D35) : const Color(0xFFE5E7EB)),
      highlightColor: highlightColor ?? (isDark ? const Color(0xFF3A3D45) : const Color(0xFFF3F4F6)),
      child: child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius.r),
      ),
    );
  }
}

class SkeletonListItem extends StatelessWidget {
  const SkeletonListItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: ShimmerSkeleton(
        child: Row(
          children: [
            SkeletonBox(width: 32.w, height: 32.w, borderRadius: 8),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180.w, height: 14.h),
                  SizedBox(height: 8.h),
                  SkeletonBox(width: 120.w, height: 12.h),
                ],
              ),
            ),
            SkeletonBox(width: 16.w, height: 16.w, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

class SkeletonDetailSection extends StatelessWidget {
  final double height;

  const SkeletonDetailSection({super.key, this.height = 100});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 100.w, height: 14.h),
            SizedBox(height: 12.h),
            SkeletonBox(height: 40.h),
          ],
        ),
      ),
    );
  }
}

class SkeletonStatisticsHeader extends StatelessWidget {
  const SkeletonStatisticsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 80.w, height: 13.h),
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(3, (_) {
                return Column(
                  children: [
                    SkeletonBox(width: 80.w, height: 22.h),
                    SizedBox(height: 4.h),
                    SkeletonBox(width: 50.w, height: 11.h),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  final double height;

  const SkeletonCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        height: height.h,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16.r),
        ),
      ),
    );
  }
}

/// 首页骨架屏：模拟 header + 过滤卡片 + 电站列表
class SkeletonHomePage extends StatelessWidget {
  const SkeletonHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          // Header 骨架
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12.h,
                left: 20.w,
                right: 20.w,
                bottom: 8.h,
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 100.w, height: 20.h),
                      SizedBox(height: 4.h),
                      SkeletonBox(width: 140.w, height: 12.h),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 过滤卡片骨架
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Row(
                children: List.generate(
                  4,
                  (_) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3.w),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 10.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Column(
                          children: [
                            SkeletonBox(width: 30.w, height: 16.h, borderRadius: 4),
                            SizedBox(height: 3.h),
                            SkeletonBox(width: 28.w, height: 11.h, borderRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 电站列表骨架
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => Padding(
                  padding: EdgeInsets.only(bottom: 14.h),
                  child: Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 72.w, height: 72.w, borderRadius: 14),
                        SizedBox(width: 14.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonBox(width: 120.w, height: 16.h),
                                  const Spacer(),
                                  SkeletonBox(width: 40.w, height: 18.h, borderRadius: 6),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              SkeletonBox(width: 160.w, height: 11.h),
                              SizedBox(height: 10.h),
                              Row(
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(width: 60.w, height: 18.h),
                                      SizedBox(height: 2.h),
                                      SkeletonBox(width: 50.w, height: 10.h),
                                    ],
                                  ),
                                  SizedBox(width: 24.w),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(width: 60.w, height: 18.h),
                                      SizedBox(height: 2.h),
                                      SkeletonBox(width: 50.w, height: 10.h),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                childCount: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 电站详情页骨架屏
class SkeletonStationDetail extends StatelessWidget {
  const SkeletonStationDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Column(
        children: [
          // Top bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(
              20.w,
              MediaQuery.of(context).padding.top + 6.h,
              20.w,
              6.h,
            ),
            child: Row(
              children: [
                SkeletonBox(width: 24.w, height: 24.w, borderRadius: 8),
                SizedBox(width: 12.w),
                SkeletonBox(width: 140.w, height: 18.h),
                const Spacer(),
                SkeletonBox(width: 40.w, height: 22.h, borderRadius: 6),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          // 能量流区域占位
          Container(
            height: 380.h,
            margin: EdgeInsets.symmetric(horizontal: 16.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.r),
            ),
          ),
          SizedBox(height: 10.h),
          // 两个数据卡片
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                Expanded(child: SkeletonBox(height: 80.h, borderRadius: 14)),
                SizedBox(width: 10.w),
                Expanded(child: SkeletonBox(height: 80.h, borderRadius: 14)),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          // 发电量统计
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: SkeletonBox(height: 70.h, borderRadius: 14),
          ),
          SizedBox(height: 10.h),
          // 社会贡献
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: SkeletonBox(height: 100.h, borderRadius: 14),
          ),
        ],
      ),
    );
  }
}

/// 设备实时数据页骨架屏
class SkeletonDeviceRealtime extends StatelessWidget {
  const SkeletonDeviceRealtime({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
        itemCount: 5,
        itemBuilder: (_, i) => Container(
          margin: EdgeInsets.only(bottom: 12.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
                ),
                child: Row(
                  children: [
                    SkeletonBox(width: 6.w, height: 6.w, borderRadius: 3),
                    SizedBox(width: 8.w),
                    SkeletonBox(width: 18.w, height: 18.w, borderRadius: 4),
                    SizedBox(width: 6.w),
                    SkeletonBox(width: 80.w, height: 14.h),
                  ],
                ),
              ),
              // Data items
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                child: Column(
                  children: List.generate(
                    4,
                    (_) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Row(
                        children: [
                          SkeletonBox(width: 100.w, height: 13.h),
                          const Spacer(),
                          SkeletonBox(width: 60.w, height: 13.h),
                        ],
                      ),
                    ),
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

/// 离线数据指示条：显示正在使用缓存数据
class OfflineDataBanner extends StatelessWidget {
  final VoidCallback? onRetry;

  const OfflineDataBanner({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFFDE68A), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16.sp, color: const Color(0xFFD97706)),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '当前无网络，显示缓存数据',
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF92400E)),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  '重试',
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
