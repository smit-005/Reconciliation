class ReconciliationDebugInfo {
  final List<String> originalSellerNames;
  final List<String> normalizedSellerNames;
  final List<String> originalPans;
  final String resolvedSellerId;
  final String resolvedIdentitySource;
  final String section;
  final String financialYear;
  final double cumulativePurchaseBeforeRow;
  final double cumulativePurchaseAfterRow;
  final bool thresholdCrossed;
  final String applicableAmountReason;
  final String expectedTdsReason;
  final String finalStatusReason;
  final bool mappingAttempted;
  final String mappingSectionUsed;
  final String mappingHit;
  final List<String> identityFlags;
  final String identityNotes;

  const ReconciliationDebugInfo({
    this.originalSellerNames = const [],
    this.normalizedSellerNames = const [],
    this.originalPans = const [],
    this.resolvedSellerId = '',
    this.resolvedIdentitySource = '',
    this.section = '',
    this.financialYear = '',
    this.cumulativePurchaseBeforeRow = 0.0,
    this.cumulativePurchaseAfterRow = 0.0,
    this.thresholdCrossed = false,
    this.applicableAmountReason = '',
    this.expectedTdsReason = '',
    this.finalStatusReason = '',
    this.mappingAttempted = false,
    this.mappingSectionUsed = '',
    this.mappingHit = 'none',
    this.identityFlags = const [],
    this.identityNotes = '',
  });

  ReconciliationDebugInfo copyWith({
    List<String>? originalSellerNames,
    List<String>? normalizedSellerNames,
    List<String>? originalPans,
    String? resolvedSellerId,
    String? resolvedIdentitySource,
    String? section,
    String? financialYear,
    double? cumulativePurchaseBeforeRow,
    double? cumulativePurchaseAfterRow,
    bool? thresholdCrossed,
    String? applicableAmountReason,
    String? expectedTdsReason,
    String? finalStatusReason,
    bool? mappingAttempted,
    String? mappingSectionUsed,
    String? mappingHit,
    List<String>? identityFlags,
    String? identityNotes,
  }) {
    return ReconciliationDebugInfo(
      originalSellerNames: originalSellerNames ?? this.originalSellerNames,
      normalizedSellerNames:
          normalizedSellerNames ?? this.normalizedSellerNames,
      originalPans: originalPans ?? this.originalPans,
      resolvedSellerId: resolvedSellerId ?? this.resolvedSellerId,
      resolvedIdentitySource:
          resolvedIdentitySource ?? this.resolvedIdentitySource,
      section: section ?? this.section,
      financialYear: financialYear ?? this.financialYear,
      cumulativePurchaseBeforeRow:
          cumulativePurchaseBeforeRow ?? this.cumulativePurchaseBeforeRow,
      cumulativePurchaseAfterRow:
          cumulativePurchaseAfterRow ?? this.cumulativePurchaseAfterRow,
      thresholdCrossed: thresholdCrossed ?? this.thresholdCrossed,
      applicableAmountReason:
          applicableAmountReason ?? this.applicableAmountReason,
      expectedTdsReason: expectedTdsReason ?? this.expectedTdsReason,
      finalStatusReason: finalStatusReason ?? this.finalStatusReason,
      mappingAttempted: mappingAttempted ?? this.mappingAttempted,
      mappingSectionUsed: mappingSectionUsed ?? this.mappingSectionUsed,
      mappingHit: mappingHit ?? this.mappingHit,
      identityFlags: identityFlags ?? this.identityFlags,
      identityNotes: identityNotes ?? this.identityNotes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'Debug Original Seller Names': originalSellerNames.join(' | '),
      'Debug Normalized Seller Names': normalizedSellerNames.join(' | '),
      'Debug Original PANs': originalPans.join(' | '),
      'Debug Resolved Seller Id': resolvedSellerId,
      'Debug Identity Source': resolvedIdentitySource,
      'Debug FY': financialYear,
      'Debug Section': section,
      'Debug Cumulative Before': cumulativePurchaseBeforeRow,
      'Debug Cumulative After': cumulativePurchaseAfterRow,
      'Debug Threshold Crossed': thresholdCrossed ? 'Yes' : 'No',
      'Debug Applicable Reason': applicableAmountReason,
      'Debug Expected TDS Reason': expectedTdsReason,
      'Debug Final Status Reason': finalStatusReason,
      'Debug Mapping Attempted': mappingAttempted ? 'Yes' : 'No',
      'Debug Mapping Section Used': mappingSectionUsed,
      'Debug Mapping Hit': mappingHit,
      'Debug Identity Flags': identityFlags.join(', '),
      'Debug Identity Notes': identityNotes,
    };
  }
}
