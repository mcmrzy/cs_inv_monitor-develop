import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class _OnboardingPageData {
  final String asset;
  final String title;
  final String description;
  final String semanticLabel;

  const _OnboardingPageData({
    required this.asset,
    required this.title,
    required this.description,
    required this.semanticLabel,
  });
}

/// 首次引导页。
///
/// 内容区可以独立滚动，底部进度和主操作始终占据相同空间，避免翻到
/// 最后一页时布局跳动，也兼容小屏、横屏和较大的系统字体。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _pageCount = 3;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await OnboardingStorage().markSeen();
    if (!mounted) return;

    final target = GoRouterState.of(context).extra as String? ?? '/login';
    context.go(target);
  }

  Future<void> _handlePrimaryAction() async {
    if (_currentPage < _pageCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = _buildPages(context);
    final isLastPage = _currentPage == _pageCount - 1;

    return Scaffold(
      backgroundColor: AppColor.background(context),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: TextButton(
                    key: const Key('onboarding-skip'),
                    onPressed: _finishing ? null : _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColor.textSecondary(context),
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(l10n.skip),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) => _OnboardingSlide(
                  key: index == _currentPage
                      ? const Key('onboarding-page-content')
                      : ValueKey('onboarding-page-$index'),
                  page: pages[index],
                ),
              ),
            ),
            SizedBox(
              key: const Key('onboarding-footer'),
              height: 112,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    _ProgressIndicator(currentPage: _currentPage),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('onboarding-primary-action'),
                          onPressed: _finishing ? null : _handlePrimaryAction,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.primary(context),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isLastPage
                                ? _startLabel(context)
                                : _continueLabel(context),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  String _continueLabel(BuildContext context) =>
      AppLocalizations.of(context)!.onboardingContinue;

  String _startLabel(BuildContext context) =>
      AppLocalizations.of(context)!.onboardingStart;

  List<_OnboardingPageData> _buildPages(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_isChinese(context)) {
      return [
        _OnboardingPageData(
          asset: CsergyAssets.xiaoshuoStation,
          title: l10n.onboardingPage1Title,
          description: l10n.onboardingPage1Desc,
          semanticLabel: '看见能源',
        ),
        _OnboardingPageData(
          asset: CsergyAssets.xiaoshuoReminder,
          title: l10n.onboardingPage2Title,
          description: l10n.onboardingPage2Desc,
          semanticLabel: '及时掌握状态',
        ),
        _OnboardingPageData(
          asset: CsergyAssets.xiaoshuoWifiGuide,
          title: l10n.onboardingPage3Title,
          description: l10n.onboardingPage3Desc,
          semanticLabel: '随时近场维护',
        ),
      ];
    }

    return [
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoStation,
        title: l10n.onboardingPage1Title,
        description: l10n.onboardingPage1Desc,
        semanticLabel: 'Energy overview',
      ),
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoReminder,
        title: l10n.onboardingPage2Title,
        description: l10n.onboardingPage2Desc,
        semanticLabel: 'Status and alerts',
      ),
      _OnboardingPageData(
        asset: CsergyAssets.xiaoshuoWifiGuide,
        title: l10n.onboardingPage3Title,
        description: l10n.onboardingPage3Desc,
        semanticLabel: 'Local device service',
      ),
    ];
  }
}

class _OnboardingSlide extends StatelessWidget {
  final _OnboardingPageData page;

  const _OnboardingSlide({
    super.key,
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final contentWidth = math.min(constraints.maxWidth - 40, 560.0);
        final illustrationHeight = math.min(
          landscape ? 132.0 : 280.0,
          math.max(104.0, constraints.maxHeight * (landscape ? 0.5 : 0.52)),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: illustrationHeight,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColor.primary(context).withValues(alpha: 0.16),
                          AppColor.primarySoft(context),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Semantics(
                      image: true,
                      label: page.semanticLabel,
                      child: Image.asset(
                        page.asset,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.solar_power_outlined,
                          color: AppColor.primary(context),
                          size: 72,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColor.textPrimary(context),
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    page.description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColor.textSecondary(context),
                          height: 1.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressIndicator extends StatelessWidget {
  final int currentPage;

  const _ProgressIndicator({required this.currentPage});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_OnboardingPageState._pageCount, (index) {
        final active = index == currentPage;
        return AnimatedContainer(
          key: active ? Key('onboarding-progress-$index') : null,
          duration: const Duration(milliseconds: 220),
          width: active ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color:
                active ? AppColor.primary(context) : AppColor.border(context),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
