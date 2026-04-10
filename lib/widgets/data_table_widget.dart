class CalculationService {
  static const double threshold = 5000000; // 50 lakh

  // Financial Year
  static String getFinancialYear(DateTime date) {
    if (date.month >= 4) {
      return "${date.year}-${date.year + 1}";
    } else {
      return "${date.year - 1}-${date.year}";
    }
  }

  // Applicable Amount Calculation
  static double calculateApplicable({
    required double prevCumulative,
    required double currentPurchase,
  }) {
    if (prevCumulative >= threshold) {
      return currentPurchase;
    } else if (prevCumulative + currentPurchase <= threshold) {
      return 0;
    } else {
      return (prevCumulative + currentPurchase) - threshold;
    }
  }

  // Amount Difference
  static double calculateAmountDiff({
    required double applicable,
    required double deducted,
  }) {
    return double.parse((applicable - deducted).toStringAsFixed(2));
  }

  // Expected TDS
  static double calculateExpectedTds(double deductedAmount) {
    return double.parse((deductedAmount * 0.001).toStringAsFixed(2));
  }

  // Tax Difference
  static double calculateTaxDiff({
    required double expectedTds,
    required double actualTds,
  }) {
    return double.parse((expectedTds - actualTds).toStringAsFixed(2));
  }

  // Status
  static String getStatus({
    required double amountDiff,
    required double taxDiff,
  }) {
    if (amountDiff == 0 && taxDiff == 0) {
      return "Clear";
    } else if (amountDiff != 0 && taxDiff == 0) {
      return "Amount Diff";
    } else if (amountDiff == 0 && taxDiff != 0) {
      return "TDS Diff";
    } else {
      return "Critical";
    }
  }
}