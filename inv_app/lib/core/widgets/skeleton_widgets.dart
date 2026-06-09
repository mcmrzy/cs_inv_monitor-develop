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
