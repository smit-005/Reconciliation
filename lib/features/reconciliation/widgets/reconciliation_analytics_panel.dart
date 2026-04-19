import 'package:flutter/material.dart';

import 'reconciliation_common_widgets.dart';

class ReconciliationAnalyticsPanel extends StatelessWidget {
  final int mismatchRowsCount;
  final double mismatchPercentage;
  final double matchedPercentage;
  final String topMismatchSection;
  final int totalSellers;
  final int totalSections;
  final Map<String, int> sectionCounts;

  const ReconciliationAnalyticsPanel({
    super.key,
    required this.mismatchRowsCount,
    required this.mismatchPercentage,
    required this.matchedPercentage,
    required this.topMismatchSection,
    required this.totalSellers,
    required this.totalSections,
    required this.sectionCounts,
  });

  @override
  Widget build(BuildContext context) {
    final sections = sectionCounts.entries.take(6).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Analytics Dashboard',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              mismatchTile(
                label: 'Total Mismatch Rows',
                value: mismatchRowsCount.toString(),
                bgColor: Colors.red.shade50,
                textColor: Colors.red.shade700,
              ),
              mismatchTile(
                label: 'Mismatch %',
                value: '${mismatchPercentage.toStringAsFixed(1)}%',
                bgColor: Colors.orange.shade50,
                textColor: Colors.orange.shade800,
              ),
              mismatchTile(
                label: 'Matched %',
                value: '${matchedPercentage.toStringAsFixed(1)}%',
                bgColor: Colors.green.shade50,
                textColor: Colors.green.shade700,
              ),
              mismatchTile(
                label: 'Top Mismatch Section',
                value: topMismatchSection,
                bgColor: Colors.indigo.shade50,
                textColor: Colors.indigo.shade700,
              ),
              mismatchTile(
                label: 'Total Sellers',
                value: totalSellers.toString(),
                bgColor: Colors.blue.shade50,
                textColor: Colors.blue.shade700,
              ),
              mismatchTile(
                label: 'Sections Found',
                value: totalSections.toString(),
                bgColor: Colors.purple.shade50,
                textColor: Colors.purple.shade700,
              ),
            ],
          ),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Section Breakdown',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sections
                  .map(
                    (entry) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '${entry.key}: ${entry.value} rows',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
