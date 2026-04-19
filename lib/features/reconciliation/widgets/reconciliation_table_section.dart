import 'package:flutter/material.dart';

import '../../../core/utils/normalize_utils.dart';
import '../models/reconciliation_row.dart';
import '../services/reconciliation_service.dart';
import '../../../core/utils/reconciliation_helpers.dart';
import 'reconciliation_common_widgets.dart';
import 'reconciliation_financial_year_section.dart';

class ReconciliationTableSection extends StatelessWidget {
  final List<ReconciliationRow> filteredRows;
  final bool isRecalculating;
  final String Function(double value) formatAmount;

  final Color Function(String status) statusColor;
  final Color Function(String status) statusTextColor;

  const ReconciliationTableSection({
    super.key,
    required this.filteredRows,
    required this.isRecalculating,
    required this.formatAmount,
    required this.statusColor,
    required this.statusTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.table_view_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              'Reconciliation Table',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Text(
                '${filteredRows.length} rows',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo.shade700,
                ),
              ),
            ),
            if (isRecalculating) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildTable(context)),
      ],
    );
  }

  Widget _buildTable(BuildContext context) {
    if (filteredRows.isEmpty) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No rows found for selected filters.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    String resolveDisplayPan(List<ReconciliationRow> rows) {
      for (final row in rows) {
        final pan = normalizePan(row.sellerPan);
        if (pan.isNotEmpty) return pan;
      }
      return '-';
    }

    final grouped = <String, List<ReconciliationRow>>{};

    for (final row in filteredRows) {
      final key = buildSellerDisplayKey(row);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(row);
    }

    final groupKeys = grouped.keys.toList()..sort();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: groupKeys.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final key = groupKeys[index];
          final sourceRows = grouped[key]!;

          final rows = List<ReconciliationRow>.from(sourceRows)
            ..sort((a, b) {
              final fyCompare = a.financialYear.compareTo(b.financialYear);
              if (fyCompare != 0) return fyCompare;
              return CalculationService.compareMonthLabels(a.month, b.month);
            });

          final displayRow = rows.firstWhere(
                (r) => r.sellerPan.trim().isNotEmpty && r.sellerName.trim().isNotEmpty,
            orElse: () => rows.firstWhere(
                  (r) => r.sellerName.trim().isNotEmpty,
              orElse: () => rows.first,
            ),
          );

          final sellerName =
          displayRow.sellerName.trim().isEmpty ? '-' : displayRow.sellerName.trim();
          final sellerPan = resolveDisplayPan(rows);

          final totalBasic = rows.fold<double>(0.0, (sum, row) => sum + row.basicAmount);
          final totalApplicable = rows.fold<double>(0.0, (sum, row) => sum + row.applicableAmount);
          final total26Q = rows.fold<double>(0.0, (sum, row) => sum + row.tds26QAmount);
          final totalExpected = rows.fold<double>(0.0, (sum, row) => sum + row.expectedTds);
          final totalActual = rows.fold<double>(0.0, (sum, row) => sum + row.actualTds);

          final fyGroups = <String, List<ReconciliationRow>>{};
          for (final row in rows) {
            fyGroups.putIfAbsent(row.financialYear, () => []);
            fyGroups[row.financialYear]!.add(row);
          }

          final fyKeys = fyGroups.keys.toList()..sort();

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        sellerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      miniInfoChip(context, 'PAN', sellerPan),
                      miniInfoChip(context, 'Rows', rows.length.toString()),
                      miniInfoChip(context, 'Basic', formatAmount(totalBasic)),
                      miniInfoChip(context, 'Applicable', formatAmount(totalApplicable)),
                      miniInfoChip(context, '26Q', formatAmount(total26Q)),
                      miniInfoChip(context, 'Expected TDS', formatAmount(totalExpected)),
                      miniInfoChip(context, 'Actual TDS', formatAmount(totalActual)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: fyKeys.map((fy) {
                      final fyRows = List<ReconciliationRow>.from(fyGroups[fy]!)
                        ..sort(
                              (a, b) => CalculationService.compareMonthLabels(a.month, b.month),
                        );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ReconciliationFinancialYearSection(
                          financialYear: fy,
                          rows: fyRows,
                          formatAmount: formatAmount,
                          statusColor: statusColor,
                          statusTextColor: statusTextColor,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
