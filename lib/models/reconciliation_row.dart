class ReconciliationRow {
  final String buyerName;
  final String buyerPan;
  final String financialYear;
  final String month;

  final String sellerName;
  final String sellerPan;
  final String section;

  final double basicAmount;
  final double applicableAmount;

  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double tdsRateUsed;

  final double amountDifference;
  final double tdsDifference;

  final String status;
  final String remarks;

  final bool purchasePresent;
  final bool tdsPresent;

  final double openingTimingBalance;
  final double monthTdsDifference;
  final double closingTimingBalance;

  ReconciliationRow({
    required this.buyerName,
    required this.buyerPan,
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.section,
    required this.basicAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.tdsRateUsed,
    required this.amountDifference,
    required this.tdsDifference,
    required this.status,
    required this.remarks,
    required this.purchasePresent,
    required this.tdsPresent,
    required this.openingTimingBalance,
    required this.monthTdsDifference,
    required this.closingTimingBalance,
  });

  ReconciliationRow copyWith({
    String? buyerName,
    String? buyerPan,
    String? financialYear,
    String? month,
    String? sellerName,
    String? sellerPan,
    String? section,
    double? basicAmount,
    double? applicableAmount,
    double? tds26QAmount,
    double? expectedTds,
    double? actualTds,
    double? tdsRateUsed,
    double? amountDifference,
    double? tdsDifference,
    String? status,
    String? remarks,
    bool? purchasePresent,
    bool? tdsPresent,
    double? openingTimingBalance,
    double? monthTdsDifference,
    double? closingTimingBalance,
  }) {
    return ReconciliationRow(
      buyerName: buyerName ?? this.buyerName,
      buyerPan: buyerPan ?? this.buyerPan,
      financialYear: financialYear ?? this.financialYear,
      month: month ?? this.month,
      sellerName: sellerName ?? this.sellerName,
      sellerPan: sellerPan ?? this.sellerPan,
      section: section ?? this.section,
      basicAmount: basicAmount ?? this.basicAmount,
      applicableAmount: applicableAmount ?? this.applicableAmount,
      tds26QAmount: tds26QAmount ?? this.tds26QAmount,
      expectedTds: expectedTds ?? this.expectedTds,
      actualTds: actualTds ?? this.actualTds,
      tdsRateUsed: tdsRateUsed ?? this.tdsRateUsed,
      amountDifference: amountDifference ?? this.amountDifference,
      tdsDifference: tdsDifference ?? this.tdsDifference,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      purchasePresent: purchasePresent ?? this.purchasePresent,
      tdsPresent: tdsPresent ?? this.tdsPresent,
      openingTimingBalance: openingTimingBalance ?? this.openingTimingBalance,
      monthTdsDifference: monthTdsDifference ?? this.monthTdsDifference,
      closingTimingBalance: closingTimingBalance ?? this.closingTimingBalance,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'Buyer Name': buyerName,
      'Buyer PAN': buyerPan,
      'Financial Year': financialYear,
      'Month': month,
      'Seller Name': sellerName,
      'Seller PAN': sellerPan,
      'Section': section,
      'Basic Amount': basicAmount,
      'Applicable Amount': applicableAmount,
      '26Q Amount': tds26QAmount,
      'Expected TDS': expectedTds,
      'Actual TDS': actualTds,
      'TDS Difference': tdsDifference,
      'Amount Difference': amountDifference,
      'Opening Timing Balance': openingTimingBalance,
      'Month TDS Difference': monthTdsDifference,
      'Closing Timing Balance': closingTimingBalance,
      'Status': status,
      'Remarks': remarks,
    };
  }
}