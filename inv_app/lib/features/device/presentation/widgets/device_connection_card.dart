import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';

class DeviceConnectionCard extends StatelessWidget {
  const DeviceConnectionCard({
    super.key,
    required this.icon,
    required this.connection,
    required this.connected,
    required this.dataStatus,
    this.sampleTime,
    this.action,
  });

  final IconData icon;
  final String connection;
  final bool connected;
  final String dataStatus;
  final DateTime? sampleTime;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        connected ? AppColor.primary(context) : AppColor.textHint(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return DecoratedBox(
      decoration: AppColor.card(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SettingsIconContainer(icon: icon, accent: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(connection, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(dataStatus, style: theme.textTheme.bodySmall),
                  if (sampleTime case final time?)
                    Text(
                      '${zh ? '采样时间' : 'Sample time'} '
                      '${DateFormat('MM-dd HH:mm:ss').format(time.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColor.textSecondary(context),
                      ),
                    ),
                ],
              ),
            ),
            if (action case final button?) button,
          ],
        ),
      ),
    );
  }
}
