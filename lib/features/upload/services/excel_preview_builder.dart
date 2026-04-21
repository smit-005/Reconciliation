part of 'excel_service.dart';

ExcelPreviewData? _buildPreviewData(
  List<int> bytes, {
  required ExcelImportType fileType,
  required String fileName,
  Map<String, String> initialMappedColumns = const {},
  List<String> warnings = const [],
  double? confidenceScore,
  String? preferredSheetName,
  ImportSessionCache? sessionCache,
}) {
  final decoder = ExcelService._decoderFromCache(
    bytes,
    sessionCache: sessionCache,
  );
  if (decoder.tables.isEmpty) return null;

  final sheetInfo = ExcelService._findBestSheetAndHeader(
    decoder,
    forcedType: fileType,
    preferredSheetName: preferredSheetName,
  );
  if (sheetInfo == null) return null;

  final table = decoder.tables[sheetInfo.sheetName];
  if (table == null || table.rows.isEmpty) return null;

  final rawHeaderRow = table.rows[sheetInfo.headerRowIndex];
  final mappedHeaders = ExcelService._resolveMappedHeaders(
    rows: table.rows,
    headerRowIndex: sheetInfo.headerRowIndex,
    forcedType: fileType,
    headersTrusted: sheetInfo.headersTrusted,
  );
  final presentHeaders = mappedHeaders.whereType<String>().toSet();
  final previewConfidence =
      confidenceScore ??
      ExcelService._headerConfidenceScore(
        presentHeaders,
        type: fileType,
      );

  final columnKeys = <String>[];
  final columnLabels = <String, String>{};
  final suggestedMappings = <String, String>{};
  final normalizedInitialMapping = ExcelService
      ._normalizeCanonicalColumnMappingByType(
        ExcelService._normalizeProfileColumnMapping(initialMappedColumns),
        type: fileType,
      );

  for (int i = 0; i < mappedHeaders.length; i++) {
    final columnKey = 'COL_$i';
    final rawLabel = i < rawHeaderRow.length
        ? rawHeaderRow[i]?.toString().trim() ?? ''
        : '';
    final displayLabel = sheetInfo.headersTrusted && rawLabel.isNotEmpty
        ? rawLabel
        : 'Column ${i + 1}';

    columnKeys.add(columnKey);
    columnLabels[columnKey] = displayLabel;

    final canonical = i < mappedHeaders.length ? mappedHeaders[i] : null;
    if (canonical != null && canonical.isNotEmpty) {
      suggestedMappings[columnKey] = canonical;
    }
  }

  for (final entry in normalizedInitialMapping.entries) {
    final canonical = entry.key.trim();
    final rawKey = entry.value.trim();
    if (canonical.isEmpty || rawKey.isEmpty) continue;

    if (rawKey.startsWith('COL_') && columnLabels.containsKey(rawKey)) {
      suggestedMappings[rawKey] = canonical;
      continue;
    }

    final matchedEntry = columnLabels.entries.firstWhere(
      (item) => item.value == rawKey,
      orElse: () => const MapEntry('', ''),
    );
    if (matchedEntry.key.isNotEmpty) {
      suggestedMappings[matchedEntry.key] = canonical;
    }
  }

  final dataStartIndex = sheetInfo.headersTrusted
      ? sheetInfo.headerRowIndex + 1
      : sheetInfo.headerRowIndex;
  final sampleRows = <Map<String, String>>[];

  for (int i = dataStartIndex; i < table.rows.length && sampleRows.length < 8; i++) {
    final row = table.rows[i];
    final sampleRow = <String, String>{};
    var hasValue = false;

    for (int j = 0; j < columnKeys.length; j++) {
      final value = j < row.length ? ExcelService._normalizeCellValue(row[j]) : '';
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        hasValue = true;
      }
      sampleRow[columnKeys[j]] = text;
    }

    if (hasValue) {
      sampleRows.add(sampleRow);
    }
  }

  final unmappedHeaders = sheetInfo.headersTrusted
      ? ExcelService._extractUnmappedRawHeaders(rawHeaderRow, mappedHeaders)
      : columnKeys
            .where((key) => !suggestedMappings.containsKey(key))
            .map((key) => columnLabels[key] ?? key)
            .toList();

  return ExcelPreviewData(
    fileType: fileType.name,
    fileName: fileName,
    sheetName: sheetInfo.sheetName,
    headerRowIndex: sheetInfo.headerRowIndex,
    headersTrusted: sheetInfo.headersTrusted,
    confidenceScore: previewConfidence,
    warnings: warnings,
    unmappedRawHeaders: unmappedHeaders,
    columnKeys: columnKeys,
    columnLabels: columnLabels,
    suggestedMappings: suggestedMappings,
    sampleRows: sampleRows,
  );
}

ExcelPreviewData? _buildPreviewDataWithProfile(
  List<int> bytes, {
  required ExcelImportType fileType,
  required String fileName,
  required String sheetName,
  required int headerRowIndex,
  required bool headersTrusted,
  required Map<String, String> columnMapping,
  List<String> warnings = const [],
  double? confidenceScore,
  ImportSessionCache? sessionCache,
}) {
  final decoder = ExcelService._decoderFromCache(
    bytes,
    sessionCache: sessionCache,
  );
  if (sheetName.isEmpty) return null;
  final table = decoder.tables[sheetName];
  if (table == null || table.rows.isEmpty) return null;
  if (headerRowIndex < 0 || headerRowIndex >= table.rows.length) {
    return null;
  }

  final rawHeaderRow = table.rows[headerRowIndex];
  final mappedHeaders = ExcelService._buildMappedHeadersFromProfile(
    rawHeaderRow: rawHeaderRow,
    columnMapping: ExcelService._normalizeCanonicalColumnMappingByType(
      columnMapping,
      type: fileType,
    ),
  );
  final presentHeaders = mappedHeaders.whereType<String>().toSet();
  final previewConfidence =
      confidenceScore ??
      ExcelService._headerConfidenceScore(
        presentHeaders,
        type: fileType,
      );

  final columnKeys = <String>[];
  final columnLabels = <String, String>{};
  final suggestedMappings = <String, String>{};
  final normalizedInitialMapping = ExcelService
      ._normalizeCanonicalColumnMappingByType(
        ExcelService._normalizeProfileColumnMapping(columnMapping),
        type: fileType,
      );

  for (int i = 0; i < mappedHeaders.length; i++) {
    final columnKey = 'COL_$i';
    final rawLabel = i < rawHeaderRow.length
        ? rawHeaderRow[i]?.toString().trim() ?? ''
        : '';
    final displayLabel = headersTrusted && rawLabel.isNotEmpty
        ? rawLabel
        : 'Column ${i + 1}';

    columnKeys.add(columnKey);
    columnLabels[columnKey] = displayLabel;

    final canonical = i < mappedHeaders.length ? mappedHeaders[i] : null;
    if (canonical != null && canonical.isNotEmpty) {
      suggestedMappings[columnKey] = canonical;
    }
  }

  for (final entry in normalizedInitialMapping.entries) {
    final canonical = entry.key.trim();
    final rawKey = entry.value.trim();
    if (canonical.isEmpty || rawKey.isEmpty) continue;

    if (rawKey.startsWith('COL_') && columnLabels.containsKey(rawKey)) {
      suggestedMappings[rawKey] = canonical;
      continue;
    }

    final matchedEntry = columnLabels.entries.firstWhere(
      (item) => item.value == rawKey,
      orElse: () => const MapEntry('', ''),
    );
    if (matchedEntry.key.isNotEmpty) {
      suggestedMappings[matchedEntry.key] = canonical;
    }
  }

  final dataStartIndex = headersTrusted ? headerRowIndex + 1 : headerRowIndex;
  final sampleRows = <Map<String, String>>[];

  for (int i = dataStartIndex; i < table.rows.length && sampleRows.length < 8; i++) {
    final row = table.rows[i];
    final sampleRow = <String, String>{};
    var hasValue = false;

    for (int j = 0; j < columnKeys.length; j++) {
      final value = j < row.length ? ExcelService._normalizeCellValue(row[j]) : '';
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        hasValue = true;
      }
      sampleRow[columnKeys[j]] = text;
    }

    if (hasValue) {
      sampleRows.add(sampleRow);
    }
  }

  final unmappedHeaders = headersTrusted
      ? ExcelService._extractUnmappedRawHeaders(rawHeaderRow, mappedHeaders)
      : columnKeys
            .where((key) => !suggestedMappings.containsKey(key))
            .map((key) => columnLabels[key] ?? key)
            .toList();

  return ExcelPreviewData(
    fileType: fileType.name,
    fileName: fileName,
    sheetName: sheetName,
    headerRowIndex: headerRowIndex,
    headersTrusted: headersTrusted,
    confidenceScore: previewConfidence,
    warnings: warnings,
    unmappedRawHeaders: unmappedHeaders,
    columnKeys: columnKeys,
    columnLabels: columnLabels,
    suggestedMappings: suggestedMappings,
    sampleRows: sampleRows,
  );
}
