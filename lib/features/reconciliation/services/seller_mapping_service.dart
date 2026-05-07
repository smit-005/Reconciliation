import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';

class SellerMappingService {
  static const int _batchChunkSize = 250;

  /// SAVE mapping (called when user manually maps)
  static Future<void> saveMapping(SellerMapping mapping) async {
    await saveMappings(<SellerMapping>[mapping]);
  }

  /// SAVE mappings in one DB transaction, preserving single-row save behavior.
  static Future<void> saveMappings(List<SellerMapping> mappings) async {
    if (mappings.isEmpty) return;

    final db = await DBHelper.database;
    await db.transaction((txn) async {
      for (var start = 0; start < mappings.length; start += _batchChunkSize) {
        final end = (start + _batchChunkSize < mappings.length)
            ? start + _batchChunkSize
            : mappings.length;
        final batch = txn.batch();

        for (final mapping in mappings.sublist(start, end)) {
          final normalizedMap = mapping.toMap();
          batch.rawInsert(
            '''
INSERT INTO seller_mappings (
  id,
  buyer_name,
  buyer_pan,
  alias_name,
  section_code,
  mapped_pan,
  mapped_name,
  created_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(buyer_pan, alias_name, section_code) DO UPDATE SET
  buyer_name = excluded.buyer_name,
  mapped_pan = excluded.mapped_pan,
  mapped_name = excluded.mapped_name
''',
            [
              normalizedMap['id'],
              normalizedMap['buyer_name'],
              normalizedMap['buyer_pan'],
              normalizedMap['alias_name'],
              normalizedMap['section_code'],
              normalizedMap['mapped_pan'],
              normalizedMap['mapped_name'],
              normalizedMap['created_at'],
            ],
          );
        }

        await batch.commit(noResult: true);
      }
    });
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
      where: 'buyer_pan = ? AND alias_name = ? AND section_code IN (?, ?)',
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
    await deleteMappings(<Map<String, String>>[
      {
        'buyerPan': buyerPan,
        'aliasName': aliasName,
        'sectionCode': sectionCode,
      },
    ]);
  }

  /// DELETE mappings using the same buyer + alias + section criteria.
  static Future<void> deleteMappings(List<Map<String, String>> mappings) async {
    if (mappings.isEmpty) return;

    final db = await DBHelper.database;
    await db.transaction((txn) async {
      for (var start = 0; start < mappings.length; start += _batchChunkSize) {
        final end = (start + _batchChunkSize < mappings.length)
            ? start + _batchChunkSize
            : mappings.length;
        final batch = txn.batch();

        for (final mapping in mappings.sublist(start, end)) {
          final normalizedBuyerPan = (mapping['buyerPan'] ?? '')
              .trim()
              .toUpperCase();
          final normalizedAlias = normalizeName(
            (mapping['aliasName'] ?? '').trim(),
          );
          final normalizedSection = normalizeSellerMappingSectionCode(
            mapping['sectionCode'] ?? 'ALL',
          );

          batch.delete(
            'seller_mappings',
            where: 'buyer_pan = ? AND alias_name = ? AND section_code = ?',
            whereArgs: [normalizedBuyerPan, normalizedAlias, normalizedSection],
          );
        }

        await batch.commit(noResult: true);
      }
    });
  }
}
