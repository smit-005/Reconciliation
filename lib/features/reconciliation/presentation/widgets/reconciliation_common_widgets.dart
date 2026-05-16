import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_info_chip.dart';

Widget summaryTile(String label, String value) {
  return Container(
    width: 175,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColorScheme.surfaceVariant,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColorScheme.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColorScheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppColorScheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

Widget mismatchTile({
  required String label,
  required String value,
  required Color bgColor,
  required Color textColor,
}) {
  return Container(
    width: 190,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: textColor.withValues(alpha: 0.20)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ],
    ),
  );
}

Widget miniInfoChip(BuildContext context, String label, String value) {
  return AppInfoChip(
    label: '$label:',
    value: value,
    compact: true,
    backgroundColor: Colors.white,
    borderColor: AppColorScheme.divider,
    labelFontWeight: FontWeight.w600,
    valueFontWeight: FontWeight.w800,
    fontSize: 12,
  );
}
