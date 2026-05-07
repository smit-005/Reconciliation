import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_store.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_export_path_service.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory workspaceRoot;
  late WorkspaceExportPathService exportPathService;

  setUp(() async {
    workspaceRoot = await Directory.systemTemp.createTemp(
      'ledgermatch_export_path_test_',
    );
    await DBHelper.debugResetForTest(databaseName: 'workspace_export_test.db');
    await WorkspaceService().initWorkspace(workspaceRoot.path);
    await WorkspaceService().saveWorkspaceRootPath(workspaceRoot.path);
    await BuyerStore.load();
    exportPathService = WorkspaceExportPathService();
  });

  tearDown(() async {
    await DBHelper.debugResetForTest();
    if (await workspaceRoot.exists()) {
      await workspaceRoot.delete(recursive: true);
    }
  });

  test('resolves FY Working folder from stored FY relative path', () async {
    final context = await _createBuyerWithActiveFy();

    final workingDirectory = await exportPathService.resolveWorkingDirectory(
      buyerId: context.buyer.id,
      financialYearId: context.financialYear.id,
    );

    expect(workingDirectory, isNotNull);
    expect(
      p.normalize(workingDirectory!.path),
      p.normalize(
        p.join(
          workspaceRoot.path,
          context.financialYear.workspaceRelativePath,
          'Working',
        ),
      ),
    );
    expect(await workingDirectory.exists(), isTrue);
  });

  test('resolves all standard FY workspace folders', () async {
    final context = await _createBuyerWithActiveFy();

    final finalExportsDirectory = await exportPathService
        .resolveFinalExportsDirectory(
          buyerId: context.buyer.id,
          financialYearId: context.financialYear.id,
        );
    final sourceFilesDirectory = await exportPathService
        .resolveSourceFilesDirectory(
          buyerId: context.buyer.id,
          financialYearId: context.financialYear.id,
        );
    final exceptionReportsDirectory = await exportPathService
        .resolveExceptionReportsDirectory(
          buyerId: context.buyer.id,
          financialYearId: context.financialYear.id,
        );
    final sourceSnapshotsDirectory = await exportPathService
        .resolveSourceSnapshotsDirectory(
          buyerId: context.buyer.id,
          financialYearId: context.financialYear.id,
        );

    final fyPath = p.join(
      workspaceRoot.path,
      context.financialYear.workspaceRelativePath,
    );
    expect(
      p.normalize(finalExportsDirectory!.path),
      p.normalize(p.join(fyPath, 'Final_Exports')),
    );
    expect(
      p.normalize(sourceFilesDirectory!.path),
      p.normalize(p.join(fyPath, 'Source_Files')),
    );
    expect(
      p.normalize(exceptionReportsDirectory!.path),
      p.normalize(p.join(fyPath, 'Exception_Reports')),
    );
    expect(
      p.normalize(sourceSnapshotsDirectory!.path),
      p.normalize(p.join(fyPath, 'Source_Snapshots')),
    );
    expect(await finalExportsDirectory.exists(), isTrue);
    expect(await sourceFilesDirectory.exists(), isTrue);
    expect(await exceptionReportsDirectory.exists(), isTrue);
    expect(await sourceSnapshotsDirectory.exists(), isTrue);
  });

  test('creates source snapshot folders and copies files', () async {
    final context = await _createBuyerWithActiveFy();

    final tdsPath = await exportPathService.copySourceFileSnapshot(
      buyerId: context.buyer.id,
      financialYearId: context.financialYear.id,
      originalFileName: '26q.xlsx',
      bytes: [1, 2, 3],
      type: SourceFileSnapshotType.tds26q,
    );
    final ledgerPath = await exportPathService.copySourceFileSnapshot(
      buyerId: context.buyer.id,
      financialYearId: context.financialYear.id,
      originalFileName: 'ledger.xlsx',
      bytes: [4, 5, 6],
      type: SourceFileSnapshotType.ledger,
    );

    expect(tdsPath, isNotNull);
    expect(ledgerPath, isNotNull);
    expect(p.basename(p.dirname(tdsPath!)), '26Q');
    expect(p.basename(p.dirname(ledgerPath!)), 'Ledgers');
    expect(await File(tdsPath).readAsBytes(), [1, 2, 3]);
    expect(await File(ledgerPath).readAsBytes(), [4, 5, 6]);
  });

  test(
    'adds timestamp suffix instead of overwriting source snapshots',
    () async {
      final context = await _createBuyerWithActiveFy();
      final now = DateTime(2026, 5, 6, 18, 44, 55);

      final firstPath = await exportPathService.copySourceFileSnapshot(
        buyerId: context.buyer.id,
        financialYearId: context.financialYear.id,
        originalFileName: 'ledger.xlsx',
        bytes: [1],
        type: SourceFileSnapshotType.ledger,
        now: now,
      );
      final secondPath = await exportPathService.copySourceFileSnapshot(
        buyerId: context.buyer.id,
        financialYearId: context.financialYear.id,
        originalFileName: 'ledger.xlsx',
        bytes: [2],
        type: SourceFileSnapshotType.ledger,
        now: now,
      );

      expect(firstPath, isNot(secondPath));
      expect(p.basename(firstPath!), 'ledger.xlsx');
      expect(p.basename(secondPath!), 'ledger_20260506_184455.xlsx');
      expect(await File(firstPath).readAsBytes(), [1]);
      expect(await File(secondPath).readAsBytes(), [2]);
    },
  );

  test('returns null safely when workspace or FY path is missing', () async {
    await DBHelper.debugResetForTest(databaseName: 'workspace_missing_test.db');
    await BuyerStore.load();
    expect(
      await BuyerStore.add(
        'No Workspace Ltd',
        'NOPQR1234S',
        '',
        currentDateForTest: DateTime(2026, 4, 1),
      ),
      isNull,
    );
    final buyer = BuyerStore.getAll().single;
    final financialYear = (await BuyerFinancialYearStore.listActive(
      buyer.id,
    )).single;

    final workingDirectory = await exportPathService.resolveWorkingDirectory(
      buyerId: buyer.id,
      financialYearId: financialYear.id,
    );
    final snapshotPath = await exportPathService.copySourceFileSnapshot(
      buyerId: buyer.id,
      financialYearId: financialYear.id,
      originalFileName: '26q.xlsx',
      bytes: [1, 2, 3],
      type: SourceFileSnapshotType.tds26q,
    );

    expect(workingDirectory, isNull);
    expect(snapshotPath, isNull);
  });
}

class _BuyerFyContext {
  final Buyer buyer;
  final BuyerFinancialYear financialYear;

  const _BuyerFyContext({required this.buyer, required this.financialYear});
}

Future<_BuyerFyContext> _createBuyerWithActiveFy() async {
  expect(
    await BuyerStore.add(
      'Radha Industries',
      'ABCDE1234F',
      '',
      currentDateForTest: DateTime(2026, 4, 1),
    ),
    isNull,
  );
  final buyer = BuyerStore.getAll().single;
  final financialYear = (await BuyerFinancialYearStore.listActive(
    buyer.id,
  )).single;
  return _BuyerFyContext(buyer: buyer, financialYear: financialYear);
}
