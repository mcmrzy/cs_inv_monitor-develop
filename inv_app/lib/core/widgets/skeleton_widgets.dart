import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

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
      baseColor: baseColor ?? AppColor.border(context),
      // highlight 无语义色对应项，按明暗模式分别给值
      highlightColor: highlightColor ??
          (isDark ? const Color(0xFF3A3D45) : const Color(0xFFF3F4F6)),
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
        color: AppColor.surfaceContainer(context),
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
        color: AppColor.surfaceContainer(context),
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
          color: AppColor.surfaceContainer(context),
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
          color: AppColor.surfaceContainer(context),
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
          color: AppColor.surfaceContainer(context),
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
              color: AppColor.surfaceContainer(context),
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
              color: AppColor.surfaceContainer(context),
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
                          color: AppColor.surfaceContainer(context),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Column(
                          children: [
                            SkeletonBox(
                              width: 30.w,
                              height: 16.h,
                              borderRadius: 4,
                            ),
                            SizedBox(height: 3.h),
                            SkeletonBox(
                              width: 28.w,
                              height: 11.h,
                              borderRadius: 4,
                            ),
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
                      color: AppColor.surfaceContainer(context),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 72.w,
                          height: 72.w,
                          borderRadius: 14,
                        ),
                        SizedBox(width: 14.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonBox(width: 120.w, height: 16.h),
                                  const Spacer(),
                                  SkeletonBox(
                                    width: 40.w,
                                    height: 18.h,
                                    borderRadius: 6,
                                  ),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              SkeletonBox(width: 160.w, height: 11.h),
                              SizedBox(height: 10.h),
                              Row(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox(width: 60.w, height: 18.h),
                                      SizedBox(height: 2.h),
                                      SkeletonBox(width: 50.w, height: 10.h),
                                    ],
                                  ),
                                  SizedBox(width: 24.w),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
            color: AppColor.surfaceContainer(context),
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
              color: AppColor.surfaceContainer(context),
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
            color: AppColor.surfaceContainer(context),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: AppColor.surfaceHover(context),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(14.r)),
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

/// 设备控制页骨架屏：模拟 TabBar + 内容区域
class SkeletonDeviceControl extends StatelessWidget {
  const SkeletonDeviceControl({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Column(
        children: [
          // TabBar 骨架
          Container(
            color: AppColor.surfaceContainer(context),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 6.h,
              bottom: 8.h,
            ),
            child: Row(
              children: List.generate(
                4,
                (_) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: SkeletonBox(width: 60.w, height: 30.h, borderRadius: 8),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          // 内容区域骨架
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 40.h),
              itemCount: 4,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceContainer(context),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120.w, height: 16.h),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          SkeletonBox(width: 80.w, height: 14.h),
                          const Spacer(),
                          SkeletonBox(width: 60.w, height: 14.h),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Row(
                        children: [
                          SkeletonBox(width: 80.w, height: 14.h),
                          const Spacer(),
                          SkeletonBox(width: 60.w, height: 14.h),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// OTA页面骨架屏
class SkeletonOtaPage extends StatelessWidget {
  const SkeletonOtaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
        itemCount: 3,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 40.w, height: 40.w, borderRadius: 8),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 150.w, height: 16.h),
                          SizedBox(height: 6.h),
                          SkeletonBox(width: 100.w, height: 12.h),
                        ],
                      ),
                    ),
                    SkeletonBox(width: 70.w, height: 28.h, borderRadius: 8),
                  ],
                ),
                SizedBox(height: 12.h),
                SkeletonBox(height: 8.h, borderRadius: 4),
                SizedBox(height: 8.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonBox(width: 80.w, height: 12.h),
                    SkeletonBox(width: 60.w, height: 12.h),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置页面骨架屏
class SkeletonSettingsPage extends StatelessWidget {
  const SkeletonSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
        children: [
          // 用户信息卡片
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Row(
              children: [
                SkeletonBox(width: 56.w, height: 56.w, borderRadius: 28),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120.w, height: 18.h),
                      SizedBox(height: 6.h),
                      SkeletonBox(width: 180.w, height: 13.h),
                    ],
                  ),
                ),
                SkeletonBox(width: 16.w, height: 16.w, borderRadius: 4),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          // 设置列表
          ...List.generate(
            6,
            (_) => Padding(
              padding: EdgeInsets.only(bottom: 2.h),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                decoration: BoxDecoration(
                  color: AppColor.surfaceContainer(context),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Row(
                  children: [
                    SkeletonBox(width: 22.w, height: 22.w, borderRadius: 6),
                    SizedBox(width: 14.w),
                    Expanded(child: SkeletonBox(width: 100.w, height: 15.h)),
                    SkeletonBox(width: 16.w, height: 16.w, borderRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
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
      decoration: const BoxDecoration(
        color: AppColors.warningSoft,
        border: Border(
          bottom: BorderSide(color: AppColors.warningBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16.sp,
            color: AppColors.warningStrong,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              AppLocalizations.of(context)?.noNetworkCached ??
                  'No network, showing cached data',
              style: TextStyle(fontSize: 12.sp, color: AppColors.warningText),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  AppLocalizations.of(context)?.retry ?? 'Retry',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 通用页面级骨架屏：统一替代各页面的裸 CircularProgressIndicator，
/// 保证加载态视觉一致（加载=骨架屏、错误=XiaoshuoStatePanel+重试）
class PageSkeleton extends StatelessWidget {
  /// 骨架卡片数量
  final int cardCount;

  /// 顶部标题条宽度
  final double titleWidth;

  const PageSkeleton({super.key, this.cardCount = 3, this.titleWidth = 120});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: titleWidth.w, height: 16.h),
          SizedBox(height: 14.h),
          for (var i = 0; i < cardCount; i++) const SkeletonCard(height: 96),
        ],
      ),
    );
  }
}