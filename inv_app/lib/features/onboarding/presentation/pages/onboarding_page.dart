import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 单页引导数据：主题插画 + 装饰图标组合 + 标题 + 副文案
class _OnboardingPageData {
  final String asset;
  final IconData icon;
  final List<IconData> featureIcons;
  final String title;
  final String desc;

  const _OnboardingPageData({
    required this.asset,
    required this.icon,
    required this.featureIcons,
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                  itemBuilder: (context, index) =>
                      _buildPageContent(context, pages[index]),
                ),
              ),
              // 底部：圆点指示器；最后一页为「快速开始」三入口 + 立即体验
              Padding(
                padding: EdgeInsets.fromLTRB(32.w, 8.h, 32.w, 28.h),
                child: _currentPage == _pageCount - 1
                    ? _buildQuickStart(l10n)
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
      // 第 1 页：智能监控——随时随地掌握电站发电
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoStation,
        icon: Icons.solar_power,
        featureIcons: const [
          Icons.solar_power,
          Icons.insights,
          Icons.map_outlined,
        ],
        title: l10n.onboardingPage1Title,
        desc: l10n.onboardingPage1Desc,
      ),
      // 第 2 页：极速告警——异常实时推送
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoWarning,
        icon: Icons.notifications_active,
        featureIcons: const [
          Icons.notifications_active,
          Icons.bolt,
          Icons.check_circle_outline,
        ],
        title: l10n.onboardingPage2Title,
        desc: l10n.onboardingPage2Desc,
      ),
      // 第 3 页：本地升级——OTA 无网也能升
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoOtaGuide,
        icon: Icons.system_update,
        featureIcons: const [
          Icons.system_update,
          Icons.wifi_off,
          Icons.flash_on,
        ],
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

  /// 尾屏快速开始：创建电站 / 添加设备 / 配网三入口 + 立即体验。
  /// 未登录点击入口会被路由守卫重定向到登录页，登录后由首启向导接管
  Widget _buildQuickStart(AppLocalizations l10n) {
    return Column(
      children: [
        Text(
          l10n.str('quick_start'),
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        _quickStartButton(
          icon: Icons.add_home_work_outlined,
          label: l10n.createStation,
          onTap: () => context.push('/station/create'),
        ),
        SizedBox(height: 8.h),
        _quickStartButton(
          icon: Icons.solar_power,
          label: l10n.addDevice,
          onTap: () => context.push('/add-device'),
        ),
        SizedBox(height: 8.h),
        _quickStartButton(
          icon: Icons.wifi,
          label: l10n.wifiConfig,
          onTap: () => context.push('/wifi-config'),
        ),
        SizedBox(height: 14.h),
        _buildStartButton(l10n),
      ],
    );
  }

  Widget _quickStartButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18.sp),
        label: Text(
          label,
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
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

  Widget _buildPageContent(
    BuildContext context,
    _OnboardingPageData page,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40.w),
      child: Column(
        children: [
          // 主题图标（半透明圆底）
          Container(
            width: 64.w,
            height: 64.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 32.w, color: Colors.white),
          ),
          SizedBox(height: 20.h),
          // 小烁吉祥物插画
          Image.asset(
            page.asset,
            width: 260.w,
            height: 240.h,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              page.icon,
              size: 120.w,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 28.h),
          // 标题
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 10.h),
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
          SizedBox(height: 24.h),
          // 图标组合点缀
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: page.featureIcons
                .map(
                  (icon) => Container(
                    width: 40.w,
                    height: 40.w,
                    margin: EdgeInsets.symmetric(horizontal: 6.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(icon, size: 20.w, color: Colors.white),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
