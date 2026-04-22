class ReconciliationSummary {
  final String section;
  final int totalRows;
  final int matchedRows;
  final int mismatchRows;
  final int purchaseOnlyRows;
  final int only26QRows;
  final int applicableButNo26QRows;
  final double sourceAmount;
  final double applicableAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double amountDifference;
  final double tdsDifference;

  const ReconciliationSummary({
    required this.section,
    required this.totalRows,
    required this.matchedRows,
    required this.mismatchRows,
    required this.purchaseOnlyRows,
    required this.only26QRows,
    required this.applicableButNo26QRows,
    required this.sourceAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.amountDifference,
    required this.tdsDifference,
  });
}
