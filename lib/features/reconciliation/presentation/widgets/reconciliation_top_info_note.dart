import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';

class ReconciliationTopInfoNote extends StatelessWidget {
  const ReconciliationTopInfoNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColorScheme.infoSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColorScheme.info.withValues(alpha: 0.18)),
      ),
      child: const Text(
        'Relevant sellers only: this report includes only sellers who are present in 26Q or whose total purchase crosses Rs 50,00,000 in the financial year. Sellers below threshold and not present in 26Q are excluded to avoid false mismatches.',
        style: TextStyle(
          color: AppColorScheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
