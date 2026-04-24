import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';

const Set<String> _summaryActionableStatuses = <String>{
  ReconciliationStatus.amountMismatch,
  ReconciliationStatus.applicableButNo26Q,
  ReconciliationStatus.reviewRequired,
  ReconciliationStatus.sectionMissing,
  ReconciliationStatus.shortDeduction,
  ReconciliationStatus.excessDeduction,
  ReconciliationStatus.timingDifference,
  ReconciliationStatus.purchaseOnly,
  ReconciliationStatus.onlyIn26Q,
};

bool isReconciliationRowSummaryEligible(ReconciliationRow row) {
  final status = row.status.trim();
  if (status == ReconciliationStatus.belowThreshold) {
    return false;
  }

  if (row.applicableAmount > 0 ||
      row.expectedTds > 0 ||
      row.actualTds > 0 ||
      row.tds26QAmount > 0) {
    return true;
  }

  return _summaryActionableStatuses.contains(status);
}

bool isReconciliationSellerVisibleInViewMode(
  Iterable<ReconciliationRow> sellerRows,
  ReconciliationViewMode viewMode,
) {
  if (viewMode == ReconciliationViewMode.audit) {
    return true;
  }

  return sellerRows.any(isReconciliationRowSummaryEligible);
}

bool isSellerMappingRowVisibleInViewMode({
  required ReconciliationViewMode viewMode,
  required String status,
  bool hasAmbiguousCandidate = false,
  bool blockedByPanConflict = false,
}) {
  if (viewMode == ReconciliationViewMode.audit) {
    return true;
  }

  return status == 'Unmapped' ||
      status == 'PAN Conflict' ||
      status == 'Mapped (PAN missing)' ||
      hasAmbiguousCandidate ||
      blockedByPanConflict;
}
