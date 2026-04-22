class ReconciliationStatus {
  static const String matched = 'Matched';
  static const String purchaseOnly = 'Purchase Only';
  static const String onlyIn26Q = 'Only in 26Q';
  static const String applicableButNo26Q = 'Applicable but no 26Q';
  static const String belowThreshold = 'Below Threshold';
  static const String reviewRequired = 'Review Required';
  static const String amountMismatch = 'Amount Mismatch';
  static const String shortDeduction = 'Short Deduction';
  static const String excessDeduction = 'Excess Deduction';
  static const String timingDifference = 'Timing Difference';
  static const String noData = 'No Data';
  static const String sectionMissing = 'Section Missing';
  static const String noDeductionRequired = 'No Deduction Required';

  static const List<String> filterOptions = [
    matched,
    timingDifference,
    shortDeduction,
    excessDeduction,
    purchaseOnly,
    onlyIn26Q,
    applicableButNo26Q,
    reviewRequired,
  ];
}
