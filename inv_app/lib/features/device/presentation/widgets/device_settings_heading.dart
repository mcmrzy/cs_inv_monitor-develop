import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

class DeviceSettingsHeading extends StatelessWidget {
  const DeviceSettingsHeading({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.headlineSmall?.copyWith(
              color: AppColor.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (description case final detail?) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: text.bodySmall?.copyWith(
                color: AppColor.textSecondary(context),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
