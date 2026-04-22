import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';

class BuyerRepository {
  Future<List<Buyer>> getAllBuyers() async {
    final db = await DBHelper.database;

    final rows = await db.query(
      'buyers',
      orderBy: 'name COLLATE NOCASE ASC',
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

  Future<void> deleteBuyer(String id) async {
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'buyers',
        columns: ['id', 'pan'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        return;
      }

      final buyerId = (rows.first['id'] ?? id).toString();
      final buyerPan = (rows.first['pan'] ?? '').toString().trim().toUpperCase();

      if (buyerPan.isNotEmpty) {
        await txn.delete(
          'seller_mappings',
          where: 'buyer_pan = ?',
          whereArgs: [buyerPan],
        );
      }

      await txn.delete(
        'import_format_profiles',
        where: 'buyer_id = ?',
        whereArgs: [buyerId],
      );

      await txn.delete(
        'buyers',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<bool> panExists(String pan, {String? excludeId}) async {
    final db = await DBHelper.database;

    final rows = await db.query(
      'buyers',
      where: excludeId == null ? 'pan = ?' : 'pan = ? AND id != ?',
      whereArgs: excludeId == null ? [pan] : [pan, excludeId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }
}
