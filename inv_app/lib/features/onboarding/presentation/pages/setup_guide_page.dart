import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/onboarding/data/setup_guide_storage.dart';
import 'package:inv_app/features/onboarding/presentation/widgets/guide_artwork.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class _SetupStep {
  const _SetupStep({
    required this.title,
    required this.description,
    required this.items,
    required this.route,
    required this.asset,
    required this.icon,
    required this.accent,
    this.done = false,
    this.optional = false,
  });

  final String title;
  final String description;
  final List<String> items;
  final String route;
  final String asset;
  final IconData icon;
  final GuideAccent accent;
  final bool done;
  final bool optional;
}

/// 登录后引导用户创建电站、绑定设备和按需配网。
class SetupGuidePage extends StatefulWidget {
  const SetupGuidePage({super.key});

  @override
  State<SetupGuidePage> createState() => _SetupGuidePageState();
}

class _SetupGuidePageState extends State<SetupGuidePage> {
  static const _totalSteps = 3;
  final _guideStorage = SetupGuideStorage();
  final _pageController = PageController();
  int _step = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    context.read<StationBloc>().add(StationSummaryRequested());
    context.read<DeviceBloc>().add(const DeviceListRequested(pageSize: 200));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndPop() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _guideStorage.markDone();
    if (mounted) context.pop();
  }

  void _goTo(int step) {
    final target = step.clamp(0, _totalSteps - 1);
    if (target == _step || !_pageController.hasClients) return;
    setState(() => _step = target);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _hasStation(StationState state) =>
      state is StationSummaryLoaded && state.stations.isNotEmpty;

  bool _hasDevice(DeviceState state) =>
      state is DeviceListLoaded && state.devices.isNotEmpty;

  List<_SetupStep> _steps(
    AppLocalizations l10n,
    StationState stationState,
    DeviceState deviceState,
  ) =>
      [
        _SetupStep(
          title: l10n.createStation,
          description: l10n.str('setup_guide_step1_desc'),
          items: [
            l10n.str('setup_guide_s1_item1'),
            l10n.str('setup_guide_s1_item2'),
            l10n.str('setup_guide_s1_item3'),
          ],
          route: '/station/create',
          asset: CsergyAssets.xiaoshuoStation,
          icon: Icons.solar_power_rounded,
          accent: GuideAccent.solar,
          done: _hasStation(stationState),
        ),
        _SetupStep(
          title: l10n.addDevice,
          description: l10n.str('setup_guide_step2_desc'),
          items: [
            l10n.str('setup_guide_s2_item1'),
            l10n.str('setup_guide_s2_item2'),
            l10n.str('setup_guide_s2_item3'),
          ],
          route: '/add-device',
          asset: CsergyAssets.xiaoshuoDevice,
          icon: Icons.qr_code_scanner_rounded,
          accent: GuideAccent.device,
          done: _hasDevice(deviceState),
        ),
        _SetupStep(
          title: l10n.wifiConfig,
          description: l10n.str('setup_guide_step3_desc'),
          items: [
            l10n.str('setup_guide_s3_item1'),
            l10n.str('setup_guide_s3_item2'),
            l10n.str('setup_guide_s3_item3'),
          ],
          route: '/wifi-config',
          asset: CsergyAssets.xiaoshuoWifiGuide,
          icon: Icons.wifi_rounded,
          accent: GuideAccent.connection,
          optional: true,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final steps = _steps(
      l10n,
      context.watch<StationBloc>().state,
      context.watch<DeviceBloc>().state,
    );
    final activeStep = steps[_step];

    return MultiBlocListener(
      listeners: [
        BlocListener<StationBloc, StationState>(
          listener: (_, state) {
            if (_step == 0 && _hasStation(state)) _goTo(1);
          },
        ),
        BlocListener<DeviceBloc, DeviceState>(
          listener: (_, state) {
            if (_step == 1 && _hasDevice(state)) _goTo(2);
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: AppColor.background(context),
        appBar: AppBar(
          title: Text(l10n.str('setup_guide_title')),
          backgroundColor: AppColor.background(context),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: TextButton(
                onPressed: _finishing ? null : _finishAndPop,
                style: TextButton.styleFrom(
                  foregroundColor: AppColor.textSecondary(context),
                  minimumSize: const Size(48, 48),
                ),
                child: Text(l10n.skip),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  _SetupProgress(steps: steps, currentIndex: _step),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: steps.length,
                      onPageChanged: (index) {
                        if (_step != index) setState(() => _step = index);
                      },
                      itemBuilder: (_, index) => _SetupSlide(
                        key: ValueKey('setup-guide-step-$index'),
                        step: steps[index],
                      ),
                    ),
                  ),
                  _SetupFooter(
                    step: activeStep,
                    first: _step == 0,
                    last: _step == steps.length - 1,
                    onPrimary: _finishing
                        ? null
                        : activeStep.done
                            ? () => _goTo(_step + 1)
                            : () => context.push(activeStep.route),
                    onBack: _finishing ? null : () => _goTo(_step - 1),
                    onAdvance: _finishing
                        ? null
                        : _step == steps.length - 1
                            ? _finishAndPop
                            : () => _goTo(_step + 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.steps, required this.currentIndex});

  final List<_SetupStep> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primary = AppColor.primary(context);
    final surface = AppColor.surfaceContainer(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              l10n.str('setup_guide_step_of', {
                'current': '${currentIndex + 1}',
                'total': '${steps.length}',
              }),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColor.textSecondary(context),
                  ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var index = 0; index < steps.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: index == currentIndex
                              ? primary
                              : steps[index].done
                                  ? _doneColor(context)
                                  : Color.lerp(surface, primary, 0.16),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupSlide extends StatelessWidget {
  const _SetupSlide({super.key, required this.step});

  final _SetupStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                step.title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ),
            if (step.done || step.optional)
              _StepStatus(
                label: l10n.str(
                  step.done
                      ? 'setup_guide_step_done'
                      : 'setup_guide_step_optional',
                ),
                done: step.done,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          step.description,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColor.textSecondary(context),
            height: 1.5,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 600 &&
            constraints.maxWidth > constraints.maxHeight;
        const radius = Radius.circular(22);
        final overview = DecoratedBox(
          decoration: BoxDecoration(
            color: AppColor.surfaceContainer(context),
            borderRadius: const BorderRadius.all(radius),
            border: Border.all(color: AppColor.divider(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.36)
                    .clamp(100.0, 220.0)
                    .toDouble(),
                child: GuideArtwork(
                  asset: step.asset,
                  icon: step.icon,
                  accent: step.accent,
                  compact: true,
                  borderRadius: const BorderRadius.vertical(top: radius),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: heading,
              ),
            ],
          ),
        );
        final checklist = _SetupChecklist(
          items: step.items,
          accent: step.accent,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: sideBySide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: overview),
                    const SizedBox(width: 24),
                    Expanded(child: checklist),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [overview, const SizedBox(height: 16), checklist],
                ),
        );
      },
    );
  }
}

Color _doneColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF68D4A9)
        : AppColors.success;

class _StepStatus extends StatelessWidget {
  const _StepStatus({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? _doneColor(context) : AppColor.textSecondary(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: done
            ? color.withValues(alpha: 0.12)
            : AppColor.surfaceHover(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _SetupChecklist extends StatelessWidget {
  const _SetupChecklist({required this.items, required this.accent});

  final List<String> items;
  final GuideAccent accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppColor.surfaceContainer(context);
    final markerColor = dark ? accent.detail : accent.background;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: AppColor.divider(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  indent: 40,
                  color: AppColor.divider(context),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          surface,
                          accent.light,
                          dark ? 0.30 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: markerColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        items[index],
                        style: textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          color: AppColor.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupFooter extends StatelessWidget {
  const _SetupFooter({
    required this.step,
    required this.first,
    required this.last,
    required this.onPrimary,
    required this.onBack,
    required this.onAdvance,
  });

  final _SetupStep step;
  final bool first;
  final bool last;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = TextButton.styleFrom(
      foregroundColor: AppColor.textSecondary(context),
      minimumSize: const Size(48, 44),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColor.background(context),
        border: Border(top: BorderSide(color: AppColor.divider(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('setup-guide-primary-action'),
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primary(context),
                  foregroundColor:
                      dark ? const Color(0xFF102438) : Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  step.done ? l10n.str('setup_guide_next') : step.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Row(
              children: [
                if (!first)
                  Expanded(
                    child: TextButton(
                      onPressed: onBack,
                      style: secondary,
                      child: Text(
                        l10n.str('setup_guide_back'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (!step.done || last)
                  Expanded(
                    child: TextButton(
                      key: const Key('setup-guide-secondary-action'),
                      onPressed: onAdvance,
                      style: secondary,
                      child: Text(
                        l10n.str(
                          last ? 'setup_guide_finish' : 'setup_guide_next',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
