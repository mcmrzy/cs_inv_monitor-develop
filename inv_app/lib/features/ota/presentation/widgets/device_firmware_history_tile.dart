import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/features/ota/presentation/models/firmware_module_presentation.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class DeviceFirmwareHistoryTile extends StatelessWidget {
  const DeviceFirmwareHistoryTile({
    super.key,
    required this.item,
    this.isFirst = false,
    this.isLast = false,
  });
  final DeviceFirmwareHistory item;
  final bool isFirst;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final module = FirmwareModulePresentation.fromTarget(item.target);
    const knownStatuses = {
      'pending',
      'downloading',
      'upgrading',
      'success',
      'failed',
      'cancelled',
    };
    final statusLabel = knownStatuses.contains(item.status)
        ? l10n.str('upgrade_history_status_${item.status}')
        : l10n.unknown;
    final time = item.updatedAt == null
        ? '—'
        : DateFormat('yyyy-MM-dd HH:mm').format(item.updatedAt!.toLocal());
    final statusColor = switch (item.status) {
      'success' => AppColors.successLight,
      'failed' => AppColors.errorLight,
      'cancelled' => AppColors.offline,
      _ => AppColors.blue,
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Stack(alignment: Alignment.topCenter, children: [
            if (!isFirst && !isLast)
              Positioned(
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: AppColor.border(context)))
            else if (!isLast)
              Positioned(
                  top: 18,
                  bottom: 0,
                  child: Container(width: 2, color: AppColor.border(context))),
            if (isLast && !isFirst)
              Positioned(
                  top: 0,
                  height: 18,
                  child: Container(width: 2, color: AppColor.border(context))),
            Positioned(
              top: 11,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColor.surface(context), width: 3),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColor.surfaceContainer(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColor.border(context)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColor.primarySoft(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(module.icon,
                      size: 18, color: AppColor.primary(context)),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(module.displayLabel(l10n),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _VersionLabel(
                    value: item.oldVersion.isEmpty ? '—' : item.oldVersion),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppColor.textHint(context)),
                ),
                _VersionLabel(
                    value: item.newVersion.isEmpty ? '—' : item.newVersion,
                    emphasized: true),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: AppColor.textHint(context)),
                const SizedBox(width: 5),
                Text(time,
                    style: TextStyle(
                        fontSize: 12, color: AppColor.textSecondary(context))),
              ]),
              if (item.changelog.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHover(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(item.changelog,
                      style: TextStyle(
                          height: 1.4,
                          fontSize: 13,
                          color: AppColor.textSecondary(context))),
                ),
              ],
              if (item.errorMessage.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.errorMessage,
                    style: const TextStyle(color: AppColors.errorLight)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel({required this.value, this.emphasized = false});
  final String value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: emphasized
              ? AppColor.primarySoft(context)
              : AppColor.surfaceHover(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: emphasized
                    ? AppColor.primary(context)
                    : AppColor.textSecondary(context))),
      );
}
