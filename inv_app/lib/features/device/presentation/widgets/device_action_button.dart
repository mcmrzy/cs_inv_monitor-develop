import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DeviceActionButton extends StatelessWidget {
  const DeviceActionButton({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = AppColor.textSecondary(context);
    final enabled = onPressed != null;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 84),
        padding: const EdgeInsets.all(16),
        backgroundColor: AppColor.surfaceContainer(context),
        foregroundColor: AppColor.primary(context),
        disabledBackgroundColor: AppColor.surfaceHover(context),
        side: BorderSide(color: AppColor.border(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    color: enabled ? AppColor.textPrimary(context) : muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 20, color: muted),
        ],
      ),
    );
  }
}
