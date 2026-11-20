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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final accent = AppColor.primary(context);
    final muted = AppColor.textSecondary(context);
    final fill = AppColor.primarySoft(context);
    final statusStyle = text.bodySmall?.copyWith(color: muted);
    final statusColor =
        ready ? AppColor.accent(context, AppColors.success) : muted;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SettingsIconContainer(
                icon: icon,
                accent: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: AppColor.textPrimary(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (device case final serial? when serial.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        serial,
                        style: text.bodySmall?.copyWith(color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
          Divider(height: 16, color: AppColor.divider(context)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 7, color: statusColor),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            style: statusStyle?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detail case final message?)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 13,
                          top: 3,
                        ),
                        child: Text(
                          message,
                          style: statusStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    onPressed: reading ? null : onRead,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      foregroundColor: theme.colorScheme.onPrimary,
                      backgroundColor: accent,
                      disabledForegroundColor: reading ? accent : muted,
                      disabledBackgroundColor:
                          reading ? fill : AppColor.surfaceHover(context),
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(readLabel, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ),
          if (reading) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: readProgress,
              minHeight: 3,
              color: accent,
              backgroundColor: fill,
              borderRadius: BorderRadius.circular(2),
              semanticsLabel: readLabel,
            ),
          ],
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColor.surfaceContainer(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColor.divider(context)),
      ),
      child: content,
    );
  }
}

typedef DeviceSettingsEntry = ({
  String title,
  String summary,
  IconData icon,
  Color accent,
  VoidCallback onTap,
});

class DeviceSettingsDirectory extends StatelessWidget {
  const DeviceSettingsDirectory({super.key, required this.entries});

  final List<DeviceSettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final text = Theme.of(context).textTheme;
    final muted = AppColor.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            zh ? '参数分类' : 'Parameter categories',
            style: text.labelLarge?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SettingsCard(
          [
            for (final entry in entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                minTileHeight: 54,
                horizontalTitleGap: 10,
                leading: SizedBox.square(
                  dimension: 28,
                  child: Icon(entry.icon, color: entry.accent, size: 22),
                ),
                title: Text(
                  entry.title,
                  style: text.titleSmall?.copyWith(
                    color: AppColor.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: entry.summary.isEmpty
                    ? null
                    : Text(
                        entry.summary,
                        style: text.bodySmall?.copyWith(color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing:
                    Icon(Icons.chevron_right_rounded, color: muted, size: 18),
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
