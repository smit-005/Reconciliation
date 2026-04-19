import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  static Database? _database;
  static const String _dbName = 'tds_reconciliation.db';
  static const int _dbVersion = 3;

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
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE buyers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pan TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
CREATE TABLE seller_mappings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  buyer_name TEXT,
  buyer_pan TEXT,
  alias_name TEXT,
  mapped_pan TEXT,
  mapped_name TEXT,
  created_at TEXT
)
''');
    await db.execute('''
CREATE TABLE import_format_profiles (
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
}
