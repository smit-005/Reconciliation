import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/data/local/import_staging_repository.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUpAll(() async {
    await DBHelper.debugResetForTest(
      databaseName: 'tds_reconciliation_import_staging_test.db',
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

  group('ImportStagingRepository', () {
    test('opens v7 database with staging tables and indexes', () async {
      final db = await DBHelper.database;

      expect(await db.getVersion(), 7);

      final tableRows = await db.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name IN (?, ?)',
        whereArgs: ['table', 'staged_purchase_rows', 'staged_26q_rows'],
      );
      final indexRows = await db.query(
        'sqlite_master',
        columns: ['name'],
        where: 'type = ? AND name IN (?, ?, ?, ?)',
        whereArgs: [
          'index',
          'idx_staged_purchase_import_row',
          'idx_staged_purchase_created_at',
          'idx_staged_26q_import_row',
          'idx_staged_26q_created_at',
        ],
      );

      expect(
        tableRows.map((row) => row['name']).toSet(),
        containsAll(<String>{'staged_purchase_rows', 'staged_26q_rows'}),
      );
      expect(
        indexRows.map((row) => row['name']).toSet(),
        containsAll(<String>{
          'idx_staged_purchase_import_row',
          'idx_staged_purchase_created_at',
          'idx_staged_26q_import_row',
          'idx_staged_26q_created_at',
        }),
      );
    });

    test('stages, loads, and deletes rows in chunks', () async {
      final repository = ImportStagingRepository();
      final purchaseImportId = 'purchase_test_chunked';
      final tdsImportId = 'tds_test_chunked';
      final purchaseRows = List<PurchaseRow>.generate(
        2505,
        (index) => PurchaseRow.fromMap({
          'date': '2024-04-${((index % 28) + 1).toString().padLeft(2, '0')}',
          'bill_no': 'BILL-$index',
          'party_name': 'Vendor ${index % 5}',
          'gst_no': '',
          'pan_number': 'ABCDE1234F',
          'productname': 'Item $index',
          'basic_amount': 1000 + index,
          'bill_amount': 1000 + index,
        }),
      );
      final tdsRows = List<Tds26QRow>.generate(
        2505,
        (index) => Tds26QRow.fromMap({
          'date_month': 'Apr-2024',
          'financial_year': '2024-25',
          'party_name': 'Vendor ${index % 5}',
          'pan_number': 'ABCDE1234F',
          'amount_paid': 1000 + index,
          'tds_amount': 100 + (index % 10),
          'section': '194Q',
        }),
      );

      await repository.stagePurchaseRows(
        importId: purchaseImportId,
        rows: purchaseRows,
        sourceFileName: 'purchase.xlsx',
        buyerId: 'buyer-1',
        buyerPan: 'ABCDE1234F',
        sectionCode: '194Q',
        sheetName: 'Purchase',
        headerRowIndex: 0,
        headersTrusted: true,
        chunkSize: 1000,
      );
      await repository.stage26QRows(
        importId: tdsImportId,
        rows: tdsRows,
        sourceFileName: '26q.xlsx',
        buyerId: 'buyer-1',
        sheetName: '26Q',
        headerRowIndex: 1,
        headersTrusted: true,
        chunkSize: 1000,
      );

      final loadedPurchaseRows = await repository.loadPurchaseRows(
        purchaseImportId,
      );
      final loadedTdsRows = await repository.load26QRows(tdsImportId);

      expect(loadedPurchaseRows, hasLength(purchaseRows.length));
      expect(loadedTdsRows, hasLength(tdsRows.length));
      expect(loadedPurchaseRows.first.billNo, purchaseRows.first.billNo);
      expect(loadedPurchaseRows.last.billNo, purchaseRows.last.billNo);
      expect(loadedTdsRows.first.deductedAmount, tdsRows.first.deductedAmount);
      expect(loadedTdsRows.last.tds, tdsRows.last.tds);

      await repository.deleteImport(purchaseImportId);
      await repository.deleteImport(tdsImportId);

      expect(await repository.loadPurchaseRows(purchaseImportId), isEmpty);
      expect(await repository.load26QRows(tdsImportId), isEmpty);
    });
  });
}
