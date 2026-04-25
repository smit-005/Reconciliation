import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_debug_info.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/reconciliation_row_explanation_builder.dart';

void main() {
  group('ReconciliationRowExplanationBuilder', () {
    test('reuses threshold signals for below-threshold rows', () {
      final explanation = ReconciliationRowExplanationBuilder.build(
        row: _row(
          status: ReconciliationStatus.belowThreshold,
          remarks: 'Threshold not crossed',
          debugInfo: const ReconciliationDebugInfo(
            applicableAmountReason:
                '194Q threshold not crossed yet; cumulative remained at 4800000.',
            finalStatusReason:
                'Purchase bucket stayed below the applicable threshold and no 26Q bucket exists.',
            cumulativePurchaseBeforeRow: 4200000,
            cumulativePurchaseAfterRow: 4800000,
          ),
        ),
        formatAmount: _fmt,
      );

      expect(explanation.reasonCategory, 'Threshold not crossed');
      expect(
        explanation.explanation,
        contains('below the applicable section threshold'),
      );
      expect(
        explanation.comparedValues.any(
          (item) => item.label == 'Cumulative after',
        ),
        isTrue,
      );
      expect(explanation.supportingNotes, contains('Threshold not crossed'));
    });

    test('surfaces amount mismatch with compared values and difference', () {
      final explanation = ReconciliationRowExplanationBuilder.build(
        row: _row(
          status: ReconciliationStatus.amountMismatch,
          applicableAmount: 120000,
          tds26QAmount: 100000,
          amountDifference: 20000,
          remarks: 'Amount mismatch',
          debugInfo: const ReconciliationDebugInfo(
            finalStatusReason:
                'Applicable purchase amount and deducted 26Q amount differ by 20000.0.',
          ),
        ),
        formatAmount: _fmt,
      );

      expect(explanation.reasonCategory, 'Amount mismatch');
      expect(
        explanation.comparedValues.map((item) => item.label),
        containsAll(<String>['Applicable amount', '26Q amount']),
      );
      expect(
        explanation.computedDifferenceLabel,
        'Applicable minus 26Q amount',
      );
      expect(explanation.computedDifferenceValue, '20,000.00');
    });

    test(
      'surfaces TDS mismatch and identity ambiguity impact when present',
      () {
        final explanation = ReconciliationRowExplanationBuilder.build(
          row: _row(
            status: ReconciliationStatus.shortDeduction,
            expectedTds: 1000,
            actualTds: 700,
            tdsDifference: 300,
            identityConfidence: 0.62,
            debugInfo: const ReconciliationDebugInfo(
              identityFlags: <String>['ambiguous_identity'],
              identityNotes: 'Multiple PANs for name',
            ),
          ),
          formatAmount: _fmt,
        );

        expect(explanation.reasonCategory, 'TDS mismatch');
        expect(explanation.computedDifferenceValue, '300.00');
        expect(explanation.identityImpact, contains('ambiguous'));
      },
    );

    test(
      'uses pragmatic section-missing explanation instead of synthetic section mismatch',
      () {
        final explanation = ReconciliationRowExplanationBuilder.build(
          row: _row(
            status: ReconciliationStatus.sectionMissing,
            section: '',
            debugInfo: const ReconciliationDebugInfo(
              finalStatusReason:
                  'Section was unavailable, blank, or unsupported for this bucket.',
            ),
          ),
          formatAmount: _fmt,
        );

        expect(explanation.reasonCategory, 'Section missing');
        expect(explanation.explanation, contains('missing or unsupported'));
        expect(explanation.comparedValues.first.value, 'Missing');
      },
    );
  });
}

ReconciliationRow _row({
  String status = ReconciliationStatus.matched,
  String remarks = '',
  String section = '194Q',
  double applicableAmount = 0,
  double tds26QAmount = 0,
  double expectedTds = 0,
  double actualTds = 0,
  double amountDifference = 0,
  double tdsDifference = 0,
  double identityConfidence = 1.0,
  ReconciliationDebugInfo debugInfo = const ReconciliationDebugInfo(),
}) {
  return ReconciliationRow(
    buyerName: 'Buyer',
    buyerPan: 'ABCDE1234F',
    financialYear: '2024-25',
    month: 'Apr-2024',
    sellerName: 'Vendor One',
    sellerPan: '',
    section: section,
    resolvedSellerId: 'NAME:VENDORONE',
    resolvedSellerName: 'Vendor One',
    resolvedPan: '',
    identitySource: 'normalized_name',
    identityConfidence: identityConfidence,
    identityNotes: debugInfo.identityNotes,
    basicAmount: 600000,
    applicableAmount: applicableAmount,
    tds26QAmount: tds26QAmount,
    expectedTds: expectedTds,
    actualTds: actualTds,
    tdsRateUsed: 0.001,
    amountDifference: amountDifference,
    tdsDifference: tdsDifference,
    status: status,
    remarks: remarks,
    calculationRemark: '',
    purchasePresent: true,
    tdsPresent: tds26QAmount > 0 || actualTds > 0,
    openingTimingBalance: 0,
    monthTdsDifference: tdsDifference,
    closingTimingBalance: 0,
    debugInfo: debugInfo,
  );
}

String _fmt(double value) {
  return value
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
}
