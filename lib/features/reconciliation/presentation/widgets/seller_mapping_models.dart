import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';

class SellerMappingRowVm {
  final String purchasePartyDisplayName;
  final String normalizedAlias;
  final String sectionCode;
  final String purchasePan;
  final String purchaseGstNo;
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
    required this.purchasePan,
    required this.purchaseGstNo,
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

  String get rowKey => '$normalizedAlias|$sectionCode';
}

enum SellerMappingListView {
  needsAction,
  aboveThreshold,
  unmatched26Q,
  allSellers,
}

extension SellerMappingListViewX on SellerMappingListView {
  String get label {
    switch (this) {
      case SellerMappingListView.needsAction:
        return 'Needs Action';
      case SellerMappingListView.aboveThreshold:
        return 'Above Threshold';
      case SellerMappingListView.unmatched26Q:
        return '26Q Unmatched';
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
