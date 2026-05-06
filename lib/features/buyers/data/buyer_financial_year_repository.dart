import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';

class BuyerFinancialYearRepository {
  Future<List<BuyerFinancialYear>> getActiveByBuyer(String buyerId) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'buyer_financial_years',
      where: 'buyer_id = ? AND archived_at IS NULL',
      whereArgs: [buyerId.trim()],
      orderBy: 'fy_label DESC',
    );

    return rows.map(BuyerFinancialYear.fromMap).toList();
  }

  Future<BuyerFinancialYear?> getActiveByIdForBuyer({
    required String buyerId,
    required String financialYearId,
  }) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'buyer_financial_years',
      where: 'buyer_id = ? AND id = ? AND archived_at IS NULL',
      whereArgs: [buyerId.trim(), financialYearId.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return BuyerFinancialYear.fromMap(rows.first);
  }

  Future<BuyerFinancialYear?> getByLabelForBuyer({
    required String buyerId,
    required String fyLabel,
  }) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'buyer_financial_years',
      where: 'buyer_id = ? AND fy_label = ? AND archived_at IS NULL',
      whereArgs: [buyerId.trim(), fyLabel.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }
    return BuyerFinancialYear.fromMap(rows.first);
  }

  Future<void> create(BuyerFinancialYear financialYear) async {
    final db = await DBHelper.database;
    await db.insert('buyer_financial_years', financialYear.toMap());
  }

  Future<void> archive(String id) async {
    final db = await DBHelper.database;
    final archivedAt = DateTime.now().toIso8601String();
    await db.update(
      'buyer_financial_years',
      {'archived_at': archivedAt, 'updated_at': archivedAt},
      where: 'id = ? AND archived_at IS NULL',
      whereArgs: [id.trim()],
    );
  }

  Future<bool> existsForBuyer({
    required String buyerId,
    required String fyLabel,
  }) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'buyer_financial_years',
      columns: ['id'],
      where: 'buyer_id = ? AND fy_label = ?',
      whereArgs: [buyerId.trim(), fyLabel.trim()],
      limit: 1,
    );

    return rows.isNotEmpty;
  }
}
