import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;
  final IconData? icon;
  final Color? accentColor;
  final double? width;

  const AppMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.helper,
    this.icon,
    this.accentColor,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedAccent = accentColor ?? AppColorScheme.primary;

    return Container(
      width: width,
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (icon != null)
                Icon(icon, size: 18, color: resolvedAccent),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColorScheme.textPrimary,
                ),
          ),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              helper!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
