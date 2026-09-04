import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 单页引导数据：主题插画 + 标题 + 副文案
///
/// 精简结构：每页只保留吉祥物插画、大标题和一句话描述，
/// 移除图标圆底和功能图标组合，视觉焦点更集中。
class _OnboardingPageData {
  final String asset;
  final IconData icon;
  final String title;
  final String desc;

  const _OnboardingPageData({
    required this.asset,
    required this.icon,
    required this.title,
    required this.desc,
  });
}

/// 引导页（首次安装 / 版本升级后展示）：
/// 串联式插画（复用品牌吉祥物小烁资源）+ 渐变背景 + 图标组合，
/// 右上角「跳过」、底部圆点指示器、最后一页「立即体验」按钮。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 完成 / 跳过引导：记录已看版本后，回到登录分流目标页
  Future<void> _finish() async {
    await OnboardingStorage().markSeen();
    if (!mounted) return;
    // 启动分流时通过 extra 传入登录分流目标（/home、/login、/jverify-login 等）
    final target =
        GoRouterState.of(context).extra as String? ?? '/login';
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = _buildPages(l10n);

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Container(
        decoration: BoxDecoration(
          // 径向渐变：中心亮（42A5F5）→ 过渡层（1565C0）→ 边缘深（0D47A1）
          gradient: LinearGradient(
            colors: [
              Color(0xFF42A5F5),
              Color(0xFF1565C0),
              Color(0xFF0D47A1),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部：右上角「跳过」按钮
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(0, 8.h, 20.w, 0),
                  child: _buildSkipButton(l10n),
                ),
              ),
              // 中部：可滑动引导内容
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return _SlideFadeContent(
                      key: ValueKey('$index-${page.title}'),
                      child: _buildPageContent(page),
                    );
                  },
                ),
              ),
              // 底部：圆点指示器；最后一页为单一 CTA 按钮
              Padding(
                padding: EdgeInsets.all(32.w),
                child: _currentPage == _pageCount - 1
                    ? _buildStartButton(l10n)
                    : _buildDotsIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_OnboardingPageData> _buildPages(AppLocalizations l10n) {
    return [
      // 第 1 页：智能监控 -> "每一度电，尽在掌握"
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoStation,
        icon: Icons.solar_power,
        title: l10n.onboardingPage1Title,
        desc: l10n.onboardingPage1Desc,
      ),
      // 第 2 页：极速告警 -> "第一时间预警，安心无忧"
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoWarning,
        icon: Icons.notifications_active,
        title: l10n.onboardingPage2Title,
        desc: l10n.onboardingPage2Desc,
      ),
      // 第 3 页：本地升级 -> "断网也不怕，固件随心换"
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoOtaGuide,
        icon: Icons.system_update,
        title: l10n.onboardingPage3Title,
        desc: l10n.onboardingPage3Desc,
      ),
    ];
  }

  Widget _buildSkipButton(AppLocalizations l10n) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: _finish,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 7.h),
          child: Text(
            l10n.skip,
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primaryDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        onPressed: _finish,
        child: Text(
          l10n.onboardingStart,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDotsIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pageCount, (index) {
        final active = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: active ? 22.w : 8.w,
          height: 8.h,
          margin: EdgeInsets.symmetric(horizontal: 4.w),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4.r),
          ),
        );
      }),
    );
  }

  Widget _buildPageContent(_OnboardingPageData page) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40.w),
      child: Column(
        children: [
          // 小烁吉祥物插画（统一尺寸，视觉焦点）
          Image.asset(
            page.asset,
            width: 280.w,
            height: 260.h,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              page.icon,
              size: 120.w,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 36.h),
          // 标题：大标题，情感化场景文案
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12.h),
          // 副文案
          Text(
            page.desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.sp,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面内容入场动画容器：淡入 + 轻微上移，提升页面切换质感。
///
/// 每次页面索引变化时重建（依赖 PageView itemBuilder 的 key 变化），
/// 内容从下方 40 逻辑像素处淡入上移至目标位置。
class _SlideFadeContent extends StatefulWidget {
  final Widget child;

  const _SlideFadeContent({super.key, required this.child});

  @override
  State<_SlideFadeContent> createState() => _SlideFadeContentState();
}

class _SlideFadeContentState extends State<_SlideFadeContent> {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 40 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: widget.child,
    );
  }
}
