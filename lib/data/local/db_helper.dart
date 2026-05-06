import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/utils/normalize_utils.dart';

class DBHelper {
  static Database? _database;
  static const String _dbName = 'tds_reconciliation.db';
  static const int _dbVersion = 10;
  static String? _dbNameOverrideForTest;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, _dbNameOverrideForTest ?? _dbName);

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
    if (oldVersion < 7) {
      await _createStagingTables(db);
    }
    if (oldVersion < 8) {
      await _migrateBuyersTable(db);
      await _createAppSettingsTable(db);
    }
    if (oldVersion < 9) {
      await _migrateBuyersTable(db);
    }
    if (oldVersion < 10) {
      await _createBuyerFinancialYearsTable(db);
    }
  }

  static Future<void> debugResetForTest({String? databaseName}) async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _dbNameOverrideForTest = databaseName;
    if (databaseName == null) {
      return;
    }

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, databaseName);
    await databaseFactory.deleteDatabase(path);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE buyers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pan TEXT NOT NULL UNIQUE,
        gst_number TEXT NOT NULL DEFAULT '',
        archived_at TEXT,
        workspace_relative_path TEXT
      )
    ''');
    await _createSellerMappingsTable(db);
    await _createImportFormatProfilesTable(db);
    await _createStagingTables(db);
    await _createAppSettingsTable(db);
    await _createBuyerFinancialYearsTable(db);
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

  static Future<void> _createStagingTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS staged_purchase_rows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  import_id TEXT NOT NULL,
  source_file_name TEXT NOT NULL,
  buyer_id TEXT,
  buyer_pan TEXT,
  section_code TEXT,
  sheet_name TEXT,
  header_row_index INTEGER,
  headers_trusted INTEGER NOT NULL DEFAULT 0,
  row_number INTEGER NOT NULL,
  date TEXT,
  bill_no TEXT,
  party_name TEXT,
  gst_no TEXT,
  pan_number TEXT,
  productname TEXT,
  basic_amount REAL NOT NULL DEFAULT 0,
  bill_amount REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_staged_purchase_import_row
ON staged_purchase_rows(import_id, row_number)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_staged_purchase_created_at
ON staged_purchase_rows(created_at)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS staged_26q_rows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  import_id TEXT NOT NULL,
  source_file_name TEXT NOT NULL,
  buyer_id TEXT,
  sheet_name TEXT,
  header_row_index INTEGER,
  headers_trusted INTEGER NOT NULL DEFAULT 0,
  row_number INTEGER NOT NULL,
  date_month TEXT,
  financial_year TEXT,
  party_name TEXT,
  pan_number TEXT,
  amount_paid REAL NOT NULL DEFAULT 0,
  tds_amount REAL NOT NULL DEFAULT 0,
  section TEXT,
  nature_of_payment TEXT,
  created_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_staged_26q_import_row
ON staged_26q_rows(import_id, row_number)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_staged_26q_created_at
ON staged_26q_rows(created_at)
''');
  }

  static Future<void> _createAppSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT
)
''');
    await db.insert('app_settings', const {
      'key': 'workspace_root_path',
      'value': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _createBuyerFinancialYearsTable(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS buyer_financial_years (
  id TEXT PRIMARY KEY,
  buyer_id TEXT NOT NULL,
  fy_label TEXT NOT NULL,
  workspace_relative_path TEXT,
  status TEXT NOT NULL DEFAULT 'not_started',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(buyer_id, fy_label)
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
        gst_number TEXT NOT NULL DEFAULT '',
        archived_at TEXT,
        workspace_relative_path TEXT
      )
    ''');
      return;
    }

    final columns = await db.rawQuery("PRAGMA table_info(buyers)");
    final hasGstNumber = columns.any(
      (row) => (row['name'] ?? '').toString().toLowerCase() == 'gst_number',
    );
    final hasArchivedAt = columns.any(
      (row) => (row['name'] ?? '').toString().toLowerCase() == 'archived_at',
    );
    final hasWorkspaceRelativePath = columns.any(
      (row) =>
          (row['name'] ?? '').toString().toLowerCase() ==
          'workspace_relative_path',
    );

    if (!hasGstNumber) {
      await db.execute(
        "ALTER TABLE buyers ADD COLUMN gst_number TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!hasArchivedAt) {
      await db.execute("ALTER TABLE buyers ADD COLUMN archived_at TEXT");
    }
    if (!hasWorkspaceRelativePath) {
      await db.execute(
        "ALTER TABLE buyers ADD COLUMN workspace_relative_path TEXT",
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
        final buyerPan = (row['buyer_pan'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final aliasName = normalizeName((row['alias_name'] ?? '').toString());
        final sectionCode = _normalizeSellerMappingSectionCode(
          (row['section_code'] ?? 'ALL').toString(),
        );

        if (buyerPan.isEmpty || aliasName.isEmpty) {
          continue;
        }

        batch.insert('seller_mappings', {
          'buyer_name': (row['buyer_name'] ?? '').toString().trim(),
          'buyer_pan': buyerPan,
          'alias_name': aliasName,
          'section_code': sectionCode,
          'mapped_pan': (row['mapped_pan'] ?? '')
              .toString()
              .trim()
              .toUpperCase(),
          'mapped_name': (row['mapped_name'] ?? '').toString().trim(),
          'created_at': (row['created_at'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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

        batch.insert('import_format_profiles', {
          'buyer_id': buyerId,
          'file_type': fileType,
          'sheet_name_pattern': sheetNamePattern,
          'header_row_index': row['header_row_index'] ?? 0,
          'headers_trusted': row['headers_trusted'] ?? 0,
          'column_mapping_json': (row['column_mapping_json'] ?? '').toString(),
          'sample_signature': sampleSignature,
          'last_used_at': (row['last_used_at'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    if (isLegacyUnsupportedSection(trimmed)) {
      return '194IB';
    }

    final normalized = normalizeSection(trimmed);
    return normalized.isEmpty ? trimmed : normalized;
  }
}
