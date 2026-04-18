import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../data/db_helper.dart';
import '../models/seller_mapping.dart';
import '../core/utils/normalize_utils.dart';

class MappingService {
  /// SAVE mapping (called when user manually maps)
  static Future<void> saveMapping(SellerMapping mapping) async {
    final db = await DBHelper.database;

    await db.insert(
      'seller_mappings',
      mapping.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// GET single mapping using alias + buyer
  static Future<SellerMapping?> getMapping({
    required String buyerPan,
    required String aliasName,
  }) async {
    final db = await DBHelper.database;

    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final normalizedAlias = normalizeName(aliasName.trim());

    final result = await db.query(
      'seller_mappings',
      where: 'buyer_pan = ? AND alias_name = ?',
      whereArgs: [normalizedBuyerPan, normalizedAlias],
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
      orderBy: 'alias_name ASC',
    );

    return result.map((e) => SellerMapping.fromMap(e)).toList();
  }

  /// DELETE one mapping if needed later
  static Future<void> deleteMapping({
    required String buyerPan,
    required String aliasName,
  }) async {
    final db = await DBHelper.database;

    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final normalizedAlias = normalizeName(aliasName.trim());

    await db.delete(
      'seller_mappings',
      where: 'buyer_pan = ? AND alias_name = ?',
      whereArgs: [normalizedBuyerPan, normalizedAlias],
    );
  }
}
