import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_view_mode_toggle.dart';

class ReconciliationTopToolbar extends StatelessWidget {
  final String buyerName;
  final String buyerPan;
  final String gstNo;
  final Widget sectionTabs;
  final Widget filters;
  final ReconciliationViewMode viewMode;
  final bool isRecalculating;
  final ValueChanged<ReconciliationViewMode> onViewModeChanged;
  final VoidCallback? onRecalculate;
  final VoidCallback? onManualMapping;
  final String? viewModeHelperText;

  const ReconciliationTopToolbar({
    super.key,
    required this.buyerName,
    required this.buyerPan,
    required this.gstNo,
    required this.sectionTabs,
    required this.filters,
    required this.viewMode,
    required this.isRecalculating,
    required this.onViewModeChanged,
    required this.onRecalculate,
    this.onManualMapping,
    this.viewModeHelperText,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFDFEFF),
            Color(0xFFF6F9FC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: AppSectionCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        borderColor: AppColorScheme.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderBlock(),
            const SizedBox(height: AppSpacing.md),
            _buildTabSection(),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 1240;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      filters,
                      const SizedBox(height: AppSpacing.sm),
                      _buildActionRow(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: filters),
                    const SizedBox(width: AppSpacing.md),
                    _buildActionRow(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBlock() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 980;
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _displayBuyerTitle(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColorScheme.textPrimary,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _buildBuyerLine(),
          ],
        );

        final viewModeControl = ReconciliationViewModeToggle(
          value: viewMode,
          onChanged: onViewModeChanged,
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: AppSpacing.sm),
              viewModeControl,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            const SizedBox(width: AppSpacing.md),
            viewModeControl,
          ],
        );
      },
    );
  }

  Widget _buildBuyerLine() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _metaText('PAN', buyerPan.isEmpty ? '-' : buyerPan),
        _metaText('GST', gstNo.isEmpty ? '-' : gstNo),
      ],
    );
  }

  String _displayBuyerTitle() {
    final trimmed = buyerName.trim();
    if (trimmed.isEmpty) {
      return '-';
    }

    return trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  Widget _buildTabSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFE),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: sectionTabs,
    );
  }

  Widget _metaText(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColorScheme.textSecondary,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColorScheme.textMuted,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColorScheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppPrimaryButton(
          onPressed: onRecalculate,
          label: isRecalculating ? 'Recalculating...' : 'Recalculate',
          icon: Icons.refresh_rounded,
          isLoading: isRecalculating,
        ),
        if (onManualMapping != null)
          AppSecondaryButton(
            onPressed: onManualMapping,
            icon: Icons.link_rounded,
            label: 'Seller Mapping',
          ),
      ],
    );
  }
}
