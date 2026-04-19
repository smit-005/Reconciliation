import 'package:flutter/cupertino.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../core/utils/normalize_utils.dart';
import '../core/utils/parse_utils.dart';
import '../models/excel_preview_data.dart';
import '../models/import_format_profile.dart';
import '../models/normalized_ledger_row.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import '../models/reconciliation_row.dart';
import 'import_profile_service.dart';
import 'reconciliation_service.dart';

class ExcelService {
  static Future<List<ImportFormatProfile>> getBuyerImportProfiles({
    required String buyerId,
    required String fileType,
  }) {
    return ImportProfileService.getProfiles(
      buyerId: buyerId,
      fileType: fileType,
    );
  }

  static Future<ImportFormatProfile?> findMatchingProfile({
    required String buyerId,
    required String fileType,
    required String sheetName,
    required String sampleSignature,
  }) async {
    final profiles = await getBuyerImportProfiles(
      buyerId: buyerId,
      fileType: fileType,
    );

    for (final profile in profiles) {
      final normalizedMapping = _normalizeCanonicalColumnMappingByType(
        _normalizeProfileColumnMapping(profile.columnMapping),
        type: _importTypeFromFileType(fileType),
      );
      final sheetPattern = profile.sheetNamePattern.trim().toLowerCase();
      final normalizedSheet = sheetName.trim().toLowerCase();
      final matchesSheet =
          sheetPattern.isEmpty || normalizedSheet.contains(sheetPattern);
      final matchesSignature = profile.sampleSignature.isNotEmpty &&
          profile.sampleSignature == sampleSignature;

      if (!_hasRequiredProfileMapping(
        fileType: fileType,
        columnMapping: normalizedMapping,
      )) {
        continue;
      }

      if (matchesSignature || matchesSheet) {
        return profile;
      }
    }

    return null;
  }

  static ExcelImportType _importTypeFromFileType(String fileType) {
    switch (fileType) {
      case 'tds26q':
        return ExcelImportType.tds26q;
      case 'genericLedger':
        return ExcelImportType.genericLedger;
      default:
        return ExcelImportType.purchase;
    }
  }

  static List<Map<String, dynamic>> excelToMapList(
      List<int> bytes, {
        ExcelImportType? forcedType,
      }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return [];
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: forcedType,
    );

    if (sheetInfo == null) {
      return [];
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    final headerRowIndex = sheetInfo.headerRowIndex;
    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: headerRowIndex,
      forcedType: sheetInfo.detectedType,
      headersTrusted: sheetInfo.headersTrusted,
    );
    debugPrint(
      'FINAL CANONICAL MAPPING => type=${sheetInfo.detectedType.name} '
      'headers=${mappedHeaders.whereType<String>().toList()}',
    );
    final dataStartIndex = sheetInfo.headersTrusted
        ? headerRowIndex + 1
        : headerRowIndex;

    final rows = <Map<String, dynamic>>[];

    for (int i = dataStartIndex; i < table.rows.length; i++) {
      final row = table.rows[i];

      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (int j = 0; j < mappedHeaders.length; j++) {
        final header = mappedHeaders[j];
        if (header == null || header.isEmpty) continue;

        final value = j < row.length ? row[j] : null;
        final normalizedValue = _normalizeCellValue(value);
        final textValue = normalizedValue.toString().trim();

        if (textValue.isNotEmpty) {
          isEmptyRow = false;
        }

        rowMap[header] = normalizedValue;
      }

      if (!isEmptyRow) {
        rows.add(rowMap);
      }
    }

    return rows;
  }

  static ({
    String sheetName,
    int headerRowIndex,
    List<dynamic> rawHeaderRow,
    bool headersTrusted,
  })? inspectExcelFile(
    List<int> bytes, {
    ExcelImportType? forcedType,
    String? preferredSheetName,
  }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    if (decoder.tables.isEmpty) return null;

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: forcedType,
      preferredSheetName: preferredSheetName,
    );
    if (sheetInfo == null) return null;

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) return null;

    return (
      sheetName: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      rawHeaderRow: table.rows[sheetInfo.headerRowIndex],
      headersTrusted: sheetInfo.headersTrusted,
    );
  }

  static List<Map<String, dynamic>> excelToMapListWithProfile(
    List<int> bytes, {
    required ExcelImportType forcedType,
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
  }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    final table = decoder.tables[sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    final normalizedColumnMapping = _normalizeCanonicalColumnMappingByType(
      columnMapping,
      type: forcedType,
    );
    debugPrint(
      'FINAL CANONICAL MAPPING => type=${forcedType.name} mapping=$normalizedColumnMapping',
    );

    final mappedHeaders = _buildMappedHeadersFromProfile(
      rawHeaderRow: table.rows[headerRowIndex],
      columnMapping: normalizedColumnMapping,
    );
    final dataStartIndex = headersTrusted ? headerRowIndex + 1 : headerRowIndex;
    final rows = <Map<String, dynamic>>[];

    for (int i = dataStartIndex; i < table.rows.length; i++) {
      final row = table.rows[i];
      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (int j = 0; j < mappedHeaders.length; j++) {
        final header = mappedHeaders[j];
        if (header == null || header.isEmpty) continue;

        final value = j < row.length ? row[j] : null;
        final normalizedValue = _normalizeCellValue(value);
        final textValue = normalizedValue.toString().trim();

        if (textValue.isNotEmpty) {
          isEmptyRow = false;
        }

        rowMap[header] = normalizedValue;
      }

      if (!isEmptyRow) {
        rows.add(rowMap);
      }
    }

    return rows;
  }

  static List<PurchaseRow> parsePurchaseRows(List<int> bytes) {
    final mapList = excelToMapList(
      bytes,
      forcedType: ExcelImportType.purchase,
    );

    final parsed = mapList.map((row) {
      final parsedRow = PurchaseRow.fromMap(row);

      if (parsedRow.partyName.trim().toLowerCase() == 'ganesh cattle feed') {
        debugPrint(
          'DEBUG PURCHASE PARSE => seller=${parsedRow.partyName}, '
          'rawDate=${(readAny(row, ['date', 'eom']) ?? '').trim()}, '
          'dateCol=${(row['date'] ?? '').toString().trim()}, '
          'eomCol=${(row['eom'] ?? '').toString().trim()}, '
          'month=${parsedRow.month}, '
          'basicAmount=${parsedRow.basicAmount}, '
          'billAmount=${parsedRow.billAmount}',
        );
      }

      return parsedRow;
    }).toList();
    final deduped = _dedupePurchaseRows(parsed);

    for (final row in deduped.take(10)) {
      debugPrint(
        'DEBUG PURCHASE => party=${row.partyName}, gst=${row.gstNo}, pan=${row.panNumber}, basic=${row.basicAmount}, bill=${row.billAmount}',
      );
    }

    return deduped;
  }

  static List<PurchaseRow> parsePurchaseRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
  }) {
    final mapList = excelToMapListWithProfile(
      bytes,
      forcedType: ExcelImportType.purchase,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
    );

    final parsed = mapList.map((row) => PurchaseRow.fromMap(row)).toList();
    return _dedupePurchaseRows(parsed);
  }

  static ExcelPreviewData? buildPreviewData(
    List<int> bytes, {
    required ExcelImportType fileType,
    required String fileName,
    Map<String, String> initialMappedColumns = const {},
    List<String> warnings = const [],
    double? confidenceScore,
    String? preferredSheetName,
  }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    if (decoder.tables.isEmpty) return null;

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: fileType,
      preferredSheetName: preferredSheetName,
    );
    if (sheetInfo == null) return null;

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) return null;

    final rawHeaderRow = table.rows[sheetInfo.headerRowIndex];
    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: fileType,
      headersTrusted: sheetInfo.headersTrusted,
    );
    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    final previewConfidence = confidenceScore ??
        _headerConfidenceScore(
          presentHeaders,
          type: fileType,
        );

    final columnKeys = <String>[];
    final columnLabels = <String, String>{};
    final suggestedMappings = <String, String>{};
    final normalizedInitialMapping = _normalizeCanonicalColumnMappingByType(
      _normalizeProfileColumnMapping(initialMappedColumns),
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

    for (int i = dataStartIndex;
        i < table.rows.length && sampleRows.length < 8;
        i++) {
      final row = table.rows[i];
      final sampleRow = <String, String>{};
      bool hasValue = false;

      for (int j = 0; j < columnKeys.length; j++) {
        final value = j < row.length ? _normalizeCellValue(row[j]) : '';
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
        ? _extractUnmappedRawHeaders(rawHeaderRow, mappedHeaders)
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

  static ExcelPreviewData? buildPreviewDataWithProfile(
    List<int> bytes, {
    required ExcelImportType fileType,
    required String fileName,
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    List<String> warnings = const [],
    double? confidenceScore,
  }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    if (sheetName.isEmpty) return null;
    final table = decoder.tables[sheetName];
    if (table == null || table.rows.isEmpty) return null;
    if (headerRowIndex < 0 || headerRowIndex >= table.rows.length) {
      return null;
    }

    final rawHeaderRow = table.rows[headerRowIndex];
    final mappedHeaders = _buildMappedHeadersFromProfile(
      rawHeaderRow: rawHeaderRow,
      columnMapping: _normalizeCanonicalColumnMappingByType(
        columnMapping,
        type: fileType,
      ),
    );
    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    final previewConfidence = confidenceScore ??
        _headerConfidenceScore(
          presentHeaders,
          type: fileType,
        );

    final columnKeys = <String>[];
    final columnLabels = <String, String>{};
    final suggestedMappings = <String, String>{};
    final normalizedInitialMapping = _normalizeCanonicalColumnMappingByType(
      _normalizeProfileColumnMapping(columnMapping),
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

    final dataStartIndex =
        headersTrusted ? headerRowIndex + 1 : headerRowIndex;
    final sampleRows = <Map<String, String>>[];

    for (int i = dataStartIndex;
        i < table.rows.length && sampleRows.length < 8;
        i++) {
      final row = table.rows[i];
      final sampleRow = <String, String>{};
      bool hasValue = false;

      for (int j = 0; j < columnKeys.length; j++) {
        final value = j < row.length ? _normalizeCellValue(row[j]) : '';
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
        ? _extractUnmappedRawHeaders(rawHeaderRow, mappedHeaders)
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

  static List<Tds26QRow> parseTds26QRows(List<int> bytes) {
    final mapList = excelToMapList(
      bytes,
      forcedType: ExcelImportType.tds26q,
    );

    final parsed = mapList.map((row) => Tds26QRow.fromMap(row)).toList();
    final deduped = _dedupeTdsRows(parsed);

    for (final row in deduped.take(5)) {
      debugPrint(
        'DEBUG 26Q => month=${row.month}, party=${row.deducteeName}, '
            'pan=${row.panNumber}, deducted=${row.deductedAmount}, tds=${row.tds}, section=${row.section}',
      );
    }

    return deduped;
  }

  static List<Tds26QRow> parseTds26QRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
  }) {
    final mapList = excelToMapListWithProfile(
      bytes,
      forcedType: ExcelImportType.tds26q,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
    );

    final parsed = mapList.map((row) => Tds26QRow.fromMap(row)).toList();
    return _dedupeTdsRows(parsed);
  }

  static List<NormalizedLedgerRow> parseGenericLedgerRows(
    List<int> bytes, {
    required String defaultSection,
    String sourceFileName = '',
  }) {
    final mapList = excelToMapList(
      bytes,
      forcedType: ExcelImportType.genericLedger,
    );

    final parsed = mapList
        .map(
          (row) => NormalizedLedgerRow.fromMap(
            row,
            sourceFileName: sourceFileName,
            defaultSection: defaultSection,
          ),
        )
        .toList();

    return _dedupeNormalizedLedgerRows(parsed);
  }

  static List<NormalizedLedgerRow> parseGenericLedgerRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    required String defaultSection,
    String sourceFileName = '',
  }) {
    final mapList = excelToMapListWithProfile(
      bytes,
      forcedType: ExcelImportType.genericLedger,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
    );

    final parsed = mapList
        .map(
          (row) => NormalizedLedgerRow.fromMap(
            row,
            sourceFileName: sourceFileName,
            defaultSection: defaultSection,
          ),
        )
        .toList();

    return _dedupeNormalizedLedgerRows(parsed);
  }

  static ExcelValidationResult validatePurchaseFile(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.purchase,
    );

    if (sheetInfo == null) {
      return ExcelValidationResult.invalid(
        'Could not detect a valid purchase register sheet.',
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return ExcelValidationResult.invalid(
        'Detected purchase sheet is empty.',
      );
    }

    final rawHeaderRow = table.rows[sheetInfo.headerRowIndex];
    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: ExcelImportType.purchase,
      headersTrusted: sheetInfo.headersTrusted,
    );
    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    final unmappedRawHeaders = _extractUnmappedRawHeaders(
      rawHeaderRow,
      mappedHeaders,
    );
    final confidenceScore = _headerConfidenceScore(
      presentHeaders,
      type: ExcelImportType.purchase,
    );
    final warnings = <String>[];

    debugPrint('PURCHASE PRESENT HEADERS => $presentHeaders');

    final hasPurchaseDate = _hasPurchaseDateColumn(presentHeaders);
    final hasPurchaseAmount = _hasPurchaseAmountColumn(presentHeaders);

    debugPrint('FINAL HEADERS => $presentHeaders');
    debugPrint('HAS DATE => $hasPurchaseDate');
    debugPrint('HAS AMOUNT => $hasPurchaseAmount');

    final missing = <String>[
      if (!hasPurchaseDate) 'Date / EOM',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!presentHeaders.contains('bill_no')) 'Bill No',
      if (!hasPurchaseAmount) 'Amount Column',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Manual mapping is required instead of auto-parsing.',
      );
      return ExcelValidationResult.valid(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
        warnings: warnings,
        confidenceScore: confidenceScore,
        requiresManualMapping: true,
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (missing.isNotEmpty) {
      return ExcelValidationResult.invalid(
        'Missing required purchase columns: ${missing.join(', ')}',
      );
    }

    if (_hasSuspiciousAmountCollision(mappedHeaders, rawHeaderRow)) {
      warnings.add(
        'Amount columns could not be clearly distinguished. Bill Amount will be used as the primary purchase amount.',
      );
    }

    if (confidenceScore < 0.65) {
      warnings.add(
        'Low header-detection confidence. Review column mapping if imported values look incorrect.',
      );
    }

    final parsed = parsePurchaseRows(bytes);

    if (parsed.isEmpty) {
      return ExcelValidationResult.invalid(
        'No valid purchase rows found after parsing.',
      );
    }

    final validAmountRows = parsed.where((e) => e.basicAmount > 0).length;
    if (validAmountRows == 0) {
      return ExcelValidationResult.invalid(
        'Purchase amount column could not be read correctly. All values are zero.',
      );
    }

    final billAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.billAmount);
    final basicAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.basicAmount);
    warnings.addAll(_buildPurchaseWarnings(parsed));

    if (billAmountSum > 0 && (billAmountSum - basicAmountSum).abs() < 1) {
      warnings.add(
        'Single amount column detected (Bill Amount used as Basic Amount)',
      );
    }

      return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
      warnings: warnings,
      confidenceScore: confidenceScore,
      requiresManualMapping: confidenceScore < 0.50,
      unmappedRawHeaders: unmappedRawHeaders,
    );
  }

  static ExcelValidationResult validateTds26QFile(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final selectableSheets = _list26QSelectableSheetsFromDecoder(decoder);
    final preferred26QSheet = _detectBest26QSheet(
      {
        for (final entry in decoder.tables.entries) entry.key: entry.value.rows,
      },
    );

    if (preferred26QSheet == null) {
      return ExcelValidationResult.selectionRequired(
        candidateSheets: selectableSheets,
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.tds26q,
      preferredSheetName: preferred26QSheet,
    );

    if (sheetInfo == null) {
      return ExcelValidationResult.invalid(
        'Could not detect a valid 26Q sheet.',
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return ExcelValidationResult.invalid(
        'Detected 26Q sheet is empty.',
      );
    }

    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: ExcelImportType.tds26q,
      headersTrusted: sheetInfo.headersTrusted,
    );

    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    final confidenceScore = _headerConfidenceScore(
      presentHeaders,
      type: ExcelImportType.tds26q,
    );
    final warnings = <String>[];
    final unmappedRawHeaders = _extractUnmappedRawHeaders(
      table.rows[sheetInfo.headerRowIndex],
      mappedHeaders,
    );

    final missing = <String>[
      if (!presentHeaders.contains('date_month')) 'Date / Month',
      if (!presentHeaders.contains('party_name') &&
          !presentHeaders.contains('pan_number'))
        'Party Name or PAN',
      if (!presentHeaders.contains('amount_paid')) 'Amount Paid',
      if (!presentHeaders.contains('tds_amount'))
        'TDS',
      if (!presentHeaders.contains('section')) 'Section',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Manual mapping is required instead of auto-parsing.',
      );
      return ExcelValidationResult.valid(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(
          table.rows[sheetInfo.headerRowIndex],
          mappedHeaders,
        ),
        warnings: warnings,
        confidenceScore: confidenceScore,
        requiresManualMapping: true,
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (missing.isNotEmpty) {
      return ExcelValidationResult.invalid(
        'Missing required 26Q columns: ${missing.join(', ')}',
      );
    }

    final parsed = parseTds26QRows(bytes);

    if (parsed.isEmpty) {
      return ExcelValidationResult.invalid(
        'No valid 26Q rows found after parsing.',
      );
    }

    final validAmountRows =
        parsed.where((e) => e.deductedAmount > 0 || e.tds > 0).length;
    if (validAmountRows == 0) {
      return ExcelValidationResult.invalid(
        'Amount Paid / TDS Amount columns could not be read correctly. All values are zero.',
      );
    }

    if (confidenceScore < 0.65) {
      warnings.add(
        'Low header-detection confidence. Review column mapping if imported values look incorrect.',
      );
    }

    warnings.addAll(_buildTdsWarnings(parsed));

      return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: _headerPreviewMap(
        table.rows[sheetInfo.headerRowIndex],
        mappedHeaders,
      ),
      warnings: warnings,
      confidenceScore: confidenceScore,
      requiresManualMapping: confidenceScore < 0.50,
      unmappedRawHeaders: unmappedRawHeaders,
    );
  }

  static ExcelValidationResult validateGenericLedgerFile(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.genericLedger,
    );

    if (sheetInfo == null) {
      return ExcelValidationResult.invalid(
        'Could not detect a valid ledger sheet.',
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return ExcelValidationResult.invalid(
        'Detected ledger sheet is empty.',
      );
    }

    final rawHeaderRow = table.rows[sheetInfo.headerRowIndex];
    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: ExcelImportType.genericLedger,
      headersTrusted: sheetInfo.headersTrusted,
    );
    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    final confidenceScore = _headerConfidenceScore(
      presentHeaders,
      type: ExcelImportType.genericLedger,
    );
    final warnings = <String>[];
    final unmappedRawHeaders = _extractUnmappedRawHeaders(
      rawHeaderRow,
      mappedHeaders,
    );

    final hasDate = presentHeaders.contains('date');
    final hasAmount = presentHeaders.contains('amount');

    final missing = <String>[
      if (!hasDate) 'Date',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!hasAmount) 'Amount',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Manual mapping is required instead of auto-parsing.',
      );
      return ExcelValidationResult.valid(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
        warnings: warnings,
        confidenceScore: confidenceScore,
        requiresManualMapping: true,
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (missing.isNotEmpty) {
      return ExcelValidationResult.invalid(
        'Missing required ledger columns: ${missing.join(', ')}',
      );
    }

    return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
      warnings: warnings,
      confidenceScore: confidenceScore,
      requiresManualMapping: confidenceScore < 0.60,
      unmappedRawHeaders: unmappedRawHeaders,
    );
  }

  static String? detectBuyerNameFromSheet(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) return null;

    final table = decoder.tables.values.first;
    if (table.rows.isEmpty) return null;

    for (int i = 0; i < table.rows.length && i < 5; i++) {
      final row = table.rows[i];

      for (final cell in row) {
        final text = cell?.toString().trim();

        if (text != null && text.isNotEmpty) {
          final lower = text.toLowerCase();

          if (!lower.contains('date') &&
              !lower.contains('party') &&
              !lower.contains('bill')) {
            return text;
          }
        }
      }
    }

    return null;
  }

  static String? detectGstNoFromPurchase(List<PurchaseRow> rows) {
    if (rows.isEmpty) return null;

    final gstNos = rows
        .map((e) => e.gstNo.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    if (gstNos.isEmpty) return null;
    return gstNos.first;
  }

  static List<String> getSheetHeaders(
      List<int> bytes, {
        ExcelImportType? forcedType,
      }) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return [];
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: forcedType,
    );

    if (sheetInfo == null) {
      return [];
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: sheetInfo.detectedType,
      headersTrusted: sheetInfo.headersTrusted,
    );

    return mappedHeaders.map((e) => e ?? '').toList();
  }

  static bool isPurchaseRegisterFormat(List<int> bytes) {
    final result = validatePurchaseFile(bytes);
    return result.isValid;
  }

  static bool isTds26QFormat(List<int> bytes) {
    final result = validateTds26QFile(bytes);
    return result.isValid;
  }

  static ({
  String sheetName,
  int headerRowIndex,
  ExcelImportType detectedType,
  bool headersTrusted,
  })? _findBestSheetAndHeader(
      SpreadsheetDecoder decoder, {
        ExcelImportType? forcedType,
        String? preferredSheetName,
      }) {
    final preferred26QSheet = preferredSheetName ??
        (forcedType == ExcelImportType.tds26q
        ? _detectBest26QSheet(
            {
              for (final entry in decoder.tables.entries)
                entry.key: entry.value.rows,
            },
          )
        : null);

    if (forcedType == ExcelImportType.tds26q &&
        preferredSheetName == null &&
        (preferred26QSheet == null || preferred26QSheet.isEmpty)) {
      debugPrint(
        '26Q SHEET SELECTION => requires user selection, auto-selection skipped',
      );
      return null;
    }
    ({
    String sheetName,
    int headerRowIndex,
    ExcelImportType detectedType,
    bool headersTrusted,
    int score,
    })? best;

    for (final entry in decoder.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;

      if (table.rows.isEmpty) continue;
      if (preferredSheetName != null && sheetName != preferredSheetName) {
        continue;
      }
      if (forcedType == ExcelImportType.tds26q) {
        if (preferred26QSheet != null && preferred26QSheet.isNotEmpty) {
          if (sheetName != preferred26QSheet) continue;
        } else {
          if (_isLikely26QReferenceSheet(table.rows)) {
            debugPrint('Rejected $sheetName as reference sheet');
            debugPrint('Skipping reference sheet: $sheetName');
            continue;
          }
        }
      }

      for (int i = 0; i < table.rows.length && i < 20; i++) {
        final row = table.rows[i];

        int purchaseScore = _scoreHeaderRow(
          row,
          type: ExcelImportType.purchase,
        );
        bool purchaseHeadersTrusted = purchaseScore > 0;

        int tdsScore = _scoreHeaderRow(
          row,
          type: ExcelImportType.tds26q,
        );
        bool tdsHeadersTrusted = tdsScore > 0;

        if (purchaseScore < 40 && i + 1 < table.rows.length) {
          final inferredHeaders = _inferMappedHeadersFromDataRows(
            table.rows.skip(i).take(8).toList(),
            type: ExcelImportType.purchase,
          );
          final inferredSet = inferredHeaders.whereType<String>().toSet();
          final inferredScore =
              (_headerConfidenceScore(
                        inferredSet,
                        type: ExcelImportType.purchase,
                      ) *
                      100)
                  .round();
          if (inferredScore > 70 && inferredScore > purchaseScore) {
            purchaseScore = inferredScore;
            purchaseHeadersTrusted = false;
          }
        }

        if (tdsScore < 40 && i + 1 < table.rows.length) {
          final inferredHeaders = _inferMappedHeadersFromDataRows(
            table.rows.skip(i).take(8).toList(),
            type: ExcelImportType.tds26q,
          );
          final inferredSet = inferredHeaders.whereType<String>().toSet();
          final inferredScore =
              (_headerConfidenceScore(
                        inferredSet,
                        type: ExcelImportType.tds26q,
                      ) *
                      100)
                  .round();
          if (inferredScore > 70 && inferredScore > tdsScore) {
            tdsScore = inferredScore;
            tdsHeadersTrusted = false;
          }
        }

        purchaseScore += _sheetNameBonus(
          sheetName,
          type: ExcelImportType.purchase,
        );

        tdsScore += _sheetNameBonus(
          sheetName,
          type: ExcelImportType.tds26q,
        );

        if (forcedType == ExcelImportType.purchase) {
          if (purchaseScore >= 40 &&
              (best == null || purchaseScore > best.score)) {
              best = (
              sheetName: sheetName,
              headerRowIndex: i,
              detectedType: ExcelImportType.purchase,
              headersTrusted: purchaseHeadersTrusted,
              score: purchaseScore,
              );
            }
          } else if (forcedType == ExcelImportType.tds26q) {
            if (tdsScore >= 40 && (best == null || tdsScore > best.score)) {
              best = (
              sheetName: sheetName,
              headerRowIndex: i,
              detectedType: ExcelImportType.tds26q,
              headersTrusted: tdsHeadersTrusted,
              score: tdsScore,
              );
            }
          } else {
            if (purchaseScore >= 40 &&
                (best == null || purchaseScore > best.score)) {
              best = (
              sheetName: sheetName,
              headerRowIndex: i,
              detectedType: ExcelImportType.purchase,
              headersTrusted: purchaseHeadersTrusted,
              score: purchaseScore,
              );
            }

            if (tdsScore >= 40 && (best == null || tdsScore > best.score)) {
              best = (
              sheetName: sheetName,
              headerRowIndex: i,
              detectedType: ExcelImportType.tds26q,
              headersTrusted: tdsHeadersTrusted,
              score: tdsScore,
              );
            }
        }
      }
    }

    if (best == null) return null;

    final bestTable = decoder.tables[best.sheetName];
    final confidenceScore = bestTable == null || bestTable.rows.isEmpty
        ? 0.0
        : _headerConfidenceScore(
            _resolveMappedHeaders(
              rows: bestTable.rows,
              headerRowIndex: best.headerRowIndex,
              forcedType: best.detectedType,
              headersTrusted: best.headersTrusted,
            ).whereType<String>().toSet(),
            type: best.detectedType,
          );

    debugPrint('DETECTION CHOSEN SHEET => ${best.sheetName}');
    debugPrint('DETECTION HEADER ROW => ${best.headerRowIndex}');
    debugPrint('DETECTION CONFIDENCE => $confidenceScore');

    return (
    sheetName: best.sheetName,
    headerRowIndex: best.headerRowIndex,
    detectedType: best.detectedType,
    headersTrusted: best.headersTrusted,
    );
  }

  static double _score26QSheet(String sheetName, List<List<dynamic>> rows) {
    if (rows.isEmpty) return double.negativeInfinity;

    var score = 0.0;
    final normalizedSheetName = sheetName.trim().toLowerCase();

    if (normalizedSheetName.contains('deduction')) score += 60;
    if (normalizedSheetName.contains('deductee')) score += 10;
    if (_containsPanPattern(rows)) score += 20;
    if (_containsSectionValues(rows)) score += 30;
    if (_containsDateLikeValues(rows)) score += 20;
    if (_containsLargeAmountColumn(rows)) score += 35;
    if (_containsTdsAmountColumn(rows)) score += 40;

    if (_isLikely26QReferenceSheet(rows)) {
      score -= 80;
      debugPrint(
        '26Q SHEET SCORE => $sheetName treated as reference/master sheet',
      );
    }

    return score;
  }

  static String? _detectBest26QSheet(Map<String, List<List<dynamic>>> sheets) {
    String? bestSheet;
    double bestScore = double.negativeInfinity;
    double secondBestScore = double.negativeInfinity;

    for (final entry in sheets.entries) {
      final score = _score26QSheet(entry.key, entry.value);
      debugPrint(
        '26Q SHEET SCORE => ${entry.key}: $score '
        '(PAN:${_containsPanPattern(entry.value)} '
        'SEC:${_containsSectionValues(entry.value)} '
        'TDS:${_containsTdsAmountColumn(entry.value)})',
      );

      if (score > bestScore) {
        secondBestScore = bestScore;
        bestScore = score;
        bestSheet = entry.key;
      } else if (score > secondBestScore) {
        secondBestScore = score;
      }
    }

    final scoreGap = bestScore - secondBestScore;
    final isWeakSelection =
        bestSheet == null || bestScore <= 70 || scoreGap <= 10;

    if (isWeakSelection) {
      debugPrint(
        '26Q SHEET SELECTION => weak confidence, no sheet auto-selected '
        '(best=${bestSheet ?? 'none'}, score=$bestScore, gap=$scoreGap)',
      );
      return null;
    }

    debugPrint('26Q SHEET SELECTION => selected $bestSheet');
    return bestSheet;
  }

  static List<String> list26QSelectableSheets(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    if (decoder.tables.isEmpty) return const [];
    return _list26QSelectableSheetsFromDecoder(decoder);
  }

  static List<String> _list26QSelectableSheetsFromDecoder(
    SpreadsheetDecoder decoder,
  ) {
    final selectable = decoder.tables.entries
        .where((entry) => entry.value.rows.isNotEmpty)
        .where((entry) => !_isLikely26QReferenceSheet(entry.value.rows))
        .map((entry) => entry.key)
        .toList();

    if (selectable.isNotEmpty) {
      return selectable;
    }

    return decoder.tables.entries
        .where((entry) => entry.value.rows.isNotEmpty)
        .map((entry) => entry.key)
        .toList();
  }

  static bool _isLikely26QReferenceSheet(List<List<dynamic>> rows) {
    final headerRow = _findLikely26QHeaderRow(rows);
    final normalizedHeaders = headerRow
        .map((cell) => _normalizeLooseText(cell?.toString() ?? ''))
        .where((value) => value.isNotEmpty)
        .toList();

    final hasReferenceHeaders = normalizedHeaders.any(
          (header) => header == 'name' || header.contains('deductee'),
        ) &&
        normalizedHeaders.any((header) => header == 'pan' || header.contains('pan')) &&
        normalizedHeaders.any(
          (header) =>
              header.contains('type of deductee') ||
              header.contains('deductee type'),
        ) &&
        normalizedHeaders.any(
          (header) =>
              header.contains('pan validation result') ||
              header.contains('pan status') ||
              header.contains('validation result'),
        );

    if (!hasReferenceHeaders) return false;

    final hasTransactionSignals = _containsSectionValues(rows) ||
        _containsDateLikeValues(rows) ||
        _containsLargeAmountColumn(rows) ||
        _containsTdsAmountColumn(rows);

    if (!hasTransactionSignals) {
      debugPrint('Rejected ${headerRow.join(' | ')} as reference sheet');
    }

    return !hasTransactionSignals;
  }

  static bool _containsPanPattern(List<List<dynamic>> rows) {
    for (final row in rows.take(25)) {
      for (final cell in row) {
        if (_looksLikePanText(cell?.toString() ?? '')) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _containsSectionValues(List<List<dynamic>> rows) {
    for (final row in rows.take(25)) {
      for (final cell in row) {
        if (_looksLikeSectionText(cell?.toString() ?? '')) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _containsDateLikeValues(List<List<dynamic>> rows) {
    for (final row in rows.take(25)) {
      for (final cell in row) {
        if (cell is DateTime) return true;
        if (cell is num && _looksLikeExcelDate(cell)) return true;
        if (_looksLikeDateText(cell?.toString() ?? '')) return true;
      }
    }
    return false;
  }

  static bool _containsLargeAmountColumn(List<List<dynamic>> rows) {
    final headerIndex = _findLikely26QHeaderRowIndex(rows);
    final headerRow = rows[headerIndex];
    final dataRows = rows.skip(headerIndex + 1).take(20).toList();
    final width =
        rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);

    for (int column = 0; column < width; column++) {
      final header = column < headerRow.length
          ? _normalizeLooseText(headerRow[column]?.toString() ?? '')
          : '';
      final headerHintsAmountPaid = header.contains('amount paid') ||
          header.contains('amount credited') ||
          header.contains('amount paid credited') ||
          header.contains('paid credited');

      int numericCount = 0;
      double maxValue = 0;

      for (final row in dataRows) {
        if (column >= row.length) continue;
        final value = _tryParseNumericCell(row[column]);
        if (value == null) continue;
        numericCount++;
        if (value > maxValue) maxValue = value;
      }

      final avg = numericCount == 0 ? 0 : maxValue / numericCount;

      if ((headerHintsAmountPaid && numericCount >= 2) ||
          (numericCount >= 3 &&
              maxValue >= 500 &&
              avg > 100 &&
              maxValue > avg * 2)) {
        return true;
      }
    }

    return false;
  }

  static bool _containsTdsAmountColumn(List<List<dynamic>> rows) {
    final headerIndex = _findLikely26QHeaderRowIndex(rows);
    final headerRow = rows[headerIndex];
    final dataRows = rows.skip(headerIndex + 1).take(20).toList();
    final width =
        rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);

    for (int column = 0; column < width; column++) {
      final header = column < headerRow.length
          ? _normalizeLooseText(headerRow[column]?.toString() ?? '')
          : '';
      final headerHintsTds = header == 'tds' ||
          header.contains('tds amount') ||
          header.contains('deducted amount') ||
          header.contains('deducted and deposited tax') ||
          header.contains('tax deducted');

      int numericCount = 0;
      double total = 0;

      for (final row in dataRows) {
        if (column >= row.length) continue;
        final value = _tryParseNumericCell(row[column]);
        if (value == null) continue;
        numericCount++;
        total += value;
      }

      final avg = numericCount == 0 ? 0 : total / numericCount;

      if ((headerHintsTds && numericCount >= 2) ||
          (numericCount >= 3 &&
              total > 0 &&
              avg > 0 &&
              avg < 50000 &&
              total < 1000000)) {
        return true;
      }
    }

    return false;
  }

  static List<dynamic> _findLikely26QHeaderRow(List<List<dynamic>> rows) {
    return rows[_findLikely26QHeaderRowIndex(rows)];
  }

  static int _findLikely26QHeaderRowIndex(List<List<dynamic>> rows) {
    var bestIndex = 0;
    var bestScore = -1;

    for (int i = 0; i < rows.length && i < 10; i++) {
      final score = _scoreHeaderRow(
        rows[i],
        type: ExcelImportType.tds26q,
      );
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  static double? _tryParseNumericCell(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final text = value.toString().replaceAll(',', '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String inferSection(
    double amount,
    double tds, {
    String? sectionHint,
  }) {
    final normalizedHint = normalizeSection(sectionHint ?? '');
    if (normalizedHint == '194Q' ||
        normalizedHint == '194C' ||
        normalizedHint == '194J' ||
        normalizedHint == '194I' ||
        normalizedHint == '194A' ||
        normalizedHint == '194H') {
      return normalizedHint;
    }

    if (amount <= 0 || tds <= 0) return 'UNKNOWN';

    final rate = (tds / amount) * 100;

    if (rate >= 0.05 && rate <= 0.2 && amount >= 10000) return '194Q';
    if (rate >= 0.5 && rate <= 2.5 && amount >= 1000) return '194C';
    if (rate >= 8 && rate <= 12 && amount >= 1000) return '194J';

    return 'UNKNOWN';
  }

  static int _sheetNameBonus(
      String sheetName, {
        required ExcelImportType type,
      }) {
    final name = sheetName.trim().toLowerCase();

    if (type == ExcelImportType.purchase) {
      int bonus = 0;
      if (name.contains('purchase')) bonus += 20;
      if (name.contains('register')) bonus += 10;
      if (name.contains('sales')) bonus -= 30;
      if (name.contains('deduction')) bonus -= 20;
      if (name.contains('challan')) bonus -= 20;
      return bonus;
    }

    if (type == ExcelImportType.genericLedger) {
      int bonus = 0;
      if (name.contains('ledger')) bonus += 20;
      if (name.contains('register')) bonus += 10;
      if (name.contains('purchase')) bonus += 5;
      if (name.contains('summary')) bonus -= 10;
      if (name.contains('challan')) bonus -= 20;
      return bonus;
    }

    int bonus = 0;
    if (name.contains('deduction')) bonus += 30;
    if (name.contains('deductee')) bonus += 10;
    if (name.contains('26q')) bonus += 10;
    if (name.contains('challan')) bonus -= 20;
    if (name.contains('deductor')) bonus -= 15;
    return bonus;
  }

  static int _scoreHeaderRow(
      List<dynamic> row, {
        required ExcelImportType type,
      }) {
    final mappedHeaders = _buildMappedHeaders(
      row,
      forcedType: type,
    );

    final presentHeaders = mappedHeaders.whereType<String>().toSet();

    if (type == ExcelImportType.purchase) {
      int score = 0;
      if (presentHeaders.contains('date') || presentHeaders.contains('eom')) {
        score += 30;
      }
      if (presentHeaders.contains('party_name')) score += 30;
      if (presentHeaders.contains('bill_no')) score += 30;
      if (presentHeaders.contains('bill_amount')) score += 40;
      if (presentHeaders.contains('basic_amount')) score += 20;
      if (presentHeaders.contains('gst_no')) score += 5;
      if (presentHeaders.contains('pan_number')) score += 5;
      if (presentHeaders.length >= 5) score += 20;
      return score;
    }

    if (type == ExcelImportType.genericLedger) {
      int score = 0;
      if (presentHeaders.contains('date')) score += 25;
      if (presentHeaders.contains('party_name')) score += 25;
      if (presentHeaders.contains('amount')) score += 30;
      if (presentHeaders.contains('pan_number')) score += 10;
      if (presentHeaders.contains('gst_no')) score += 5;
      if (presentHeaders.contains('bill_no')) score += 5;
      if (presentHeaders.contains('description')) score += 5;
      return score;
    }

    int score = 0;
    if (presentHeaders.contains('date_month')) score += 20;
    if (presentHeaders.contains('pan_number')) score += 20;
    if (presentHeaders.contains('amount_paid')) score += 25;
    if (presentHeaders.contains('tds_amount')) score += 25;
    if (presentHeaders.contains('party_name')) score += 10;
    if (presentHeaders.contains('section')) score += 20;
    return score;
  }

  static bool _hasPurchaseDateColumn(Set<String> presentHeaders) {
    return presentHeaders.contains('date') || presentHeaders.contains('eom');
  }

  static bool _hasPurchaseAmountColumn(Set<String> presentHeaders) {
    return presentHeaders.contains('bill_amount') ||
        presentHeaders.contains('basic_amount');
  }

  static double _headerConfidenceScore(
    Set<String> presentHeaders, {
    required ExcelImportType type,
  }) {
    if (type == ExcelImportType.purchase) {
      int matchedRequired = 0;
      if (_hasPurchaseDateColumn(presentHeaders)) matchedRequired++;
      if (presentHeaders.contains('party_name')) matchedRequired++;
      if (presentHeaders.contains('bill_no')) matchedRequired++;
      if (_hasPurchaseAmountColumn(presentHeaders)) matchedRequired++;

      final coverage = matchedRequired / 4.0;
      final bonusFields = <String>{
        'gst_no',
        'pan_number',
        'productname',
        'basic_amount',
        'eom',
      }.intersection(presentHeaders).length;
      final bonus = (bonusFields / 5.0) * 0.15;
      return (coverage + bonus).clamp(0.0, 1.0);
    }

    if (type == ExcelImportType.genericLedger) {
      int matchedRequired = 0;
      if (presentHeaders.contains('date')) matchedRequired++;
      if (presentHeaders.contains('party_name')) matchedRequired++;
      if (presentHeaders.contains('amount')) matchedRequired++;

      final coverage = matchedRequired / 3.0;
      final bonusFields = <String>{
        'pan_number',
        'gst_no',
        'bill_no',
        'description',
      }.intersection(presentHeaders).length;
      final bonus = (bonusFields / 4.0) * 0.15;
      return (coverage + bonus).clamp(0.0, 1.0);
    }

    int matchedRequired = 0;
    if (presentHeaders.contains('date_month')) matchedRequired++;
    if (presentHeaders.contains('pan_number')) matchedRequired++;
    if (presentHeaders.contains('amount_paid')) matchedRequired++;
    if (presentHeaders.contains('tds_amount')) matchedRequired++;
    if (presentHeaders.contains('section')) matchedRequired++;

    return (matchedRequired / 5.0).clamp(0.0, 1.0);
  }

  static List<String> _extractUnmappedRawHeaders(
    List<dynamic> rawHeaders,
    List<String?> mappedHeaders,
  ) {
    final result = <String>[];

    for (int i = 0; i < rawHeaders.length; i++) {
      final raw = rawHeaders[i]?.toString().trim() ?? '';
      final mapped = i < mappedHeaders.length ? mappedHeaders[i] : null;

      if (raw.isNotEmpty && (mapped == null || mapped.isEmpty)) {
        result.add(raw);
      }
    }

    return result;
  }

  static String buildSampleSignature(
    String sheetName,
    List<dynamic> rawHeaderRow,
  ) {
    final headerText = rawHeaderRow
        .map((e) => e?.toString().trim().toLowerCase() ?? '')
        .where((e) => e.isNotEmpty)
        .join('|');
    return '${sheetName.trim().toLowerCase()}::$headerText';
  }

  static List<String?> _resolveMappedHeaders({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required ExcelImportType forcedType,
    required bool headersTrusted,
  }) {
    if (headersTrusted) {
      return _buildMappedHeaders(
        rows[headerRowIndex],
        forcedType: forcedType,
      );
    }

    return _inferMappedHeadersFromDataRows(
      rows.skip(headerRowIndex).take(8).toList(),
      type: forcedType,
    );
  }

  static List<String?> _buildMappedHeadersFromProfile({
    required List<dynamic> rawHeaderRow,
    required Map<String, String> columnMapping,
  }) {
    final normalizedMapping = _normalizeProfileColumnMapping(columnMapping);
    final mapped = <String?>[];

    for (int i = 0; i < rawHeaderRow.length; i++) {
      final raw = rawHeaderRow[i]?.toString().trim() ?? '';
      final columnKey = 'COL_$i';
      String? canonical;

      for (final entry in normalizedMapping.entries) {
        if (entry.value == raw || entry.value == columnKey) {
          canonical = entry.key;
          break;
        }
      }

      mapped.add(canonical);
    }

    return mapped;
  }

  static Map<String, String> _normalizeProfileColumnMapping(
    Map<String, String> columnMapping,
  ) {
    const canonicalKeys = {
      'date',
      'eom',
      'bill_no',
      'party_name',
      'basic_amount',
      'bill_amount',
      'gst_no',
      'pan_number',
      'productname',
      'date_month',
      'amount',
      'amount_paid',
      'tds_amount',
      'section',
      'description',
    };

    final result = <String, String>{};

    for (final entry in columnMapping.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;

      final normalizedKey = _normalizeProfileCanonicalKey(key);
      final normalizedValue = _normalizeProfileCanonicalKey(value);

      if (canonicalKeys.contains(normalizedKey)) {
        result[normalizedKey] = value;
      } else if (canonicalKeys.contains(normalizedValue)) {
        result[normalizedValue] = key;
      }
    }

    return result;
  }

  static Map<String, String> _normalizeCanonicalColumnMappingByType(
    Map<String, String> columnMapping, {
    required ExcelImportType type,
  }) {
    final normalized = <String, String>{};

    for (final entry in columnMapping.entries) {
      final key = _normalizeProfileCanonicalKey(entry.key.trim());
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      normalized[key] = value;
    }

    if (type == ExcelImportType.tds26q) {
      normalized.remove('description');
      normalized.remove('productname');
      normalized.remove('amount');
    }

    if (type == ExcelImportType.genericLedger) {
      final amount = normalized.remove('amount_paid');
      if (amount != null && amount.isNotEmpty) {
        normalized['amount'] = amount;
      }

      final description = normalized.remove('productname');
      if (description != null && description.isNotEmpty) {
        normalized['description'] = description;
      }

      normalized.remove('tds_amount');
      normalized.remove('section');
      normalized.remove('date_month');
      normalized.remove('eom');
    }

    return normalized;
  }

  static String _normalizeProfileCanonicalKey(String key) {
    switch (key) {
      case 'pan_no':
        return 'pan_number';
      case 'tds':
        return 'tds_amount';
      case 'deducted_amount':
        return 'amount_paid';
      default:
        return key;
    }
  }

  static bool _hasRequiredProfileMapping({
    required String fileType,
    required Map<String, String> columnMapping,
  }) {
    if (fileType == 'tds26q') {
      final hasPartyIdentity = columnMapping.containsKey('party_name') ||
          columnMapping.containsKey('pan_number');
      return columnMapping.containsKey('date_month') &&
          hasPartyIdentity &&
          columnMapping.containsKey('amount_paid') &&
          columnMapping.containsKey('tds_amount') &&
          columnMapping.containsKey('section');
    }

    if (fileType == 'genericLedger') {
      return columnMapping.containsKey('date') &&
          columnMapping.containsKey('party_name') &&
          columnMapping.containsKey('amount');
    }

    return true;
  }

  static List<String?> _inferMappedHeadersFromDataRows(
    List<List<dynamic>> rows, {
    required ExcelImportType type,
  }) {
    if (rows.isEmpty) return const [];

    final width =
        rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    final mapped = List<String?>.filled(width, null);
    final assigned = <String>{};
    int? bestSectionColumn;
    int bestSectionScore = 0;

    if (type == ExcelImportType.tds26q) {
      for (int c = 0; c < width; c++) {
        final samples = rows
            .take(8)
            .map(
              (row) => c < row.length ? (row[c]?.toString().trim() ?? '') : '',
            )
            .where((e) => e.isNotEmpty)
            .toList();

        if (samples.isEmpty) continue;

        final score = _scoreSectionColumnSamples(samples);
        if (score > bestSectionScore) {
          bestSectionScore = score;
          bestSectionColumn = c;
        }
      }

      if (bestSectionColumn != null && bestSectionScore >= 8) {
        mapped[bestSectionColumn] = 'section';
        assigned.add('section');
      }
    }

    if (type == ExcelImportType.genericLedger) {
      final prioritizedColumns = List<int>.generate(width, (index) => index)
        ..sort((a, b) {
          final aSamples = _columnSamples(rows, a);
          final bSamples = _columnSamples(rows, b);
          final aProfile = _analyzeColumnProfile(aSamples);
          final bProfile = _analyzeColumnProfile(bSamples);

          final aDateScore = aProfile.dateCount * 3;
          final bDateScore = bProfile.dateCount * 3;
          if (aDateScore != bDateScore) return bDateScore.compareTo(aDateScore);

          final aAmountScore =
              (aProfile.largeNumericCount * 3) + aProfile.smallNumericCount;
          final bAmountScore =
              (bProfile.largeNumericCount * 3) + bProfile.smallNumericCount;
          if (aAmountScore != bAmountScore) {
            return bAmountScore.compareTo(aAmountScore);
          }

          final aTextScore =
              (aProfile.textCount * 2) + aProfile.alphaNumericCount;
          final bTextScore =
              (bProfile.textCount * 2) + bProfile.alphaNumericCount;
          return bTextScore.compareTo(aTextScore);
        });

      for (final c in prioritizedColumns) {
        final samples = _columnSamples(rows, c);
        if (samples.isEmpty) continue;

        final profile = _analyzeColumnProfile(samples);
        final scores = _scoreGenericLedgerColumn(samples, profile);
        debugPrint(
          'GENERIC LEDGER COLUMN SCORE => COL_$c '
          'samples=${samples.take(2).join(' | ')} '
          'scores=$scores',
        );
        final best = _pickBestInferredColumn(scores, assigned);

        if (best == null || best.$2 < 8) continue;

        mapped[c] = best.$1;
        assigned.add(best.$1);
      }

      debugPrint(
        'GENERIC LEDGER INFERRED COLUMNS => '
        '${mapped.asMap().entries.where((e) => e.value != null).map((e) => 'COL_${e.key}:${e.value}').join(', ')}',
      );
      return mapped;
    }

    for (int c = 0; c < width; c++) {
      if (mapped[c] == 'section') continue;

      final samples = _columnSamples(rows, c);

      if (samples.isEmpty) continue;

      final scores = <String, int>{};
      final profile = _analyzeColumnProfile(samples);

      void addScore(String key, int value) {
        scores[key] = (scores[key] ?? 0) + value;
      }

      final dateKey = type == ExcelImportType.tds26q ? 'date_month' : 'date';
      final amountKey = type == ExcelImportType.purchase
          ? 'bill_amount'
          : type == ExcelImportType.genericLedger
              ? 'amount'
              : 'amount_paid';

      if (profile.dateCount >= 3) {
        addScore(type == ExcelImportType.purchase ? 'date' : dateKey, 18);
      }
      if (profile.panCount >= 2) addScore('pan_number', 20);
      if (type == ExcelImportType.purchase && profile.gstCount >= 2) {
        addScore('gst_no', 18);
      }
      if (profile.textCount >= 3 &&
          profile.numericCount == 0 &&
          profile.panCount == 0 &&
          profile.gstCount == 0) {
        addScore('party_name', 14);
      }
      if (type == ExcelImportType.purchase &&
          profile.alphaNumericCount >= 3 &&
          profile.numericCount <= 2) {
        addScore('bill_no', 8);
      }
      if (profile.numericCount >= 3) {
        if (type == ExcelImportType.purchase) {
          addScore('bill_amount', 12);
          if (profile.largeNumericCount >= 2) {
            addScore('basic_amount', 8);
          }
        } else if (type == ExcelImportType.genericLedger) {
          if (profile.largeNumericCount >= 2 || profile.smallNumericCount >= 2) {
            addScore('amount', 18);
          }
        } else {
          if (profile.smallNumericCount >= 2) {
            addScore('tds_amount', 16);
          }
          if (profile.largeNumericCount >= 2) {
            addScore(amountKey, 16);
          }
        }
      }

      for (final sample in samples) {
        if (_looksLikeDateText(sample)) {
          addScore(type == ExcelImportType.purchase ? 'date' : dateKey, 5);
        }
        if (_looksLikePanText(sample)) addScore('pan_number', 6);
        if (type == ExcelImportType.purchase && _looksLikeGstText(sample)) {
          addScore('gst_no', 6);
        }
        if (_looksLikeAmountText(sample)) {
          addScore(
            type == ExcelImportType.purchase ? 'bill_amount' : amountKey,
            4,
          );
        }
        if (RegExp(r'^[A-Za-z].{3,}$').hasMatch(sample)) {
          addScore('party_name', 3);
        }
        if (type == ExcelImportType.purchase &&
            RegExp(r'^[A-Za-z0-9\\/-]{3,}$').hasMatch(sample)) {
          addScore('bill_no', 2);
        }
        if (type == ExcelImportType.genericLedger &&
            RegExp(r'^[A-Za-z].{3,}$').hasMatch(sample)) {
          addScore('description', 2);
        }
      }

      String? bestKey;
      var bestScore = 0;
      for (final entry in scores.entries) {
        if (assigned.contains(entry.key)) continue;
        if (entry.value > bestScore) {
          bestScore = entry.value;
          bestKey = entry.key;
        }
      }

      if (bestKey != null && bestScore >= 6) {
        mapped[c] = bestKey;
        assigned.add(bestKey);
      }
    }

    return mapped;
  }

  static List<String> _columnSamples(List<List<dynamic>> rows, int columnIndex) {
    return rows
        .take(8)
        .map(
          (row) =>
              columnIndex < row.length ? (row[columnIndex]?.toString().trim() ?? '') : '',
        )
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Map<String, int> _scoreGenericLedgerColumn(
    List<String> samples,
    ({
      int dateCount,
      int panCount,
      int gstCount,
      int numericCount,
      int smallNumericCount,
      int largeNumericCount,
      int textCount,
      int alphaNumericCount,
    }) profile,
  ) {
    final scores = <String, int>{};

    void addScore(String key, int value) {
      scores[key] = (scores[key] ?? 0) + value;
    }

    if (profile.dateCount >= 3) addScore('date', 20);
    if (profile.panCount >= 2) addScore('pan_number', 20);
    if (profile.gstCount >= 2) addScore('gst_no', 18);

    if (profile.textCount >= 3 &&
        profile.numericCount == 0 &&
        profile.panCount == 0 &&
        profile.gstCount == 0) {
      addScore('party_name', 16);
      addScore('description', 8);
    }

    if (profile.alphaNumericCount >= 3 && profile.numericCount <= 2) {
      addScore('bill_no', 10);
      addScore('description', 4);
    }

    if (profile.numericCount >= 3) {
      final amountConfidence =
          (profile.largeNumericCount * 3) + (profile.smallNumericCount * 2);
      if (amountConfidence >= 6) {
        addScore('amount', 20);
      }
    }

    for (final sample in samples) {
      if (_looksLikeDateText(sample)) addScore('date', 5);
      if (_looksLikePanText(sample)) addScore('pan_number', 6);
      if (_looksLikeGstText(sample)) addScore('gst_no', 6);
      if (_looksLikeAmountText(sample)) addScore('amount', 4);
      if (RegExp(r'^[A-Za-z0-9\\/-]{3,}$').hasMatch(sample)) {
        addScore('bill_no', 2);
      }
      if (RegExp(r'^[A-Za-z].{3,}$').hasMatch(sample)) {
        addScore('party_name', 3);
        addScore('description', 2);
      }
    }

    return scores;
  }

  static (String, int)? _pickBestInferredColumn(
    Map<String, int> scores,
    Set<String> assigned,
  ) {
    String? bestKey;
    var bestScore = 0;

    for (final entry in scores.entries) {
      if (assigned.contains(entry.key)) continue;
      if (entry.value > bestScore) {
        bestKey = entry.key;
        bestScore = entry.value;
      }
    }

    if (bestKey == null) return null;
    return (bestKey, bestScore);
  }

  static ({
    int dateCount,
    int panCount,
    int gstCount,
    int numericCount,
    int smallNumericCount,
    int largeNumericCount,
    int textCount,
    int alphaNumericCount,
  }) _analyzeColumnProfile(List<String> samples) {
    var dateCount = 0;
    var panCount = 0;
    var gstCount = 0;
    var numericCount = 0;
    var smallNumericCount = 0;
    var largeNumericCount = 0;
    var textCount = 0;
    var alphaNumericCount = 0;

    for (final sample in samples) {
      final trimmed = sample.trim();
      if (trimmed.isEmpty) continue;

      if (_looksLikeDateText(trimmed)) dateCount++;
      if (_looksLikePanText(trimmed)) panCount++;
      if (_looksLikeGstText(trimmed)) gstCount++;

      final numericValue = _tryParseNumericCell(trimmed);
      if (numericValue != null) {
        numericCount++;
        if (numericValue > 0 && numericValue <= 50000) smallNumericCount++;
        if (numericValue >= 500) largeNumericCount++;
      } else if (RegExp(r'^[A-Za-z][A-Za-z .,&()/-]{2,}$').hasMatch(trimmed)) {
        textCount++;
      } else if (RegExp(r'^[A-Za-z0-9\\/-]{3,}$').hasMatch(trimmed)) {
        alphaNumericCount++;
      }
    }

    return (
      dateCount: dateCount,
      panCount: panCount,
      gstCount: gstCount,
      numericCount: numericCount,
      smallNumericCount: smallNumericCount,
      largeNumericCount: largeNumericCount,
      textCount: textCount,
      alphaNumericCount: alphaNumericCount,
    );
  }

  static bool _looksLikeDateText(String value) {
    return RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$')
        .hasMatch(value.trim());
  }

  static bool _looksLikePanText(String value) {
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
        .hasMatch(value.trim().toUpperCase());
  }

  static bool _looksLikeGstText(String value) {
    return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$')
        .hasMatch(value.trim().toUpperCase());
  }

  static bool _looksLikeAmountText(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned) != null;
  }

  static bool _looksLikeSectionText(String value) {
    final text = value.trim().toUpperCase().replaceAll(' ', '');
    if (text.isEmpty) return false;

    return RegExp(r'\b(19[0-9][A-Z]?|20[0-9][A-Z]?)\b').hasMatch(text);
  }

  static int _scoreSectionColumnSamples(List<String> samples) {
    var score = 0;

    for (final sample in samples) {
      final normalized = _normalizeLooseText(sample);
      final compact = sample.trim().toUpperCase().replaceAll(' ', '');

      if (RegExp(r'\b(19[0-9][A-Z]?|20[0-9][A-Z]?)\b').hasMatch(compact)) {
        score += 8;
      }

      if (normalized.contains('operative') ||
          normalized == 'yes' ||
          normalized == 'no') {
        score -= 6;
      }

      if (normalized.contains('applicable') || normalized.contains('206ab')) {
        score -= 8;
      }
    }

    return score;
  }

  static List<String?> _buildMappedHeaders(
      List<dynamic> rawHeaderRow, {
        required ExcelImportType forcedType,
      }) {
    final usedCanonical = <String>{};
    final mapped = <String?>[];

    for (final cell in rawHeaderRow) {
      final raw = cell?.toString() ?? '';
      final canonical = _detectCanonicalHeader(
        raw,
        type: forcedType,
        usedCanonical: usedCanonical,
      );

      if (canonical != null) {
        usedCanonical.add(canonical);
      }

      mapped.add(canonical);
    }

    return mapped;
  }

  static String? _detectCanonicalHeader(
      String raw, {
        required ExcelImportType type,
        required Set<String> usedCanonical,
      }) {
    final normalized = _normalizeLooseText(raw);
    if (normalized.isEmpty) return null;

    if (type == ExcelImportType.purchase && normalized == 'amount') {
      return null;
    }

    final dictionary = type == ExcelImportType.purchase
        ? _purchaseHeaderDictionary
        : type == ExcelImportType.genericLedger
            ? _genericLedgerHeaderDictionary
            : _tdsHeaderDictionary;

    String? bestKey;
    int bestScore = 0;

    for (final entry in dictionary.entries) {
      final canonical = entry.key;
      final aliases = entry.value;

      if (usedCanonical.contains(canonical)) continue;

      if (type == ExcelImportType.purchase &&
          canonical == 'basic_amount' &&
          (normalized.contains('total') ||
              normalized.contains('bill') ||
              normalized.contains('gross') ||
              normalized.contains('net') ||
              normalized.contains('invoice amount'))) {
        continue;
      }

      if (type == ExcelImportType.purchase &&
          canonical == 'bill_amount' &&
          (normalized.contains('taxable') ||
              normalized.contains('basic') ||
              normalized.contains('assessable'))) {
        continue;
      }

      if (type == ExcelImportType.tds26q &&
          canonical == 'section' &&
          (normalized.contains('206ab') ||
              normalized.contains('applicable') ||
              normalized.contains('status'))) {
        continue;
      }

      for (final alias in aliases) {
        final score = _headerSimilarityScore(normalized, alias);
        if (score > bestScore) {
          bestScore = score;
          bestKey = canonical;
        }
      }
    }

    if (bestScore >= 75) {
      return bestKey;
    }

    return null;
  }

  static int _headerSimilarityScore(String a, String b) {
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 90;

    final aWords = a.split(' ').where((e) => e.isNotEmpty).toSet();
    final bWords = b.split(' ').where((e) => e.isNotEmpty).toSet();

    final common = aWords.intersection(bWords).length;
    final maxLen = aWords.length > bWords.length ? aWords.length : bWords.length;

    final wordScore = maxLen == 0 ? 0 : ((common / maxLen) * 100).round();

    return wordScore;
  }

  static bool _hasSuspiciousAmountCollision(
      List<String?> mappedHeaders,
      List<dynamic> rawHeaders,
      ) {
    final hasExplicitBasicAmount = mappedHeaders.contains('basic_amount');
    final hasExplicitBillAmount = mappedHeaders.contains('bill_amount');

    if (hasExplicitBasicAmount && hasExplicitBillAmount) {
      return false;
    }

    int basicCount = 0;
    int billCount = 0;

    for (int i = 0; i < mappedHeaders.length; i++) {
      final mapped = mappedHeaders[i];
      final raw = i < rawHeaders.length ? rawHeaders[i]?.toString() ?? '' : '';
      final rawNormalized = _normalizeLooseText(raw);

      if (mapped == 'basic_amount') basicCount++;
      if (mapped == 'bill_amount') billCount++;

      if (rawNormalized == 'amount') {
        return true;
      }
    }

    if (basicCount > 1) return true;
    if (billCount > 1) return true;

    return false;
  }

  static Map<String, String> _headerPreviewMap(
      List<dynamic> rawHeaders,
      List<String?> mappedHeaders,
      ) {
    final result = <String, String>{};

    for (int i = 0; i < rawHeaders.length; i++) {
      final raw = rawHeaders[i]?.toString().trim() ?? '';
      final mapped = i < mappedHeaders.length ? mappedHeaders[i] : null;

      if (raw.isNotEmpty && mapped != null && mapped.isNotEmpty) {
        result[raw] = mapped;
      }
    }

    return result;
  }

  static List<String> _buildPurchaseWarnings(List<PurchaseRow> rows) {
    final warnings = <String>[];

    final zeroBasic = rows.where((e) => e.basicAmount <= 0).length;
    if (zeroBasic > 0) {
      warnings.add('$zeroBasic purchase rows have zero or negative Basic Amount.');
    }

    final missingParty = rows.where((e) => e.partyName.trim().isEmpty).length;
    if (missingParty > 0) {
      warnings.add('$missingParty purchase rows have missing Party Name.');
    }

    final missingDate = rows.where((e) => e.month.trim().isEmpty).length;
    if (missingDate > 0) {
      warnings.add('$missingDate purchase rows have unreadable Date / Month.');
    }

    final invalidPan = rows
        .where((e) => e.panNumber.trim().isNotEmpty && !_isValidPan(e.panNumber))
        .length;
    if (invalidPan > 0) {
      warnings.add('$invalidPan purchase rows have invalid PAN format.');
    }

    return warnings;
  }

  static List<String> _buildTdsWarnings(List<Tds26QRow> rows) {
    final warnings = <String>[];

    final missingPan = rows.where((e) => e.panNumber.trim().isEmpty).length;
    if (missingPan > 0) {
      warnings.add('$missingPan 26Q rows have missing PAN.');
    }

    final invalidPan = rows
        .where((e) => e.panNumber.trim().isNotEmpty && !_isValidPan(e.panNumber))
        .length;
    if (invalidPan > 0) {
      warnings.add('$invalidPan 26Q rows have invalid PAN format.');
    }

    final missingMonth = rows.where((e) => e.month.trim().isEmpty).length;
    if (missingMonth > 0) {
      warnings.add('$missingMonth 26Q rows have unreadable Date / Month.');
    }

    final zeroAmounts =
        rows.where((e) => e.deductedAmount <= 0 && e.tds <= 0).length;
    if (zeroAmounts > 0) {
      warnings.add('$zeroAmounts 26Q rows have both Amount Paid and TDS Amount as zero.');
    }

    final missingSection = rows.where((e) => e.section.trim().isEmpty).length;
    if (missingSection > 0) {
      warnings.add('$missingSection 26Q rows have missing Section.');
    }

    return warnings;
  }

  static List<PurchaseRow> _dedupePurchaseRows(List<PurchaseRow> rows) {
    final map = <String, PurchaseRow>{};

    for (final row in rows) {
      final key = [
        row.date.trim(),
        row.month.trim().toUpperCase(),
        row.billNo.trim().toUpperCase(),
        row.partyName.trim().toUpperCase(),
        row.panNumber.trim().toUpperCase(),
        row.productName.trim().toUpperCase(),
        row.basicAmount.toStringAsFixed(2),
        row.billAmount.toStringAsFixed(2),
      ].join('|');

      map[key] = row;
    }

    return map.values.toList();
  }

  static List<Tds26QRow> _dedupeTdsRows(List<Tds26QRow> rows) {
    final map = <String, Tds26QRow>{};

    for (final row in rows) {
      final key = [
        row.month.trim().toUpperCase(),
        row.deducteeName.trim().toUpperCase(),
        row.panNumber.trim().toUpperCase(),
        row.deductedAmount.toStringAsFixed(2),
        row.tds.toStringAsFixed(2),
        row.section.trim().toUpperCase(),
      ].join('|');

      map[key] = row;
    }

    return map.values.toList();
  }

  static List<NormalizedLedgerRow> _dedupeNormalizedLedgerRows(
    List<NormalizedLedgerRow> rows,
  ) {
    final map = <String, NormalizedLedgerRow>{};

    for (final row in rows) {
      final key = [
        row.sectionCode.trim().toUpperCase(),
        row.month.trim().toUpperCase(),
        row.partyName.trim().toUpperCase(),
        row.panNumber.trim().toUpperCase(),
        row.documentNo.trim().toUpperCase(),
        row.amount.toStringAsFixed(2),
        row.tdsAmount.toStringAsFixed(2),
      ].join('|');

      map[key] = row;
    }

    return map.values.toList();
  }

  static dynamic _normalizeCellValue(dynamic value) {
    if (value == null) return '';

    if (value is DateTime) {
      return _formatDate(value);
    }

    if (value is num) {
      if (_looksLikeExcelDate(value)) {
        return _convertExcelDate(value);
      }

      if (value == value.roundToDouble()) {
        return value.toInt().toString();
      }

      return value.toString();
    }

    return value.toString().trim();
  }

  static bool _looksLikeExcelDate(num value) {
    return value >= 20000 && value <= 60000;
  }

  static DateTime _excelSerialToDate(num serial) {
    final wholeDays = serial.floor();
    return DateTime(1899, 12, 30).add(Duration(days: wholeDays));
  }

  static String _convertExcelDate(num serial) {
    final dt = _excelSerialToDate(serial);
    return _formatDate(dt);
  }

  static String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    return '$dd/$mm/$yyyy';
  }

  static bool _isValidPan(String pan) {
    final normalized = pan.trim().toUpperCase();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(normalized);
  }

  static String _normalizeLooseText(String value) {
    var text = value.trim().toLowerCase();

    text = text.replaceAll('\n', ' ');
    text = text.replaceAll('\r', ' ');
    text = text.replaceAll('_', ' ');
    text = text.replaceAll('-', ' ');
    text = text.replaceAll('/', ' ');
    text = text.replaceAll('.', ' ');
    text = text.replaceAll('(', ' ');
    text = text.replaceAll(')', ' ');
    text = text.replaceAll(',', ' ');
    text = text.replaceAll(':', ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  static const Map<String, List<String>> _purchaseHeaderDictionary = {
    'bill_no': [
      'bill no',
      'bill_no',
      'bill number',
      'voucher no',
      'voucher number',
      'invoice no',
      'invoice number',
      'doc no',
      'document no',
    ],
    'date': [
      'date',
      'bill date',
      'bill_date',
      'invoice date',
      'voucher date',
      'document date',
    ],
    'eom': [
      'eom',
      'end of month',
      'month end',
    ],
    'party_name': [
      'party name',
      'party_name',
      'party',
      'vendor',
      'vendor name',
      'supplier',
      'supplier name',
      'name',
      'seller name',
    ],
    'gst_no': [
      'gst no',
      'gst no.',
      'gst number',
      'gstin',
      'gst',
    ],
    'pan_number': [
      'pan',
      'pan no',
      'pan no.',
      'pan number',
      'panno',
    ],
    'productname': [
      'product name',
      'productname',
      'item name',
      'item',
      'description',
    ],
    'basic_amount': [
      'basic amount',
      'product amount',
      'product_amount',
    ],
    'bill_amount': [
      'bill amount',
      'bill_amount',
      'amount',
      'total amount',
      'gross amount',
      'net amount',
      'invoice amount',
      'bill amt',
      'total bill amount',
    ],
    'sgst': ['sgst'],
    'cgst': ['cgst'],
    'igst': ['igst'],
  };

  static const Map<String, List<String>> _tdsHeaderDictionary = {
    'date_month': [
      'date month',
      'month',
      'date',
      'paid credited date',
      'paid credited dt',
      'payment date',
      'credited date',
    ],
    'party_name': [
      'party name',
      'party_name',
      'name',
      'deductee name',
      'deductee',
      'party',
      'vendor name',
      'vendor',
      'supplier',
      'seller name',
    ],
    'pan_number': [
      'pan',
      'pan no',
      'pan number',
      'panno',
      'deductee pan',
    ],
    'amount_paid': [
      'deducted amount',
      'deducted amt',
      'amount paid credited',
      'amount paid or credited',
      'amount paid',
      'credited amount',
      'payment amount',
    ],
    'tds_amount': [
      'tds',
      'tax',
      'deducted and deposited tax',
      'deducted deposited tax',
      'tds amount',
      'tax deducted',
    ],
    'section': [
      'section',
      'tds section',
      'section code',
      'section name',
      'sec',
      'section no',
      'nature of payment',
      'nature',
      'nature of transaction',
      'nature of remittance',
      'payment nature',
      'tds nature',
    ],
    'challan': [
      'challan',
      'chalan',
      'challan id no details',
      'challan id no',
    ],
  };

  static const Map<String, List<String>> _genericLedgerHeaderDictionary = {
    'date': [
      'date',
      'bill date',
      'invoice date',
      'posting date',
      'voucher date',
      'document date',
      'txn date',
      'transaction date',
    ],
    'party_name': [
      'party name',
      'party',
      'ledger name',
      'account name',
      'vendor name',
      'supplier name',
      'name',
    ],
    'pan_number': [
      'pan',
      'pan no',
      'pan number',
      'panno',
    ],
    'gst_no': [
      'gst no',
      'gst number',
      'gstin',
      'gst',
    ],
    'bill_no': [
      'bill no',
      'bill number',
      'invoice no',
      'voucher no',
      'document no',
      'ref no',
      'reference no',
    ],
    'amount': [
      'amount',
      'amount paid',
      'amount',
      'taxable amount',
      'basic amount',
      'gross amount',
      'invoice amount',
      'ledger amount',
      'transaction amount',
    ],
    'description': [
      'description',
      'narration',
      'remarks',
      'particulars',
      'product name',
    ],
  };
}

enum ExcelImportType {
  purchase,
  tds26q,
  genericLedger,
}

class ExcelValidationResult {
  final bool isValid;
  final String message;
  final String? detectedSheet;
  final int? headerRowIndex;
  final ExcelImportType? detectedType;
  final Map<String, String> mappedColumns;
  final List<String> warnings;
  final double confidenceScore;
  final bool requiresManualMapping;
  final bool requiresUserSelection;
  final List<String> candidateSheets;
  final List<String> unmappedRawHeaders;

  ExcelValidationResult({
    required this.isValid,
    required this.message,
    required this.detectedSheet,
    required this.headerRowIndex,
    required this.detectedType,
    required this.mappedColumns,
    required this.warnings,
    required this.confidenceScore,
    required this.requiresManualMapping,
    required this.requiresUserSelection,
    required this.candidateSheets,
    required this.unmappedRawHeaders,
  });

  factory ExcelValidationResult.valid({
    required String detectedSheet,
    required int headerRowIndex,
    required ExcelImportType detectedType,
    required Map<String, String> mappedColumns,
    List<String> warnings = const [],
    double confidenceScore = 1.0,
    bool requiresManualMapping = false,
    bool requiresUserSelection = false,
    List<String> candidateSheets = const [],
    List<String> unmappedRawHeaders = const [],
  }) {
    return ExcelValidationResult(
      isValid: true,
      message: 'File validated successfully.',
      detectedSheet: detectedSheet,
      headerRowIndex: headerRowIndex,
      detectedType: detectedType,
      mappedColumns: mappedColumns,
      warnings: warnings,
      confidenceScore: confidenceScore,
      requiresManualMapping: requiresManualMapping,
      requiresUserSelection: requiresUserSelection,
      candidateSheets: candidateSheets,
      unmappedRawHeaders: unmappedRawHeaders,
    );
  }

  factory ExcelValidationResult.selectionRequired({
    String message = 'Please select the correct 26Q sheet.',
    List<String> candidateSheets = const [],
  }) {
    return ExcelValidationResult(
      isValid: false,
      message: message,
      detectedSheet: null,
      headerRowIndex: null,
      detectedType: ExcelImportType.tds26q,
      mappedColumns: const {},
      warnings: const [],
      confidenceScore: 0.0,
      requiresManualMapping: false,
      requiresUserSelection: true,
      candidateSheets: candidateSheets,
      unmappedRawHeaders: const [],
    );
  }

  factory ExcelValidationResult.invalid(String message) {
    return ExcelValidationResult(
      isValid: false,
      message: message,
      detectedSheet: null,
      headerRowIndex: null,
      detectedType: null,
      mappedColumns: const {},
      warnings: const [],
      confidenceScore: 0.0,
      requiresManualMapping: false,
      requiresUserSelection: false,
      candidateSheets: const [],
      unmappedRawHeaders: const [],
    );
  }
}
