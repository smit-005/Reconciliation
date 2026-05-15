import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_sticky_action_bar.dart';

class ReconciliationBottomActionBar extends StatelessWidget {
  final VoidCallback? onExportCurrentView;
  final VoidCallback? onExportSection;
  final VoidCallback? onExportPivotReport;
  final VoidCallback? onExportDetailedReport;

  const ReconciliationBottomActionBar({
    super.key,
    required this.onExportCurrentView,
    required this.onExportSection,
    required this.onExportPivotReport,
    required this.onExportDetailedReport,
  });

  @override
  Widget build(BuildContext context) {
    return AppStickyActionBar(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.98),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 860;
          final actions = [
            _ActionButtonSlot(
              child: Tooltip(
                message:
                    'Export the current filtered working view to the Working folder.',
                child: AppPrimaryButton(
                  key: const ValueKey('export_current_button'),
                  onPressed: onExportCurrentView,
                  icon: Icons.download_rounded,
                  label: 'Export Working View',
                ),
              ),
            ),
            _ActionButtonSlot(
              child: Tooltip(
                message:
                    'Export the full selected section package to the Working folder.',
                child: AppSecondaryButton(
                  key: const ValueKey('export_section_button'),
                  onPressed: onExportSection,
                  icon: Icons.download_for_offline_rounded,
                  label: 'Export Section',
                ),
              ),
            ),
            _ActionButtonSlot(
              child: Tooltip(
                message:
                    'Export the final reconciliation workbook to Final_Exports.',
                child: AppSecondaryButton(
                  key: const ValueKey('export_pivot_button'),
                  onPressed: onExportPivotReport,
                  icon: Icons.table_chart_rounded,
                  label: 'Final Export',
                ),
              ),
            ),
            _ActionButtonSlot(
              child: Tooltip(
                message:
                    'Export the detailed audit workbook with raw reconciliation data.',
                child: AppSecondaryButton(
                  key: const ValueKey('export_detailed_button'),
                  onPressed: onExportDetailedReport,
                  icon: Icons.article_rounded,
                  label: 'Detailed Audit Export',
                ),
              ),
            ),
          ];
          final stackedChildren = <Widget>[
            const Text(
              'Exports',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...actions.expand(
              (slot) => [slot, const SizedBox(height: AppSpacing.xs)],
            ),
          ]..removeLast();

          if (stacked) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: stackedChildren,
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exports',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColorScheme.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    Expanded(child: actions[i]),
                    if (i != actions.length - 1)
                      const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionButtonSlot extends StatelessWidget {
  final Widget child;

  const _ActionButtonSlot({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Theme(
          data: Theme.of(context).copyWith(
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
