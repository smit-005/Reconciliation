import '../models/buyer.dart';
import 'db_helper.dart';

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
    await db.delete(
      'buyers',
      where: 'id = ?',
      whereArgs: [id],
    );
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