import 'package:flutter/material.dart';

import '../../core/utils/normalize_utils.dart';
import '../../models/reconciliation_row.dart';
import '../../services/reconciliation_service.dart';
import '../../core/utils/reconciliation_helpers.dart';
import 'reconciliation_common_widgets.dart';

class ReconciliationFinancialYearSection extends StatelessWidget {
  final String financialYear;
  final List<ReconciliationRow> rows;
  final String Function(double value) formatAmount;
  final Color Function(String status) statusColor;
  final Color Function(String status) statusTextColor;

  const ReconciliationFinancialYearSection({
    super.key,
    required this.financialYear,
    required this.rows,
    required this.formatAmount,
    required this.statusColor,
    required this.statusTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final totalBasic = rows.fold<double>(0.0, (sum, row) => sum + row.basicAmount);
    final totalApplicable = rows.fold<double>(0.0, (sum, row) => sum + row.applicableAmount);
    final total26Q = rows.fold<double>(0.0, (sum, row) => sum + row.tds26QAmount);
    final totalExpected = rows.fold<double>(0.0, (sum, row) => sum + row.expectedTds);
    final totalActual = rows.fold<double>(0.0, (sum, row) => sum + row.actualTds);
    final totalTdsDiff = rows.fold<double>(0.0, (sum, row) => sum + row.tdsDifference);
    final totalAmountDiff = rows.fold<double>(0.0, (sum, row) => sum + row.amountDifference);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'FY $financialYear',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                miniInfoChip(context, 'Basic', formatAmount(totalBasic)),
                miniInfoChip(context, 'Applicable', formatAmount(totalApplicable)),
                miniInfoChip(context, '26Q', formatAmount(total26Q)),
                miniInfoChip(context, 'Expected', formatAmount(totalExpected)),
                miniInfoChip(context, 'Actual', formatAmount(totalActual)),
                miniInfoChip(context, 'TDS Diff', formatAmount(totalTdsDiff)),
                miniInfoChip(context, 'Amt Diff', formatAmount(totalAmountDiff)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 68,
              headingRowColor: WidgetStatePropertyAll(Colors.blue.shade100),
              columns: const [
                DataColumn(
                  label: Text(
                    'Month',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Section',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Basic Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Applicable Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '26Q Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Expected TDS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Actual TDS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'TDS Diff',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Amt Diff',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Remarks',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: [
                ...rows.map(
                      (row) => DataRow(
                    color: WidgetStatePropertyAll(statusColor(row.status)),
                    cells: [
                      DataCell(Text(row.month.isEmpty ? '-' : row.month)),
                      DataCell(Text(normalizeSection(row.section))),
                      DataCell(Text(formatAmount(row.basicAmount))),
                      DataCell(Text(formatAmount(row.applicableAmount))),
                      DataCell(Text(formatAmount(row.tds26QAmount))),
                      DataCell(Text(formatAmount(row.expectedTds))),
                      DataCell(Text(formatAmount(row.actualTds))),
                      DataCell(Text(formatAmount(row.tdsDifference))),
                      DataCell(Text(formatAmount(row.amountDifference))),
                      DataCell(
                        Text(
                          row.status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: statusTextColor(row.status),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Text(row.remarks.isEmpty ? '-' : row.remarks),
                        ),
                      ),
                    ],
                  ),
                ),
                DataRow(
                  color: WidgetStatePropertyAll(Colors.amber.shade50),
                  cells: [
                    const DataCell(
                      Text(
                        'TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const DataCell(Text('')),
                    DataCell(
                      Text(
                        formatAmount(totalBasic),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(totalApplicable),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(total26Q),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(totalExpected),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(totalActual),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(totalTdsDiff),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        formatAmount(totalAmountDiff),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}