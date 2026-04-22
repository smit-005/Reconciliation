import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/reconciliation_helpers.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';
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
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Reconciliation Table',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColorScheme.textPrimary,
                  ),
                ),
              ),
              AppStatusBadge(
                label: '${widget.filteredRows.length} rows',
                icon: Icons.table_rows_rounded,
              ),
              if (widget.isRecalculating) ...[
                const SizedBox(width: AppSpacing.sm),
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
        ),
        const SizedBox(height: AppSpacing.xs),
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
          border: Border.all(color: AppColorScheme.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
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
        border: Border.all(color: AppColorScheme.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        itemCount: _groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          final group = _groups[index];

          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColorScheme.divider),
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFBFCFD),
                        Color(0xFFF6F9FC),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.md),
                    ),
                    border: const Border(
                      bottom: BorderSide(color: AppColorScheme.divider),
                    ),
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        group.sellerName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColorScheme.textPrimary,
                        ),
                      ),
                      AppStatusBadge(
                        label: group.finalStatus,
                        icon: Icons.insights_rounded,
                        tone: _statusTone(group.finalStatus),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.xs,
                  ),
                  child: Column(
                    children: group.financialYearGroups.map((fyGroup) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
        (r) =>
            r.resolvedPan.trim().isNotEmpty &&
            r.resolvedSellerName.trim().isNotEmpty,
        orElse: () => sellerRows.firstWhere(
          (r) => r.resolvedSellerName.trim().isNotEmpty,
          orElse: () => sellerRows.first,
        ),
      );

      final fyGroups = <String, List<ReconciliationRow>>{};
      for (final row in sellerRows) {
        fyGroups.putIfAbsent(row.financialYear, () => <ReconciliationRow>[]).add(row);
      }

      final fyKeys = fyGroups.keys.toList()..sort();

      return _SellerGroupViewModel(
        sellerName: displayRow.resolvedSellerName.trim().isEmpty
            ? '-'
            : displayRow.resolvedSellerName.trim(),
        sellerPan: _resolveDisplayPan(sellerRows),
        finalStatus: CalculationService.buildSellerLevelStatus(sellerRows).status,
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
      final pan = normalizePan(row.resolvedPan);
      if (pan.isNotEmpty) return pan;
    }
    return '-';
  }

  Widget _inlineMeta(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: AppColorScheme.textMuted),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColorScheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppStatusBadgeTone _statusTone(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('match') && !normalized.contains('mismatch')) {
      return AppStatusBadgeTone.success;
    }
    if (normalized.contains('timing') || normalized.contains('review')) {
      return AppStatusBadgeTone.info;
    }
    if (normalized.contains('threshold') || normalized.contains('no 26q')) {
      return AppStatusBadgeTone.warning;
    }
    if (normalized.contains('mismatch') ||
        normalized.contains('short') ||
        normalized.contains('excess') ||
        normalized.contains('only')) {
      return AppStatusBadgeTone.danger;
    }
    return AppStatusBadgeTone.neutral;
  }
}

class _SellerGroupViewModel {
  final String sellerName;
  final String sellerPan;
  final String finalStatus;
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
    required this.finalStatus,
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
