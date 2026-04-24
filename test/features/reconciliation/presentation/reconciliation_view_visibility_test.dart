import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_debug_info.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/reconciliation_view_visibility.dart';

void main() {
  group('reconciliation summary visibility', () {
    test('below-threshold rows are not summary-eligible', () {
      final row = _buildRow(
        status: ReconciliationStatus.belowThreshold,
        applicableAmount: 0,
      );

      expect(isReconciliationRowSummaryEligible(row), isFalse);
    });

    test('applicable matched rows are summary-eligible', () {
      final row = _buildRow(
        status: ReconciliationStatus.matched,
        applicableAmount: 125000,
        expectedTds: 125,
        actualTds: 125,
      );

      expect(isReconciliationRowSummaryEligible(row), isTrue);
    });

    test('seller stays visible in summary if any row is actionable', () {
      final sellerRows = [
        _buildRow(
          status: ReconciliationStatus.belowThreshold,
          applicableAmount: 0,
        ),
        _buildRow(
          status: ReconciliationStatus.shortDeduction,
          applicableAmount: 1000,
          expectedTds: 1,
        ),
      ];

      expect(
        isReconciliationSellerVisibleInViewMode(
          sellerRows,
          ReconciliationViewMode.summary,
        ),
        isTrue,
      );
    });
  });

  group('isSellerMappingRowVisibleInViewMode', () {
    test('shows only actionable rows in summary view', () {
      expect(
        isSellerMappingRowVisibleInViewMode(
          viewMode: ReconciliationViewMode.summary,
          status: 'Mapped',
        ),
        isFalse,
      );
      expect(
        isSellerMappingRowVisibleInViewMode(
          viewMode: ReconciliationViewMode.summary,
          status: 'Unmapped',
        ),
        isTrue,
      );
      expect(
        isSellerMappingRowVisibleInViewMode(
          viewMode: ReconciliationViewMode.summary,
          status: 'Mapped',
          hasAmbiguousCandidate: true,
        ),
        isTrue,
      );
    });
  });
}

ReconciliationRow _buildRow({
  required String status,
  required double applicableAmount,
  double expectedTds = 0,
  double actualTds = 0,
}) {
  return ReconciliationRow(
    buyerName: 'Buyer',
    buyerPan: 'ABCDE1234F',
    financialYear: '2024-25',
    month: 'Apr-2024',
    sellerName: 'Seller',
    sellerPan: 'AAAAA1111A',
    section: '194Q',
    resolvedSellerId: 'seller-1',
    resolvedSellerName: 'Seller',
    resolvedPan: 'AAAAA1111A',
    basicAmount: 1000,
    applicableAmount: applicableAmount,
    tds26QAmount: actualTds,
    expectedTds: expectedTds,
    actualTds: actualTds,
    tdsRateUsed: 0.1,
    amountDifference: 0,
    tdsDifference: 0,
    status: status,
    remarks: '',
    purchasePresent: true,
    tdsPresent: actualTds > 0,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
    debugInfo: const ReconciliationDebugInfo(),
  );
}
