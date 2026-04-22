import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/utils/normalize_utils.dart';

class DBHelper {
  static Database? _database;
  static const String _dbName = 'tds_reconciliation.db';
  static const int _dbVersion = 6;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }
  static Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    if (oldVersion < 2) {
      // Future schema updates here
      // Example:
      // await db.execute('ALTER TABLE seller_mappings ADD COLUMN note TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS import_format_profiles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  buyer_id TEXT NOT NULL,
  file_type TEXT NOT NULL,
  sheet_name_pattern TEXT,
  header_row_index INTEGER NOT NULL,
  headers_trusted INTEGER NOT NULL DEFAULT 0,
  column_mapping_json TEXT NOT NULL,
  sample_signature TEXT,
  last_used_at TEXT NOT NULL
)
''');
    }
    if (oldVersion < 4) {
      await _migrateSellerMappingsTable(db);
      await _migrateImportFormatProfilesTable(db);
    }
    if (oldVersion < 5) {
      await _migrateSellerMappingsTable(db);
    }
    if (oldVersion < 6) {
      await _migrateBuyersTable(db);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE buyers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pan TEXT NOT NULL UNIQUE,
        gst_number TEXT NOT NULL DEFAULT ''
      )
    ''');
    await _createSellerMappingsTable(db);
    await _createImportFormatProfilesTable(db);
  }

  static Future<void> _createSellerMappingsTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE seller_mappings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  buyer_name TEXT,
  buyer_pan TEXT NOT NULL,
  alias_name TEXT NOT NULL,
  section_code TEXT NOT NULL DEFAULT 'ALL',
  mapped_pan TEXT,
  mapped_name TEXT,
  created_at TEXT,
  UNIQUE(buyer_pan, alias_name, section_code)
)
''');
  }

  static Future<void> _createImportFormatProfilesTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
CREATE TABLE import_format_profiles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  buyer_id TEXT NOT NULL,
  file_type TEXT NOT NULL,
  sheet_name_pattern TEXT,
  header_row_index INTEGER NOT NULL,
  headers_trusted INTEGER NOT NULL DEFAULT 0,
  column_mapping_json TEXT NOT NULL,
  sample_signature TEXT NOT NULL,
  last_used_at TEXT NOT NULL,
  UNIQUE(buyer_id, file_type, sample_signature)
)
''');
  }

  static Future<void> _migrateBuyersTable(Database db) async {
    if (!await _tableExists(db, 'buyers')) {
      await db.execute('''
      CREATE TABLE buyers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pan TEXT NOT NULL UNIQUE,
        gst_number TEXT NOT NULL DEFAULT ''
      )
    ''');
      return;
    }

    final columns = await db.rawQuery("PRAGMA table_info(buyers)");
    final hasGstNumber = columns.any(
      (row) => (row['name'] ?? '').toString().toLowerCase() == 'gst_number',
    );

    if (!hasGstNumber) {
      await db.execute(
        "ALTER TABLE buyers ADD COLUMN gst_number TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> _migrateSellerMappingsTable(Database db) async {
    if (!await _tableExists(db, 'seller_mappings')) {
      await _createSellerMappingsTable(db);
      return;
    }

    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE seller_mappings RENAME TO seller_mappings_legacy',
      );
      await _createSellerMappingsTable(txn);

      final rows = await txn.query(
        'seller_mappings_legacy',
        orderBy: 'created_at ASC, id ASC',
      );
      final batch = txn.batch();

      for (final row in rows) {
        final buyerPan = (row['buyer_pan'] ?? '').toString().trim().toUpperCase();
        final aliasName = normalizeName((row['alias_name'] ?? '').toString());
        final sectionCode = _normalizeSellerMappingSectionCode(
          (row['section_code'] ?? 'ALL').toString(),
        );

        if (buyerPan.isEmpty || aliasName.isEmpty) {
          continue;
        }

        batch.insert(
          'seller_mappings',
          {
            'buyer_name': (row['buyer_name'] ?? '').toString().trim(),
            'buyer_pan': buyerPan,
            'alias_name': aliasName,
            'section_code': sectionCode,
            'mapped_pan': (row['mapped_pan'] ?? '').toString().trim().toUpperCase(),
            'mapped_name': (row['mapped_name'] ?? '').toString().trim(),
            'created_at': (row['created_at'] ?? '').toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      await txn.execute('DROP TABLE seller_mappings_legacy');
    });
  }

  static Future<void> _migrateImportFormatProfilesTable(Database db) async {
    if (!await _tableExists(db, 'import_format_profiles')) {
      await _createImportFormatProfilesTable(db);
      return;
    }

    await db.transaction((txn) async {
      await txn.execute(
        'ALTER TABLE import_format_profiles RENAME TO import_format_profiles_legacy',
      );
      await _createImportFormatProfilesTable(txn);

      final rows = await txn.query(
        'import_format_profiles_legacy',
        orderBy: 'last_used_at ASC, id ASC',
      );
      final batch = txn.batch();

      for (final row in rows) {
        final buyerId = (row['buyer_id'] ?? '').toString().trim();
        final fileType = (row['file_type'] ?? '').toString().trim();
        final sheetNamePattern = (row['sheet_name_pattern'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final sampleSignature = _normalizeProfileSampleSignature(
          sampleSignature: (row['sample_signature'] ?? '').toString(),
          sheetNamePattern: sheetNamePattern,
        );

        if (buyerId.isEmpty || fileType.isEmpty || sampleSignature.isEmpty) {
          continue;
        }

        batch.insert(
          'import_format_profiles',
          {
            'buyer_id': buyerId,
            'file_type': fileType,
            'sheet_name_pattern': sheetNamePattern,
            'header_row_index': row['header_row_index'] ?? 0,
            'headers_trusted': row['headers_trusted'] ?? 0,
            'column_mapping_json': (row['column_mapping_json'] ?? '').toString(),
            'sample_signature': sampleSignature,
            'last_used_at': (row['last_used_at'] ?? '').toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      await txn.execute('DROP TABLE import_format_profiles_legacy');
    });
  }

  static String _normalizeProfileSampleSignature({
    required String sampleSignature,
    required String sheetNamePattern,
  }) {
    final normalizedSignature = sampleSignature.trim();
    if (normalizedSignature.isNotEmpty) {
      return normalizedSignature;
    }

    return sheetNamePattern.trim().toLowerCase();
  }

  static String _normalizeSellerMappingSectionCode(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed == 'ALL' || trimmed.isEmpty) {
      return 'ALL';
    }

    final normalized = normalizeSection(trimmed);
    return normalized.isEmpty ? 'ALL' : normalized;
  }
}
