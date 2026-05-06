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

  test('creates FY row and workspace folders for buyer', () async {
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
    expect(await Directory(p.join(fyPath, 'Working')).exists(), isTrue);
    expect(await Directory(p.join(fyPath, 'Final_Exports')).exists(), isTrue);
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
}
