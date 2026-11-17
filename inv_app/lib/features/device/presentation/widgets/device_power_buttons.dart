import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DevicePowerButtons extends StatelessWidget {
  const DevicePowerButtons({
    super.key,
    required this.startLabel,
    required this.stopLabel,
    required this.onStart,
    required this.onStop,
    this.busy = false,
  });

  final String startLabel;
  final String stopLabel;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 270 ||
                MediaQuery.textScalerOf(context).scale(16) >= 24;
            final start = _button(
              context,
              label: startLabel,
              icon: Icons.power_settings_new_rounded,
              onPressed: busy ? null : onStart,
              stop: false,
              stacked: stacked,
            );
            final stop = _button(
              context,
              label: stopLabel,
              icon: Icons.power_off_rounded,
              onPressed: busy ? null : onStop,
              stop: true,
              stacked: stacked,
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [start, const SizedBox(height: 12), stop],
              );
            }
            return Row(
              children: [
                Expanded(child: start),
                const SizedBox(width: 12),
                Expanded(child: stop),
              ],
            );
          },
        ),
        if (busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            zh ? '正在等待设备回执…' : 'Waiting for the device response…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _button(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool stop,
    required bool stacked,
  }) {
    final error = Theme.of(context).colorScheme.error;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(double.infinity, stacked ? 92 : 124),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        backgroundColor:
            stop ? error.withValues(alpha: 0.1) : AppColors.primary,
        foregroundColor: stop ? error : Colors.white,
        disabledBackgroundColor: AppColor.surfaceHover(context),
        disabledForegroundColor: AppColor.textHint(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onPressed == null
                      ? AppColor.textHint(context)
                      : stop
                          ? error
                          : Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}
