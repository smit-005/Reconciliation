import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DBHelper.debugResetForTest(
      databaseName: 'seller_mapping_service_test.db',
    );
  });

  tearDown(() async {
    await DBHelper.debugResetForTest();
  });

  test('bulk upsert preserves existing row identity and created_at', () async {
    await SellerMappingService.saveMapping(
      SellerMapping(
        buyerName: 'Buyer One',
        buyerPan: 'abcde1234f',
        aliasName: 'Vendor One',
        sectionCode: '194c',
        mappedPan: 'aaaaa1111a',
        mappedName: 'Original Vendor',
      ),
    );

    final db = await DBHelper.database;
    final originalRows = await db.query(
      'seller_mappings',
      where: 'buyer_pan = ? AND alias_name = ? AND section_code = ?',
      whereArgs: ['ABCDE1234F', 'VENDORONE', '194C'],
      limit: 1,
    );
    final originalId = originalRows.single['id'];
    await db.update(
      'seller_mappings',
      {'created_at': 'ORIGINAL_CREATED_AT'},
      where: 'id = ?',
      whereArgs: [originalId],
    );

    await SellerMappingService.saveMappings(
      List<SellerMapping>.generate(
        300,
        (index) => SellerMapping(
          buyerName: 'Buyer One',
          buyerPan: 'ABCDE1234F',
          aliasName: index == 0 ? 'Vendor One' : 'Vendor $index',
          sectionCode: '194C',
          mappedPan: index == 0 ? 'BBBBB2222B' : 'CCCCC3333C',
          mappedName: index == 0 ? 'Updated Vendor' : 'Mapped $index',
        ),
      ),
    );

    final updatedRows = await db.query(
      'seller_mappings',
      where: 'buyer_pan = ? AND alias_name = ? AND section_code = ?',
      whereArgs: ['ABCDE1234F', 'VENDORONE', '194C'],
      limit: 1,
    );
    final updatedRow = updatedRows.single;
    expect(updatedRow['id'], originalId);
    expect(updatedRow['created_at'], 'ORIGINAL_CREATED_AT');
    expect(updatedRow['mapped_pan'], 'BBBBB2222B');
    expect(updatedRow['mapped_name'], 'Updated Vendor');

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS mapping_count FROM seller_mappings WHERE buyer_pan = ?',
      ['ABCDE1234F'],
    );
    expect(countRows.single['mapping_count'], 300);
  });

  test('bulk delete matches single delete normalization behavior', () async {
    await SellerMappingService.saveMappings(<SellerMapping>[
      SellerMapping(
        buyerName: 'Buyer One',
        buyerPan: 'ABCDE1234F',
        aliasName: 'Vendor One',
        sectionCode: '194C',
        mappedPan: 'AAAAA1111A',
        mappedName: 'Vendor One',
      ),
      SellerMapping(
        buyerName: 'Buyer One',
        buyerPan: 'ABCDE1234F',
        aliasName: 'Vendor Two',
        sectionCode: '194C',
        mappedPan: 'BBBBB2222B',
        mappedName: 'Vendor Two',
      ),
    ]);

    await SellerMappingService.deleteMappings(<Map<String, String>>[
      {
        'buyerPan': ' abcde1234f ',
        'aliasName': ' vendor one ',
        'sectionCode': '194c',
      },
    ]);

    final remaining = await SellerMappingService.getAllMappings('ABCDE1234F');
    expect(remaining.map((mapping) => mapping.aliasName), ['VENDORTWO']);
  });
}
