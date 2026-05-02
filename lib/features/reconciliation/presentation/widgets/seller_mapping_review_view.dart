import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_models.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_theme.dart';

typedef SellerReviewStatusGetter = String Function(SellerMappingRowVm row);
typedef SellerReviewValueGetter = String? Function(SellerMappingRowVm row);
typedef SellerReviewStringGetter = String Function(SellerMappingRowVm row);
typedef SellerReviewLinkedLedgerGetter =
    SellerMappingRowVm? Function(SellerMappingRowVm row);

class SellerMappingReviewView extends StatelessWidget {
  final List<SellerMappingRowVm> rows;
  final List<SellerMappingRowVm> allRowsForSection;
  final String activeSectionLabel;
  final SellerReviewStatusGetter statusForRow;
  final SellerReviewValueGetter selectedValueForRow;
  final SellerReviewStringGetter selectedPanForRow;
  final SellerReviewLinkedLedgerGetter linkedLedgerRowForRow;

  const SellerMappingReviewView({
    super.key,
    required this.rows,
    required this.allRowsForSection,
    required this.activeSectionLabel,
    required this.statusForRow,
    required this.selectedValueForRow,
    required this.selectedPanForRow,
    required this.linkedLedgerRowForRow,
  });

  @override
  Widget build(BuildContext context) {
    final summary = _ReviewSummary.fromRows(allRowsForSection, statusForRow);

    return Container(
      decoration: BoxDecoration(
        color: SellerMappingTheme.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SellerMappingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Review View',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: SellerMappingTheme.titleTextColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$activeSectionLabel seller mapping audit. Use this view to verify every 26Q seller is either mapped or marked as a reviewed exception.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: SellerMappingTheme.mutedTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SummaryChip(
                      label: '26Q Sellers',
                      value: summary.total26QSellers,
                      icon: Icons.receipt_long_outlined,
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      label: 'Mapped',
                      value: summary.mappedSellers,
                      icon: Icons.link_rounded,
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      label: 'Exceptions',
                      value: summary.exceptionSellers,
                      icon: Icons.rule_folder_outlined,
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      label: 'Pending',
                      value: summary.pendingSellers,
                      icon: Icons.pending_actions_rounded,
                      emphasized: summary.pendingSellers > 0,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _CompletionBanner(summary: summary),
              ],
            ),
          ),
          const Divider(height: 1, color: SellerMappingTheme.borderColor),
          Expanded(
            child: rows.isEmpty
                ? const _EmptyReviewState()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _ReviewSellerRow(
                        row: row,
                        status: statusForRow(row),
                        selectedValue: selectedValueForRow(row),
                        selectedPan: selectedPanForRow(row),
                        linkedLedgerRow: linkedLedgerRowForRow(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSummary {
  final int total26QSellers;
  final int mappedSellers;
  final int exceptionSellers;
  final int pendingSellers;

  const _ReviewSummary({
    required this.total26QSellers,
    required this.mappedSellers,
    required this.exceptionSellers,
    required this.pendingSellers,
  });

  bool get isComplete => total26QSellers > 0 && pendingSellers == 0;

  static _ReviewSummary fromRows(
    List<SellerMappingRowVm> rows,
    SellerReviewStatusGetter statusForRow,
  ) {
    var total26Q = 0;
    var mapped = 0;
    var exceptions = 0;
    var pending = 0;

    for (final row in rows) {
      final has26Q = row.tdsRowCount > 0 || row.is26QUnmatched;
      if (!has26Q) continue;
      total26Q++;

      final status = statusForRow(row);
      if (_isMappedStatus(status)) {
        mapped++;
      } else if (_isExceptionStatus(status)) {
        exceptions++;
      } else if (_isPendingStatus(status)) {
        pending++;
      }
    }

    return _ReviewSummary(
      total26QSellers: total26Q,
      mappedSellers: mapped,
      exceptionSellers: exceptions,
      pendingSellers: pending,
    );
  }

  static bool _isMappedStatus(String status) {
    return status == 'Mapped' ||
        status == 'Mapped (PAN missing)' ||
        status == 'Linked to Ledger';
  }

  static bool _isExceptionStatus(String status) {
    return status == 'Missing in Books' ||
        status == 'Timing Difference' ||
        status == 'Marked Separate' ||
        status == 'Purchase Only';
  }

  static bool _isPendingStatus(String status) {
    return status == '26Q Unmatched' ||
        status == 'PAN Conflict' ||
        status == 'Conflicting PAN' ||
        status == 'Ambiguous Identity' ||
        status == 'Unresolved Identity' ||
        status == 'Unmapped';
  }
}

class _CompletionBanner extends StatelessWidget {
  final _ReviewSummary summary;

  const _CompletionBanner({required this.summary});

  @override
  Widget build(BuildContext context) {
    final isComplete = summary.isComplete;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isComplete ? const Color(0xFFEAF7EF) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isComplete ? const Color(0xFFB7E4C7) : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.verified_rounded : Icons.warning_amber_rounded,
            color: isComplete
                ? const Color(0xFF15803D)
                : const Color(0xFFC2410C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isComplete
                  ? 'All sellers reviewed. Every 26Q seller is mapped or marked as a valid exception.'
                  : '${summary.pendingSellers} seller(s) still need review before mapping can be considered complete.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isComplete
                    ? const Color(0xFF166534)
                    : const Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool emphasized;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized
              ? const Color(0xFFFED7AA)
              : SellerMappingTheme.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: SellerMappingTheme.mutedTextColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: SellerMappingTheme.mutedTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: SellerMappingTheme.titleTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSellerRow extends StatelessWidget {
  final SellerMappingRowVm row;
  final String status;
  final String? selectedValue;
  final String selectedPan;
  final SellerMappingRowVm? linkedLedgerRow;

  const _ReviewSellerRow({
    required this.row,
    required this.status,
    required this.selectedValue,
    required this.selectedPan,
    required this.linkedLedgerRow,
  });

  @override
  Widget build(BuildContext context) {
    final isException = _ReviewSummary._isExceptionStatus(status);
    final isMapped = _ReviewSummary._isMappedStatus(status);
    final borderColor = isMapped
        ? const Color(0xFFBBF7D0)
        : isException
        ? const Color(0xFFFED7AA)
        : const Color(0xFFFECACA);
    final bgColor = isMapped
        ? const Color(0xFFF0FDF4)
        : isException
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFFEF2F2);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _SellerInfoBlock(
              title: row.purchasePartyDisplayName.trim().isEmpty
                  ? row.normalizedAlias
                  : row.purchasePartyDisplayName.trim(),
              subtitle: row.is26QUnmatched ? '26Q Seller' : 'Ledger Seller',
              chips: [
                'Section ${row.sectionCode}',
                row.purchasePan.trim().isEmpty
                    ? '${row.is26QUnmatched ? '26Q' : 'Ledger'} PAN not available'
                    : '${row.is26QUnmatched ? '26Q' : 'Ledger'} PAN ${row.purchasePan.trim().toUpperCase()}',
                'Ledger rows ${row.sourceRowCount}',
                '26Q rows ${row.tdsRowCount}',
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _SellerInfoBlock(
              title: _targetTitle(),
              subtitle: _targetSubtitle(),
              chips: _targetChips(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: Align(
              alignment: Alignment.topRight,
              child: _StatusBadge(status: status),
            ),
          ),
        ],
      ),
    );
  }

  String _targetTitle() {
    final selected = selectedValue?.trim() ?? '';
    if (selected.isEmpty) return 'No reviewed target';
    if (selected.startsWith('__MISSING_IN_BOOKS__:')) return 'Missing in Books';
    if (selected.startsWith('__TIMING_DIFFERENCE__:'))
      return 'Timing Difference';
    if (selected.startsWith('__SEPARATE__:')) return 'Keep Separate';
    if (selected.startsWith('__LINK_LEDGER__:')) {
      final linkedName = linkedLedgerRow?.purchasePartyDisplayName.trim() ?? '';
      return linkedName.isEmpty ? 'Linked ledger seller' : linkedName;
    }
    return selected;
  }

  String _targetSubtitle() {
    if (_ReviewSummary._isExceptionStatus(status)) {
      return 'Reviewed Exception';
    }
    if (_ReviewSummary._isMappedStatus(status)) {
      return 'Mapped Decision';
    }
    return 'Pending Decision';
  }

  List<String> _targetChips() {
    final linkedPan = linkedLedgerRow?.purchasePan.trim() ?? '';
    if (linkedPan.isNotEmpty) {
      return ['Ledger PAN ${linkedPan.toUpperCase()}'];
    }
    if (linkedLedgerRow != null) {
      return ['Ledger PAN not available'];
    }
    if (selectedPan.trim().isNotEmpty && selectedPan != '-') {
      return ['Target PAN ${selectedPan.trim().toUpperCase()}'];
    }
    return ['Target PAN not available'];
  }
}

class _SellerInfoBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> chips;

  const _SellerInfoBlock({
    required this.title,
    required this.subtitle,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: SellerMappingTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: SellerMappingTheme.titleTextColor,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: chips
              .where((chip) => chip.trim().isNotEmpty)
              .map(
                (chip) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: SellerMappingTheme.borderColor),
                  ),
                  child: Text(
                    chip,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SellerMappingTheme.mutedTextColor,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isMapped = _ReviewSummary._isMappedStatus(status);
    final isException = _ReviewSummary._isExceptionStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isMapped
            ? const Color(0xFFDCFCE7)
            : isException
            ? const Color(0xFFFFEDD5)
            : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isMapped
              ? const Color(0xFF86EFAC)
              : isException
              ? const Color(0xFFFDBA74)
              : const Color(0xFFFCA5A5),
        ),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: isMapped
              ? const Color(0xFF166534)
              : isException
              ? const Color(0xFF9A3412)
              : const Color(0xFF991B1B),
        ),
      ),
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  const _EmptyReviewState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No seller rows match the current filters.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: SellerMappingTheme.mutedTextColor,
        ),
      ),
    );
  }
}
