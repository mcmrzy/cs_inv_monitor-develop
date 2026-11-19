import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';

class DeviceSettingsHeader extends StatelessWidget {
  const DeviceSettingsHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.status,
    required this.readLabel,
    this.device,
    this.detail,
    this.ready = false,
    this.reading = false,
    this.readProgress,
    this.onRead,
    this.onRefresh,
    this.refreshLabel,
  });

  final String title;
  final IconData icon;
  final String status;
  final String readLabel;
  final String? device;
  final String? detail;
  final bool ready;
  final bool reading;
  final double? readProgress;
  final VoidCallback? onRead;
  final VoidCallback? onRefresh;
  final String? refreshLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    final fill = AppColor.primarySoft(context);
    final statusStyle = text.bodySmall?.copyWith(color: muted);

    return DecoratedBox(
      decoration: AppColor.card(context).copyWith(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SettingsIconContainer(icon: icon, accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleLarge?.copyWith(
                          color: AppColor.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (device case final serial? when serial.isNotEmpty)
                        Text(
                          serial,
                          style: text.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                if (refreshLabel case final label?)
                  IconButton(
                    tooltip: label,
                    color: accent,
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 21),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: ready ? accent : AppColor.textHint(context),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 7),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    status,
                    style: statusStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: reading ? null : onRead,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: accent,
                backgroundColor: fill,
                disabledForegroundColor: reading ? accent : muted,
                disabledBackgroundColor:
                    reading ? fill : AppColor.surfaceHover(context),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: Text(readLabel, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 6),
            Text(
              detail ?? '\u00a0',
              style: statusStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 3,
              child: reading
                  ? LinearProgressIndicator(
                      value: readProgress,
                      color: accent,
                      backgroundColor: fill,
                      borderRadius: BorderRadius.circular(2),
                      semanticsLabel: readLabel,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

typedef DeviceSettingsEntry = ({
  String title,
  String summary,
  IconData icon,
  VoidCallback onTap,
});

class DeviceSettingsDirectory extends StatelessWidget {
  const DeviceSettingsDirectory({super.key, required this.entries});

  final List<DeviceSettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final text = Theme.of(context).textTheme;
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            zh ? '参数分类' : 'Parameter categories',
            style: text.titleSmall?.copyWith(color: muted),
          ),
        ),
        SettingsCard(
          [
            for (final entry in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading:
                    SettingsIconContainer(icon: entry.icon, accent: accent),
                title: Text(
                  entry.title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: entry.summary.isEmpty
                    ? null
                    : Text(
                        entry.summary,
                        style: text.bodySmall?.copyWith(color: muted),
                      ),
                trailing:
                    Icon(Icons.chevron_right_rounded, color: muted, size: 20),
                onTap: entry.onTap,
              ),
          ],
          margin: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class DeviceSettingsCategoryBack extends StatelessWidget {
  const DeviceSettingsCategoryBack({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: Text(zh ? '全部分类' : 'All categories'),
      ),
    );
  }
}

class DeviceSettingsNotice extends StatelessWidget {
  const DeviceSettingsNotice({
    super.key,
    required this.text,
    this.warning = false,
  });

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        warning ? AppColor.textPrimary(context) : AppColor.primary(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning
            ? AppColors.warning.withValues(alpha: 0.12)
            : AppColor.primarySoft(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
