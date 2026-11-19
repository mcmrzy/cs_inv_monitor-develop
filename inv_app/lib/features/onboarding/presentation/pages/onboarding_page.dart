import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/onboarding/data/onboarding_storage.dart';
import 'package:inv_app/features/onboarding/presentation/widgets/guide_artwork.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class _SlideContent {
  const _SlideContent({
    required this.title,
    required this.description,
    required this.asset,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final String asset;
  final IconData icon;
  final GuideAccent accent;
}

/// 首次打开 App 时展示功能介绍。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final target = GoRouterState.of(context).extra as String? ?? '/login';
    setState(() => _finishing = true);
    await OnboardingStorage().markSeen();
    if (mounted) context.go(target);
  }

  void _continue(int lastPage) {
    if (_currentPage == lastPage) {
      _finish();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(_currentPage + 1);
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = [
      _SlideContent(
        title: l10n.onboardingPage1Title,
        description: l10n.onboardingPage1Desc,
        asset: CsergyAssets.xiaoshuoStation,
        icon: Icons.solar_power_rounded,
        accent: GuideAccent.solar,
      ),
      _SlideContent(
        title: l10n.onboardingPage2Title,
        description: l10n.onboardingPage2Desc,
        asset: CsergyAssets.xiaoshuoReminder,
        icon: Icons.notifications_active_outlined,
        accent: GuideAccent.alert,
      ),
      _SlideContent(
        title: l10n.onboardingPage3Title,
        description: l10n.onboardingPage3Desc,
        asset: CsergyAssets.xiaoshuoWifiGuide,
        icon: Icons.bluetooth_connected_rounded,
        accent: GuideAccent.connection,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColor.background(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CSERGY',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColor.primary(context),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8,
                                  ),
                        ),
                      ),
                      TextButton(
                        key: const Key('onboarding-skip'),
                        onPressed: _finishing ? null : _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColor.textSecondary(context),
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(l10n.skip),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: pages.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) => _OnboardingSlide(
                      key: index == _currentPage
                          ? const Key('onboarding-page-content')
                          : ValueKey('onboarding-page-$index'),
                      page: pages[index],
                    ),
                  ),
                ),
                _OnboardingFooter(
                  currentPage: _currentPage,
                  pageCount: pages.length,
                  onContinue:
                      _finishing ? null : () => _continue(pages.length - 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({super.key, required this.page});

  final _SlideContent page;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 580 &&
            constraints.maxWidth > constraints.maxHeight;
        final artworkHeight = sideBySide
            ? (constraints.maxHeight - 24).clamp(130.0, 320.0).toDouble()
            : (constraints.maxHeight * 0.64).clamp(130.0, 392.0).toDouble();
        final illustration = SizedBox(
          width: double.infinity,
          height: artworkHeight,
          child: GuideArtwork(
            asset: page.asset,
            icon: page.icon,
            accent: page.accent,
          ),
        );
        final copy = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                page.title,
                style: textTheme.headlineMedium?.copyWith(
                  fontSize: constraints.maxWidth >= 390 ? 32 : 28,
                  height: 1.18,
                  color: AppColor.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              page.description,
              style: textTheme.bodyLarge?.copyWith(
                color: AppColor.textSecondary(context),
                height: 1.55,
              ),
            ),
          ],
        );

        const verticalPadding = 12.0;
        final leadSpace = ((constraints.maxHeight - artworkHeight - 150) / 3)
            .clamp(0.0, 36.0)
            .toDouble();
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: verticalPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: sideBySide ? 712 : 460,
                minHeight:
                    math.max(0, constraints.maxHeight - 2 * verticalPadding),
              ),
              child: sideBySide
                  ? Row(
                      children: [
                        Expanded(child: illustration),
                        const SizedBox(width: 28),
                        Expanded(child: copy),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: leadSpace),
                        illustration,
                        const SizedBox(height: 24),
                        copy,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.currentPage,
    required this.pageCount,
    required this.onContinue,
  });

  final int currentPage;
  final int pageCount;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLast = currentPage == pageCount - 1;
    final primary = AppColor.primary(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      key: const Key('onboarding-footer'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: [
            Semantics(
              label: l10n.str('setup_guide_step_of', {
                'current': '${currentPage + 1}',
                'total': '$pageCount',
              }),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < pageCount; index++)
                    AnimatedContainer(
                      key: currentPage == index
                          ? Key('onboarding-progress-$index')
                          : null,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      width: currentPage == index ? 28 : 8,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: currentPage == index
                            ? primary
                            : AppColor.outline(context),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('onboarding-primary-action'),
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor:
                      dark ? const Color(0xFF102438) : Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        isLast ? l10n.onboardingStart : l10n.onboardingContinue,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
