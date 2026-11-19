import 'package:flutter/material.dart';
import 'package:inv_app/core/theme/app_theme.dart';

/// Connection and upgrade screens use the same frame for their current state.
class DeviceWorkflowCard extends StatelessWidget {
  const DeviceWorkflowCard({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    this.description,
    this.subtitle,
    this.action,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String status;
  final String? description;
  final String? subtitle;
  final Widget? action;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const foreground = Color(0xFFEEF6FF);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142D4C), Color(0xFF195678)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.13),
                  ),
                  child: Icon(icon, color: foreground, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle case final detail?) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: text.bodySmall?.copyWith(color: foreground),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (description case final detail?) ...[
              const SizedBox(height: 10),
              Text(detail, style: text.bodySmall?.copyWith(color: foreground)),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black.withValues(alpha: .2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text(
                      status,
                      style: text.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (action case final button?) button,
              ],
            ),
            if (progress case final value?) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: value,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
                color: const Color(0xFF9DD8FD),
                backgroundColor: foreground.withValues(alpha: .20),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static ButtonStyle actionStyle(BuildContext context) => FilledButton.styleFrom(
        backgroundColor: const Color(0xFFEEF6FF),
        foregroundColor: const Color(0xFF142D4C),
        disabledBackgroundColor: AppColor.surfaceContainer(context)
            .withValues(alpha: .15),
        disabledForegroundColor: const Color(0xFFDBE7F2),
        minimumSize: const Size(0, 44),
      );
}
