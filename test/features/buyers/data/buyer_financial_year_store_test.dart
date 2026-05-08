import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
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

  test('creating buyer does not auto-create current FY row', () async {
    expect(await BuyerStore.add('Acme Pvt Ltd', 'ABCDE1234F', ''), isNull);
    final buyer = BuyerStore.getAll().single;

    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    expect(financialYears, isEmpty);
    expect(buyer.activeFinancialYearId, isNull);

    final unexpectedCurrentFyPath = Directory(
      p.join(workspaceRoot.path, buyer.workspaceRelativePath, 'FY_2026-27'),
    );
    expect(await unexpectedCurrentFyPath.exists(), isFalse);
  });

  test('explicitly creates FY row and workspace folders for buyer', () async {
    expect(await BuyerStore.add('Acme Pvt Ltd', 'ABCDE1234F', ''), isNull);
    final buyer = BuyerStore.getAll().single;

    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: '2024-25',
    );
    expect(error, isNull);

    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    expect(financialYears, hasLength(1));
    expect(financialYears.single.fyLabel, '2024-25');
    expect(financialYears.single.status, 'not_started');
    expect(
      financialYears.single.workspaceRelativePath,
      p.join(buyer.workspaceRelativePath, 'FY_2024-25'),
    );

    final fyPath = p.join(
      workspaceRoot.path,
      financialYears.single.workspaceRelativePath,
    );
    for (final folderName in const [
      WorkspaceFolderNames.working,
      WorkspaceFolderNames.finalExports,
      WorkspaceFolderNames.sourceFiles,
      WorkspaceFolderNames.exceptionReports,
      WorkspaceFolderNames.sourceSnapshots,
    ]) {
      expect(await Directory(p.join(fyPath, folderName)).exists(), isTrue);
    }
  });

  test('ensures explicit default FY without creating current FY', () async {
    expect(await BuyerStore.add('Default FY Ltd', 'FGHIJ4567K', ''), isNull);
    final buyer = BuyerStore.getAll().single;

    final financialYear = await BuyerFinancialYearStore.ensureForBuyer(
      buyer: buyer,
      fyLabel: '2024-25',
    );

    expect(financialYear, isNotNull);
    expect(financialYear!.fyLabel, '2024-25');
    expect(financialYear.workspaceRelativePath, contains('FY_2024-25'));
    expect(await BuyerFinancialYearStore.listActive(buyer.id), hasLength(1));
    expect(
      await Directory(
        p.join(workspaceRoot.path, buyer.workspaceRelativePath, 'FY_2026-27'),
      ).exists(),
      isFalse,
    );
  });

  test('prevents duplicate FY rows for buyer', () async {
    expect(await BuyerStore.add('Duplicate FY Ltd', 'ABCDE1234F', ''), isNull);
    final buyer = BuyerStore.getAll().single;
    expect(
      await BuyerFinancialYearStore.create(buyer: buyer, fyLabel: '2024-25'),
      isNull,
    );

    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: '2024-25',
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
    expect(await BuyerStore.add('Archive FY Ltd', 'BCDEF2345G', ''), isNull);
    final buyer = BuyerStore.getAll().single;
    expect(
      await BuyerFinancialYearStore.create(buyer: buyer, fyLabel: '2024-25'),
      isNull,
    );
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
      await BuyerStore.add('Clear Active FY Ltd', 'CDEFG3456H', ''),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;
    expect(
      await BuyerFinancialYearStore.create(buyer: buyer, fyLabel: '2024-25'),
      isNull,
    );
    final financialYear = (await BuyerFinancialYearStore.listActive(
      buyer.id,
    )).single;
    await BuyerStore.setActiveFinancialYear(buyer.id, financialYear.id);

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
