import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_bottom_action_bar.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_table_section.dart';

void main() {
  testWidgets(
    'reconciliation table scrolls horizontally without flex overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 360,
              child: ReconciliationTableSection(
                filteredRows: [_row()],
                isRecalculating: false,
                formatAmount: (value) => value.toStringAsFixed(2),
                statusColor: (_) => Colors.green.shade50,
                statusTextColor: (_) => Colors.green.shade700,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Reconciliation Table'), findsOneWidget);
    },
  );

  testWidgets('reconciliation export actions stack in narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ReconciliationBottomActionBar(
            onExportCurrentView: () {},
            onExportSection: () {},
            onExportPivotReport: () {},
            onExportDetailedReport: () {},
          ),
          body: const SizedBox(width: 280, height: 120),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Exports'), findsOneWidget);
  });
}

ReconciliationRow _row() {
  return ReconciliationRow(
    buyerName: 'Buyer',
    buyerPan: 'ABCDE1234F',
    financialYear: '2024-25',
    month: 'April',
    sellerName: 'Sample Vendor Private Limited',
    sellerPan: 'AAAAA1111A',
    section: '194Q',
    resolvedSellerName: 'Sample Vendor Private Limited',
    resolvedPan: 'AAAAA1111A',
    basicAmount: 125000,
    applicableAmount: 125000,
    tds26QAmount: 125,
    expectedTds: 125,
    actualTds: 125,
    tdsRateUsed: 0.1,
    amountDifference: 0,
    tdsDifference: 0,
    status: ReconciliationStatus.matched,
    remarks: 'Matched by seller, section, financial year and month.',
    purchasePresent: true,
    tdsPresent: true,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
