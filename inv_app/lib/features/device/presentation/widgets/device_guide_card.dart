import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

/// A short introduction to an action, using the App's existing illustrations.
class DeviceGuideCard extends StatelessWidget {
  const DeviceGuideCard({
    super.key,
    required this.title,
    required this.illustration,
    this.action,
    this.details,
    this.subtitle,
    this.description,
  });

  final String title;
  final String? description;
  final String illustration;
  final Widget? action;
  final Widget? details;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: AppColor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                    if (subtitle case final line?) ...[
                      const SizedBox(height: 4),
                      Text(line,
                          style: text.labelMedium?.copyWith(
                            color: AppColor.primary(context),
                          )),
                    ],
                    if (description case final detail?) ...[
                      const SizedBox(height: 6),
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
              ),
              const SizedBox(width: 8),
              Image.asset(
                illustration,
                width: 92,
                height: 88,
                fit: BoxFit.contain,
                cacheWidth: 384,
                excludeFromSemantics: true,
              ),
            ],
          ),
          if (action case final button?) ...[
            const SizedBox(height: 12),
            button,
          ],
          if (details case final content?) ...[
            Divider(height: 24, color: AppColor.divider(context)),
            content,
          ],
        ],
      ),
    );
  }
}
