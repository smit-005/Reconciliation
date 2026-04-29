import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/data/local/import_staging_repository.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUpAll(() async {
    await DBHelper.debugResetForTest(
      databaseName: 'tds_reconciliation_staging_parity_test.db',
    );
  });

  tearDownAll(() async {
    await DBHelper.debugResetForTest();
  });

  setUp(() async {
    final db = await DBHelper.database;
    await db.delete('staged_purchase_rows');
    await db.delete('staged_26q_rows');
  });

  test(
    'staged reload matches in-memory reconciliation and purchase rows still fall back to 194Q',
    () async {
      final repository = ImportStagingRepository();
      const purchaseImportId = 'parity_purchase';
      const tdsImportId = 'parity_tds';
      final purchaseRows = <PurchaseRow>[
        PurchaseRow.fromMap({
          'date': '2024-04-15',
          'bill_no': 'BILL-1',
          'party_name': 'Acme Traders',
          'gst_no': '',
          'pan_number': 'ABCPD1234F',
          'productname': 'Primary line',
          'basic_amount': 6000000,
          'bill_amount': 6000000,
        }),
        PurchaseRow.fromMap({
          'date': '2024-05-20',
          'bill_no': 'BILL-2',
          'party_name': 'Beta Services',
          'gst_no': '',
          'pan_number': '',
          'productname': '',
          'basic_amount': 50000,
          'bill_amount': 50000,
        }),
      ];
      final tdsRows = <Tds26QRow>[
        Tds26QRow.fromMap({
          'date_month': 'Apr-2024',
          'financial_year': '2024-25',
          'party_name': 'Acme Traders',
          'pan_number': 'ABCPD1234F',
          'amount_paid': 1000000,
          'tds_amount': 1000,
          'section': '194Q',
        }),
        Tds26QRow.fromMap({
          'date_month': 'May-2024',
          'financial_year': '2024-25',
          'party_name': 'Beta Services',
          'pan_number': '',
          'amount_paid': 50000,
          'tds_amount': 500,
          'section': '194C',
        }),
      ];

      final inMemoryResult = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'ZZZZZ9999Z',
        sourceRows: purchaseRows
            .map(NormalizedTransactionRow.fromPurchaseRow)
            .toList(),
        tdsRows: tdsRows,
      );

      await repository.stagePurchaseRows(
        importId: purchaseImportId,
        rows: purchaseRows,
        sourceFileName: 'purchase.xlsx',
        buyerId: 'buyer-1',
        buyerPan: 'ZZZZZ9999Z',
        sectionCode: '194Q',
        sheetName: 'Purchase',
        headerRowIndex: 0,
        headersTrusted: true,
      );
      await repository.stage26QRows(
        importId: tdsImportId,
        rows: tdsRows,
        sourceFileName: '26q.xlsx',
        buyerId: 'buyer-1',
        sheetName: '26Q',
        headerRowIndex: 0,
        headersTrusted: true,
      );

      final loadedPurchaseRows = await repository.loadPurchaseRows(
        purchaseImportId,
      );
      final loadedTdsRows = await repository.load26QRows(tdsImportId);

      expect(
        loadedPurchaseRows
            .map(NormalizedTransactionRow.fromPurchaseRow)
            .every((row) => row.normalizedSection == '194Q'),
        isTrue,
      );

      final stagedResult = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'ZZZZZ9999Z',
        sourceRows: loadedPurchaseRows
            .map(NormalizedTransactionRow.fromPurchaseRow)
            .toList(),
        tdsRows: loadedTdsRows,
      );

      expect(stagedResult.rows.length, inMemoryResult.rows.length);
      expect(
        stagedResult.combinedSummary.totalRows,
        inMemoryResult.combinedSummary.totalRows,
      );
      expect(
        stagedResult.combinedSummary.matchedRows,
        inMemoryResult.combinedSummary.matchedRows,
      );
      expect(
        stagedResult.combinedSummary.mismatchRows,
        inMemoryResult.combinedSummary.mismatchRows,
      );
      expect(
        stagedResult.combinedSummary.sourceAmount,
        inMemoryResult.combinedSummary.sourceAmount,
      );
      expect(
        stagedResult.combinedSummary.expectedTds,
        inMemoryResult.combinedSummary.expectedTds,
      );
      expect(
        stagedResult.combinedSummary.actualTds,
        inMemoryResult.combinedSummary.actualTds,
      );

      final stagedRowsByKey = {
        for (final row in stagedResult.rows)
          '${row.sellerName}|${row.month}|${row.section}': row,
      };
      final inMemoryRowsByKey = {
        for (final row in inMemoryResult.rows)
          '${row.sellerName}|${row.month}|${row.section}': row,
      };

      expect(stagedRowsByKey.keys, inMemoryRowsByKey.keys);
      for (final key in inMemoryRowsByKey.keys) {
        final stagedRow = stagedRowsByKey[key]!;
        final inMemoryRow = inMemoryRowsByKey[key]!;
        expect(stagedRow.status, inMemoryRow.status);
        expect(stagedRow.basicAmount, inMemoryRow.basicAmount);
        expect(stagedRow.applicableAmount, inMemoryRow.applicableAmount);
        expect(stagedRow.tds26QAmount, inMemoryRow.tds26QAmount);
        expect(stagedRow.expectedTds, inMemoryRow.expectedTds);
        expect(stagedRow.actualTds, inMemoryRow.actualTds);
        expect(stagedRow.amountDifference, inMemoryRow.amountDifference);
        expect(stagedRow.tdsDifference, inMemoryRow.tdsDifference);
      }
    },
  );
}
