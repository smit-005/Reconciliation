import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';

class ImportStagingRepository {
  static const int defaultChunkSize = 1000;

  Future<void> stagePurchaseRows({
    required String importId,
    required List<PurchaseRow> rows,
    required String sourceFileName,
    String? buyerId,
    String? buyerPan,
    String? sectionCode,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    int chunkSize = defaultChunkSize,
  }) async {
    final db = await DBHelper.database;
    final createdAt = DateTime.now().toIso8601String();
    final normalizedChunkSize = chunkSize <= 0 ? defaultChunkSize : chunkSize;

    await db.transaction((txn) async {
      for (int start = 0; start < rows.length; start += normalizedChunkSize) {
        final end = (start + normalizedChunkSize) > rows.length
            ? rows.length
            : (start + normalizedChunkSize);
        final batch = txn.batch();

        for (int index = start; index < end; index++) {
          final row = rows[index];
          final map = ExcelService.purchaseRowToStagingMap(row);
          batch.insert('staged_purchase_rows', <String, dynamic>{
            'import_id': importId,
            'source_file_name': sourceFileName,
            'buyer_id': buyerId,
            'buyer_pan': buyerPan,
            'section_code': sectionCode,
            'sheet_name': sheetName,
            'header_row_index': headerRowIndex,
            'headers_trusted': headersTrusted == true ? 1 : 0,
            'row_number': index + 1,
            'date': map['date'],
            'bill_no': map['bill_no'],
            'party_name': map['party_name'],
            'gst_no': map['gst_no'],
            'pan_number': map['pan_number'],
            'productname': map['productname'],
            'basic_amount': map['basic_amount'],
            'bill_amount': map['bill_amount'],
            'created_at': createdAt,
          });
        }

        await batch.commit(noResult: true);
      }
    });
  }

  Future<void> stage26QRows({
    required String importId,
    required List<Tds26QRow> rows,
    required String sourceFileName,
    String? buyerId,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    int chunkSize = defaultChunkSize,
  }) async {
    final db = await DBHelper.database;
    final createdAt = DateTime.now().toIso8601String();
    final normalizedChunkSize = chunkSize <= 0 ? defaultChunkSize : chunkSize;

    await db.transaction((txn) async {
      for (int start = 0; start < rows.length; start += normalizedChunkSize) {
        final end = (start + normalizedChunkSize) > rows.length
            ? rows.length
            : (start + normalizedChunkSize);
        final batch = txn.batch();

        for (int index = start; index < end; index++) {
          final row = rows[index];
          final map = ExcelService.tds26QRowToStagingMap(row);
          batch.insert('staged_26q_rows', <String, dynamic>{
            'import_id': importId,
            'source_file_name': sourceFileName,
            'buyer_id': buyerId,
            'sheet_name': sheetName,
            'header_row_index': headerRowIndex,
            'headers_trusted': headersTrusted == true ? 1 : 0,
            'row_number': index + 1,
            'date_month': map['date_month'],
            'financial_year': map['financial_year'],
            'party_name': map['party_name'],
            'pan_number': map['pan_number'],
            'amount_paid': map['amount_paid'],
            'tds_amount': map['tds_amount'],
            'section': map['section'],
            'nature_of_payment': map['nature_of_payment'],
            'created_at': createdAt,
          });
        }

        await batch.commit(noResult: true);
      }
    });
  }

  Future<List<PurchaseRow>> loadPurchaseRows(String importId) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'staged_purchase_rows',
      where: 'import_id = ?',
      whereArgs: [importId],
      orderBy: 'row_number ASC',
    );

    return rows
        .map(
          (row) => PurchaseRow.fromMap(<String, dynamic>{
            'date': row['date'],
            'bill_no': row['bill_no'],
            'party_name': row['party_name'],
            'gst_no': row['gst_no'],
            'pan_number': row['pan_number'],
            'productname': row['productname'],
            'basic_amount': row['basic_amount'],
            'bill_amount': row['bill_amount'],
          }),
        )
        .toList();
  }

  Future<List<Tds26QRow>> load26QRows(String importId) async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'staged_26q_rows',
      where: 'import_id = ?',
      whereArgs: [importId],
      orderBy: 'row_number ASC',
    );

    return rows
        .map(
          (row) => Tds26QRow.fromMap(<String, dynamic>{
            'date_month': row['date_month'],
            'financial_year': row['financial_year'],
            'party_name': row['party_name'],
            'pan_number': row['pan_number'],
            'amount_paid': row['amount_paid'],
            'tds_amount': row['tds_amount'],
            'section': row['section'],
            'nature_of_payment': row['nature_of_payment'],
          }),
        )
        .toList();
  }

  Future<void> deleteImport(String importId) async {
    final db = await DBHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'staged_purchase_rows',
        where: 'import_id = ?',
        whereArgs: [importId],
      );
      await txn.delete(
        'staged_26q_rows',
        where: 'import_id = ?',
        whereArgs: [importId],
      );
    });
  }
}
