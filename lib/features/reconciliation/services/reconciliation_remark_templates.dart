import 'package:reconciliation_app/core/utils/normalize_utils.dart';

class ReconciliationRemarkTemplates {
  static const String panMissingHighRisk = 'PAN missing, high-risk';
  static const String sectionReviewRequired = 'Section review required';
  static const String thresholdNotCrossed = 'Threshold not crossed';
  static const String onlyIn26Q = 'Only in 26Q';
  static const String applicableNo26Q = 'Applicable, no 26Q';
  static const String noDeductionRequired = 'No deduction required';
  static const String amountMismatch = 'Amount mismatch';
  static const String tdsMismatch = 'TDS mismatch';
  static const String minorRoundingGap = 'Minor rounding gap';
  static const String lowConfidenceMatch = 'Low-confidence match';
  static const String panFromGstin = 'PAN from GSTIN';
  static const String exactMappingUsed = 'Exact mapping used';
  static const String fallbackMappingUsed = 'Fallback mapping used';
  static const String mappedPanConflict = 'Mapped PAN conflict';
  static const String panMatched = 'PAN matched';
  static const String panNameMismatch = 'PAN/name mismatch';
  static const String aliasPanUsed = 'Alias PAN used';
  static const String weakSellerMatch = 'Weak seller match';
  static const String inferredSellerMatch = 'Inferred seller match';
  static const String multiplePansForName = 'Multiple PANs for name';
  static const String nameOnlyMatch = 'Name-only match';
  static const String sellerIdentityIncomplete = 'Seller identity incomplete';
  static const String no26QEntry = 'No 26Q entry';

  static String manualReview(String section) {
    switch (normalizeSection(section)) {
      case '194C':
        return '194C rate review';
      case '194I':
      case '194I_A':
      case '194I_B':
        return '194I rate review';
      case '194J':
      case '194J_A':
      case '194J_B':
        return '194J rate review';
      default:
        return 'Manual review required';
    }
  }

  static String join(Iterable<String> values) {
    final unique = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        unique.add(trimmed);
      }
    }
    return unique.join(', ');
  }
}
