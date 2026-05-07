import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_repository.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

enum SourceFileSnapshotType { tds26q, ledger }

class WorkspaceExportPathService {
  final WorkspaceService _workspaceService;
  final BuyerFinancialYearRepository _financialYearRepository;

  WorkspaceExportPathService({
    WorkspaceService? workspaceService,
    BuyerFinancialYearRepository? financialYearRepository,
  }) : _workspaceService = workspaceService ?? WorkspaceService(),
       _financialYearRepository =
           financialYearRepository ?? BuyerFinancialYearRepository();

  Future<Directory?> resolveWorkingDirectory({
    required String? buyerId,
    required String? financialYearId,
  }) async {
    return _resolveFinancialYearSubdirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      folderSegments: const [WorkspaceFolderNames.working],
    );
  }

  Future<Directory?> resolveFinalExportsDirectory({
    required String? buyerId,
    required String? financialYearId,
  }) async {
    return _resolveFinancialYearSubdirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      folderSegments: const [WorkspaceFolderNames.finalExports],
    );
  }

  Future<Directory?> resolveSourceFilesDirectory({
    required String? buyerId,
    required String? financialYearId,
    SourceFileSnapshotType? type,
  }) async {
    return _resolveFinancialYearSubdirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      folderSegments: [
        WorkspaceFolderNames.sourceFiles,
        if (type != null) _sourceFolderName(type),
      ],
    );
  }

  Future<Directory?> resolveExceptionReportsDirectory({
    required String? buyerId,
    required String? financialYearId,
  }) async {
    return _resolveFinancialYearSubdirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      folderSegments: const [WorkspaceFolderNames.exceptionReports],
    );
  }

  Future<Directory?> resolveSourceSnapshotsDirectory({
    required String? buyerId,
    required String? financialYearId,
  }) async {
    return _resolveFinancialYearSubdirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      folderSegments: const [WorkspaceFolderNames.sourceSnapshots],
    );
  }

  Future<Directory?> _resolveFinancialYearSubdirectory({
    required String? buyerId,
    required String? financialYearId,
    required List<String> folderSegments,
  }) async {
    final fyPath = await _resolveFinancialYearPath(
      buyerId: buyerId,
      financialYearId: financialYearId,
    );
    if (fyPath == null) {
      return null;
    }

    final directory = Directory(p.joinAll([fyPath, ...folderSegments]));
    await directory.create(recursive: true);
    debugPrint('WORKSPACE PATH => ${directory.path}');
    return directory;
  }

  Future<String?> copySourceFileSnapshot({
    required String? buyerId,
    required String? financialYearId,
    required String originalFileName,
    required List<int> bytes,
    required SourceFileSnapshotType type,
    DateTime? now,
  }) async {
    final directory = await resolveSourceFilesDirectory(
      buyerId: buyerId,
      financialYearId: financialYearId,
      type: type,
    );
    if (directory == null) {
      return null;
    }

    final targetPath = await _resolveAvailableSnapshotPath(
      directory: directory,
      originalFileName: originalFileName,
      now: now ?? DateTime.now(),
    );
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  Future<String?> _resolveFinancialYearPath({
    required String? buyerId,
    required String? financialYearId,
  }) async {
    final normalizedBuyerId = buyerId?.trim() ?? '';
    final normalizedFinancialYearId = financialYearId?.trim() ?? '';
    if (normalizedBuyerId.isEmpty || normalizedFinancialYearId.isEmpty) {
      return null;
    }

    final workspaceStatus = await _workspaceService.getWorkspaceStatus();
    if (workspaceStatus != WorkspaceStatus.valid) {
      return null;
    }

    final financialYear = await _financialYearRepository.getActiveByIdForBuyer(
      buyerId: normalizedBuyerId,
      financialYearId: normalizedFinancialYearId,
    );
    final relativePath = financialYear?.workspaceRelativePath.trim() ?? '';
    if (relativePath.isEmpty) {
      return null;
    }

    final resolvedPath = await _workspaceService.resolveRelativePath(
      relativePath,
    );
    if (resolvedPath == null) {
      return null;
    }

    return resolvedPath;
  }

  Future<String> _resolveAvailableSnapshotPath({
    required Directory directory,
    required String originalFileName,
    required DateTime now,
  }) async {
    final sanitizedName = _safeSnapshotFileName(originalFileName);
    var targetPath = p.join(directory.path, sanitizedName);
    if (!await File(targetPath).exists()) {
      return targetPath;
    }

    final extension = p.extension(sanitizedName);
    final baseName = p.basenameWithoutExtension(sanitizedName);
    final timestamp = _timestamp(now);
    targetPath = p.join(directory.path, '${baseName}_$timestamp$extension');
    if (!await File(targetPath).exists()) {
      return targetPath;
    }

    var index = 2;
    while (true) {
      final candidate = p.join(
        directory.path,
        '${baseName}_${timestamp}_$index$extension',
      );
      if (!await File(candidate).exists()) {
        return candidate;
      }
      index++;
    }
  }

  String _sourceFolderName(SourceFileSnapshotType type) {
    switch (type) {
      case SourceFileSnapshotType.tds26q:
        return '26Q';
      case SourceFileSnapshotType.ledger:
        return 'Ledgers';
    }
  }

  String _safeSnapshotFileName(String fileName) {
    final basename = p.basename(fileName.trim());
    final extension = p.extension(basename);
    final stem = p.basenameWithoutExtension(basename);
    final safeStem = _safePathPart(stem, fallback: 'source_file');
    final safeExtension = extension.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '',
    );

    return '$safeStem$safeExtension';
  }

  String _safePathPart(String value, {required String fallback}) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .trim();

    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _timestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}';
  }
}
