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
  final structuredCandidates = _supportsManualHeaderRowSelection(fileType)
      ? ExcelService._collectStructuredHeaderCandidates(
          table.rows,
          type: fileType,
          fileLabel: fileName,
        )
      : const <({int headerRowIndex, int score, List<String> matchedFields})>[];
  final selectedStructuredCandidate = _structuredCandidateForRow(
    structuredCandidates,
    headerRowIndex: sheetInfo.headerRowIndex,
  );

  final primaryCandidate = _buildPreviewHeaderCandidateFromTable(
    rows: table.rows,
    fileType: fileType,
    headerRowIndex: sheetInfo.headerRowIndex,
    headersTrusted: sheetInfo.headersTrusted,
    initialMappedColumns: initialMappedColumns,
    confidenceScore: confidenceScore,
    detectionScore: selectedStructuredCandidate?.score ?? 0,
    matchedFields: selectedStructuredCandidate?.matchedFields ?? const [],
  );
  if (primaryCandidate == null) return null;

  final headerRowCandidates = _buildManualHeaderRowCandidates(
    rows: table.rows,
    fileType: fileType,
    primaryCandidate: primaryCandidate,
    initialMappedColumns: initialMappedColumns,
    structuredCandidates: structuredCandidates,
  );

  ExcelService._flushForcedNumericDateAvoidanceSummary('build_preview');

  return ExcelPreviewData(
    fileType: fileType.name,
    fileName: fileName,
    sheetName: sheetInfo.sheetName,
    headerRowIndex: primaryCandidate.headerRowIndex,
    headersTrusted: primaryCandidate.headersTrusted,
    confidenceScore: primaryCandidate.confidenceScore,
    warnings: warnings,
    unmappedRawHeaders: primaryCandidate.unmappedRawHeaders,
    columnKeys: primaryCandidate.columnKeys,
    columnLabels: primaryCandidate.columnLabels,
    suggestedMappings: primaryCandidate.suggestedMappings,
    rawSampleRows: primaryCandidate.rawSampleRows,
    sampleRows: primaryCandidate.sampleRows,
    headerRowCandidates: headerRowCandidates,
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
  final structuredCandidates = _supportsManualHeaderRowSelection(fileType)
      ? ExcelService._collectStructuredHeaderCandidates(
          table.rows,
          type: fileType,
          fileLabel: fileName,
        )
      : const <({int headerRowIndex, int score, List<String> matchedFields})>[];
  final selectedStructuredCandidate = _structuredCandidateForRow(
    structuredCandidates,
    headerRowIndex: headerRowIndex,
  );

  final primaryCandidate = _buildPreviewHeaderCandidateFromTable(
    rows: table.rows,
    fileType: fileType,
    headerRowIndex: headerRowIndex,
    headersTrusted: headersTrusted,
    initialMappedColumns: columnMapping,
    explicitColumnMapping: columnMapping,
    confidenceScore: confidenceScore,
    detectionScore: selectedStructuredCandidate?.score ?? 0,
    matchedFields: selectedStructuredCandidate?.matchedFields ?? const [],
  );
  if (primaryCandidate == null) return null;

  final headerRowCandidates = _buildManualHeaderRowCandidates(
    rows: table.rows,
    fileType: fileType,
    primaryCandidate: primaryCandidate,
    initialMappedColumns: columnMapping,
    structuredCandidates: structuredCandidates,
  );

  ExcelService._flushForcedNumericDateAvoidanceSummary(
    'build_preview_with_profile',
  );

  return ExcelPreviewData(
    fileType: fileType.name,
    fileName: fileName,
    sheetName: sheetName,
    headerRowIndex: primaryCandidate.headerRowIndex,
    headersTrusted: primaryCandidate.headersTrusted,
    confidenceScore: primaryCandidate.confidenceScore,
    warnings: warnings,
    unmappedRawHeaders: primaryCandidate.unmappedRawHeaders,
    columnKeys: primaryCandidate.columnKeys,
    columnLabels: primaryCandidate.columnLabels,
    suggestedMappings: primaryCandidate.suggestedMappings,
    rawSampleRows: primaryCandidate.rawSampleRows,
    sampleRows: primaryCandidate.sampleRows,
    headerRowCandidates: headerRowCandidates,
  );
}

ExcelPreviewHeaderCandidate? _buildPreviewHeaderCandidateFromTable({
  required List<List<dynamic>> rows,
  required ExcelImportType fileType,
  required int headerRowIndex,
  required bool headersTrusted,
  required Map<String, String> initialMappedColumns,
  Map<String, String>? explicitColumnMapping,
  double? confidenceScore,
  int detectionScore = 0,
  List<String> matchedFields = const [],
}) {
  if (headerRowIndex < 0 || headerRowIndex >= rows.length) {
    return null;
  }

  final rawHeaderRow = rows[headerRowIndex];
  final mappedHeaders = explicitColumnMapping == null
      ? ExcelService._resolveMappedHeaders(
          rows: rows,
          headerRowIndex: headerRowIndex,
          forcedType: fileType,
          headersTrusted: headersTrusted,
        )
      : ExcelService._buildMappedHeadersFromProfile(
          rawHeaderRow: rawHeaderRow,
          columnMapping: ExcelService._normalizeCanonicalColumnMappingByType(
            explicitColumnMapping,
            type: fileType,
          ),
        );
  final presentHeaders = mappedHeaders.whereType<String>().toSet();
  final previewConfidence =
      confidenceScore ??
      ExcelService._headerConfidenceScore(presentHeaders, type: fileType);

  final columnKeys = <String>[];
  final columnLabels = <String, String>{};
  final suggestedMappings = <String, String>{};
  final normalizedInitialMapping =
      ExcelService._normalizeCanonicalColumnMappingByType(
        ExcelService._normalizeProfileColumnMapping(initialMappedColumns),
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

    final canonical = mappedHeaders[i];
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
  final rawSampleRows = <Map<String, dynamic>>[];
  final sampleRows = <Map<String, String>>[];

  for (int i = dataStartIndex; i < rows.length && sampleRows.length < 8; i++) {
    final row = rows[i];
    final rawSampleRow = <String, dynamic>{};
    final sampleRow = <String, String>{};
    var hasValue = false;

    for (int j = 0; j < columnKeys.length; j++) {
      final columnKey = columnKeys[j];
      final canonicalField = suggestedMappings[columnKey];
      final rawValue = j < row.length ? row[j] : null;
      rawSampleRow[columnKey] = rawValue;
      final value = ExcelService.formatPreviewValue(
        rawValue,
        canonicalField: canonicalField,
      );
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        hasValue = true;
      }
      sampleRow[columnKey] = text;
    }

    if (hasValue) {
      rawSampleRows.add(rawSampleRow);
      sampleRows.add(sampleRow);
    }
  }

  final unmappedHeaders = headersTrusted
      ? ExcelService._extractUnmappedRawHeaders(rawHeaderRow, mappedHeaders)
      : columnKeys
            .where((key) => !suggestedMappings.containsKey(key))
            .map((key) => columnLabels[key] ?? key)
            .toList();

  return ExcelPreviewHeaderCandidate(
    headerRowIndex: headerRowIndex,
    headersTrusted: headersTrusted,
    confidenceScore: previewConfidence,
    unmappedRawHeaders: unmappedHeaders,
    columnKeys: columnKeys,
    columnLabels: columnLabels,
    suggestedMappings: suggestedMappings,
    rawSampleRows: rawSampleRows,
    sampleRows: sampleRows,
    detectionScore: detectionScore,
    matchedFields: matchedFields,
  );
}

List<ExcelPreviewHeaderCandidate> _buildManualHeaderRowCandidates({
  required List<List<dynamic>> rows,
  required ExcelImportType fileType,
  required ExcelPreviewHeaderCandidate primaryCandidate,
  required Map<String, String> initialMappedColumns,
  required List<({int headerRowIndex, int score, List<String> matchedFields})>
  structuredCandidates,
}) {
  if (!_supportsManualHeaderRowSelection(fileType)) {
    return const [];
  }

  final lowConfidence =
      primaryCandidate.confidenceScore < 0.75 ||
      !primaryCandidate.headersTrusted;
  if (!lowConfidence) {
    return const [];
  }

  final rowIndexes = <int>{primaryCandidate.headerRowIndex};
  final byRowIndex = <int, ExcelPreviewHeaderCandidate>{
    primaryCandidate.headerRowIndex: primaryCandidate,
  };

  for (final candidate in structuredCandidates) {
    rowIndexes.add(candidate.headerRowIndex);
  }

  for (int i = 0; i < rows.length && i < 30; i++) {
    if (_looksLikeManualHeaderSelectionRow(rows[i])) {
      rowIndexes.add(i);
    }
  }

  if (rowIndexes.length <= 1) {
    return const [];
  }

  final scoreByRow = <int, int>{
    for (final candidate in structuredCandidates)
      candidate.headerRowIndex: candidate.score,
  };
  final matchedFieldsByRow = <int, List<String>>{
    for (final candidate in structuredCandidates)
      candidate.headerRowIndex: candidate.matchedFields,
  };

  final sortedRowIndexes = rowIndexes.toList()..sort();
  for (final rowIndex in sortedRowIndexes) {
    if (byRowIndex.containsKey(rowIndex)) {
      continue;
    }

    final candidate = _buildPreviewHeaderCandidateFromTable(
      rows: rows,
      fileType: fileType,
      headerRowIndex: rowIndex,
      headersTrusted: true,
      initialMappedColumns: initialMappedColumns,
      detectionScore: scoreByRow[rowIndex] ?? 0,
      matchedFields: matchedFieldsByRow[rowIndex] ?? const [],
    );
    if (candidate != null) {
      byRowIndex[rowIndex] = candidate;
    }
  }

  final manualCandidates = byRowIndex.values.toList()
    ..sort(
      (left, right) => left.headerRowIndex.compareTo(right.headerRowIndex),
    );

  return manualCandidates.length > 1 ? manualCandidates : const [];
}

bool _supportsManualHeaderRowSelection(ExcelImportType fileType) {
  return fileType == ExcelImportType.purchase ||
      fileType == ExcelImportType.genericLedger;
}

bool _looksLikeManualHeaderSelectionRow(List<dynamic> row) {
  final normalizedCells = row
      .map((cell) => ExcelService._normalizeLooseText(cell?.toString() ?? ''))
      .where((value) => value.isNotEmpty)
      .toList();
  if (normalizedCells.length < 2) {
    return false;
  }

  final alphabeticCellCount = normalizedCells
      .where((value) => RegExp(r'[a-z]').hasMatch(value))
      .length;
  if (alphabeticCellCount < 2) {
    return false;
  }

  final joined = normalizedCells.join(' ');
  if (ExcelService._looksLikeDateRangeText(joined) &&
      normalizedCells.length <= 2) {
    return false;
  }

  return true;
}

({int headerRowIndex, int score, List<String> matchedFields})?
_structuredCandidateForRow(
  List<({int headerRowIndex, int score, List<String> matchedFields})>
  structuredCandidates, {
  required int headerRowIndex,
}) {
  for (final candidate in structuredCandidates) {
    if (candidate.headerRowIndex == headerRowIndex) {
      return candidate;
    }
  }

  return null;
}
