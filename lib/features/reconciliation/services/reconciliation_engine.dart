import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/parse_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_remark_templates.dart';

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
    required String section,
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
    required bool manualReviewRequired,
  }) {
    if (!hasValidSection) {
      return ReconciliationStatus.sectionMissing;
    }

    if (purchaseMissing && !tdsMissing) {
      return ReconciliationStatus.onlyIn26Q;
    }

    if (!purchaseMissing && tdsMissing) {
      if (manualReviewRequired) {
        return ReconciliationStatus.reviewRequired;
      }

      if (applicableAmount > amountTolerance) {
        return ReconciliationStatus.applicableButNo26Q;
      }

      if (applicableAmount.abs() <= amountTolerance &&
          expectedTds.abs() <= tdsTolerance &&
          actualTds.abs() <= tdsTolerance) {
        return ReconciliationStatus.belowThreshold;
      }

      return ReconciliationStatus.belowThreshold;
    }

    if (purchaseMissing && tdsMissing) {
      return ReconciliationStatus.noData;
    }

    if (manualReviewRequired) {
      return ReconciliationStatus.reviewRequired;
    }

    final amountDiffAbs = amountDifference.abs();
    final tdsDiffAbs = tdsDifference.abs();

    if (applicableAmount.abs() <= amountTolerance &&
        actualTds.abs() <= tdsTolerance) {
      return ReconciliationStatus.noDeductionRequired;
    }

    if (amountDiffAbs > amountTolerance) {
      return ReconciliationStatus.amountMismatch;
    }

    if (tdsDiffAbs <= tdsTolerance) {
      return ReconciliationStatus.matched;
    }

    if (tdsDiffAbs <= minorTdsTolerance) {
      return ReconciliationStatus.matched;
    }

    if (tdsDifference > minorTdsTolerance) {
      return ReconciliationStatus.shortDeduction;
    }

    return ReconciliationStatus.excessDeduction;
  }

  static String buildRemarks({
    required String section,
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
    required bool manualReviewRequired,
    required String manualReviewReason,
  }) {
    final remarks = <String>{};
    final normalizedSection = normalizeSection(section);

    if (!hasValidSection) {
      if (sellerPan.trim().isEmpty) {
        remarks.add(ReconciliationRemarkTemplates.panMissingHighRisk);
      }
      remarks.add(ReconciliationRemarkTemplates.sectionReviewRequired);
      return remarks.join(', ');
    }

    if (manualReviewRequired) {
      if (sellerPan.trim().isEmpty) {
        remarks.add(ReconciliationRemarkTemplates.panMissingHighRisk);
      }
      remarks.add(ReconciliationRemarkTemplates.manualReview(normalizedSection));
      if (manualReviewReason.trim().isNotEmpty) {
        remarks.add(manualReviewReason.trim());
      }
      if (!purchaseMissing && tdsMissing) {
        remarks.add(ReconciliationRemarkTemplates.no26QEntry);
      }
      return remarks.join(', ');
    }

    final isBelowThresholdPurchase = !purchaseMissing &&
        tdsMissing &&
        applicableAmount.abs() <= amountTolerance &&
        expectedTds.abs() <= tdsTolerance &&
        actualTds.abs() <= tdsTolerance;

    if (isBelowThresholdPurchase) {
      remarks.add(ReconciliationRemarkTemplates.thresholdNotCrossed);
      return remarks.join(', ');
    }

    if (sellerPan.trim().isEmpty) {
      remarks.add(ReconciliationRemarkTemplates.panMissingHighRisk);
    }

    if (purchaseMissing && !tdsMissing) {
      remarks.add(ReconciliationRemarkTemplates.onlyIn26Q);
      return remarks.join(', ');
    }

    if (!purchaseMissing && tdsMissing) {
      if (amountDifference > amountTolerance) {
        remarks.add(ReconciliationRemarkTemplates.applicableNo26Q);
      } else {
        remarks.add(ReconciliationRemarkTemplates.noDeductionRequired);
      }
      return remarks.join(', ');
    }

    final amountDiffAbs = amountDifference.abs();
    final tdsDiffAbs = tdsDifference.abs();

    if (amountDiffAbs > amountTolerance) {
      remarks.add(ReconciliationRemarkTemplates.amountMismatch);
    } else if (tdsDiffAbs > tdsTolerance) {
      if (tdsDiffAbs <= minorTdsTolerance) {
        remarks.add(ReconciliationRemarkTemplates.minorRoundingGap);
      } else {
        remarks.add(ReconciliationRemarkTemplates.tdsMismatch);
      }
    }

    return remarks.join(', ');
  }

  static ReconciliationStatusRemarks buildStatusAndRemarks({
    required String section,
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
    required bool manualReviewRequired,
    String manualReviewReason = '',
    bool isLowConfidenceMatch = false,
    bool panDerivedFromGstin = false,
  }) {
    final status = buildBaseStatus(
      section: section,
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
      manualReviewRequired: manualReviewRequired,
    );

    final remarks = buildRemarks(
      section: section,
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
      manualReviewRequired: manualReviewRequired,
      manualReviewReason: manualReviewReason,
    );

    final lowConfidenceRemarks = isLowConfidenceMatch
        ? [
            remarks,
            ReconciliationRemarkTemplates.lowConfidenceMatch,
          ].where((e) => e.trim().isNotEmpty).join(', ')
        : remarks;

    final finalRemarks = panDerivedFromGstin
        ? [
            lowConfidenceRemarks,
            ReconciliationRemarkTemplates.panFromGstin,
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
    bool manualReviewRequired = false,
  }) {
    if (manualReviewRequired) {
      return row;
    }

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
      status: ReconciliationStatus.belowThreshold,
      remarks: ReconciliationRemarkTemplates.thresholdNotCrossed,
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
