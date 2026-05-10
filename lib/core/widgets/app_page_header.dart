import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_spacing.dart';
import 'app_section_card.dart';

/// Reconciliation-style header reused by Upload, Mapping, Buyers and future pages.
class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final List<Widget> actions;
  final IconData? icon;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.chips = const [],
    this.actions = const [],
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColorScheme.infoSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColorScheme.info, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
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
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColorScheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: chips,
                  ),
                ],
              ],
            ),
          ),
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
