import 'package:flutter/material.dart';

import '../../../core/utils/normalize_utils.dart';
import '../models/reconciliation_row.dart';
import '../services/reconciliation_service.dart';
import '../../../core/utils/reconciliation_helpers.dart';
import 'reconciliation_financial_year_section.dart';

class ReconciliationTableSection extends StatefulWidget {
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
  State<ReconciliationTableSection> createState() =>
      _ReconciliationTableSectionState();
}

class _ReconciliationTableSectionState extends State<ReconciliationTableSection> {
  late List<_SellerGroupViewModel> _groups;

  @override
  void initState() {
    super.initState();
    _groups = _buildSellerGroups(widget.filteredRows);
  }

  @override
  void didUpdateWidget(covariant ReconciliationTableSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.filteredRows, widget.filteredRows)) {
      _groups = _buildSellerGroups(widget.filteredRows);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Reconciliation Table',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                '${widget.filteredRows.length} rows',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
            if (widget.isRecalculating) ...[
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
        const SizedBox(height: 6),
        Expanded(child: _buildTable(context)),
      ],
    );
  }

  Widget _buildTable(BuildContext context) {
    if (widget.filteredRows.isEmpty) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
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

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DCE4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final group = _groups[index];

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFCFD),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        group.sellerName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      _inlineMeta('PAN', group.sellerPan),
                      _inlineMeta('Rows', group.rowCount.toString()),
                      _inlineMeta('Basic', widget.formatAmount(group.totalBasic)),
                      _inlineMeta(
                        'Applicable',
                        widget.formatAmount(group.totalApplicable),
                      ),
                      _inlineMeta('26Q', widget.formatAmount(group.total26Q)),
                      _inlineMeta(
                        'Expected',
                        widget.formatAmount(group.totalExpected),
                      ),
                      _inlineMeta('Actual', widget.formatAmount(group.totalActual)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    children: group.financialYearGroups.map((fyGroup) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ReconciliationFinancialYearSection(
                          financialYear: fyGroup.financialYear,
                          rows: fyGroup.rows,
                          formatAmount: widget.formatAmount,
                          statusColor: widget.statusColor,
                          statusTextColor: widget.statusTextColor,
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

  List<_SellerGroupViewModel> _buildSellerGroups(List<ReconciliationRow> rows) {
    final grouped = <String, List<ReconciliationRow>>{};

    for (final row in rows) {
      final key = buildSellerDisplayKey(row);
      grouped.putIfAbsent(key, () => <ReconciliationRow>[]).add(row);
    }

    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final sellerRows = List<ReconciliationRow>.from(grouped[key]!)
        ..sort((a, b) {
          final fyCompare = a.financialYear.compareTo(b.financialYear);
          if (fyCompare != 0) return fyCompare;
          return CalculationService.compareMonthLabels(a.month, b.month);
        });

      final displayRow = sellerRows.firstWhere(
        (r) => r.sellerPan.trim().isNotEmpty && r.sellerName.trim().isNotEmpty,
        orElse: () => sellerRows.firstWhere(
          (r) => r.sellerName.trim().isNotEmpty,
          orElse: () => sellerRows.first,
        ),
      );

      final fyGroups = <String, List<ReconciliationRow>>{};
      for (final row in sellerRows) {
        fyGroups.putIfAbsent(row.financialYear, () => <ReconciliationRow>[]).add(row);
      }

      final fyKeys = fyGroups.keys.toList()..sort();

      return _SellerGroupViewModel(
        sellerName: displayRow.sellerName.trim().isEmpty
            ? '-'
            : displayRow.sellerName.trim(),
        sellerPan: _resolveDisplayPan(sellerRows),
        rowCount: sellerRows.length,
        totalBasic: sellerRows.fold(0.0, (sum, row) => sum + row.basicAmount),
        totalApplicable:
            sellerRows.fold(0.0, (sum, row) => sum + row.applicableAmount),
        total26Q: sellerRows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
        totalExpected:
            sellerRows.fold(0.0, (sum, row) => sum + row.expectedTds),
        totalActual: sellerRows.fold(0.0, (sum, row) => sum + row.actualTds),
        financialYearGroups: fyKeys
            .map(
              (fy) => _FinancialYearGroupViewModel(
                financialYear: fy,
                rows: List<ReconciliationRow>.from(fyGroups[fy]!)
                  ..sort(
                    (a, b) =>
                        CalculationService.compareMonthLabels(a.month, b.month),
                  ),
              ),
            )
            .toList(),
      );
    }).toList();
  }

  String _resolveDisplayPan(List<ReconciliationRow> rows) {
    for (final row in rows) {
      final pan = normalizePan(row.sellerPan);
      if (pan.isNotEmpty) return pan;
    }
    return '-';
  }

  Widget _inlineMeta(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        children: [
          const TextSpan(
            text: '| ',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerGroupViewModel {
  final String sellerName;
  final String sellerPan;
  final int rowCount;
  final double totalBasic;
  final double totalApplicable;
  final double total26Q;
  final double totalExpected;
  final double totalActual;
  final List<_FinancialYearGroupViewModel> financialYearGroups;

  const _SellerGroupViewModel({
    required this.sellerName,
    required this.sellerPan,
    required this.rowCount,
    required this.totalBasic,
    required this.totalApplicable,
    required this.total26Q,
    required this.totalExpected,
    required this.totalActual,
    required this.financialYearGroups,
  });
}

class _FinancialYearGroupViewModel {
  final String financialYear;
  final List<ReconciliationRow> rows;

  const _FinancialYearGroupViewModel({
    required this.financialYear,
    required this.rows,
  });
}
