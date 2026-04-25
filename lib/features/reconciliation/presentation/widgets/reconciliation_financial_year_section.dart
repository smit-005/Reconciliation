import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/reconciliation_row_explanation_builder.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';

const double _monthColumnWidth = 92;
const double _sectionColumnWidth = 84;
const double _amountColumnWidth = 96;
const double _statusColumnWidth = 132;
const double _remarksColumnWidth = 240;
const double _columnGap = 12;
const double _rowHorizontalPadding = 10;
const double _cellMinHeight = 26;
const double _minimumTableWidth =
    _monthColumnWidth +
    _sectionColumnWidth +
    (_amountColumnWidth * 7) +
    _statusColumnWidth +
    _remarksColumnWidth +
    (_columnGap * 10) +
    (_rowHorizontalPadding * 2);

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
    final totalBasic = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.basicAmount,
    );
    final totalApplicable = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.applicableAmount,
    );
    final total26Q = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.tds26QAmount,
    );
    final totalExpected = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.expectedTds,
    );
    final totalActual = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.actualTds,
    );
    final totalTdsDiff = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.tdsDifference,
    );
    final totalAmountDiff = rows.fold<double>(
      0.0,
      (sum, row) => sum + row.amountDifference,
    );
    final finalStatus = CalculationService.buildSellerLevelStatus(rows).status;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFCFE),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sm),
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
                  'FY $financialYear',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColorScheme.textPrimary,
                  ),
                ),
                _inlineMetric('Basic', formatAmount(totalBasic)),
                _inlineMetric('Applicable', formatAmount(totalApplicable)),
                _inlineMetric('26Q', formatAmount(total26Q)),
                _inlineMetric('Expected', formatAmount(totalExpected)),
                _inlineMetric('Actual', formatAmount(totalActual)),
                _inlineMetric('TDS Diff', formatAmount(totalTdsDiff)),
                _inlineMetric('Amt Diff', formatAmount(totalAmountDiff)),
              ],
            ),
          ),
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: const Text(
                'No reconciliation rows available for this financial year.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColorScheme.textMuted,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final hasBoundedWidth = constraints.maxWidth.isFinite;
                final effectiveWidth = hasBoundedWidth
                    ? constraints.maxWidth
                    : _minimumTableWidth;
                final tableWidth = effectiveWidth < _minimumTableWidth
                    ? _minimumTableWidth
                    : effectiveWidth;
                final needsHorizontalScroll = hasBoundedWidth
                    ? constraints.maxWidth < _minimumTableWidth
                    : true;

                final tableContent = SizedBox(
                  width: tableWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _HeaderRow(),
                        ...List.generate(
                          rows.length,
                          (index) => _DataRowCard(
                            index: index,
                            row: rows[index],
                            formatAmount: formatAmount,
                            statusColor: statusColor,
                            statusTextColor: statusTextColor,
                          ),
                        ),
                        _TotalRowCard(
                          totalBasic: totalBasic,
                          totalApplicable: totalApplicable,
                          total26Q: total26Q,
                          totalExpected: totalExpected,
                          totalActual: totalActual,
                          totalTdsDiff: totalTdsDiff,
                          totalAmountDiff: totalAmountDiff,
                          totalStatus: finalStatus,
                          formatAmount: formatAmount,
                          statusColor: statusColor,
                          statusTextColor: statusTextColor,
                        ),
                      ],
                    ),
                  ),
                );

                if (needsHorizontalScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    child: tableContent,
                  );
                }

                return tableContent;
              },
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _rowHorizontalPadding,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: const Border(bottom: BorderSide(color: AppColorScheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _buildTableColumns(
          month: const _HeaderText('Month'),
          section: const _HeaderText('Section'),
          basic: const _NumericHeaderText('Basic'),
          applicable: const _NumericHeaderText('Applicable'),
          tds26Q: const _NumericHeaderText('26Q'),
          expected: const _NumericHeaderText('Expected'),
          actual: const _NumericHeaderText('Actual'),
          tdsDiff: const _NumericHeaderText('TDS Diff'),
          amountDiff: const _NumericHeaderText('Amt Diff'),
          status: const _HeaderText('Status'),
          remarks: const _HeaderText('Remarks'),
        ),
      ),
    );
  }
}

class _DataRowCard extends StatefulWidget {
  final int index;
  final ReconciliationRow row;
  final String Function(double value) formatAmount;
  final Color Function(String status) statusColor;
  final Color Function(String status) statusTextColor;

  const _DataRowCard({
    required this.index,
    required this.row,
    required this.formatAmount,
    required this.statusColor,
    required this.statusTextColor,
  });

  @override
  State<_DataRowCard> createState() => _DataRowCardState();
}

class _DataRowCardState extends State<_DataRowCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final remarks = widget.row.remarks.trim();
    final zebra = widget.index.isEven
        ? const Color(0xFFFFFFFF)
        : const Color(0xFFF8FAFC);
    final hover = const Color(0xFFF3F7FB);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: () => _showRowExplanationDialog(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: _rowHorizontalPadding,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? hover : zebra,
            border: const Border(
              bottom: BorderSide(color: AppColorScheme.divider),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _buildTableColumns(
              month: _primaryText(
                widget.row.month.isEmpty ? '-' : widget.row.month,
              ),
              section: _secondaryText(normalizeSection(widget.row.section)),
              basic: _amountText(widget.formatAmount(widget.row.basicAmount)),
              applicable: _amountText(
                widget.formatAmount(widget.row.applicableAmount),
              ),
              tds26Q: _amountText(widget.formatAmount(widget.row.tds26QAmount)),
              expected: _amountText(
                widget.formatAmount(widget.row.expectedTds),
                emphasize: true,
              ),
              actual: _amountText(
                widget.formatAmount(widget.row.actualTds),
                emphasize: true,
              ),
              tdsDiff: _amountText(
                widget.formatAmount(widget.row.tdsDifference),
                emphasize: true,
                color: _deltaColor(widget.row.tdsDifference),
              ),
              amountDiff: _amountText(
                widget.formatAmount(widget.row.amountDifference),
                emphasize: true,
                color: _deltaColor(widget.row.amountDifference),
              ),
              status: _statusWithAction(),
              remarks: _remarksWithAction(remarks),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusWithAction() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _statusBadge(
            _statusDisplayLabel(widget.row.status),
            backgroundColor: widget.statusColor(widget.row.status),
            textColor: widget.statusTextColor(widget.row.status),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: AppColorScheme.textMuted,
        ),
      ],
    );
  }

  Widget _remarksWithAction(String remarks) {
    return Tooltip(
      message: remarks.isEmpty
          ? 'Open row explanation'
          : '$remarks\n\nClick for explanation',
      child: Row(
        children: [
          Expanded(
            child: Text(
              remarks.isEmpty ? '-' : remarks,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                height: 1.3,
                color: AppColorScheme.textMuted,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColorScheme.textMuted,
          ),
        ],
      ),
    );
  }

  Future<void> _showRowExplanationDialog(BuildContext context) async {
    final explanation = ReconciliationRowExplanationBuilder.build(
      row: widget.row,
      formatAmount: widget.formatAmount,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(explanation.reasonCategory),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.row.sellerName} • ${widget.row.month} • ${normalizeSection(widget.row.section).isEmpty ? widget.row.section : normalizeSection(widget.row.section)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColorScheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    explanation.explanation,
                    style: const TextStyle(
                      color: AppColorScheme.textPrimary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Values Compared',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColorScheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...explanation.comparedValues.map(
                    (value) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 190,
                            child: Text(
                              value.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColorScheme.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              value.value,
                              style: const TextStyle(
                                color: AppColorScheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${explanation.computedDifferenceLabel}: ${explanation.computedDifferenceValue}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColorScheme.textPrimary,
                    ),
                  ),
                  if (explanation.identityImpact.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Identity Impact',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColorScheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      explanation.identityImpact,
                      style: const TextStyle(
                        color: AppColorScheme.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (explanation.supportingNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Supporting Notes',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColorScheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...explanation.supportingNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $note',
                          style: const TextStyle(
                            color: AppColorScheme.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _primaryText(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _secondaryText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 11.5,
        color: Color(0xFF475569),
      ),
    );
  }

  Widget _amountText(String value, {bool emphasize = false, Color? color}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        value,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          fontSize: emphasize ? 12 : 11.5,
          color:
              color ??
              (emphasize ? const Color(0xFF0F172A) : const Color(0xFF334155)),
        ),
      ),
    );
  }

  Color _deltaColor(double value) {
    if (value > 0) return const Color(0xFFB45309);
    if (value < 0) return const Color(0xFFB91C1C);
    return const Color(0xFF0F172A);
  }
}

class _TotalRowCard extends StatelessWidget {
  final double totalBasic;
  final double totalApplicable;
  final double total26Q;
  final double totalExpected;
  final double totalActual;
  final double totalTdsDiff;
  final double totalAmountDiff;
  final String totalStatus;
  final String Function(double value) formatAmount;
  final Color Function(String status) statusColor;
  final Color Function(String status) statusTextColor;

  const _TotalRowCard({
    required this.totalBasic,
    required this.totalApplicable,
    required this.total26Q,
    required this.totalExpected,
    required this.totalActual,
    required this.totalTdsDiff,
    required this.totalAmountDiff,
    required this.totalStatus,
    required this.formatAmount,
    required this.statusColor,
    required this.statusTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _rowHorizontalPadding,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: const Border(top: BorderSide(color: AppColorScheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _buildTableColumns(
          month: const Text(
            'TOTAL',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          section: const SizedBox.shrink(),
          basic: _totalAmountText(formatAmount(totalBasic)),
          applicable: _totalAmountText(formatAmount(totalApplicable)),
          tds26Q: _totalAmountText(formatAmount(total26Q)),
          expected: _totalAmountText(formatAmount(totalExpected)),
          actual: _totalAmountText(formatAmount(totalActual)),
          tdsDiff: _totalAmountText(formatAmount(totalTdsDiff)),
          amountDiff: _totalAmountText(formatAmount(totalAmountDiff)),
          status: _statusBadge(
            _statusDisplayLabel(totalStatus),
            backgroundColor: statusColor(totalStatus),
            textColor: statusTextColor(totalStatus),
          ),
          remarks: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _totalAmountText(String value) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        value,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}

List<Widget> _buildTableColumns({
  required Widget month,
  required Widget section,
  required Widget basic,
  required Widget applicable,
  required Widget tds26Q,
  required Widget expected,
  required Widget actual,
  required Widget tdsDiff,
  required Widget amountDiff,
  required Widget status,
  required Widget remarks,
}) {
  return [
    _tableCell(width: _monthColumnWidth, child: month),
    const SizedBox(width: _columnGap),
    _tableCell(width: _sectionColumnWidth, child: section),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: basic),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: applicable),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: tds26Q),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: expected),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: actual),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: tdsDiff),
    const SizedBox(width: _columnGap),
    _tableCell(width: _amountColumnWidth, child: amountDiff),
    const SizedBox(width: _columnGap),
    _tableCell(width: _statusColumnWidth, child: status),
    const SizedBox(width: _columnGap),
    _tableCell(width: _remarksColumnWidth, child: remarks),
  ];
}

Widget _tableCell({
  required double width,
  required Widget child,
  Alignment alignment = Alignment.centerLeft,
}) {
  return SizedBox(
    width: width,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _cellMinHeight),
      child: Align(alignment: alignment, child: child),
    ),
  );
}

class _HeaderText extends StatelessWidget {
  final String label;

  const _HeaderText(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
        color: AppColorScheme.textSecondary,
      ),
    );
  }
}

class _NumericHeaderText extends StatelessWidget {
  final String label;

  const _NumericHeaderText(this.label);

  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.centerRight, child: _HeaderText(label));
  }
}

String _statusDisplayLabel(String status) {
  switch (status) {
    case ReconciliationStatus.belowThreshold:
      return 'Below Threshold';
    case ReconciliationStatus.reviewRequired:
      return 'Review';
    case ReconciliationStatus.amountMismatch:
      return 'Amt mismatch';
    case ReconciliationStatus.applicableButNo26Q:
      return 'No 26Q';
    case ReconciliationStatus.onlyIn26Q:
      return 'Only 26Q';
    default:
      return status;
  }
}

Widget _inlineMetric(String label, String value) {
  return RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 10.8, color: Color(0xFF64748B)),
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
            color: AppColorScheme.textSecondary,
          ),
        ),
      ],
    ),
  );
}

Widget _statusBadge(
  String label, {
  required Color backgroundColor,
  required Color textColor,
}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: textColor,
          fontSize: 11.5,
          height: 1.1,
        ),
      ),
    ),
  );
}
