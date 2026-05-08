import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';

class BuyerRepository {
  Future<List<Buyer>> getAllBuyers() async {
    final db = await DBHelper.database;

    final rows = await db.query(
      'buyers',
      where: 'archived_at IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map((e) => Buyer.fromMap(e)).toList();
  }

  Future<List<Buyer>> getArchivedBuyers() async {
    final db = await DBHelper.database;

    final rows = await db.query(
      'buyers',
      where: 'archived_at IS NOT NULL',
      orderBy: 'archived_at DESC, name COLLATE NOCASE ASC',
    );

    return rows.map((e) => Buyer.fromMap(e)).toList();
  }

  Future<void> addBuyer(Buyer buyer) async {
    final db = await DBHelper.database;
    await db.insert('buyers', buyer.toMap());
  }

  Future<void> updateBuyer(Buyer buyer) async {
    final db = await DBHelper.database;
    await db.update(
      'buyers',
      buyer.toMap(),
      where: 'id = ?',
      whereArgs: [buyer.id],
    );
  }

  Future<void> updateActiveFinancialYearId(
    String buyerId,
    String? financialYearId,
  ) async {
    final db = await DBHelper.database;
    await db.update(
      'buyers',
      {'active_financial_year_id': financialYearId?.trim()},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [buyerId.trim()],
    );
  }

  Future<void> clearActiveFinancialYearReference(String financialYearId) async {
    final db = await DBHelper.database;
    await db.update(
      'buyers',
      {'active_financial_year_id': null},
      where: 'active_financial_year_id = ?',
      whereArgs: [financialYearId.trim()],
    );
  }

  Future<void> archiveBuyer(String id) async {
    final db = await DBHelper.database;
    await db.update(
      'buyers',
      {'archived_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> restoreBuyer(String id) async {
    final db = await DBHelper.database;
    await db.update(
      'buyers',
      {'archived_at': null},
      where: 'id = ? AND archived_at IS NOT NULL',
      whereArgs: [id],
    );
  }

  Future<bool> panExists(String pan, {String? excludeId}) async {
    final normalizedPan = pan.trim().toUpperCase();
    if (normalizedPan.isEmpty) {
      return false;
    }

    final db = await DBHelper.database;

    final rows = await db.query(
      'buyers',
      where: excludeId == null ? 'pan = ?' : 'pan = ? AND id != ?',
      whereArgs: excludeId == null
          ? [normalizedPan]
          : [normalizedPan, excludeId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }
}
