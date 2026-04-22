import 'package:flutter/material.dart';

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DCE4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: ReconciliationSummaryHeader(
              title: 'Analysis Panel',
              subtitle:
                  '${activeSectionTab == 'All' ? 'Combined' : activeSectionTab} scope | $sourceFileCount file(s) | $sourceRowCount row(s)',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _metricCardGrid(),
                  const SizedBox(height: 14),
                  _chipSection(),
                  const SizedBox(height: 14),
                  _insightsCard(),
                  if (detailedSummary != null) ...[
                    const SizedBox(height: 14),
                    Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        childrenPadding: EdgeInsets.zero,
                        collapsedBackgroundColor: const Color(0xFFF8FAFC),
                        backgroundColor: const Color(0xFFF8FAFC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                            padding: const EdgeInsets.all(10),
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
    );
  }

  Widget _metricCardGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mismatch Reasons',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unsupportedSections.isNotEmpty
            ? const Color(0xFFFFF7ED)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unsupportedSections.isNotEmpty
              ? const Color(0xFFF59E0B)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Notes & Insights',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
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
