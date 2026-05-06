import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/core/utils/financial_year_utils.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_store.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory workspaceRoot;

  setUp(() async {
    workspaceRoot = await Directory.systemTemp.createTemp(
      'ledgermatch_fy_workspace_test_',
    );
    await DBHelper.debugResetForTest(databaseName: 'buyer_fy_test.db');
    await WorkspaceService().saveWorkspaceRootPath(workspaceRoot.path);
    await BuyerStore.load();
  });

  tearDown(() async {
    await DBHelper.debugResetForTest();
    if (await workspaceRoot.exists()) {
      await workspaceRoot.delete(recursive: true);
    }
  });

  test('auto-creates current FY row and workspace folders for buyer', () async {
    final now = DateTime(2026, 4, 1);
    expect(
      await BuyerStore.add(
        'Acme Pvt Ltd',
        'ABCDE1234F',
        '',
        currentDateForTest: now,
      ),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;
    final expectedFyLabel = currentIndianFinancialYearLabel(now: now);
    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    expect(financialYears, hasLength(1));
    expect(financialYears.single.fyLabel, expectedFyLabel);
    expect(buyer.activeFinancialYearId, financialYears.single.id);
    expect(financialYears.single.status, 'not_started');
    expect(
      financialYears.single.workspaceRelativePath,
      p.join(buyer.workspaceRelativePath, 'FY_$expectedFyLabel'),
    );

    final fyPath = p.join(
      workspaceRoot.path,
      financialYears.single.workspaceRelativePath,
    );
    expect(await Directory(p.join(fyPath, 'Working')).exists(), isTrue);
    expect(await Directory(p.join(fyPath, 'Final_Exports')).exists(), isTrue);
  });

  test('prevents duplicate FY rows for buyer', () async {
    final now = DateTime(2026, 4, 1);
    expect(
      await BuyerStore.add(
        'Duplicate FY Ltd',
        'ABCDE1234F',
        '',
        currentDateForTest: now,
      ),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;

    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: currentIndianFinancialYearLabel(now: now),
    );

    expect(error, 'Financial year already exists for this buyer');
    expect(await BuyerFinancialYearStore.listActive(buyer.id), hasLength(1));
  });

  test('creates FY without folder when buyer has no workspace path', () async {
    final db = await DBHelper.database;
    const buyerId = 'legacy-buyer';
    await db.insert('buyers', {
      'id': buyerId,
      'name': 'Legacy Buyer',
      'pan': 'LMNOP6789Q',
      'gst_number': '',
      'archived_at': null,
      'workspace_relative_path': '',
    });
    await BuyerStore.load();

    final buyer = BuyerStore.getAll().single;
    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: 'FY 2025-26',
    );

    expect(error, isNull);
    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    expect(financialYears.single.fyLabel, '2025-26');
    expect(financialYears.single.workspaceRelativePath, isEmpty);
  });

  test('archives FY without deleting folders', () async {
    expect(
      await BuyerStore.add(
        'Archive FY Ltd',
        'BCDEF2345G',
        '',
        currentDateForTest: DateTime(2026, 4, 1),
      ),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;
    final financialYear = (await BuyerFinancialYearStore.listActive(
      buyer.id,
    )).single;
    final fyFolder = Directory(
      p.join(workspaceRoot.path, financialYear.workspaceRelativePath),
    );
    expect(await fyFolder.exists(), isTrue);

    await BuyerFinancialYearStore.archive(financialYear.id);

    expect(await BuyerFinancialYearStore.listActive(buyer.id), isEmpty);
    expect(await fyFolder.exists(), isTrue);
  });

  test('archives active FY and clears buyer default reference', () async {
    expect(
      await BuyerStore.add(
        'Clear Active FY Ltd',
        'CDEFG3456H',
        '',
        currentDateForTest: DateTime(2026, 4, 1),
      ),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;
    final financialYear = (await BuyerFinancialYearStore.listActive(
      buyer.id,
    )).single;

    await BuyerFinancialYearStore.archive(financialYear.id);
    await BuyerStore.load();

    expect(BuyerStore.getAll().single.activeFinancialYearId, isNull);
  });

  test('returns null active FY when buyer default is missing', () async {
    final db = await DBHelper.database;
    await db.insert('buyers', {
      'id': 'legacy-buyer',
      'name': 'Legacy Buyer',
      'pan': 'DEFGH4567I',
      'gst_number': '',
      'archived_at': null,
      'workspace_relative_path': '',
      'active_financial_year_id': 'missing-fy',
    });
    await BuyerStore.load();

    final buyer = BuyerStore.getAll().single;
    final activeFinancialYear = await BuyerFinancialYearStore.activeForBuyer(
      buyer,
    );

    expect(activeFinancialYear, isNull);
  });
}
