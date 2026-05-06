import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum WorkspaceStatus { notConfigured, valid, invalid }

class WorkspaceService {
  static const String manifestFileName = 'ledgermatch_workspace.json';
  static const int manifestVersion = 1;

  Future<Directory> initWorkspace(String rootPath) async {
    final normalizedRootPath = rootPath.trim();
    if (normalizedRootPath.isEmpty) {
      throw ArgumentError.value(rootPath, 'rootPath', 'Root path is required');
    }

    final root = Directory(normalizedRootPath);
    await root.create(recursive: true);

    final manifest = File(p.join(root.path, manifestFileName));
    if (!await manifest.exists()) {
      final manifestJson = const JsonEncoder.withIndent('  ').convert({
        'app': 'LedgerMatch',
        'version': manifestVersion,
        'created_at': DateTime.now().toIso8601String(),
      });
      await manifest.writeAsString(manifestJson, flush: true);
    }

    return root;
  }

  Future<String?> loadWorkspaceRootPath() => _loadWorkspaceRootPath();

  Future<WorkspaceStatus> getWorkspaceStatus() async {
    final rootPath = await _loadWorkspaceRootPath();
    if (rootPath == null) {
      return WorkspaceStatus.notConfigured;
    }

    final isValid = await validateWorkspace(rootPath);
    return isValid ? WorkspaceStatus.valid : WorkspaceStatus.invalid;
  }

  Future<void> saveWorkspaceRootPath(String rootPath) async {
    final normalizedRootPath = rootPath.trim();
    if (normalizedRootPath.isEmpty) {
      throw ArgumentError.value(rootPath, 'rootPath', 'Root path is required');
    }

    final db = await DBHelper.database;
    await db.insert('app_settings', {
      'key': 'workspace_root_path',
      'value': normalizedRootPath,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String buildBuyerFolderName({
    required String pan,
    required String name,
    required String buyerCode,
  }) {
    final safeName = _sanitizeFolderPart(name, fallback: 'Buyer');
    final normalizedPan = _sanitizeFolderPart(
      pan.trim().toUpperCase(),
      fallback: '',
    );

    if (normalizedPan.isNotEmpty) {
      return '${normalizedPan}_$safeName';
    }

    return 'BUYER_${_buyerCodeSegment(buyerCode)}_$safeName';
  }

  Future<String?> createBuyerFolder({
    required String buyerId,
    required String name,
    required String pan,
  }) async {
    final rootPath = await _loadWorkspaceRootPath();
    if (rootPath == null) {
      return null;
    }

    final root = await initWorkspace(rootPath);
    final folderName = buildBuyerFolderName(
      pan: pan,
      name: name,
      buyerCode: buyerId,
    );
    final relativePath = p.join('Buyers', folderName);
    final buyerFolder = Directory(p.join(root.path, relativePath));
    await buyerFolder.create(recursive: true);
    await _writeBuyerProfile(
      folder: buyerFolder,
      buyerId: buyerId,
      name: name,
      pan: pan,
      workspaceRelativePath: relativePath,
    );

    return relativePath;
  }

  Future<String?> createFinancialYearFolder({
    required String buyerWorkspaceRelativePath,
    required String fyLabel,
  }) async {
    final buyerRelativePath = buyerWorkspaceRelativePath.trim();
    if (buyerRelativePath.isEmpty) {
      return null;
    }

    final rootPath = await _loadWorkspaceRootPath();
    if (rootPath == null) {
      return null;
    }

    await initWorkspace(rootPath);

    final fyFolderName = 'FY_${_sanitizeFolderPart(fyLabel, fallback: 'FY')}';
    final fyRelativePath = p.join(buyerRelativePath, fyFolderName);
    final fyFolder = Directory(p.join(rootPath, fyRelativePath));
    await Directory(p.join(fyFolder.path, 'Working')).create(recursive: true);
    await Directory(
      p.join(fyFolder.path, 'Final_Exports'),
    ).create(recursive: true);

    return fyRelativePath;
  }

  Future<String?> resolveRelativePath(String relativePath) async {
    final rootPath = await _loadWorkspaceRootPath();
    if (rootPath == null || relativePath.trim().isEmpty) {
      return null;
    }

    final normalizedRoot = p.normalize(rootPath);
    final resolved = p.normalize(p.join(normalizedRoot, relativePath.trim()));
    final rootWithSeparator = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';

    if (resolved != normalizedRoot && !resolved.startsWith(rootWithSeparator)) {
      return null;
    }

    return resolved;
  }

  Future<bool> openFolder(String path) async {
    final targetPath = p.isAbsolute(path)
        ? p.normalize(path)
        : await resolveRelativePath(path);
    if (targetPath == null || !await Directory(targetPath).exists()) {
      return false;
    }

    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [targetPath]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [targetPath]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [targetPath]);
        return true;
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  Future<bool> validateWorkspace(String rootPath) async {
    final normalizedRootPath = rootPath.trim();
    if (normalizedRootPath.isEmpty) {
      return false;
    }

    final root = Directory(normalizedRootPath);
    if (!await root.exists()) {
      return false;
    }

    final manifest = File(p.join(root.path, manifestFileName));
    if (!await manifest.exists()) {
      return false;
    }

    try {
      final raw = await manifest.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      return decoded['app'] == 'LedgerMatch' &&
          decoded['version'] == manifestVersion;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _loadWorkspaceRootPath() async {
    final db = await DBHelper.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['workspace_root_path'],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final value = (rows.first['value'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _writeBuyerProfile({
    required Directory folder,
    required String buyerId,
    required String name,
    required String pan,
    required String workspaceRelativePath,
  }) async {
    final profile = File(p.join(folder.path, 'buyer_profile.json'));
    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'buyer_id': buyerId,
      'name': name.trim(),
      'pan': pan.trim().toUpperCase(),
      'workspace_relative_path': workspaceRelativePath,
      'updated_at': now,
    };

    if (!await profile.exists()) {
      payload['created_at'] = now;
    }

    await profile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  String _sanitizeFolderPart(String value, {required String fallback}) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .trim();

    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _buyerCodeSegment(String buyerCode) {
    final digits = RegExp(
      r'\d+',
    ).allMatches(buyerCode).map((match) => match.group(0) ?? '').join();
    if (digits.isNotEmpty) {
      final padded = digits.padLeft(4, '0');
      return padded.substring(padded.length - 4);
    }

    final fallback = _sanitizeFolderPart(
      buyerCode.toUpperCase(),
      fallback: '0000',
    );
    return fallback.length <= 8 ? fallback : fallback.substring(0, 8);
  }
}
