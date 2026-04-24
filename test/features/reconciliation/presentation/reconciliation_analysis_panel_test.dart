import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_analysis_panel.dart';

void main() {
  testWidgets(
    'seller exceptions render above seller outcomes as compact chips',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 720,
              child: ReconciliationAnalysisPanel(
                activeSectionTab: 'All',
                sourceFileCount: 2,
                sourceRowCount: 180,
                totalSellers: 24,
                totalSections: 3,
                manualMappingsCount: 6,
                matchedSellersCount: 12,
                mismatchSellersCount: 5,
                only26QSellersCount: 2,
                belowThresholdOnlySellersCount: 1,
                mismatchReasonCounts: const {
                  'No 26Q entry': 4,
                  'Amount mismatch': 3,
                  'TDS mismatch': 2,
                  'Timing difference': 1,
                  'PAN/name mismatch': 1,
                },
                unsupportedSections: const ['194C'],
                skippedSellerCount: 3,
                skippedRowsCount: 8,
                applicableButNo26QSellerCount: 2,
                applicableButNo26QRowCount: 5,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Seller Exceptions'), findsOneWidget);
      expect(find.text('Seller Outcomes'), findsOneWidget);
      expect(find.text('Click controls to filter sellers'), findsOneWidget);
      expect(find.text('Unsupported sections'), findsOneWidget);
      expect(find.text('Skipped rows'), findsOneWidget);
      expect(find.text('Missing 26Q deductions'), findsOneWidget);

      final exceptionsTop = tester
          .getTopLeft(find.text('Seller Exceptions'))
          .dy;
      final outcomesTop = tester.getTopLeft(find.text('Seller Outcomes')).dy;

      expect(exceptionsTop, lessThan(outcomesTop));
      expect(find.text('Sellers affected by skipped rows'), findsNothing);
      expect(find.text('Sellers missing 26Q deductions'), findsNothing);
    },
  );
}
