import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/local/db_helper.dart';
import '../models/import_format_profile.dart';

class ImportProfileService {
  static Future<void> saveProfile(ImportFormatProfile profile) async {
    final db = await DBHelper.database;
    final normalizedProfile = ImportFormatProfile(
      id: profile.id,
      buyerId: profile.buyerId.trim(),
      fileType: profile.fileType.trim(),
      sheetNamePattern: profile.sheetNamePattern.trim().toLowerCase(),
      headerRowIndex: profile.headerRowIndex,
      headersTrusted: profile.headersTrusted,
      columnMapping: Map<String, String>.from(profile.columnMapping),
      sampleSignature: _profileIdentitySignature(profile),
      lastUsedAt: profile.lastUsedAt,
    );
    await db.insert(
      'import_format_profiles',
      normalizedProfile.toMap(),
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
      whereArgs: [buyerId.trim(), fileType.trim()],
      orderBy: 'last_used_at DESC',
    );

    return rows.map(ImportFormatProfile.fromMap).toList();
  }

  static String _profileIdentitySignature(ImportFormatProfile profile) {
    final signature = profile.sampleSignature.trim();
    if (signature.isNotEmpty) {
      return signature;
    }

    return profile.sheetNamePattern.trim().toLowerCase();
  }
}
