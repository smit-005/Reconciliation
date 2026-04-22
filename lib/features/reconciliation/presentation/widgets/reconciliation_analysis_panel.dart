import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';

import 'reconciliation_reason_chip.dart';
import 'reconciliation_summary_header.dart';

class ReconciliationAnalysisPanel extends StatelessWidget {
  final String activeSectionTab;
  final int sourceFileCount;
  final int sourceRowCount;
  final int totalSellers;
  final int totalSections;
  final int manualMappingsCount;
  final String topMismatchSection;
  final Widget? detailedSummary;
  final Map<String, int> mismatchReasonCounts;
  final List<String> unsupportedSections;
  final int totalRows;
  final int mismatchRows;
  final double sourceAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;

  const ReconciliationAnalysisPanel({
    super.key,
    required this.activeSectionTab,
    required this.sourceFileCount,
    required this.sourceRowCount,
    required this.totalSellers,
    required this.totalSections,
    required this.manualMappingsCount,
    required this.topMismatchSection,
    required this.detailedSummary,
    required this.mismatchReasonCounts,
    required this.unsupportedSections,
    required this.totalRows,
    required this.mismatchRows,
    required this.sourceAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
  });

  String _fmt(double value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColorScheme.border),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF9FBFD),
                    Color(0xFFF3F7FB),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReconciliationSummaryHeader(
                    title: 'Analysis Panel',
                    subtitle:
                        '${activeSectionTab == 'All' ? 'Combined' : activeSectionTab} scope | $sourceFileCount file(s) | $sourceRowCount row(s)',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      AppStatusBadge(
                        label: '$totalSellers sellers',
                        icon: Icons.apartment_rounded,
                        tone: AppStatusBadgeTone.info,
                      ),
                      AppStatusBadge(
                        label: '$manualMappingsCount mappings',
                        icon: Icons.link_rounded,
                      ),
                      AppStatusBadge(
                        label: '$totalSections sections',
                        icon: Icons.grid_view_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metricCardGrid(),
                    const SizedBox(height: AppSpacing.md),
                    _chipSection(),
                    const SizedBox(height: AppSpacing.md),
                    _insightsCard(),
                    if (detailedSummary != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 2,
                          ),
                          childrenPadding: EdgeInsets.zero,
                          collapsedBackgroundColor:
                              AppColorScheme.surfaceVariant,
                          backgroundColor: AppColorScheme.surfaceVariant,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            side: const BorderSide(color: AppColorScheme.divider),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            side: const BorderSide(color: AppColorScheme.divider),
                          ),
                          title: const Text(
                            'Detailed Insights',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Expanded buyer-level analytics and mismatch detail',
                            style: TextStyle(fontSize: 12),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: detailedSummary!,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCardGrid() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _compactMetric('Total Rows', '$totalRows'),
        _compactMetric('Mismatch Rows', '$mismatchRows'),
        _compactMetric('Source Amount', _fmt(sourceAmount)),
        _compactMetric('26Q Amount', _fmt(tds26QAmount)),
        _compactMetric('Expected TDS', _fmt(expectedTds)),
        _compactMetric('Actual TDS', _fmt(actualTds)),
      ],
    );
  }

  Widget _compactMetric(String label, String value) {
    return SizedBox(
      width: 148,
      child: AppSectionCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        backgroundColor: AppColorScheme.surfaceVariant,
        borderColor: AppColorScheme.divider,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColorScheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipSection() {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      backgroundColor: AppColorScheme.surfaceVariant,
      borderColor: AppColorScheme.divider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mismatch Reasons',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              ReconciliationReasonChip(
                label: 'No 26Q entry',
                count: mismatchReasonCounts['No 26Q entry'] ?? 0,
                color: const Color(0xFFB45309),
              ),
              ReconciliationReasonChip(
                label: 'Amount mismatch',
                count: mismatchReasonCounts['Amount mismatch'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              ReconciliationReasonChip(
                label: 'TDS mismatch',
                count: mismatchReasonCounts['TDS mismatch'] ?? 0,
                color: const Color(0xFF7C3AED),
              ),
              ReconciliationReasonChip(
                label: 'Timing difference',
                count: mismatchReasonCounts['Timing difference'] ?? 0,
                color: const Color(0xFF0F766E),
              ),
              ReconciliationReasonChip(
                label: 'PAN/name mismatch',
                count: mismatchReasonCounts['PAN/name mismatch'] ?? 0,
                color: const Color(0xFF1D4ED8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightsCard() {
    final notes = <String>[
      'Top mismatch section: ${topMismatchSection.isEmpty ? '-' : topMismatchSection}',
      'Tracked sellers: $totalSellers',
      'Sections present in scope: $totalSections',
      'Seller mappings active: $manualMappingsCount',
      if (unsupportedSections.isNotEmpty)
        'Unsupported/unknown 26Q sections visible in current scope: ${unsupportedSections.join(', ')}',
    ];

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      backgroundColor: unsupportedSections.isNotEmpty
          ? const Color(0xFFFFF7ED)
          : AppColorScheme.surfaceVariant,
      borderColor: unsupportedSections.isNotEmpty
          ? const Color(0xFFF59E0B)
          : AppColorScheme.divider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Notes & Insights',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              if (unsupportedSections.isNotEmpty)
                const AppStatusBadge(
                  label: 'Attention Needed',
                  icon: Icons.warning_amber_rounded,
                  tone: AppStatusBadgeTone.warning,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColorScheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
