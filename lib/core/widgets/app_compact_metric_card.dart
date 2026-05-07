import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppCompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final double? width;

  const AppCompactMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.iconColor,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedAccent = iconColor ?? valueColor ?? AppColorScheme.primary;

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
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColorScheme.textMuted,
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 16, color: resolvedAccent),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColorScheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
