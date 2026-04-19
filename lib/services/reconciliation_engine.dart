import '../core/utils/normalize_utils.dart';
import '../core/utils/parse_utils.dart';
import '../models/reconciliation_row.dart';

class ReconciliationComputedAmounts {
  final double applicableAmount;
  final double expectedTds;
  final double deductedAmount;
  final double actualTds;
  final double amountDifference;
  final double tdsDifference;
  final double monthTdsDifference;

  const ReconciliationComputedAmounts({
    required this.applicableAmount,
    required this.expectedTds,
    required this.deductedAmount,
    required this.actualTds,
    required this.amountDifference,
    required this.tdsDifference,
    required this.monthTdsDifference,
  });
}

class ReconciliationStatusRemarks {
  final String status;
  final String remarks;

  const ReconciliationStatusRemarks({
    required this.status,
    required this.remarks,
  });
}

class ReconciliationEngine {
  static ReconciliationComputedAmounts buildComputedAmounts({
    required double rawApplicableAmount,
    required double rawExpectedTds,
    required double rawDeductedAmount,
    required double rawActualTds,
  }) {
    final applicableAmount = round2(rawApplicableAmount);
    final expectedTds = round2(rawExpectedTds);
    final deductedAmount = round2(rawDeductedAmount);
    final actualTds = round2(rawActualTds);
    final amountDifference = round2(
      computeAmountDifference(
        applicableAmount: applicableAmount,
        deductedAmount: deductedAmount,
      ),
    );
    final tdsDifference = round2(
      computeTdsDifference(
        expectedTds: expectedTds,
        actualTds: actualTds,
      ),
    );

    return ReconciliationComputedAmounts(
      applicableAmount: applicableAmount,
      expectedTds: expectedTds,
      deductedAmount: deductedAmount,
      actualTds: actualTds,
      amountDifference: amountDifference,
      tdsDifference: tdsDifference,
      monthTdsDifference: round2(actualTds - expectedTds),
    );
  }

  static double computeAmountDifference({
    required double applicableAmount,
    required double deductedAmount,
  }) {
    return applicableAmount - deductedAmount;
  }

  static double computeTdsDifference({
    required double expectedTds,
    required double actualTds,
  }) {
    return expectedTds - actualTds;
  }

  static String buildBaseStatus({
    required bool purchaseMissing,
    required bool tdsMissing,
    required double basicAmount,
    required double amountDifference,
    required double tdsDifference,
    required bool hasValidSection,
    required double applicableAmount,
    required double expectedTds,
    required double actualTds,
    required double amountTolerance,
    required double tdsTolerance,
    required double minorTdsTolerance,
  }) {
    if (purchaseMissing && !tdsMissing) {
      return 'Only in 26Q';
    }

    if (!purchaseMissing && tdsMissing) {
      if (applicableAmount > amountTolerance) {
        return 'Applicable but no 26Q';
      }

      if (applicableAmount.abs() <= amountTolerance &&
          expectedTds.abs() <= tdsTolerance &&
          actualTds.abs() <= tdsTolerance) {
        return 'Below Threshold';
      }

      return 'Below Threshold';
    }

    if (purchaseMissing && tdsMissing) {
      return 'No Data';
    }

    if (!hasValidSection) {
      return 'Section Missing';
    }

    final amountDiffAbs = amountDifference.abs();
    final tdsDiffAbs = tdsDifference.abs();

    if (applicableAmount.abs() <= amountTolerance &&
        actualTds.abs() <= tdsTolerance) {
      return 'No Deduction Required';
    }

    if (amountDiffAbs > amountTolerance) {
      return 'Amount Mismatch';
    }

    if (tdsDiffAbs <= tdsTolerance) {
      return 'Matched';
    }

    if (tdsDiffAbs <= minorTdsTolerance) {
      return 'Matched';
    }

    if (tdsDifference > minorTdsTolerance) {
      return 'Short Deduction';
    }

    return 'Excess Deduction';
  }

  static String buildRemarks({
    required String sellerPan,
    required bool purchaseMissing,
    required bool tdsMissing,
    required double basicAmount,
    required double applicableAmount,
    required double amountDifference,
    required double expectedTds,
    required double actualTds,
    required double tdsDifference,
    required bool hasValidSection,
    required double amountTolerance,
    required double tdsTolerance,
    required double minorTdsTolerance,
  }) {
    final remarks = <String>{};

    final isBelowThresholdPurchase = !purchaseMissing &&
        tdsMissing &&
        applicableAmount.abs() <= amountTolerance &&
        expectedTds.abs() <= tdsTolerance &&
        actualTds.abs() <= tdsTolerance;

    if (isBelowThresholdPurchase) {
      remarks.add('TDS not applicable yet under 194Q threshold');
      return remarks.join(', ');
    }

    if (sellerPan.trim().isEmpty) {
      remarks.add('PAN missing -> high TDS risk');
    }

    if (purchaseMissing && !tdsMissing) {
      remarks.add('Only in 26Q');
      return remarks.join(', ');
    }

    if (!purchaseMissing && tdsMissing) {
      if (amountDifference > amountTolerance) {
        remarks.add('No 26Q entry');
      } else {
        remarks.add('TDS not required');
      }
      return remarks.join(', ');
    }

    if (!hasValidSection) {
      remarks.add('Section missing');
    }

    final amountDiffAbs = amountDifference.abs();
    final tdsDiffAbs = tdsDifference.abs();

    if (amountDiffAbs > amountTolerance) {
      remarks.add('Purchase vs 26Q amount mismatch');
    } else if (tdsDiffAbs > tdsTolerance) {
      if (tdsDiffAbs <= minorTdsTolerance) {
        remarks.add('Minor rounding difference');
      } else {
        remarks.add('Rate mismatch');
      }
    }

    return remarks.join(', ');
  }

  static ReconciliationStatusRemarks buildStatusAndRemarks({
    required String sellerPan,
    required bool purchaseMissing,
    required bool tdsMissing,
    required double basicAmount,
    required double applicableAmount,
    required double amountDifference,
    required double expectedTds,
    required double actualTds,
    required double tdsDifference,
    required bool hasValidSection,
    required double amountTolerance,
    required double tdsTolerance,
    required double minorTdsTolerance,
    bool isLowConfidenceMatch = false,
    bool panDerivedFromGstin = false,
  }) {
    final status = buildBaseStatus(
      purchaseMissing: purchaseMissing,
      tdsMissing: tdsMissing,
      basicAmount: basicAmount,
      amountDifference: amountDifference,
      tdsDifference: tdsDifference,
      hasValidSection: hasValidSection,
      applicableAmount: applicableAmount,
      expectedTds: expectedTds,
      actualTds: actualTds,
      amountTolerance: amountTolerance,
      tdsTolerance: tdsTolerance,
      minorTdsTolerance: minorTdsTolerance,
    );

    final remarks = buildRemarks(
      sellerPan: sellerPan,
      purchaseMissing: purchaseMissing,
      tdsMissing: tdsMissing,
      basicAmount: basicAmount,
      applicableAmount: applicableAmount,
      amountDifference: amountDifference,
      expectedTds: expectedTds,
      actualTds: actualTds,
      tdsDifference: tdsDifference,
      hasValidSection: hasValidSection,
      amountTolerance: amountTolerance,
      tdsTolerance: tdsTolerance,
      minorTdsTolerance: minorTdsTolerance,
    );

    final lowConfidenceRemarks = isLowConfidenceMatch
        ? [
            remarks,
            'Low confidence match: matched using normalized name only',
          ].where((e) => e.trim().isNotEmpty).join(', ')
        : remarks;

    final finalRemarks = panDerivedFromGstin
        ? [
            lowConfidenceRemarks,
            'PAN derived from GSTIN; verify if seller PAN is correct',
          ].where((e) => e.trim().isNotEmpty).join(', ')
        : lowConfidenceRemarks;

    return ReconciliationStatusRemarks(
      status: status,
      remarks: finalRemarks,
    );
  }

  static String chooseSellerName({
    required String purchaseName,
    required String tdsName,
  }) {
    if (tdsName.trim().isNotEmpty) return tdsName.trim();
    if (purchaseName.trim().isNotEmpty) return purchaseName.trim();
    return '';
  }

  static String chooseSellerPan({
    required String purchasePan,
    required String tdsPan,
    required String fallbackKey,
  }) {
    if (tdsPan.trim().isNotEmpty) return tdsPan.trim();
    if (purchasePan.trim().isNotEmpty) return purchasePan.trim();
    if (looksLikePan(fallbackKey)) return fallbackKey.trim();
    return '';
  }

  static ReconciliationRow applyBelowThresholdClassification(
    ReconciliationRow row, {
    required double amountTolerance,
    required double tdsTolerance,
  }) {
    final isBelowThreshold = row.applicableAmount.abs() <= amountTolerance &&
        row.expectedTds.abs() <= tdsTolerance &&
        row.actualTds.abs() <= tdsTolerance &&
        row.tds26QAmount.abs() <= amountTolerance &&
        row.purchasePresent &&
        !row.tdsPresent;

    if (!isBelowThreshold) {
      return row;
    }

    return row.copyWith(
      status: 'Below Threshold',
      remarks: 'TDS not applicable yet under 194Q threshold',
    );
  }

  static ReconciliationRow buildRow({
    required String buyerName,
    required String buyerPan,
    required String financialYear,
    required String month,
    required String sellerName,
    required String sellerPan,
    required String section,
    required double basicAmount,
    required ReconciliationComputedAmounts computedAmounts,
    required double tdsRateUsed,
    required String status,
    required String remarks,
    String calculationRemark = '',
    required bool purchasePresent,
    required bool tdsPresent,
  }) {
    return ReconciliationRow(
      buyerName: buyerName,
      buyerPan: buyerPan,
      financialYear: financialYear,
      month: month,
      sellerName: sellerName,
      sellerPan: sellerPan,
      section: section,
      basicAmount: basicAmount,
      applicableAmount: computedAmounts.applicableAmount,
      tds26QAmount: computedAmounts.deductedAmount,
      expectedTds: computedAmounts.expectedTds,
      actualTds: computedAmounts.actualTds,
      tdsRateUsed: tdsRateUsed,
      amountDifference: computedAmounts.amountDifference,
      tdsDifference: computedAmounts.tdsDifference,
      status: status,
      remarks: remarks,
      calculationRemark: calculationRemark,
      purchasePresent: purchasePresent,
      tdsPresent: tdsPresent,
      openingTimingBalance: 0.0,
      monthTdsDifference: computedAmounts.monthTdsDifference,
      closingTimingBalance: 0.0,
    );
  }
}
