import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CalculationService section-aware reconciliation', () {
    test(
      'same seller + same FY/month + different sections stay separate',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'ZZZZZ9999Z',
          sourceRows: [
            _sourceRow(
              section: '194Q',
              amount: 6000000,
            ),
            _sourceRow(
              section: '194C',
              amount: 50000,
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194Q',
              deductedAmount: 1000000,
              tds: 1000,
            ),
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
            ),
          ],
        );

        expect(rows.rows, hasLength(2));

        final bySection = {
          for (final row in rows.rows) row.section: row,
        };

        expect(bySection.keys, containsAll(<String>['194Q', '194C']));
        expect(bySection['194Q']!.tds26QAmount, 1000000);
        expect(bySection['194Q']!.actualTds, 1000);
        expect(bySection['194Q']!.status, ReconciliationStatus.matched);
        expect(bySection['194C']!.tds26QAmount, 50000);
        expect(bySection['194C']!.actualTds, 500);
        expect(bySection['194C']!.status, ReconciliationStatus.matched);
      },
    );

    test(
      'same seller + same FY/month + same section still aggregates',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'YYYYY8888Y',
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 50000,
              documentNo: 'BILL-1',
            ),
            _sourceRow(
              section: '194C',
              amount: 50000,
              documentNo: 'BILL-2',
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
            ),
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
            ),
          ],
        );

        expect(rows.rows, hasLength(1));
        final row = rows.rows.single;
        expect(row.section, '194C');
        expect(row.basicAmount, 100000);
        expect(row.applicableAmount, 100000);
        expect(row.tds26QAmount, 100000);
        expect(row.expectedTds, 1000);
        expect(row.actualTds, 1000);
        expect(row.status, ReconciliationStatus.matched);
      },
    );

    test(
      'final matching flow does not cross-match different sections',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'XXXXX7777X',
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 50000,
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194Q',
              deductedAmount: 1000000,
              tds: 1000,
            ),
          ],
        );

        expect(rows.rows, hasLength(2));

        final bySection = {
          for (final row in rows.rows) row.section: row,
        };

        expect(
          bySection['194C']!.status,
          ReconciliationStatus.applicableButNo26Q,
        );
        expect(bySection['194C']!.purchasePresent, isTrue);
        expect(bySection['194C']!.tdsPresent, isFalse);

        expect(bySection['194Q']!.status, ReconciliationStatus.onlyIn26Q);
        expect(bySection['194Q']!.purchasePresent, isFalse);
        expect(bySection['194Q']!.tdsPresent, isTrue);
      },
    );
  });
}

NormalizedTransactionRow _sourceRow({
  required String section,
  required double amount,
  String documentNo = 'BILL-DEFAULT',
}) {
  return NormalizedTransactionRow(
    sourceType: 'purchase',
    transactionDateRaw: '2024-04-15',
    month: 'Apr-2024',
    financialYear: '2024-25',
    partyName: 'Acme Traders',
    panNumber: 'ABCPD1234F',
    gstNo: '',
    documentNo: documentNo,
    description: 'Test row',
    amount: amount,
    taxableAmount: amount,
    tdsAmount: 0,
    section: section,
    normalizedMonth: 'Apr-2024',
    normalizedSection: section,
  );
}

Tds26QRow _tdsRow({
  required String section,
  required double deductedAmount,
  required double tds,
}) {
  return Tds26QRow(
    month: 'Apr-2024',
    financialYear: '2024-25',
    deducteeName: 'Acme Traders',
    panNumber: 'ABCPD1234F',
    deductedAmount: deductedAmount,
    tds: tds,
    section: section,
    normalizedMonth: 'Apr-2024',
    normalizedSection: section,
  );
}
