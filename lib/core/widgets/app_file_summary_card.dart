import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_spacing.dart';
import 'app_section_card.dart';
import 'app_status_badge.dart';

/// Reusable upload/file card. Keeps file rows visually consistent across upload,
/// mapping and review screens.
class AppFileSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? rowCountLabel;
  final AppStatusBadge? status;
  final List<Widget> actions;
  final IconData icon;

  const AppFileSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.rowCountLabel,
    this.status,
    this.actions = const [],
    this.icon = Icons.description_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColorScheme.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColorScheme.info, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColorScheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColorScheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (rowCountLabel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AppStatusBadge(
              label: rowCountLabel!,
              icon: Icons.table_rows_rounded,
              tone: AppStatusBadgeTone.neutral,
            ),
          ],
          if (status != null) ...[
            const SizedBox(width: AppSpacing.sm),
            status!,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
