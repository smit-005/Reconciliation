import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_row_explanation.dart';

class ReconciliationRowExplanationBuilder {
  static ReconciliationRowExplanation build({
    required ReconciliationRow row,
    required String Function(double value) formatAmount,
  }) {
    final status = row.status.trim();
    final comparedValues = _buildComparedValues(
      row: row,
      status: status,
      formatAmount: formatAmount,
    );
    final computedDifference = _buildComputedDifference(
      row: row,
      status: status,
      formatAmount: formatAmount,
    );

    return ReconciliationRowExplanation(
      reasonCategory: _reasonCategory(status),
      comparedValues: comparedValues,
      computedDifferenceLabel: computedDifference.label,
      computedDifferenceValue: computedDifference.value,
      explanation: _buildExplanation(row: row, status: status),
      identityImpact: _buildIdentityImpact(row),
      supportingNotes: _buildSupportingNotes(row),
    );
  }

  static String _reasonCategory(String status) {
    switch (status) {
      case ReconciliationStatus.belowThreshold:
        return 'Threshold not crossed';
      case ReconciliationStatus.applicableButNo26Q:
        return 'Applicable but no 26Q';
      case ReconciliationStatus.amountMismatch:
        return 'Amount mismatch';
      case ReconciliationStatus.shortDeduction:
      case ReconciliationStatus.excessDeduction:
        return 'TDS mismatch';
      case ReconciliationStatus.timingDifference:
        return 'Timing difference';
      case ReconciliationStatus.sectionMissing:
        return 'Section missing';
      case ReconciliationStatus.onlyIn26Q:
        return 'Only in 26Q';
      case ReconciliationStatus.reviewRequired:
        return 'Manual review required';
      default:
        return status.isEmpty ? 'Row explanation' : status;
    }
  }

  static List<ReconciliationRowExplanationValue> _buildComparedValues({
    required ReconciliationRow row,
    required String status,
    required String Function(double value) formatAmount,
  }) {
    switch (status) {
      case ReconciliationStatus.belowThreshold:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Basic amount',
            value: formatAmount(row.basicAmount),
          ),
          ReconciliationRowExplanationValue(
            label: 'Applicable amount',
            value: formatAmount(row.applicableAmount),
          ),
          ReconciliationRowExplanationValue(
            label: 'Cumulative before',
            value: formatAmount(row.debugInfo.cumulativePurchaseBeforeRow),
          ),
          ReconciliationRowExplanationValue(
            label: 'Cumulative after',
            value: formatAmount(row.debugInfo.cumulativePurchaseAfterRow),
          ),
        ];
      case ReconciliationStatus.applicableButNo26Q:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Applicable amount',
            value: formatAmount(row.applicableAmount),
          ),
          ReconciliationRowExplanationValue(
            label: '26Q amount',
            value: formatAmount(row.tds26QAmount),
          ),
          ReconciliationRowExplanationValue(
            label: 'Expected TDS',
            value: formatAmount(row.expectedTds),
          ),
          ReconciliationRowExplanationValue(
            label: 'Actual TDS',
            value: formatAmount(row.actualTds),
          ),
        ];
      case ReconciliationStatus.amountMismatch:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Applicable amount',
            value: formatAmount(row.applicableAmount),
          ),
          ReconciliationRowExplanationValue(
            label: '26Q amount',
            value: formatAmount(row.tds26QAmount),
          ),
        ];
      case ReconciliationStatus.shortDeduction:
      case ReconciliationStatus.excessDeduction:
      case ReconciliationStatus.timingDifference:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Expected TDS',
            value: formatAmount(row.expectedTds),
          ),
          ReconciliationRowExplanationValue(
            label: 'Actual TDS',
            value: formatAmount(row.actualTds),
          ),
        ];
      case ReconciliationStatus.sectionMissing:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Section',
            value: row.section.trim().isEmpty ? 'Missing' : row.section.trim(),
          ),
          ReconciliationRowExplanationValue(
            label: 'Applicable amount',
            value: formatAmount(row.applicableAmount),
          ),
        ];
      default:
        return <ReconciliationRowExplanationValue>[
          ReconciliationRowExplanationValue(
            label: 'Applicable amount',
            value: formatAmount(row.applicableAmount),
          ),
          ReconciliationRowExplanationValue(
            label: '26Q amount',
            value: formatAmount(row.tds26QAmount),
          ),
          ReconciliationRowExplanationValue(
            label: 'Expected TDS',
            value: formatAmount(row.expectedTds),
          ),
          ReconciliationRowExplanationValue(
            label: 'Actual TDS',
            value: formatAmount(row.actualTds),
          ),
        ];
    }
  }

  static ReconciliationRowExplanationValue _buildComputedDifference({
    required ReconciliationRow row,
    required String status,
    required String Function(double value) formatAmount,
  }) {
    switch (status) {
      case ReconciliationStatus.amountMismatch:
      case ReconciliationStatus.applicableButNo26Q:
      case ReconciliationStatus.onlyIn26Q:
        return ReconciliationRowExplanationValue(
          label: 'Applicable minus 26Q amount',
          value: formatAmount(row.amountDifference),
        );
      case ReconciliationStatus.shortDeduction:
      case ReconciliationStatus.excessDeduction:
        return ReconciliationRowExplanationValue(
          label: 'Expected minus actual TDS',
          value: formatAmount(row.tdsDifference),
        );
      case ReconciliationStatus.timingDifference:
        return ReconciliationRowExplanationValue(
          label: 'Month timing difference',
          value: formatAmount(row.monthTdsDifference),
        );
      case ReconciliationStatus.belowThreshold:
        return ReconciliationRowExplanationValue(
          label: 'Applicable amount after threshold',
          value: formatAmount(row.applicableAmount),
        );
      case ReconciliationStatus.sectionMissing:
        return ReconciliationRowExplanationValue(
          label: 'Amount kept out of rule evaluation',
          value: formatAmount(row.basicAmount),
        );
      default:
        return ReconciliationRowExplanationValue(
          label: 'Expected minus actual TDS',
          value: formatAmount(row.tdsDifference),
        );
    }
  }

  static String _buildExplanation({
    required ReconciliationRow row,
    required String status,
  }) {
    switch (status) {
      case ReconciliationStatus.belowThreshold:
        return 'This row stayed below the applicable section threshold for the month, so no deductible amount and no matching 26Q entry were expected.';
      case ReconciliationStatus.applicableButNo26Q:
        return 'The row became applicable for TDS based on the section rule, but no matching 26Q amount or TDS was found for the same seller, month, financial year, and section.';
      case ReconciliationStatus.amountMismatch:
        return 'The deductible base from source records does not match the deducted amount reported in 26Q for the same reconciliation bucket.';
      case ReconciliationStatus.shortDeduction:
        return '26Q is present, but the TDS reported is lower than the TDS expected from the applicable amount and section rate.';
      case ReconciliationStatus.excessDeduction:
        return '26Q is present, but the TDS reported is higher than the TDS expected from the applicable amount and section rate.';
      case ReconciliationStatus.timingDifference:
        return 'The TDS difference is being tracked across months for this seller, so this row reflects a carry-forward timing gap rather than a simple same-month mismatch.';
      case ReconciliationStatus.sectionMissing:
        return 'The section is missing or unsupported, so the row could not be evaluated confidently against section rules and rates.';
      case ReconciliationStatus.onlyIn26Q:
        return 'A 26Q entry exists for this reconciliation bucket, but there is no matching source-side row for the same seller, month, financial year, and section.';
      case ReconciliationStatus.reviewRequired:
        return 'The row needs manual review because the section/rate decision could not be confirmed confidently from the available inputs.';
      default:
        return row.debugInfo.finalStatusReason.trim().isNotEmpty
            ? row.debugInfo.finalStatusReason.trim()
            : (row.remarks.trim().isNotEmpty
                  ? row.remarks.trim()
                  : 'This row was classified using the existing reconciliation status and debug signals.');
    }
  }

  static String _buildIdentityImpact(ReconciliationRow row) {
    final flags = row.debugInfo.identityFlags.toSet();

    if (flags.contains('conflicting_pan')) {
      return 'Seller identity showed conflicting PAN evidence, so the row should be reviewed with seller mapping and source PAN support before final sign-off.';
    }
    if (flags.contains('ambiguous_identity')) {
      return 'Seller identity relied on ambiguous PAN or name evidence, which can affect whether this row is grouped to the correct deductee.';
    }
    if (flags.contains('unresolved_identity')) {
      return 'Seller identity could not be fully verified from the available PAN/name evidence, so the row should be cross-checked before conclusion.';
    }
    if (row.identityConfidence < 0.75) {
      return 'Seller identity was matched with lower confidence than the standard bucket, so the row deserves an accountant review.';
    }
    if (row.resolvedPan.trim().isEmpty) {
      return 'Seller PAN is still missing on the resolved identity, so the row should be verified before relying on the match.';
    }
    if (row.remarks.contains('PAN from GSTIN')) {
      return 'Seller PAN was inferred from GSTIN rather than read directly from a PAN field, so the identity should be verified.';
    }

    return '';
  }

  static List<String> _buildSupportingNotes(ReconciliationRow row) {
    final notes = <String>[
      row.debugInfo.applicableAmountReason.trim(),
      row.debugInfo.expectedTdsReason.trim(),
      row.calculationRemark.trim(),
      row.debugInfo.identityNotes.trim(),
      row.debugInfo.finalStatusReason.trim(),
      row.remarks.trim(),
    ].where((value) => value.isNotEmpty).toList();

    final unique = <String>[];
    for (final note in notes) {
      if (!unique.contains(note)) {
        unique.add(note);
      }
    }
    return unique;
  }
}
