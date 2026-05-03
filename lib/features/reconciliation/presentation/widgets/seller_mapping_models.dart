import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:flutter/foundation.dart';

class SellerMappingRowVm {
  final String purchasePartyDisplayName;
  final String normalizedAlias;
  final String sectionCode;
  final int rowIndex;
  final String tdsDisplayName;
  final String tdsPan;
  final String purchasePan;
  final String purchaseGstNo;
  final int sourceRowCount;
  final int tdsRowCount;
  final SellerMapping? exactMapping;
  final SellerMapping? fallbackMapping;
  final SellerMappingResolvedSuggestion? resolvedSuggestion;
  final bool isReadOnly;
  final bool isAboveThreshold;
  final bool hasReconciliationMismatch;
  final bool hasNameOrPanConflict;
  final bool hasApplicableTdsImpact;
  final bool is26QUnmatched;
  final bool hasMissingOrUncertainPan;
  final String preflightReasonCode;
  final String preflightReasonLabel;
  final String preflightReasonDetail;
  final bool requiresDangerousReview;
  final bool isPurchaseOnly;

  const SellerMappingRowVm({
    required this.purchasePartyDisplayName,
    required this.normalizedAlias,
    required this.sectionCode,
    this.rowIndex = 0,
    this.tdsDisplayName = '',
    this.tdsPan = '',
    required this.purchasePan,
    required this.purchaseGstNo,
    this.sourceRowCount = 0,
    this.tdsRowCount = 0,
    this.exactMapping,
    this.fallbackMapping,
    this.resolvedSuggestion,
    this.isReadOnly = false,
    this.isAboveThreshold = false,
    this.hasReconciliationMismatch = false,
    this.hasNameOrPanConflict = false,
    this.hasApplicableTdsImpact = false,
    this.is26QUnmatched = false,
    this.hasMissingOrUncertainPan = false,
    this.preflightReasonCode = '',
    this.preflightReasonLabel = '',
    this.preflightReasonDetail = '',
    this.requiresDangerousReview = false,
    this.isPurchaseOnly = false,
  });

  String get rowKey =>
      '${sellerMappingSafeText(normalizedAlias)}|'
      '${sellerMappingSafeText(sectionCode)}|$rowIndex';
}

String sellerMappingSafeText(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

String resolveTdsSellerTitle(SellerMappingRowVm row) {
  final tdsDisplayName = sellerMappingSafeText(row.tdsDisplayName);
  if (tdsDisplayName.isNotEmpty) return tdsDisplayName;

  final tdsPan = sellerMappingSafeText(row.tdsPan).toUpperCase();
  if (tdsPan.isNotEmpty) return tdsPan;

  final normalizedAlias = sellerMappingSafeText(row.normalizedAlias);
  if (normalizedAlias.isNotEmpty) return normalizedAlias;

  debugPrint(
    'SELLER UI WARN => missing 26Q identity '
    'rowKey=${sellerMappingSafeText(row.rowKey)} '
    'section=${sellerMappingSafeText(row.sectionCode)}',
  );
  return 'Unknown 26Q Seller';
}

String resolveLedgerSellerTitle(SellerMappingRowVm row) {
  final purchasePartyDisplayName = sellerMappingSafeText(
    row.purchasePartyDisplayName,
  );
  if (purchasePartyDisplayName.isNotEmpty) return purchasePartyDisplayName;

  final purchasePan = sellerMappingSafeText(row.purchasePan).toUpperCase();
  if (purchasePan.isNotEmpty) return purchasePan;

  final purchaseGstNo = sellerMappingSafeText(row.purchaseGstNo).toUpperCase();
  if (purchaseGstNo.isNotEmpty) return purchaseGstNo;

  final normalizedAlias = sellerMappingSafeText(row.normalizedAlias);
  if (normalizedAlias.isNotEmpty) return normalizedAlias;

  debugPrint(
    'SELLER UI WARN => missing ledger identity '
    'rowKey=${sellerMappingSafeText(row.rowKey)} '
    'section=${sellerMappingSafeText(row.sectionCode)}',
  );
  return 'Unknown Ledger Seller';
}

enum SellerMappingListView { needsAction, allSellers }

extension SellerMappingListViewX on SellerMappingListView {
  String get label {
    switch (this) {
      case SellerMappingListView.needsAction:
        return 'Needs Action';
      case SellerMappingListView.allSellers:
        return 'All Sellers';
    }
  }
}

class AutoMapDecision {
  final String autoMapReason;
  final double autoMapConfidence;
  final String? selectedCandidate;
  final bool blockedByPanConflict;
  final bool ambiguous;

  const AutoMapDecision({
    required this.autoMapReason,
    required this.autoMapConfidence,
    this.selectedCandidate,
    this.blockedByPanConflict = false,
    this.ambiguous = false,
  });
}

class TdsPartyCandidate {
  final String partyName;
  final String normalizedName;
  final List<String> tokens;
  final Set<String> pans;

  const TdsPartyCandidate({
    required this.partyName,
    required this.normalizedName,
    required this.tokens,
    required this.pans,
  });
}

class CandidateScore {
  final TdsPartyCandidate candidate;
  final double score;

  const CandidateScore({required this.candidate, required this.score});
}
