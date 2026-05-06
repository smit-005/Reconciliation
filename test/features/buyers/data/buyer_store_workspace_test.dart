import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
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
      'ledgermatch_workspace_test_',
    );
    await DBHelper.debugResetForTest(databaseName: 'buyer_workspace_test.db');
    await WorkspaceService().saveWorkspaceRootPath(workspaceRoot.path);
    await BuyerStore.load();
  });

  tearDown(() async {
    await DBHelper.debugResetForTest();
    if (await workspaceRoot.exists()) {
      await workspaceRoot.delete(recursive: true);
    }
  });

  test('creates buyer folder and profile when PAN is available', () async {
    final error = await BuyerStore.add('Acme Pvt Ltd', 'ABCDE1234F', '');

    expect(error, isNull);
    final buyer = BuyerStore.getAll().single;
    expect(
      buyer.workspaceRelativePath,
      p.join('Buyers', 'ABCDE1234F_Acme_Pvt_Ltd'),
    );

    final buyerFolder = Directory(
      p.join(workspaceRoot.path, buyer.workspaceRelativePath),
    );
    expect(await buyerFolder.exists(), isTrue);

    final profile = await _readProfile(buyerFolder);
    expect(profile['buyer_id'], buyer.id);
    expect(profile['name'], 'Acme Pvt Ltd');
    expect(profile['pan'], 'ABCDE1234F');
    expect(profile['workspace_relative_path'], buyer.workspaceRelativePath);
  });

  test('creates fallback buyer folder when PAN is missing', () async {
    final error = await BuyerStore.add('No Pan Buyer', '', '');

    expect(error, isNull);
    final buyer = BuyerStore.getAll().single;
    final folderName = p.basename(buyer.workspaceRelativePath);
    expect(folderName, startsWith('BUYER_'));
    expect(folderName, endsWith('_No_Pan_Buyer'));

    final buyerFolder = Directory(
      p.join(workspaceRoot.path, buyer.workspaceRelativePath),
    );
    expect(await buyerFolder.exists(), isTrue);

    final profile = await _readProfile(buyerFolder);
    expect(profile['buyer_id'], buyer.id);
    expect(profile['name'], 'No Pan Buyer');
    expect(profile['pan'], '');
  });

  test('archives buyer without deleting workspace folder', () async {
    final error = await BuyerStore.add('Archive Me Ltd', 'BCDEF2345G', '');
    expect(error, isNull);

    final buyer = BuyerStore.getAll().single;
    final buyerFolder = Directory(
      p.join(workspaceRoot.path, buyer.workspaceRelativePath),
    );
    expect(await buyerFolder.exists(), isTrue);

    await BuyerStore.archive(buyer.id);
    expect(BuyerStore.getAll(), isEmpty);
    expect(await buyerFolder.exists(), isTrue);
  });

  test('loads saved workspace root path from settings table', () async {
    final service = WorkspaceService();

    expect(await service.loadWorkspaceRootPath(), workspaceRoot.path);
  });

  test('reports invalid status when workspace folder is missing', () async {
    final service = WorkspaceService();

    await service.initWorkspace(workspaceRoot.path);
    expect(await service.getWorkspaceStatus(), WorkspaceStatus.valid);

    await workspaceRoot.delete(recursive: true);
    expect(await service.getWorkspaceStatus(), WorkspaceStatus.invalid);
  });
}

Future<Map<String, dynamic>> _readProfile(Directory buyerFolder) async {
  final file = File(p.join(buyerFolder.path, 'buyer_profile.json'));
  expect(await file.exists(), isTrue);
  final decoded = jsonDecode(await file.readAsString());
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}
