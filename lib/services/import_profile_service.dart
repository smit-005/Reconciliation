import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_helper.dart';
import '../models/import_format_profile.dart';

class ImportProfileService {
  static Future<void> saveProfile(ImportFormatProfile profile) async {
    final db = await DBHelper.database;
    await db.insert(
      'import_format_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<ImportFormatProfile>> getProfiles({
    required String buyerId,
    required String fileType,
  }) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'import_format_profiles',
      where: 'buyer_id = ? AND file_type = ?',
      whereArgs: [buyerId, fileType],
      orderBy: 'last_used_at DESC',
    );

    return rows.map(ImportFormatProfile.fromMap).toList();
  }
}
