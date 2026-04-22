import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';

class SellerMappingService {
  /// SAVE mapping (called when user manually maps)
  static Future<void> saveMapping(SellerMapping mapping) async {
    final db = await DBHelper.database;
    final normalizedMap = mapping.toMap();
    final normalizedBuyerPan = (normalizedMap['buyer_pan'] ?? '').toString();
    final normalizedAlias = (normalizedMap['alias_name'] ?? '').toString();
    final normalizedSection =
        (normalizedMap['section_code'] ?? 'ALL').toString();

    final existing = await db.query(
      'seller_mappings',
      columns: ['id', 'created_at'],
      where: 'buyer_pan = ? AND alias_name = ? AND section_code = ?',
      whereArgs: [normalizedBuyerPan, normalizedAlias, normalizedSection],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingRow = existing.first;
      final updateMap = Map<String, dynamic>.from(normalizedMap)
        ..remove('id')
        ..['created_at'] =
            (existingRow['created_at'] ?? normalizedMap['created_at']).toString();

      await db.update(
        'seller_mappings',
        updateMap,
        where: 'id = ?',
        whereArgs: [existingRow['id']],
      );
      return;
    }

    await db.insert('seller_mappings', normalizedMap);
  }

  /// GET single mapping using alias + buyer + section, with ALL fallback
  static Future<SellerMapping?> getMapping({
    required String buyerPan,
    required String aliasName,
    String sectionCode = 'ALL',
  }) async {
    final db = await DBHelper.database;

    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final normalizedAlias = normalizeName(aliasName.trim());
    final normalizedSection = normalizeSellerMappingSectionCode(sectionCode);

    final result = await db.query(
      'seller_mappings',
      where:
          'buyer_pan = ? AND alias_name = ? AND section_code IN (?, ?)',
      whereArgs: [
        normalizedBuyerPan,
        normalizedAlias,
        normalizedSection,
        'ALL',
      ],
      orderBy:
          "CASE WHEN section_code = '${normalizedSection.replaceAll("'", "''")}' THEN 0 ELSE 1 END, id ASC",
      limit: 1,
    );

    if (result.isNotEmpty) {
      return SellerMapping.fromMap(result.first);
    }

    return null;
  }

  /// GET all mappings for one buyer
  static Future<List<SellerMapping>> getAllMappings(String buyerPan) async {
    final db = await DBHelper.database;

    final normalizedBuyerPan = buyerPan.trim().toUpperCase();

    final result = await db.query(
      'seller_mappings',
      where: 'buyer_pan = ?',
      whereArgs: [normalizedBuyerPan],
      orderBy: 'alias_name ASC, section_code ASC',
    );

    return result.map((e) => SellerMapping.fromMap(e)).toList();
  }

  /// DELETE one mapping if needed later
  static Future<void> deleteMapping({
    required String buyerPan,
    required String aliasName,
    String sectionCode = 'ALL',
  }) async {
    final db = await DBHelper.database;

    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final normalizedAlias = normalizeName(aliasName.trim());
    final normalizedSection = normalizeSellerMappingSectionCode(sectionCode);

    await db.delete(
      'seller_mappings',
      where: 'buyer_pan = ? AND alias_name = ? AND section_code = ?',
      whereArgs: [normalizedBuyerPan, normalizedAlias, normalizedSection],
    );
  }
}
