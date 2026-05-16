import 'package:flutter/foundation.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/core/utils/app_logger.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/parse_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/upload/models/import_audit_record.dart';
import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';
import 'package:reconciliation_app/features/upload/models/import_format_profile.dart';

import 'import_mapping_service.dart';
import 'import_profile_service.dart';

part 'excel_preview_builder.dart';

class ImportSessionCache {
  final Uint8List bytes;
  final SpreadsheetDecoder decoder;

  ImportSessionCache._({required this.bytes, required this.decoder});

  factory ImportSessionCache.fromBytes(List<int> sourceBytes) {
    final bytes = sourceBytes is Uint8List
        ? sourceBytes
        : Uint8List.fromList(sourceBytes);
    final decodeWatch = Stopwatch()..start();
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    decodeWatch.stop();
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=session_cache_decode ms=${decodeWatch.elapsedMilliseconds} sizeBytes=${bytes.length}',
    );
    return ImportSessionCache._(bytes: bytes, decoder: decoder);
  }
}

class _ImportedRowCandidate {
  final Map<String, dynamic> rowMap;
  final int rowNumber;

  const _ImportedRowCandidate({required this.rowMap, required this.rowNumber});
}

enum ImportProfileMatchKind { exactSignature, sheetPattern }

class ImportFormatProfileMatch {
  final ImportFormatProfile profile;
  final ImportProfileMatchKind kind;

  const ImportFormatProfileMatch({required this.profile, required this.kind});

  bool get isExactSignature => kind == ImportProfileMatchKind.exactSignature;
}

class ExcelService {
  static const bool _enableVerboseImportLogs = AppLogger.verboseEnabled;
  static const int _defaultHeaderScanRowLimit = 20;
  static const int _defaultStructuredHeaderScanRowLimit = 30;
  static const int _selectedSheetHeaderScanRowLimit = 80;
  static const int _moderate26QHelperHeaderScanRowLimit = 25;
  static final Map<String, int> _forcedNumericDateAvoidanceByField =
      <String, int>{};
  static final Map<
    String,
    ({
      String sheetName,
      int headerRowIndex,
      ExcelImportType detectedType,
      bool headersTrusted,
    })
  >
  _headerDetectionCache =
      <
        String,
        ({
          String sheetName,
          int headerRowIndex,
          ExcelImportType detectedType,
          bool headersTrusted,
        })
      >{};
  static final Map<String, List<String?>> _columnScoreCache =
      <String, List<String?>>{};

  static void _debugVerbose(String message) {
    if (!_enableVerboseImportLogs) return;
    AppLogger.debug(message);
  }

  static void _logUploadFreezePerformance(
    String step,
    Stopwatch watch, {
    String details = '',
  }) {
    final suffix = details.trim().isEmpty ? '' : ' | $details';
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=$step ms=${watch.elapsedMilliseconds}$suffix',
    );
  }

  static void _recordForcedNumericDateAvoidance(String field) {
    _forcedNumericDateAvoidanceByField[field] =
        (_forcedNumericDateAvoidanceByField[field] ?? 0) + 1;
  }

  static void _flushForcedNumericDateAvoidanceSummary(String context) {
    if (_forcedNumericDateAvoidanceByField.isEmpty) return;

    final summary = _forcedNumericDateAvoidanceByField.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(', ');
    _forcedNumericDateAvoidanceByField.clear();
    AppLogger.debug(
      'EXCEL VALUE FORMAT => summary context=$context avoidedForcedNumericDates={$summary}',
    );
  }

  static String _workbookCacheKey(
    SpreadsheetDecoder decoder, {
    ExcelImportType? forcedType,
    String? preferredSheetName,
  }) {
    final buffer = StringBuffer()
      ..write(forcedType?.name ?? 'any')
      ..write('|')
      ..write(preferredSheetName ?? '')
      ..write('|');
    for (final entry in decoder.tables.entries) {
      final rows = entry.value.rows;
      buffer
        ..write(entry.key)
        ..write(':')
        ..write(rows.length)
        ..write(':')
        ..write(rows.isEmpty ? 0 : rows.first.length)
        ..write('|');
    }
    return buffer.toString();
  }

  static String _columnScoreCacheKey({
    required List<dynamic> rawHeaderRow,
    required ExcelImportType forcedType,
  }) {
    final headerKey = rawHeaderRow
        .map((cell) => cell?.toString().trim().toLowerCase() ?? '')
        .join('|');
    return '${forcedType.name}|$headerKey';
  }

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
    final match = await findMatchingProfileMatch(
      buyerId: buyerId,
      fileType: fileType,
      sheetName: sheetName,
      sampleSignature: sampleSignature,
    );
    return match?.profile;
  }

  static Future<ImportFormatProfileMatch?> findMatchingProfileMatch({
    required String buyerId,
    required String fileType,
    required String sheetName,
    required String sampleSignature,
  }) async {
    final profiles = await getBuyerImportProfiles(
      buyerId: buyerId,
      fileType: fileType,
    );

    ImportFormatProfile? sheetPatternMatch;
    for (final profile in profiles) {
      final normalizedMapping = _normalizeCanonicalColumnMappingByType(
        _normalizeProfileColumnMapping(profile.columnMapping),
        type: _importTypeFromFileType(fileType),
      );
      final sheetPattern = profile.sheetNamePattern.trim().toLowerCase();
      final normalizedSheet = sheetName.trim().toLowerCase();
      final matchesSheet =
          sheetPattern.isEmpty || normalizedSheet.contains(sheetPattern);
      final matchesSignature =
          profile.sampleSignature.isNotEmpty &&
          profile.sampleSignature == sampleSignature;

      if (!_hasRequiredProfileMapping(
        fileType: fileType,
        columnMapping: normalizedMapping,
      )) {
        continue;
      }

      if (matchesSignature) {
        return ImportFormatProfileMatch(
          profile: profile,
          kind: ImportProfileMatchKind.exactSignature,
        );
      }

      if (matchesSheet && sheetPatternMatch == null) {
        sheetPatternMatch = profile;
      }
    }

    if (sheetPatternMatch != null) {
      return ImportFormatProfileMatch(
        profile: sheetPatternMatch,
        kind: ImportProfileMatchKind.sheetPattern,
      );
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

  static Future<List<PurchaseRow>> parsePurchaseRowsInBackground(
    Uint8List bytes,
  ) async {
    final computeWatch = Stopwatch()..start();
    final payload = await compute(_parsePurchaseRowsInIsolate, bytes);
    computeWatch.stop();
    final rows = _deserializePurchaseRowsForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_purchase',
      computeWatch,
      details: 'sizeBytes=${bytes.length} rows=${rows.length}',
    );
    return rows;
  }

  static Future<List<Tds26QRow>> parseTds26QRowsInBackground(
    Uint8List bytes, {
    String? sheetName,
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload = await compute(_parseTds26QRowsInIsolate, <String, dynamic>{
      'bytes': bytes,
      'sheetName': sheetName,
    });
    computeWatch.stop();
    final rows = _deserializeTdsRowsForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_tds26q',
      computeWatch,
      details: 'sizeBytes=${bytes.length} rows=${rows.length}',
    );
    return rows;
  }

  static Future<ExcelValidationResult> validatePurchaseFileInBackground(
    Uint8List bytes, {
    String? preferredSheetName,
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload = await compute(
      _validatePurchaseFileInIsolate,
      <String, dynamic>{
        'bytes': bytes,
        'preferredSheetName': preferredSheetName,
      },
    );
    computeWatch.stop();
    final result = _deserializeValidationForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_validate_purchase',
      computeWatch,
      details: 'sizeBytes=${bytes.length} valid=${result.isValid}',
    );
    return result;
  }

  static Future<ExcelValidationResult> validateTds26QFileInBackground(
    Uint8List bytes, {
    String? preferredSheetName,
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload = await compute(
      _validateTds26QFileInIsolate,
      <String, dynamic>{
        'bytes': bytes,
        'preferredSheetName': preferredSheetName,
      },
    );
    computeWatch.stop();
    final result = _deserializeValidationForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_validate_tds26q',
      computeWatch,
      details: 'sizeBytes=${bytes.length} valid=${result.isValid}',
    );
    return result;
  }

  static Future<ExcelValidationResult> validateGenericLedgerFileInBackground(
    Uint8List bytes, {
    String? preferredSheetName,
    String? expectedSection,
    String sourceFileName = '',
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload =
        await compute(_validateGenericLedgerFileInIsolate, <String, dynamic>{
          'bytes': bytes,
          'preferredSheetName': preferredSheetName,
          'expectedSection': expectedSection,
          'sourceFileName': sourceFileName,
        });
    computeWatch.stop();
    final result = _deserializeValidationForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_validate_generic_ledger',
      computeWatch,
      details: 'sizeBytes=${bytes.length} valid=${result.isValid}',
    );
    return result;
  }

  static Future<List<String>> list26QSelectableSheetsInBackground(
    Uint8List bytes,
  ) async {
    final computeWatch = Stopwatch()..start();
    final sheets = await compute(_list26QSelectableSheetsInIsolate, bytes);
    computeWatch.stop();
    _logUploadFreezePerformance(
      'parser_compute_list_26q_sheets',
      computeWatch,
      details: 'sizeBytes=${bytes.length} sheets=${sheets.length}',
    );
    return sheets;
  }

  static Future<List<String>> listWorkbookSheetNamesInBackground(
    Uint8List bytes,
  ) async {
    final computeWatch = Stopwatch()..start();
    final sheets = await compute(_listWorkbookSheetNamesInIsolate, bytes);
    computeWatch.stop();
    _logUploadFreezePerformance(
      'parser_compute_list_workbook_sheets',
      computeWatch,
      details: 'sizeBytes=${bytes.length} sheets=${sheets.length}',
    );
    return sheets;
  }

  static Future<List<NormalizedLedgerRow>> parseGenericLedgerRowsInBackground(
    Uint8List bytes, {
    required String defaultSection,
    String sourceFileName = '',
    String? sheetName,
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload =
        await compute(_parseGenericLedgerRowsInIsolate, <String, dynamic>{
          'bytes': bytes,
          'defaultSection': defaultSection,
          'sourceFileName': sourceFileName,
          'sheetName': sheetName,
        });
    computeWatch.stop();
    final rows = _deserializeNormalizedLedgerRowsForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_generic_ledger',
      computeWatch,
      details: 'sizeBytes=${bytes.length} rows=${rows.length}',
    );
    return rows;
  }

  static Future<List<NormalizedLedgerRow>>
  parseGenericLedgerRowsWithProfileInBackground(
    Uint8List bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    required String defaultSection,
    String sourceFileName = '',
  }) async {
    final computeWatch = Stopwatch()..start();
    final payload = await compute(
      _parseGenericLedgerRowsWithProfileInIsolate,
      <String, dynamic>{
        'bytes': bytes,
        'sheetName': sheetName,
        'headerRowIndex': headerRowIndex,
        'headersTrusted': headersTrusted,
        'columnMapping': columnMapping,
        'defaultSection': defaultSection,
        'sourceFileName': sourceFileName,
      },
    );
    computeWatch.stop();
    final rows = _deserializeNormalizedLedgerRowsForIsolate(payload);
    _logUploadFreezePerformance(
      'parser_compute_generic_ledger_with_profile',
      computeWatch,
      details: 'sizeBytes=${bytes.length} rows=${rows.length}',
    );
    return rows;
  }

  static SpreadsheetDecoder _decoderFromCache(
    List<int> bytes, {
    ImportSessionCache? sessionCache,
  }) {
    if (sessionCache != null) {
      return sessionCache.decoder;
    }
    return SpreadsheetDecoder.decodeBytes(bytes, update: false);
  }

  static dynamic formatPreviewValue(dynamic value, {String? canonicalField}) {
    return _normalizeCellValue(value, canonicalField: canonicalField);
  }

  static Map<String, dynamic> purchaseRowToStagingMap(PurchaseRow row) {
    return <String, dynamic>{
      'date': row.date,
      'bill_no': row.billNo,
      'party_name': row.partyName,
      'gst_no': row.gstNo,
      'pan_number': row.panNumber,
      'productname': row.productName,
      'basic_amount': row.basicAmount,
      'bill_amount': row.billAmount,
    };
  }

  static Map<String, dynamic> tds26QRowToStagingMap(Tds26QRow row) {
    return <String, dynamic>{
      'date_month': row.month,
      'financial_year': row.financialYear,
      'party_name': row.deducteeName,
      'pan_number': row.panNumber,
      'amount_paid': row.deductedAmount,
      'tds_amount': row.tds,
      'section': row.section,
      'nature_of_payment': '',
    };
  }

  static List<Map<String, dynamic>> _serializePurchaseRowsForIsolate(
    List<PurchaseRow> rows,
  ) {
    return rows
        .map(
          (row) => <String, dynamic>{
            'date': row.date,
            'month': row.month,
            'billNo': row.billNo,
            'partyName': row.partyName,
            'gstNo': row.gstNo,
            'panNumber': row.panNumber,
            'productName': row.productName,
            'basicAmount': row.basicAmount,
            'billAmount': row.billAmount,
          },
        )
        .toList();
  }

  static List<PurchaseRow> _deserializePurchaseRowsForIsolate(List payload) {
    return payload
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(
          (row) => PurchaseRow(
            date: row['date'] as String? ?? '',
            month: row['month'] as String? ?? '',
            billNo: row['billNo'] as String? ?? '',
            partyName: row['partyName'] as String? ?? '',
            gstNo: row['gstNo'] as String? ?? '',
            panNumber: row['panNumber'] as String? ?? '',
            productName: row['productName'] as String? ?? '',
            basicAmount: (row['basicAmount'] as num?)?.toDouble() ?? 0.0,
            billAmount: (row['billAmount'] as num?)?.toDouble() ?? 0.0,
          ),
        )
        .toList();
  }

  static List<Map<String, dynamic>> _serializeTdsRowsForIsolate(
    List<Tds26QRow> rows,
  ) {
    return rows
        .map(
          (row) => <String, dynamic>{
            'month': row.month,
            'financialYear': row.financialYear,
            'deducteeName': row.deducteeName,
            'panNumber': row.panNumber,
            'deductedAmount': row.deductedAmount,
            'tds': row.tds,
            'section': row.section,
          },
        )
        .toList();
  }

  static List<Tds26QRow> _deserializeTdsRowsForIsolate(List payload) {
    return payload
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(
          (row) => Tds26QRow(
            month: row['month'] as String? ?? '',
            financialYear: row['financialYear'] as String? ?? '',
            deducteeName: row['deducteeName'] as String? ?? '',
            panNumber: row['panNumber'] as String? ?? '',
            deductedAmount: (row['deductedAmount'] as num?)?.toDouble() ?? 0.0,
            tds: (row['tds'] as num?)?.toDouble() ?? 0.0,
            section: row['section'] as String? ?? '',
          ),
        )
        .toList();
  }

  static List<Map<String, dynamic>> _serializeNormalizedLedgerRowsForIsolate(
    List<NormalizedLedgerRow> rows,
  ) {
    return rows
        .map(
          (row) => <String, dynamic>{
            'sourceType': row.sourceType,
            'sourceFileName': row.sourceFileName,
            'sourceLedgerFileId': row.sourceLedgerFileId,
            'sourceLedgerUploadedAt': row.sourceLedgerUploadedAt
                ?.toIso8601String(),
            'sectionCode': row.sectionCode,
            'transactionDateRaw': row.transactionDateRaw,
            'month': row.month,
            'financialYear': row.financialYear,
            'partyName': row.partyName,
            'panNumber': row.panNumber,
            'gstNo': row.gstNo,
            'documentNo': row.documentNo,
            'description': row.description,
            'amount': row.amount,
            'taxableAmount': row.taxableAmount,
            'tdsAmount': row.tdsAmount,
            'section': row.section,
          },
        )
        .toList();
  }

  static List<NormalizedLedgerRow> _deserializeNormalizedLedgerRowsForIsolate(
    List payload,
  ) {
    return payload
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(
          (row) => NormalizedLedgerRow(
            sourceType: row['sourceType'] as String? ?? '',
            sourceFileName: row['sourceFileName'] as String? ?? '',
            sourceLedgerFileId: row['sourceLedgerFileId'] as String? ?? '',
            sourceLedgerUploadedAt: DateTime.tryParse(
              row['sourceLedgerUploadedAt'] as String? ?? '',
            ),
            sectionCode: row['sectionCode'] as String? ?? '',
            transactionDateRaw: row['transactionDateRaw'] as String? ?? '',
            month: row['month'] as String? ?? '',
            financialYear: row['financialYear'] as String? ?? '',
            partyName: row['partyName'] as String? ?? '',
            panNumber: row['panNumber'] as String? ?? '',
            gstNo: row['gstNo'] as String? ?? '',
            documentNo: row['documentNo'] as String? ?? '',
            description: row['description'] as String? ?? '',
            amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
            taxableAmount: (row['taxableAmount'] as num?)?.toDouble() ?? 0.0,
            tdsAmount: (row['tdsAmount'] as num?)?.toDouble() ?? 0.0,
            section: row['section'] as String? ?? '',
          ),
        )
        .toList();
  }

  static Map<String, dynamic> _serializeValidationForIsolate(
    ExcelValidationResult validation,
  ) {
    return {
      'isValid': validation.isValid,
      'message': validation.message,
      'detectedSheet': validation.detectedSheet,
      'headerRowIndex': validation.headerRowIndex,
      'detectedType': validation.detectedType?.name,
      'mappedColumns': validation.mappedColumns,
      'warnings': validation.warnings,
      'confidenceScore': validation.confidenceScore,
      'requiresManualMapping': validation.requiresManualMapping,
      'requiresUserSelection': validation.requiresUserSelection,
      'candidateSheets': validation.candidateSheets,
      'unmappedRawHeaders': validation.unmappedRawHeaders,
      'decision': validation.decision.name,
    };
  }

  static ExcelValidationResult _deserializeValidationForIsolate(
    Map<String, dynamic> payload,
  ) {
    final detectedTypeName = payload['detectedType'] as String?;
    final decisionName = payload['decision'] as String? ?? 'invalidMapping';

    return ExcelValidationResult(
      isValid: payload['isValid'] as bool? ?? false,
      message: payload['message'] as String? ?? '',
      detectedSheet: payload['detectedSheet'] as String?,
      headerRowIndex: payload['headerRowIndex'] as int?,
      detectedType: detectedTypeName == null
          ? null
          : ExcelImportType.values.firstWhere(
              (value) => value.name == detectedTypeName,
            ),
      mappedColumns: Map<String, String>.from(
        payload['mappedColumns'] as Map? ?? const {},
      ),
      warnings: List<String>.from(payload['warnings'] as List? ?? const []),
      confidenceScore: (payload['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      requiresManualMapping: payload['requiresManualMapping'] as bool? ?? false,
      requiresUserSelection: payload['requiresUserSelection'] as bool? ?? false,
      candidateSheets: List<String>.from(
        payload['candidateSheets'] as List? ?? const [],
      ),
      unmappedRawHeaders: List<String>.from(
        payload['unmappedRawHeaders'] as List? ?? const [],
      ),
      decision: ExcelImportDecision.values.firstWhere(
        (value) => value.name == decisionName,
        orElse: () => ExcelImportDecision.invalidMapping,
      ),
    );
  }

  static List<Map<String, dynamic>> excelToMapList(
    List<int> bytes, {
    ExcelImportType? forcedType,
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);

    if (decoder.tables.isEmpty) {
      return [];
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: forcedType,
      preferredSheetName: preferredSheetName,
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
    _debugVerbose(
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
        final normalizedValue = _normalizeCellValue(
          value,
          canonicalField: header,
        );
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
  })?
  inspectExcelFile(
    List<int> bytes, {
    ExcelImportType? forcedType,
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
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
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
    final table = decoder.tables[sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    final normalizedColumnMapping = _normalizeCanonicalColumnMappingByType(
      columnMapping,
      type: forcedType,
    );
    _debugVerbose(
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
        final normalizedValue = _normalizeCellValue(
          value,
          canonicalField: header,
        );
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
    List<_ImportedRowCandidate> rows,
    List<ImportAuditRecord> auditRecords,
  })
  _extractImportedRowCandidates(
    List<int> bytes, {
    required ExcelImportType forcedType,
    required String sourceFileName,
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: forcedType,
      preferredSheetName: preferredSheetName,
    );
    if (sheetInfo == null) {
      return (
        sheetName: preferredSheetName ?? '',
        rows: const <_ImportedRowCandidate>[],
        auditRecords: const <ImportAuditRecord>[],
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return (
        sheetName: sheetInfo.sheetName,
        rows: const <_ImportedRowCandidate>[],
        auditRecords: const <ImportAuditRecord>[],
      );
    }

    final mappedHeaders = _resolveMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      forcedType: sheetInfo.detectedType,
      headersTrusted: sheetInfo.headersTrusted,
    );

    final extracted = _buildRowCandidatesFromMappedHeaders(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: sheetInfo.headersTrusted,
      sourceFileName: sourceFileName,
      sheetName: sheetInfo.sheetName,
      rowType: forcedType == ExcelImportType.tds26q
          ? ImportAuditRowType.tds26q
          : ImportAuditRowType.ledgerSource,
      sectionBucket: forcedType == ExcelImportType.purchase ? '194Q' : '',
    );

    return (
      sheetName: sheetInfo.sheetName,
      rows: extracted.rows,
      auditRecords: extracted.auditRecords,
    );
  }

  static ({
    String sheetName,
    List<_ImportedRowCandidate> rows,
    List<ImportAuditRecord> auditRecords,
  })
  _extractImportedRowCandidatesWithProfile(
    List<int> bytes, {
    required ExcelImportType forcedType,
    required String sourceFileName,
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
    final table = decoder.tables[sheetName];
    if (table == null || table.rows.isEmpty) {
      return (
        sheetName: sheetName,
        rows: const <_ImportedRowCandidate>[],
        auditRecords: const <ImportAuditRecord>[],
      );
    }

    final normalizedColumnMapping = _normalizeCanonicalColumnMappingByType(
      columnMapping,
      type: forcedType,
    );
    final mappedHeaders = _buildMappedHeadersFromProfile(
      rawHeaderRow: table.rows[headerRowIndex],
      columnMapping: normalizedColumnMapping,
    );

    final extracted = _buildRowCandidatesFromMappedHeaders(
      rows: table.rows,
      headerRowIndex: headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: headersTrusted,
      sourceFileName: sourceFileName,
      sheetName: sheetName,
      rowType: forcedType == ExcelImportType.tds26q
          ? ImportAuditRowType.tds26q
          : ImportAuditRowType.ledgerSource,
      sectionBucket: forcedType == ExcelImportType.purchase ? '194Q' : '',
    );

    return (
      sheetName: sheetName,
      rows: extracted.rows,
      auditRecords: extracted.auditRecords,
    );
  }

  static ({
    List<_ImportedRowCandidate> rows,
    List<ImportAuditRecord> auditRecords,
  })
  _buildRowCandidatesFromMappedHeaders({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required List<String?> mappedHeaders,
    required bool headersTrusted,
    required String sourceFileName,
    required String sheetName,
    required ImportAuditRowType rowType,
    required String sectionBucket,
  }) {
    final dataStartIndex = headersTrusted ? headerRowIndex + 1 : headerRowIndex;
    final result = <_ImportedRowCandidate>[];
    final auditRecords = <ImportAuditRecord>[];

    final validHeaderIndexes = <int>[];
    for (int j = 0; j < mappedHeaders.length; j++) {
      final header = mappedHeaders[j];
      if (header != null && header.isNotEmpty) {
        validHeaderIndexes.add(j);
      }
    }

    for (int i = dataStartIndex; i < rows.length; i++) {
      final row = rows[i];
      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (final j in validHeaderIndexes) {
        final header = mappedHeaders[j]!;
        final value = j < row.length ? row[j] : null;

        dynamic normalizedValue;

        // Fast path for blank, numeric, and already-clean text cells. This
        // avoids running the heavier date/amount normalization for every cell.
        if (value == null) {
          normalizedValue = null;
        } else if (value is num) {
          normalizedValue = value;
        } else if (value is String) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            normalizedValue = '';
          } else {
            normalizedValue = _normalizeCellValue(
              trimmed,
              canonicalField: header,
            );
          }
        } else {
          normalizedValue = _normalizeCellValue(value, canonicalField: header);
        }

        // Fast blank check: avoid normalizedValue.toString().trim() on every
        // imported cell. _normalizeCellValue already returns trimmed strings
        // for text-like cells and numeric values for amount/date-like cells.
        if (normalizedValue != null && normalizedValue != '') {
          isEmptyRow = false;
        }

        rowMap[header] = normalizedValue;
      }

      if (!isEmptyRow) {
        result.add(_ImportedRowCandidate(rowMap: rowMap, rowNumber: i + 1));
      } else {
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: i + 1,
            rowType: rowType,
            sectionBucket: sectionBucket,
            reason: ImportAuditReason.emptyRowIgnored,
            message: 'Completely blank row ignored during import.',
          ),
        );
      }
    }

    _flushForcedNumericDateAvoidanceSummary('row_candidates');

    return (rows: result, auditRecords: auditRecords);
  }

  static List<PurchaseRow> parsePurchaseRows(
    List<int> bytes, {
    ImportSessionCache? sessionCache,
  }) {
    final deduped = parsePurchaseRowsWithAudit(
      bytes,
      sourceFileName: '',
      sessionCache: sessionCache,
    ).rows;

    for (final row in deduped.take(10)) {
      _debugVerbose(
        'DEBUG PURCHASE => party=${row.partyName}, gst=${row.gstNo}, pan=${row.panNumber}, basic=${row.basicAmount}, bill=${row.billAmount}',
      );
    }

    return deduped;
  }

  static ({List<PurchaseRow> rows, List<ImportAuditRecord> auditRecords})
  parsePurchaseRowsWithAudit(
    List<int> bytes, {
    required String sourceFileName,
    ImportSessionCache? sessionCache,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    Map<String, String>? columnMapping,
  }) {
    final extracted = columnMapping == null
        ? _extractImportedRowCandidates(
            bytes,
            forcedType: ExcelImportType.purchase,
            sourceFileName: sourceFileName,
            preferredSheetName: sheetName,
            sessionCache: sessionCache,
          )
        : _extractImportedRowCandidatesWithProfile(
            bytes,
            forcedType: ExcelImportType.purchase,
            sourceFileName: sourceFileName,
            sheetName: sheetName ?? '',
            headerRowIndex: headerRowIndex ?? 0,
            headersTrusted: headersTrusted ?? true,
            columnMapping: columnMapping,
            sessionCache: sessionCache,
          );

    final parsedCandidates = extracted.rows.map((candidate) {
      final parsedRow = PurchaseRow.fromMap(candidate.rowMap);

      if (parsedRow.partyName.trim().toLowerCase() == 'ganesh cattle feed') {
        _debugVerbose(
          'DEBUG PURCHASE PARSE => seller=${parsedRow.partyName}, '
          'rawDate=${(readAny(candidate.rowMap, ['date', 'eom']) ?? '').trim()}, '
          'dateCol=${(candidate.rowMap['date'] ?? '').toString().trim()}, '
          'eomCol=${(candidate.rowMap['eom'] ?? '').toString().trim()}, '
          'month=${parsedRow.month}, '
          'basicAmount=${parsedRow.basicAmount}, '
          'billAmount=${parsedRow.billAmount}',
        );
      }

      return (row: parsedRow, rowNumber: candidate.rowNumber);
    }).toList();

    final deduped = _dedupeImportedPurchaseRows(
      parsedCandidates,
      sourceFileName: sourceFileName,
      sheetName: extracted.sheetName,
    );

    return (
      rows: deduped.rows,
      auditRecords: <ImportAuditRecord>[
        ...extracted.auditRecords,
        ...deduped.auditRecords,
      ],
    );
  }

  static List<PurchaseRow> parsePurchaseRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    String sourceFileName = '',
    ImportSessionCache? sessionCache,
  }) {
    return parsePurchaseRowsWithAudit(
      bytes,
      sourceFileName: sourceFileName,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
      sessionCache: sessionCache,
    ).rows;
  }

  static ({
    String sheetName,
    int headerRowIndex,
    List<dynamic> rawHeaderRow,
    bool headersTrusted,
    ExcelValidationResult validation,
    List<PurchaseRow>? parsedRows,
  })?
  preparePurchaseUploadData(
    List<int> bytes, {
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final uploadWatch = Stopwatch()..start();
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);

    if (decoder.tables.isEmpty) {
      return null;
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.purchase,
      preferredSheetName: preferredSheetName,
    );
    if (sheetInfo == null) {
      return null;
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return null;
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
    final mappedColumns = _headerPreviewMap(rawHeaderRow, mappedHeaders);

    final hasPurchaseDate = _hasPurchaseDateColumn(presentHeaders);
    final hasPurchaseAmount = _hasPurchaseAmountColumn(presentHeaders);

    final missing = <String>[
      if (!hasPurchaseDate) 'Date / EOM',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!hasPurchaseAmount) 'Amount Column',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Column mapping is required instead of auto-parsing.',
      );
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: warnings,
          confidenceScore: confidenceScore,
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    if (missing.isNotEmpty) {
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: [
            ...warnings,
            'Required purchase columns need confirmation: ${missing.join(', ')}.',
          ],
          confidenceScore: confidenceScore,
          message:
              'Required purchase columns need review before import: ${missing.join(', ')}',
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    final hasSuspiciousAmountCollision = _hasSuspiciousAmountCollision(
      mappedHeaders,
      rawHeaderRow,
    );

    if (hasSuspiciousAmountCollision) {
      warnings.add(
        'Amount columns could not be clearly distinguished. Bill Amount will be used as the primary purchase amount.',
      );
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: warnings,
          confidenceScore: confidenceScore,
          message: 'Purchase amount columns need manual review before import.',
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    if (confidenceScore < 0.65) {
      warnings.add(
        'Low header-detection confidence. Review column mapping if imported values look incorrect.',
      );
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: warnings,
          confidenceScore: confidenceScore,
          message:
              'Low-confidence purchase mapping needs review before import.',
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    AppLogger.debug(
      'UPLOAD PERF => step=purchase_metadata_ready ms=${uploadWatch.elapsedMilliseconds} '
      'sheet=${sheetInfo.sheetName} confidence=${confidenceScore.toStringAsFixed(2)}',
    );
    final parseWatch = Stopwatch()..start();
    final parsed = _parsePurchaseRowsFromPreparedSheet(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: sheetInfo.headersTrusted,
    );
    AppLogger.debug(
      'PARSE PERF => step=parse_purchase_rows ms=${parseWatch.elapsedMilliseconds} rows=${parsed.length}',
    );

    if (parsed.isEmpty) {
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: [
            ...warnings,
            'Auto-detected mapping produced no parsed purchase rows.',
          ],
          confidenceScore: confidenceScore,
          message: 'Auto-detected mapping needs review before import.',
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    final validAmountRows = parsed.where((e) => e.basicAmount > 0).length;
    if (validAmountRows == 0) {
      return (
        sheetName: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        rawHeaderRow: rawHeaderRow,
        headersTrusted: sheetInfo.headersTrusted,
        validation: ExcelValidationResult.manualReview(
          detectedSheet: sheetInfo.sheetName,
          headerRowIndex: sheetInfo.headerRowIndex,
          detectedType: sheetInfo.detectedType,
          mappedColumns: mappedColumns,
          warnings: [
            ...warnings,
            'Detected purchase amount column produced zero values for all parsed rows.',
          ],
          confidenceScore: confidenceScore,
          message: 'Purchase amount mapping needs manual review before import.',
          unmappedRawHeaders: unmappedRawHeaders,
        ),
        parsedRows: null,
      );
    }

    final billAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.billAmount);
    final basicAmountSum = parsed.fold<double>(
      0.0,
      (s, e) => s + e.basicAmount,
    );
    warnings.addAll(_buildPurchaseWarnings(parsed));

    if (billAmountSum > 0 && (billAmountSum - basicAmountSum).abs() < 1) {
      warnings.add(
        'Single amount column detected (Bill Amount used as Basic Amount)',
      );
    }

    return (
      sheetName: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      rawHeaderRow: rawHeaderRow,
      headersTrusted: sheetInfo.headersTrusted,
      validation: ExcelValidationResult.valid(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: warnings,
        confidenceScore: confidenceScore,
        unmappedRawHeaders: unmappedRawHeaders,
      ),
      parsedRows: parsed,
    );
  }

  static ExcelPreviewData? buildPreviewData(
    List<int> bytes, {
    required ExcelImportType fileType,
    required String fileName,
    Map<String, String> initialMappedColumns = const {},
    List<String> warnings = const [],
    double? confidenceScore,
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    return _buildPreviewData(
      bytes,
      fileType: fileType,
      fileName: fileName,
      initialMappedColumns: initialMappedColumns,
      warnings: warnings,
      confidenceScore: confidenceScore,
      preferredSheetName: preferredSheetName,
      sessionCache: sessionCache,
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
    ImportSessionCache? sessionCache,
  }) {
    return _buildPreviewDataWithProfile(
      bytes,
      fileType: fileType,
      fileName: fileName,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
      warnings: warnings,
      confidenceScore: confidenceScore,
      sessionCache: sessionCache,
    );
  }

  static List<Tds26QRow> parseTds26QRows(
    List<int> bytes, {
    String? sheetName,
    ImportSessionCache? sessionCache,
  }) {
    final deduped = parseTds26QRowsWithAudit(
      bytes,
      sourceFileName: '',
      sheetName: sheetName,
      sessionCache: sessionCache,
    ).rows;

    for (final row in deduped.take(5)) {
      _debugVerbose(
        'DEBUG 26Q => month=${row.month}, party=${row.deducteeName}, '
        'pan=${row.panNumber}, deducted=${row.deductedAmount}, tds=${row.tds}, section=${row.section}',
      );
    }

    return deduped;
  }

  static ({List<Tds26QRow> rows, List<ImportAuditRecord> auditRecords})
  parseTds26QRowsWithAudit(
    List<int> bytes, {
    required String sourceFileName,
    String? sheetName,
    ImportSessionCache? sessionCache,
    int? headerRowIndex,
    bool? headersTrusted,
    Map<String, String>? columnMapping,
  }) {
    final extracted = columnMapping == null
        ? _extractImportedRowCandidates(
            bytes,
            forcedType: ExcelImportType.tds26q,
            sourceFileName: sourceFileName,
            preferredSheetName: sheetName,
            sessionCache: sessionCache,
          )
        : _extractImportedRowCandidatesWithProfile(
            bytes,
            forcedType: ExcelImportType.tds26q,
            sourceFileName: sourceFileName,
            sheetName: sheetName ?? '',
            headerRowIndex: headerRowIndex ?? 0,
            headersTrusted: headersTrusted ?? true,
            columnMapping: columnMapping,
            sessionCache: sessionCache,
          );

    final deduped = _dedupeImportedTdsRows(
      extracted.rows,
      sourceFileName: sourceFileName,
      sheetName: extracted.sheetName,
    );

    return (
      rows: deduped.rows,
      auditRecords: <ImportAuditRecord>[
        ...extracted.auditRecords,
        ...deduped.auditRecords,
      ],
    );
  }

  static List<Tds26QRow> parseTds26QRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    String sourceFileName = '',
    ImportSessionCache? sessionCache,
  }) {
    return parseTds26QRowsWithAudit(
      bytes,
      sourceFileName: sourceFileName,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
      sessionCache: sessionCache,
    ).rows;
  }

  static List<NormalizedLedgerRow> parseGenericLedgerRows(
    List<int> bytes, {
    required String defaultSection,
    String sourceFileName = '',
    String? sheetName,
    ImportSessionCache? sessionCache,
  }) {
    return parseGenericLedgerRowsWithAudit(
      bytes,
      defaultSection: defaultSection,
      sourceFileName: sourceFileName,
      sheetName: sheetName,
      sessionCache: sessionCache,
    ).rows;
  }

  static ({
    List<NormalizedLedgerRow> rows,
    List<ImportAuditRecord> auditRecords,
  })
  parseGenericLedgerRowsWithAudit(
    List<int> bytes, {
    required String defaultSection,
    String sourceFileName = '',
    ImportSessionCache? sessionCache,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    Map<String, String>? columnMapping,
  }) {
    final extracted = columnMapping == null
        ? _extractImportedRowCandidates(
            bytes,
            forcedType: ExcelImportType.genericLedger,
            sourceFileName: sourceFileName,
            preferredSheetName: sheetName,
            sessionCache: sessionCache,
          )
        : _extractImportedRowCandidatesWithProfile(
            bytes,
            forcedType: ExcelImportType.genericLedger,
            sourceFileName: sourceFileName,
            sheetName: sheetName ?? '',
            headerRowIndex: headerRowIndex ?? 0,
            headersTrusted: headersTrusted ?? true,
            columnMapping: columnMapping,
            sessionCache: sessionCache,
          );
    final prepared = _prepareGenericLedgerAuditRows(
      extracted.rows,
      sourceFileName: sourceFileName,
      sheetName: extracted.sheetName,
      sectionBucket: defaultSection,
    );

    final deduped = _dedupeImportedNormalizedLedgerRows(
      prepared.rows
          .map(
            (candidate) => (
              row: NormalizedLedgerRow.fromMap(
                candidate.rowMap,
                sourceFileName: sourceFileName,
                defaultSection: defaultSection,
              ),
              rowNumber: candidate.rowNumber,
            ),
          )
          .toList(),
      sourceFileName: sourceFileName,
      sheetName: extracted.sheetName,
      sectionBucket: defaultSection,
    );

    _logGenericLedgerImportAudit((
      rows: prepared.rows.map((candidate) => candidate.rowMap).toList(),
      sourceRowCount: extracted.rows.length,
      parsedTransactionCount: prepared.rows.length,
      continuationMergedCount: prepared.auditRecords
          .where(
            (record) => record.reason == ImportAuditReason.continuationMerged,
          )
          .length,
      invalidRowsSkippedCount: prepared.auditRecords
          .where(
            (record) => record.reason == ImportAuditReason.invalidRowSkipped,
          )
          .length,
    ));

    return (
      rows: deduped.rows,
      auditRecords: <ImportAuditRecord>[
        ...extracted.auditRecords,
        ...prepared.auditRecords,
        ...deduped.auditRecords,
      ],
    );
  }

  static List<NormalizedLedgerRow> parseGenericLedgerRowsWithProfile(
    List<int> bytes, {
    required String sheetName,
    required int headerRowIndex,
    required bool headersTrusted,
    required Map<String, String> columnMapping,
    required String defaultSection,
    String sourceFileName = '',
    ImportSessionCache? sessionCache,
  }) {
    return parseGenericLedgerRowsWithAudit(
      bytes,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
      defaultSection: defaultSection,
      sourceFileName: sourceFileName,
      sessionCache: sessionCache,
    ).rows;
  }

  static ExcelValidationResult validatePurchaseFile(
    List<int> bytes, {
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.purchase,
      preferredSheetName: preferredSheetName,
    );

    if (sheetInfo == null) {
      return ExcelValidationResult.invalid(
        'Could not detect a valid purchase register sheet.',
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return ExcelValidationResult.invalid('Detected purchase sheet is empty.');
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

    _debugVerbose('PURCHASE PRESENT HEADERS => $presentHeaders');

    final hasPurchaseDate = _hasPurchaseDateColumn(presentHeaders);
    final hasPurchaseAmount = _hasPurchaseAmountColumn(presentHeaders);

    _debugVerbose('FINAL HEADERS => $presentHeaders');
    _debugVerbose('HAS DATE => $hasPurchaseDate');
    _debugVerbose('HAS AMOUNT => $hasPurchaseAmount');

    final missing = <String>[
      if (!hasPurchaseDate) 'Date / EOM',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!hasPurchaseAmount) 'Amount Column',
    ];

    final mappedColumns = _headerPreviewMap(rawHeaderRow, mappedHeaders);

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Column mapping is required instead of auto-parsing.',
      );
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: warnings,
        confidenceScore: confidenceScore,
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (missing.isNotEmpty) {
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: [
          ...warnings,
          'Required purchase columns need confirmation: ${missing.join(', ')}.',
        ],
        confidenceScore: confidenceScore,
        message:
            'Required purchase columns need review before import: ${missing.join(', ')}',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    final hasSuspiciousAmountCollision = _hasSuspiciousAmountCollision(
      mappedHeaders,
      rawHeaderRow,
    );

    if (hasSuspiciousAmountCollision) {
      warnings.add(
        'Amount columns could not be clearly distinguished. Bill Amount will be used as the primary purchase amount.',
      );
    }

    if (confidenceScore < 0.65) {
      warnings.add(
        'Low header-detection confidence. Review column mapping if imported values look incorrect.',
      );
    }

    final parsed = _parsePurchaseRowsFromPreparedSheet(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: sheetInfo.headersTrusted,
    );

    if (parsed.isEmpty) {
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: [
          ...warnings,
          'Auto-detected mapping produced no parsed purchase rows.',
        ],
        confidenceScore: confidenceScore,
        message: 'Auto-detected mapping needs review before import.',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    final validAmountRows = parsed.where((e) => e.basicAmount > 0).length;
    if (validAmountRows == 0) {
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: [
          ...warnings,
          'Detected purchase amount column produced zero values for all parsed rows.',
        ],
        confidenceScore: confidenceScore,
        message: 'Purchase amount mapping needs manual review before import.',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    final billAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.billAmount);
    final basicAmountSum = parsed.fold<double>(
      0.0,
      (s, e) => s + e.basicAmount,
    );
    warnings.addAll(_buildPurchaseWarnings(parsed));

    if (billAmountSum > 0 && (billAmountSum - basicAmountSum).abs() < 1) {
      warnings.add(
        'Single amount column detected (Bill Amount used as Basic Amount)',
      );
    }

    if (hasSuspiciousAmountCollision) {
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: mappedColumns,
        warnings: warnings,
        confidenceScore: confidenceScore,
        message: 'Purchase amount columns need manual review before import.',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: mappedColumns,
      warnings: warnings,
      confidenceScore: confidenceScore,
      unmappedRawHeaders: unmappedRawHeaders,
    );
  }

  static ExcelValidationResult validateTds26QFile(
    List<int> bytes, {
    String? preferredSheetName,
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final selectableSheets = _list26QSelectableSheetsFromDecoder(decoder);
    final preferred26QSheet =
        preferredSheetName ??
        _detectBest26QSheet({
          for (final entry in decoder.tables.entries)
            entry.key: entry.value.rows,
        });

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
      return ExcelValidationResult.invalid('Detected 26Q sheet is empty.');
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
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!presentHeaders.contains('pan_number')) 'PAN',
      if (!presentHeaders.contains('amount_paid')) 'Amount Paid',
      if (!presentHeaders.contains('tds_amount')) 'TDS',
      if (!presentHeaders.contains('section')) 'Section',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Column mapping is required instead of auto-parsing.',
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
      if (!_hasPlausibleDataRowsAfterHeader(
        table.rows,
        sheetInfo.headerRowIndex,
      )) {
        return ExcelValidationResult.invalid(
          'Missing required 26Q columns: ${missing.join(', ')}',
        );
      }

      warnings.add(
        'Missing required 26Q columns: ${missing.join(', ')}. Manual column mapping is required.',
      );
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(
          table.rows[sheetInfo.headerRowIndex],
          mappedHeaders,
        ),
        warnings: warnings,
        confidenceScore: confidenceScore,
        message:
            '26Q column detection is incomplete. Review column mapping before import.',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    final parsed = _parseTdsRowsFromPreparedSheet(
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: sheetInfo.headersTrusted,
    );

    if (parsed.isEmpty) {
      return ExcelValidationResult.invalid(
        'No valid 26Q rows found after parsing.',
      );
    }

    final validAmountRows = parsed
        .where((e) => e.deductedAmount > 0 || e.tds > 0)
        .length;
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

  static bool _hasPlausibleDataRowsAfterHeader(
    List<List<dynamic>> rows,
    int headerRowIndex,
  ) {
    if (headerRowIndex < 0 || headerRowIndex + 1 >= rows.length) {
      return false;
    }

    for (final row in rows.skip(headerRowIndex + 1).take(20)) {
      final nonEmptyCellCount = row
          .where((cell) => cell?.toString().trim().isNotEmpty == true)
          .length;
      if (nonEmptyCellCount >= 2) {
        return true;
      }
    }

    return false;
  }

  static ExcelValidationResult validateGenericLedgerFile(
    List<int> bytes, {
    String? preferredSheetName,
    String? expectedSection,
    String sourceFileName = '',
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.genericLedger,
      preferredSheetName: preferredSheetName,
    );

    if (sheetInfo == null) {
      return ExcelValidationResult.invalid(
        'Could not detect a valid ledger sheet.',
      );
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return ExcelValidationResult.invalid('Detected ledger sheet is empty.');
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
    warnings.addAll(
      _buildGenericLedgerSectionWarnings(
        rows: table.rows,
        headerRowIndex: sheetInfo.headerRowIndex,
        headersTrusted: sheetInfo.headersTrusted,
        expectedSection: expectedSection,
        sourceFileName: sourceFileName,
        sheetName: sheetInfo.sheetName,
      ),
    );

    final hasDate = presentHeaders.contains('date');
    final hasAmount = presentHeaders.contains('amount');
    final amountDiagnostics = _analyzeGenericLedgerAmountMapping(
      rawHeaderRow: rawHeaderRow,
      mappedHeaders: mappedHeaders,
      rows: table.rows,
      headerRowIndex: sheetInfo.headerRowIndex,
      headersTrusted: sheetInfo.headersTrusted,
    );

    final missing = <String>[
      if (!hasDate) 'Date',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!hasAmount) 'Amount',
    ];

    if ((!sheetInfo.headersTrusted && confidenceScore < 0.60) ||
        (sheetInfo.headersTrusted && confidenceScore < 0.70)) {
      warnings.add(
        'Header detection is weak. Column mapping is required instead of auto-parsing.',
      );
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
        warnings: warnings,
        confidenceScore: confidenceScore,
        message: 'Generic ledger column mapping needs review before import.',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (missing.isNotEmpty) {
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
        warnings: [
          ...warnings,
          'Required ledger columns need confirmation: ${missing.join(', ')}.',
        ],
        confidenceScore: confidenceScore,
        message:
            'Required ledger columns need review before import: ${missing.join(', ')}',
        unmappedRawHeaders: unmappedRawHeaders,
      );
    }

    if (amountDiagnostics.selectedColumn.isEmpty ||
        amountDiagnostics.numericRatio < 0.60) {
      warnings.add(
        'Amount column detection is not reliable enough for auto-import.',
      );
      return ExcelValidationResult.manualReview(
        detectedSheet: sheetInfo.sheetName,
        headerRowIndex: sheetInfo.headerRowIndex,
        detectedType: sheetInfo.detectedType,
        mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
        warnings: warnings,
        confidenceScore: confidenceScore,
        message: 'Amount mapping needs review before import.',
        unmappedRawHeaders: unmappedRawHeaders,
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

    final sheetInfo = _findBestSheetAndHeader(decoder, forcedType: forcedType);

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
  })?
  _findBestSheetAndHeader(
    SpreadsheetDecoder decoder, {
    ExcelImportType? forcedType,
    String? preferredSheetName,
  }) {
    final cacheKey = _workbookCacheKey(
      decoder,
      forcedType: forcedType,
      preferredSheetName: preferredSheetName,
    );
    final cached = _headerDetectionCache[cacheKey];
    if (cached != null) {
      AppLogger.debug(
        'HEADER CACHE HIT => sheet=${cached.sheetName} row=${cached.headerRowIndex} type=${cached.detectedType.name}',
      );
      return cached;
    }

    final preferred26QSheet =
        preferredSheetName ??
        (forcedType == ExcelImportType.tds26q
            ? _detectBest26QSheet({
                for (final entry in decoder.tables.entries)
                  entry.key: entry.value.rows,
              })
            : null);

    if (forcedType == ExcelImportType.tds26q &&
        preferredSheetName == null &&
        (preferred26QSheet == null || preferred26QSheet.isEmpty)) {
      AppLogger.debug(
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
    })?
    best;

    for (final entry in decoder.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;
      final isExplicitlySelectedSheet =
          preferredSheetName != null && sheetName == preferredSheetName;
      final headerScanLimit = isExplicitlySelectedSheet
          ? _selectedSheetHeaderScanRowLimit
          : _defaultHeaderScanRowLimit;
      final structuredHeaderScanLimit = isExplicitlySelectedSheet
          ? _selectedSheetHeaderScanRowLimit
          : _defaultStructuredHeaderScanRowLimit;

      if (table.rows.isEmpty) continue;
      if (preferredSheetName != null && sheetName != preferredSheetName) {
        continue;
      }
      if (forcedType == ExcelImportType.tds26q) {
        if (preferred26QSheet != null && preferred26QSheet.isNotEmpty) {
          if (sheetName != preferred26QSheet) continue;
        } else {
          if (_isLikely26QReferenceSheet(table.rows)) {
            AppLogger.debug('Rejected $sheetName as reference sheet');
            AppLogger.debug('Skipping reference sheet: $sheetName');
            continue;
          }
        }
      }

      if (forcedType == ExcelImportType.genericLedger) {
        final ledgerCandidate = _detectGenericLedgerHeaderCandidate(
          table.rows,
          sheetName: sheetName,
          scanLimit: structuredHeaderScanLimit,
        );
        if (ledgerCandidate != null &&
            (best == null || ledgerCandidate.score > best.score)) {
          best = (
            sheetName: sheetName,
            headerRowIndex: ledgerCandidate.headerRowIndex,
            detectedType: ExcelImportType.genericLedger,
            headersTrusted: ledgerCandidate.headersTrusted,
            score: ledgerCandidate.score,
          );
        }
        continue;
      }

      if (forcedType == ExcelImportType.purchase) {
        final purchaseCandidates = _collectStructuredHeaderCandidates(
          table.rows,
          type: ExcelImportType.purchase,
          fileLabel: sheetName,
          scanLimit: structuredHeaderScanLimit,
        );
        if (purchaseCandidates.isNotEmpty) {
          final purchaseCandidate = purchaseCandidates.first;
          final purchaseScore =
              purchaseCandidate.score +
              _sheetNameBonus(sheetName, type: ExcelImportType.purchase);
          if (best == null || purchaseScore > best.score) {
            best = (
              sheetName: sheetName,
              headerRowIndex: purchaseCandidate.headerRowIndex,
              detectedType: ExcelImportType.purchase,
              headersTrusted: true,
              score: purchaseScore,
            );
          }
        }
        continue;
      }

      for (int i = 0; i < table.rows.length && i < headerScanLimit; i++) {
        final row = table.rows[i];

        int purchaseScore = _scoreHeaderRow(
          row,
          type: ExcelImportType.purchase,
        );
        bool purchaseHeadersTrusted = purchaseScore > 0;

        int tdsScore = _scoreHeaderRow(row, type: ExcelImportType.tds26q);
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

        tdsScore += _sheetNameBonus(sheetName, type: ExcelImportType.tds26q);

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

    AppLogger.debug('DETECTION CHOSEN SHEET => ${best.sheetName}');
    AppLogger.debug('DETECTION HEADER ROW => ${best.headerRowIndex}');
    AppLogger.debug('DETECTION CONFIDENCE => $confidenceScore');

    final resolved = (
      sheetName: best.sheetName,
      headerRowIndex: best.headerRowIndex,
      detectedType: best.detectedType,
      headersTrusted: best.headersTrusted,
    );
    _headerDetectionCache[cacheKey] = resolved;
    return resolved;
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
      _debugVerbose(
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
      _debugVerbose(
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
      AppLogger.debug(
        '26Q SHEET SELECTION => weak confidence, no sheet auto-selected '
        '(best=${bestSheet ?? 'none'}, score=$bestScore, gap=$scoreGap)',
      );
      return null;
    }

    AppLogger.debug('26Q SHEET SELECTION => selected $bestSheet');
    return bestSheet;
  }

  static List<String> list26QSelectableSheets(
    List<int> bytes, {
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
    if (decoder.tables.isEmpty) return const [];
    return _list26QSelectableSheetsFromDecoder(decoder);
  }

  static List<String> listWorkbookSheetNames(
    List<int> bytes, {
    ImportSessionCache? sessionCache,
  }) {
    final decoder = _decoderFromCache(bytes, sessionCache: sessionCache);
    return decoder.tables.keys.toList();
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

    final hasReferenceHeaders =
        normalizedHeaders.any(
          (header) => header == 'name' || header.contains('deductee'),
        ) &&
        normalizedHeaders.any(
          (header) => header == 'pan' || header.contains('pan'),
        ) &&
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

    final hasTransactionSignals =
        _containsSectionValues(rows) ||
        _containsDateLikeValues(rows) ||
        _containsLargeAmountColumn(rows) ||
        _containsTdsAmountColumn(rows);

    if (!hasTransactionSignals) {
      _debugVerbose('Rejected ${headerRow.join(' | ')} as reference sheet');
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
    final width = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );

    for (int column = 0; column < width; column++) {
      final header = column < headerRow.length
          ? _normalizeLooseText(headerRow[column]?.toString() ?? '')
          : '';
      final headerHintsAmountPaid =
          header.contains('amount paid') ||
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
    final width = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );

    for (int column = 0; column < width; column++) {
      final header = column < headerRow.length
          ? _normalizeLooseText(headerRow[column]?.toString() ?? '')
          : '';
      final headerHintsTds =
          header == 'tds' ||
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

  static int _findLikely26QHeaderRowIndex(
    List<List<dynamic>> rows, {
    int scanLimit = _moderate26QHelperHeaderScanRowLimit,
  }) {
    var bestIndex = 0;
    var bestScore = -1;

    for (int i = 0; i < rows.length && i < scanLimit; i++) {
      final score = _scoreHeaderRow(rows[i], type: ExcelImportType.tds26q);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  static List<({int headerRowIndex, int score, List<String> matchedFields})>
  _collectStructuredHeaderCandidates(
    List<List<dynamic>> rows, {
    required ExcelImportType type,
    required String fileLabel,
    int scanLimit = _defaultStructuredHeaderScanRowLimit,
  }) {
    final candidates =
        <({int headerRowIndex, int score, List<String> matchedFields})>[];

    for (int i = 0; i < rows.length && i < scanLimit; i++) {
      final evaluation = _evaluateStructuredHeaderRow(rows[i], type: type);
      if (evaluation == null) {
        continue;
      }

      candidates.add((
        headerRowIndex: i,
        score: evaluation.score,
        matchedFields: evaluation.matchedFields,
      ));
    }

    candidates.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return left.headerRowIndex.compareTo(right.headerRowIndex);
    });

    final selected = candidates.isEmpty ? null : candidates.first;
    AppLogger.debug(
      'UPLOAD HEADER DETECT => '
      'file=$fileLabel '
      'selectedRow=${selected == null ? 0 : selected.headerRowIndex + 1} '
      'score=${selected?.score ?? 0} '
      'matchedFields=${selected == null ? '' : selected.matchedFields.join('|')}',
    );

    return candidates;
  }

  static ({int score, List<String> matchedFields})?
  _evaluateStructuredHeaderRow(
    List<dynamic> row, {
    required ExcelImportType type,
  }) {
    if (type != ExcelImportType.purchase &&
        type != ExcelImportType.genericLedger) {
      return null;
    }

    final normalizedCells = row
        .map((cell) => _normalizeLooseText(cell?.toString() ?? ''))
        .where((value) => value.isNotEmpty)
        .toList();
    final nonEmptyCount = normalizedCells.length;
    if (nonEmptyCount < 2) {
      return null;
    }

    final mappedHeaders = _buildMappedHeaders(row, forcedType: type);
    final presentHeaders = mappedHeaders.whereType<String>().toSet();
    if (presentHeaders.isEmpty) {
      return null;
    }

    if (_looksLikeDecorativePreludeRow(
      normalizedCells,
      presentHeaders: presentHeaders,
      type: type,
    )) {
      return null;
    }

    final matchedFields = presentHeaders.toList()..sort();
    final signalCount = _headerSignalCount(presentHeaders, type: type);
    var score = _scoreHeaderRow(row, type: type);

    if (type == ExcelImportType.purchase) {
      if (signalCount >= 4) {
        score += 20;
      } else if (signalCount == 3) {
        score += 8;
      }
      if (presentHeaders.contains('date') && presentHeaders.contains('eom')) {
        score += 10;
      }
      if ((presentHeaders.contains('pan_number') ||
              presentHeaders.contains('gst_no')) &&
          presentHeaders.contains('party_name')) {
        score += 6;
      }
      if (signalCount < 3 && presentHeaders.length < 4) {
        return null;
      }
      if (score < 55) {
        return null;
      }
    } else {
      if (signalCount == 3) {
        score += 18;
      } else if (signalCount == 2) {
        score += 6;
      }
      if ((presentHeaders.contains('party_name') ||
              presentHeaders.contains('description')) &&
          presentHeaders.contains('bill_no')) {
        score += 4;
      }
      if (signalCount < 2 || score < 45) {
        return null;
      }
    }

    if (nonEmptyCount >= 4 && nonEmptyCount <= 14) {
      score += 8;
    } else if (nonEmptyCount >= 20) {
      score -= 6;
    }

    return (score: score, matchedFields: matchedFields);
  }

  static int _headerSignalCount(
    Set<String> presentHeaders, {
    required ExcelImportType type,
  }) {
    if (type == ExcelImportType.purchase) {
      return [
        presentHeaders.contains('date') || presentHeaders.contains('eom'),
        presentHeaders.contains('bill_no'),
        presentHeaders.contains('party_name'),
        presentHeaders.contains('bill_amount') ||
            presentHeaders.contains('basic_amount'),
        presentHeaders.contains('pan_number') ||
            presentHeaders.contains('gst_no'),
      ].where((value) => value).length;
    }

    return [
      presentHeaders.contains('date'),
      presentHeaders.contains('party_name') ||
          presentHeaders.contains('description'),
      presentHeaders.contains('amount'),
      presentHeaders.contains('bill_no'),
      presentHeaders.contains('pan_number') ||
          presentHeaders.contains('gst_no'),
    ].where((value) => value).length;
  }

  static bool _looksLikeDecorativePreludeRow(
    List<String> normalizedCells, {
    required Set<String> presentHeaders,
    required ExcelImportType type,
  }) {
    final joined = normalizedCells.join(' ');
    final headerKeywordHit = normalizedCells.any(
      (cell) => _rowContainsKnownHeaderKeyword(cell, type: type),
    );
    final looksLikeDateRange = _looksLikeDateRangeText(joined);
    final looksLikeMetaTitle =
        joined.contains('report') ||
        joined.contains('register') ||
        joined.contains('statement') ||
        joined.contains('summary');
    final looksLikeAddress =
        joined.contains('address') ||
        joined.contains('road') ||
        joined.contains('street') ||
        joined.contains('near ') ||
        joined.contains('dist ') ||
        joined.contains('pin ');

    if (presentHeaders.length == 1 &&
        presentHeaders.contains('party_name') &&
        normalizedCells.length <= 2) {
      return true;
    }

    if (!headerKeywordHit &&
        normalizedCells.length <= 2 &&
        (looksLikeDateRange || looksLikeMetaTitle || looksLikeAddress)) {
      return true;
    }

    return false;
  }

  static bool _rowContainsKnownHeaderKeyword(
    String text, {
    required ExcelImportType type,
  }) {
    final dictionary = type == ExcelImportType.purchase
        ? _purchaseHeaderDictionary
        : _genericLedgerHeaderDictionary;

    for (final aliases in dictionary.values) {
      for (final alias in aliases) {
        if (_headerSimilarityScore(text, alias) >= 90) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _looksLikeDateRangeText(String text) {
    final hasTwoDates =
        RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}').allMatches(text).length >= 2;
    if (hasTwoDates) {
      return true;
    }

    return (text.contains('from') && text.contains('to')) ||
        text.contains('period') ||
        text.contains('date range');
  }

  static double? _tryParseNumericCell(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final text = value.toString().replaceAll(',', '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String inferSection(double amount, double tds, {String? sectionHint}) {
    final normalizedHint = normalizeSection(sectionHint ?? '');
    if (TdsSectionCatalog.supportedSectionCodeSet.contains(normalizedHint) ||
        normalizedHint == '194J' ||
        normalizedHint == '194I') {
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
    final mappedHeaders = _buildMappedHeaders(row, forcedType: type);

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
      if (presentHeaders.contains('date')) score += 35;
      if (presentHeaders.contains('party_name')) score += 35;
      if (presentHeaders.contains('amount')) score += 35;
      if (presentHeaders.contains('bill_no')) score += 12;
      if (presentHeaders.contains('description')) score += 10;
      if (presentHeaders.contains('pan_number')) score += 10;
      if (presentHeaders.contains('gst_no')) score += 5;
      if (presentHeaders.length >= 4) score += 8;
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
    if (presentHeaders.contains('party_name')) matchedRequired++;
    if (presentHeaders.contains('pan_number')) matchedRequired++;
    if (presentHeaders.contains('amount_paid')) matchedRequired++;
    if (presentHeaders.contains('tds_amount')) matchedRequired++;
    if (presentHeaders.contains('section')) matchedRequired++;

    return (matchedRequired / 6.0).clamp(0.0, 1.0);
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
    final sampleRows = rows.skip(headerRowIndex + 1).take(8).toList();
    final resolved = headersTrusted
        ? _buildMappedHeaders(
            rows[headerRowIndex],
            forcedType: forcedType,
            sampleRows: sampleRows,
          )
        : _inferMappedHeadersFromDataRows(
            rows.skip(headerRowIndex).take(8).toList(),
            type: forcedType,
          );

    if (forcedType == ExcelImportType.genericLedger) {
      return _sanitizeGenericLedgerMappedHeaders(
        rawHeaderRow: rows[headerRowIndex],
        mappedHeaders: resolved,
      );
    }

    return resolved;
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

    return ImportMappingService.dedupeSourceColumns(result);
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
      return columnMapping.containsKey('date_month') &&
          columnMapping.containsKey('party_name') &&
          columnMapping.containsKey('pan_number') &&
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

    final width = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
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
        _debugVerbose(
          'GENERIC LEDGER COLUMN SCORE => COL_$c '
          'samples=${samples.take(2).join(' | ')} '
          'scores=$scores',
        );
        final best = _pickBestInferredColumn(scores, assigned);

        if (best == null || best.$2 < 8) continue;

        mapped[c] = best.$1;
        assigned.add(best.$1);
      }

      _debugVerbose(
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
          if (profile.largeNumericCount >= 2 ||
              profile.smallNumericCount >= 2) {
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

  static List<String> _columnSamples(
    List<List<dynamic>> rows,
    int columnIndex,
  ) {
    return rows
        .take(8)
        .map(
          (row) => columnIndex < row.length
              ? (row[columnIndex]?.toString().trim() ?? '')
              : '',
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
    })
    profile,
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
  })
  _analyzeColumnProfile(List<String> samples) {
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
    return RegExp(r'^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$').hasMatch(value.trim());
  }

  static bool _looksLikePanText(String value) {
    return RegExp(
      r'^[A-Z]{5}[0-9]{4}[A-Z]$',
    ).hasMatch(value.trim().toUpperCase());
  }

  static bool _looksLikeGstText(String value) {
    return RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$',
    ).hasMatch(value.trim().toUpperCase());
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

  static bool _isExplicitGenericLedgerSectionHeader(String value) {
    final normalized = _normalizeLooseText(value);
    return normalized == 'section' ||
        normalized == 'tds section' ||
        normalized == 'section code' ||
        normalized == 'sec' ||
        normalized == 'tds sec';
  }

  static Set<String> _detectExplicitGenericLedgerSections({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required bool headersTrusted,
  }) {
    if (!headersTrusted ||
        headerRowIndex < 0 ||
        headerRowIndex >= rows.length) {
      return const <String>{};
    }

    final headerRow = rows[headerRowIndex];
    final sectionColumns = <int>[];
    for (var i = 0; i < headerRow.length; i++) {
      if (_isExplicitGenericLedgerSectionHeader(
        headerRow[i]?.toString() ?? '',
      )) {
        sectionColumns.add(i);
      }
    }

    if (sectionColumns.isEmpty) return const <String>{};

    final detected = <String>{};
    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      for (final columnIndex in sectionColumns) {
        if (columnIndex >= row.length) continue;
        final normalized = TdsSectionCatalog.normalizeCode(
          row[columnIndex]?.toString() ?? '',
        );
        if (TdsSectionCatalog.supportedSectionCodeSet.contains(normalized)) {
          detected.add(normalized);
        }
      }
    }

    return detected;
  }

  static Set<String> _detectStrongSectionMentions(String value) {
    final compact = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (compact.isEmpty) return const <String>{};

    final detected = <String>{};
    const aliases = <String, String>{
      '194IA': '194I_A',
      '194IB': '194I_B',
      '194JA': '194J_A',
      '194JB': '194J_B',
      '194Q': '194Q',
      '194A': '194A',
      '194C': '194C',
      '194H': '194H',
    };

    for (final entry in aliases.entries) {
      if (compact.contains(entry.key)) {
        detected.add(entry.value);
      }
    }

    return detected;
  }

  static List<String> _buildGenericLedgerSectionWarnings({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required bool headersTrusted,
    required String? expectedSection,
    required String sourceFileName,
    required String sheetName,
  }) {
    final selectedSection = TdsSectionCatalog.normalizeCode(
      expectedSection ?? '',
    );
    if (!TdsSectionCatalog.supportedSectionCodeSet.contains(selectedSection)) {
      return const <String>[];
    }

    final warnings = <String>[];
    void addWarning(String warning) {
      if (!warnings.contains(warning)) warnings.add(warning);
    }

    final explicitSections = _detectExplicitGenericLedgerSections(
      rows: rows,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
    ).toList()..sort(TdsSectionCatalog.compare);

    if (explicitSections.length > 1) {
      addWarning(
        'This ledger appears to contain multiple TDS sections: ${explicitSections.join(', ')}. LedgerMatch will not split mixed ledgers yet; review before confirming.',
      );
    }

    final explicitMismatches = explicitSections
        .where((section) => section != selectedSection)
        .toList();
    if (explicitMismatches.isNotEmpty) {
      addWarning(
        'This ledger section column contains ${explicitMismatches.join(', ')}, but it was uploaded under $selectedSection. Review before confirming.',
      );
    }

    final labelSections = _detectStrongSectionMentions(
      '$sourceFileName $sheetName',
    ).toList()..sort(TdsSectionCatalog.compare);
    if (labelSections.length == 1 && labelSections.single != selectedSection) {
      addWarning(
        'The file or sheet name suggests ${labelSections.single}, but the selected upload section is $selectedSection. Review before confirming.',
      );
    }

    return warnings;
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
    List<List<dynamic>> sampleRows = const [],
  }) {
    final cacheKey = _columnScoreCacheKey(
      rawHeaderRow: rawHeaderRow,
      forcedType: forcedType,
    );
    final cached = _columnScoreCache[cacheKey];
    if (cached != null) {
      _debugVerbose(
        'COLUMN SCORE CACHE HIT => type=${forcedType.name} columns=${rawHeaderRow.length}',
      );
      return List<String?>.from(cached);
    }

    final stopwatch = Stopwatch()..start();
    final usedCanonical = <String>{};
    final mapped = <String?>[];
    final preferDebitAmount =
        forcedType == ExcelImportType.genericLedger &&
        rawHeaderRow.any(
          (cell) => _isPreferredDebitHeader(
            _normalizeLooseText(cell?.toString() ?? ''),
          ),
        );

    for (int i = 0; i < rawHeaderRow.length; i++) {
      final cell = rawHeaderRow[i];
      final raw = cell?.toString() ?? '';

      final colSamples = sampleRows
          .where((r) => r.length > i && r[i] != null)
          .map((r) => r[i].toString().trim())
          .where((v) => v.isNotEmpty)
          .toList();

      final canonical = _detectCanonicalHeader(
        raw,
        type: forcedType,
        usedCanonical: usedCanonical,
        preferDebitAmount: preferDebitAmount,
        sampleValues: colSamples,
      );

      if (canonical != null) {
        usedCanonical.add(canonical);
      }

      mapped.add(canonical);
    }

    stopwatch.stop();
    _debugVerbose(
      'COLUMN SCORE PERF => columns=${rawHeaderRow.length} rowsSampled=${sampleRows.length} ms=${stopwatch.elapsedMilliseconds}',
    );

    _columnScoreCache[cacheKey] = List<String?>.from(mapped);

    return mapped;
  }

  static bool _looksLikeDateValue(String value) {
    final val = value.trim();
    if (val.isEmpty) return false;
    final dateRegExp = RegExp(r'^(\d{1,4})[/\-](\d{1,2})[/\-](\d{1,4})$');
    if (dateRegExp.hasMatch(val)) return true;
    final dateWithTime = RegExp(
      r'^(\d{1,4})[/\-](\d{1,2})[/\-](\d{1,4})\s+\d{1,2}:\d{1,2}',
    );
    if (dateWithTime.hasMatch(val)) return true;
    return false;
  }

  static bool _looksLikeAmountValue(String value) {
    final val = value.trim().replaceAll(',', '');
    if (val.isEmpty) return false;
    if (_looksLikeDateValue(val)) return false;
    final amountRegExp = RegExp(r'^-?\d+(\.\d+)?$');
    return amountRegExp.hasMatch(val);
  }

  static bool _isTextHeavyGenericLedgerAmountHeader(String normalizedHeader) {
    return normalizedHeader.contains('party') ||
        normalizedHeader.contains('particular') ||
        normalizedHeader.contains('narration') ||
        normalizedHeader.contains('description') ||
        normalizedHeader.contains('ledger name') ||
        normalizedHeader.contains('account name') ||
        normalizedHeader == 'name';
  }

  static bool _isPreferredGenericLedgerAmountHeader(String normalizedHeader) {
    const preferredHeaders = {
      'amount',
      'debit',
      'credit',
      'gross amount',
      'taxable amount',
      'bill amount',
      'basic amount',
      'total amount',
      'debit amount',
      'credit amount',
      'dr amount',
      'cr amount',
    };
    if (preferredHeaders.contains(normalizedHeader)) {
      return true;
    }

    return normalizedHeader.contains('amount') ||
        normalizedHeader == 'debit' ||
        normalizedHeader == 'credit';
  }

  static void _logGenericLedgerAmountRejected({
    required String rawHeader,
    required String reason,
  }) {
    _debugVerbose(
      'AUTO MAP DEBUG => rejectedColumn=$rawHeader for amount reason=$reason',
    );
  }

  static void _logGenericLedgerAmountSelected({
    required String selectedColumn,
    required String reason,
    required double numericRatio,
  }) {
    _debugVerbose(
      'AUTO MAP DEBUG => field=amount selectedColumn=$selectedColumn reason=$reason numericRatio=${numericRatio.toStringAsFixed(2)}',
    );
  }

  static void _logGenericLedgerDomainReject({
    required String field,
    required String column,
    required String reason,
  }) {
    _debugVerbose(
      'AUTO MAP DOMAIN REJECT => field=$field column=$column reason=$reason',
    );
  }

  static bool _isDateLikeAmountCandidateHeader(String normalizedHeader) {
    return normalizedHeader.contains('date') ||
        normalizedHeader.contains('month') ||
        normalizedHeader.contains('eom');
  }

  static String? _genericLedgerPartyNameRejectReason(String normalizedHeader) {
    const blockedTokens = [
      'bill no',
      'bill number',
      'voucher no',
      'voucher number',
      'invoice no',
      'invoice number',
      'document no',
      'document number',
      'doc no',
      'doc number',
      'ref no',
      'reference no',
    ];
    for (final token in blockedTokens) {
      if (normalizedHeader.contains(token)) {
        return 'bill-number-column';
      }
    }
    return null;
  }

  static String? _genericLedgerAmountRejectReason(String normalizedHeader) {
    if (normalizedHeader.contains('tds amount') ||
        normalizedHeader == 'tds' ||
        normalizedHeader.contains('tds amt') ||
        normalizedHeader.contains('withholding') ||
        normalizedHeader.contains('deduction') ||
        normalizedHeader.contains('tax deducted')) {
      return 'tds-not-base-amount';
    }
    if (normalizedHeader.contains('tax amount') &&
        !normalizedHeader.contains('taxable')) {
      return 'tax-not-base-amount';
    }
    return null;
  }

  static int _genericLedgerDomainPenalty(
    String canonical,
    String normalizedHeader,
  ) {
    if (canonical == 'party_name') {
      if (normalizedHeader.contains('bill') ||
          normalizedHeader.contains('voucher') ||
          normalizedHeader.contains('invoice') ||
          normalizedHeader.contains('document') ||
          normalizedHeader.contains('doc ') ||
          normalizedHeader.contains('reference') ||
          normalizedHeader.contains('ref ')) {
        return -40;
      }
    }

    if (canonical == 'amount') {
      if (normalizedHeader.contains('tds') ||
          normalizedHeader.contains('withholding') ||
          normalizedHeader.contains('deduction')) {
        return -60;
      }
      if (normalizedHeader.contains('tax amount') &&
          !normalizedHeader.contains('taxable')) {
        return -45;
      }
      if (normalizedHeader.contains('gross amount') ||
          normalizedHeader.contains('basic amount') ||
          normalizedHeader.contains('transaction amount') ||
          normalizedHeader.contains('product amount') ||
          normalizedHeader.contains('bill amount')) {
        return 10;
      }
    }

    return 0;
  }

  static bool _isSellerLikeAlphabeticHeader(String normalizedHeader) {
    if (normalizedHeader.isEmpty) return false;
    if (_isPreferredGenericLedgerAmountHeader(normalizedHeader)) return false;
    if (_isTextHeavyGenericLedgerAmountHeader(normalizedHeader)) return false;
    if (_isDateLikeAmountCandidateHeader(normalizedHeader)) return false;
    if (_genericLedgerAmountRejectReason(normalizedHeader) != null) {
      return false;
    }
    if (normalizedHeader.contains('bill') ||
        normalizedHeader.contains('invoice') ||
        normalizedHeader.contains('voucher') ||
        normalizedHeader.contains('reference') ||
        normalizedHeader.contains('ref ') ||
        normalizedHeader.contains('gst') ||
        normalizedHeader.contains('pan')) {
      return false;
    }

    final compact = normalizedHeader.replaceAll(' ', '');
    if (compact.length < 8) return false;

    final sellerLikePattern = RegExp(r'^[a-z][a-z .,&()/\-]{7,}$');
    if (!sellerLikePattern.hasMatch(normalizedHeader)) return false;

    final tokens = normalizedHeader
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final alphaTokens = tokens
        .where((token) => RegExp(r'^[a-z][a-z.&()/-]*$').hasMatch(token))
        .length;
    return alphaTokens >= 2;
  }

  static void _logAmountHeuristicReject({
    required String column,
    required String reason,
  }) {
    AppLogger.debug('AMOUNT HEURISTIC REJECT => column=$column reason=$reason');
  }

  static List<String?> _sanitizeGenericLedgerMappedHeaders({
    required List<dynamic> rawHeaderRow,
    required List<String?> mappedHeaders,
  }) {
    final sanitized = List<String?>.from(mappedHeaders);

    for (int i = 0; i < sanitized.length && i < rawHeaderRow.length; i++) {
      if (sanitized[i] != 'amount') continue;

      final rawHeader = rawHeaderRow[i]?.toString().trim() ?? '';
      final normalizedHeader = _normalizeLooseText(rawHeader);
      final rejectReason =
          _genericLedgerAmountRejectReason(normalizedHeader) ??
          (_isSellerLikeAlphabeticHeader(normalizedHeader)
              ? 'seller-like'
              : null);
      if (rejectReason == null) continue;

      _logAmountHeuristicReject(column: rawHeader, reason: rejectReason);
      sanitized[i] = null;
    }

    return sanitized;
  }

  static String? _detectCanonicalHeader(
    String raw, {
    required ExcelImportType type,
    required Set<String> usedCanonical,
    bool preferDebitAmount = false,
    List<String> sampleValues = const [],
  }) {
    final normalized = _normalizeLooseText(raw);
    if (normalized.isEmpty) return null;

    int dateLikeCount = 0;
    int amountLikeCount = 0;
    for (final val in sampleValues) {
      if (_looksLikeDateValue(val)) dateLikeCount++;
      if (_looksLikeAmountValue(val)) amountLikeCount++;
    }

    if (type == ExcelImportType.purchase) {
      if (_shouldIgnorePurchaseHeader(normalized)) {
        return null;
      }

      // In many purchase exports a lone "Amount" column is the bill total.
      if (normalized == 'amount' && !usedCanonical.contains('bill_amount')) {
        return 'bill_amount';
      }
    }

    if (type == ExcelImportType.genericLedger &&
        _shouldIgnoreGenericLedgerHeader(normalized)) {
      return null;
    }

    if (type == ExcelImportType.genericLedger &&
        _isTextHeavyGenericLedgerAmountHeader(normalized)) {
      _logGenericLedgerAmountRejected(rawHeader: raw, reason: 'text-heavy');
    }

    if (type == ExcelImportType.genericLedger &&
        preferDebitAmount &&
        _isCreditOnlyHeader(normalized)) {
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

      bool isAmountField =
          canonical == 'amount' ||
          canonical == 'bill_amount' ||
          canonical == 'basic_amount' ||
          canonical == 'amount_paid' ||
          canonical == 'tds_amount';
      bool isDateField =
          canonical == 'date' ||
          canonical == 'date_month' ||
          canonical == 'eom';

      if (type == ExcelImportType.genericLedger && canonical == 'party_name') {
        final rejectReason = _genericLedgerPartyNameRejectReason(normalized);
        if (rejectReason != null) {
          _logGenericLedgerDomainReject(
            field: 'party_name',
            column: raw,
            reason: rejectReason,
          );
          continue;
        }
      }

      if (type == ExcelImportType.genericLedger &&
          canonical == 'amount' &&
          _isTextHeavyGenericLedgerAmountHeader(normalized)) {
        continue;
      }

      if (type == ExcelImportType.genericLedger && canonical == 'amount') {
        final rejectReason = _genericLedgerAmountRejectReason(normalized);
        if (rejectReason != null) {
          _logGenericLedgerDomainReject(
            field: 'amount',
            column: raw,
            reason: rejectReason,
          );
          continue;
        }
      }

      if (isAmountField &&
          (dateLikeCount > 0 && dateLikeCount >= sampleValues.length / 2)) {
        continue;
      }
      if (isAmountField && _isDateLikeAmountCandidateHeader(normalized)) {
        continue;
      }

      for (final alias in aliases) {
        int score = _headerSimilarityScore(normalized, alias);
        if (score == 0) continue;

        if (isAmountField) {
          if (amountLikeCount > 0) {
            score += 10;
          }
          if (type == ExcelImportType.genericLedger &&
              !_isPreferredGenericLedgerAmountHeader(normalized)) {
            score -= 6;
          }
        } else if (isDateField) {
          if (dateLikeCount > 0) {
            score += 15;
          }
        }

        if (type == ExcelImportType.genericLedger) {
          score += _genericLedgerDomainPenalty(canonical, normalized);
        }

        if (score > bestScore) {
          bestScore = score;
          bestKey = canonical;
        }
      }
    }

    if (bestKey != null) {
      _debugVerbose(
        'FIELD MAP SCORE field=$bestKey column=$raw score=$bestScore dateLike=$dateLikeCount amountLike=$amountLikeCount',
      );
      if (type == ExcelImportType.genericLedger && bestKey == 'amount') {
        final numericRatio = sampleValues.isEmpty
            ? 0.0
            : amountLikeCount / sampleValues.length;
        final reason = _isPreferredGenericLedgerAmountHeader(normalized)
            ? 'preferred-numeric-header'
            : 'numeric-samples';
        _logGenericLedgerAmountSelected(
          selectedColumn: raw,
          reason: reason,
          numericRatio: numericRatio,
        );
      }
    }

    if (bestScore >= 75) {
      return bestKey;
    }

    return null;
  }

  static bool _shouldIgnoreGenericLedgerHeader(String normalized) {
    return normalized.contains('closing balance') ||
        normalized.contains('opening balance') ||
        normalized == 'balance' ||
        normalized.contains('running balance');
  }

  static bool _isPreferredDebitHeader(String normalized) {
    return normalized == 'debit' ||
        normalized == 'debit amount' ||
        normalized == 'dr' ||
        normalized == 'dr amount';
  }

  static bool _isCreditOnlyHeader(String normalized) {
    return normalized == 'credit' ||
        normalized == 'credit amount' ||
        normalized == 'cr' ||
        normalized == 'cr amount';
  }

  static bool _shouldIgnorePurchaseHeader(String normalized) {
    if (normalized.contains('tax amount') && !normalized.contains('taxable')) {
      return true;
    }

    if (normalized.contains('tax amt') && !normalized.contains('taxable')) {
      return true;
    }

    return false;
  }

  static ({String selectedColumn, double numericRatio, String reason})
  _analyzeGenericLedgerAmountMapping({
    required List<dynamic> rawHeaderRow,
    required List<String?> mappedHeaders,
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required bool headersTrusted,
  }) {
    final amountIndex = mappedHeaders.indexOf('amount');
    if (amountIndex < 0 || amountIndex >= rawHeaderRow.length) {
      _logGenericLedgerAmountSelected(
        selectedColumn: '',
        reason: 'not-found',
        numericRatio: 0.0,
      );
      return (selectedColumn: '', numericRatio: 0.0, reason: 'not-found');
    }

    final rawHeader = rawHeaderRow[amountIndex]?.toString().trim() ?? '';
    final normalizedHeader = _normalizeLooseText(rawHeader);
    final rejectReason =
        _genericLedgerAmountRejectReason(normalizedHeader) ??
        (_isSellerLikeAlphabeticHeader(normalizedHeader)
            ? 'seller-like'
            : null);
    if (rejectReason != null) {
      _logAmountHeuristicReject(column: rawHeader, reason: rejectReason);
      _logGenericLedgerAmountSelected(
        selectedColumn: '',
        reason: rejectReason,
        numericRatio: 0.0,
      );
      return (selectedColumn: '', numericRatio: 0.0, reason: rejectReason);
    }

    final dataStartIndex = headersTrusted ? headerRowIndex + 1 : headerRowIndex;
    var nonEmptyCount = 0;
    var numericCount = 0;

    for (
      var rowIndex = dataStartIndex;
      rowIndex < rows.length && nonEmptyCount < 12;
      rowIndex++
    ) {
      final row = rows[rowIndex];
      if (amountIndex >= row.length) continue;
      final rawValue = row[amountIndex];
      final text = rawValue?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      nonEmptyCount += 1;
      if (_looksLikeAmountValue(text)) {
        numericCount += 1;
      }
    }

    final numericRatio = nonEmptyCount == 0
        ? 0.0
        : numericCount / nonEmptyCount;
    final reason = _isPreferredGenericLedgerAmountHeader(normalizedHeader)
        ? 'preferred-header'
        : _isTextHeavyGenericLedgerAmountHeader(normalizedHeader)
        ? 'text-heavy'
        : 'sample-ratio';
    _logGenericLedgerAmountSelected(
      selectedColumn: rawHeader,
      reason: reason,
      numericRatio: numericRatio,
    );
    return (
      selectedColumn: rawHeader,
      numericRatio: numericRatio,
      reason: reason,
    );
  }

  static int _headerSimilarityScore(String a, String b) {
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 90;

    final aWords = a.split(' ').where((e) => e.isNotEmpty).toSet();
    final bWords = b.split(' ').where((e) => e.isNotEmpty).toSet();

    final common = aWords.intersection(bWords).length;
    final maxLen = aWords.length > bWords.length
        ? aWords.length
        : bWords.length;

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

  static List<PurchaseRow> _parsePurchaseRowsFromPreparedSheet({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required List<String?> mappedHeaders,
    required bool headersTrusted,
  }) {
    final mapList = _buildRowMapsFromMappedHeaders(
      rows: rows,
      headerRowIndex: headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: headersTrusted,
    );

    final parsed = mapList.map((row) => PurchaseRow.fromMap(row)).toList();
    return _dedupePurchaseRows(parsed);
  }

  static List<Tds26QRow> _parseTdsRowsFromPreparedSheet({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required List<String?> mappedHeaders,
    required bool headersTrusted,
  }) {
    final mapList = _buildRowMapsFromMappedHeaders(
      rows: rows,
      headerRowIndex: headerRowIndex,
      mappedHeaders: mappedHeaders,
      headersTrusted: headersTrusted,
    );

    final parsed = mapList.map((row) => Tds26QRow.fromMap(row)).toList();
    return _dedupeTdsRows(parsed);
  }

  static List<Map<String, dynamic>> _buildRowMapsFromMappedHeaders({
    required List<List<dynamic>> rows,
    required int headerRowIndex,
    required List<String?> mappedHeaders,
    required bool headersTrusted,
  }) {
    final dataStartIndex = headersTrusted ? headerRowIndex + 1 : headerRowIndex;
    final result = <Map<String, dynamic>>[];

    for (int i = dataStartIndex; i < rows.length; i++) {
      final row = rows[i];
      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (int j = 0; j < mappedHeaders.length; j++) {
        final header = mappedHeaders[j];
        if (header == null || header.isEmpty) continue;

        final value = j < row.length ? row[j] : null;
        final normalizedValue = _normalizeCellValue(
          value,
          canonicalField: header,
        );
        final textValue = normalizedValue.toString().trim();

        if (textValue.isNotEmpty) {
          isEmptyRow = false;
        }

        rowMap[header] = normalizedValue;
      }

      if (!isEmptyRow) {
        result.add(rowMap);
      }
    }

    _flushForcedNumericDateAvoidanceSummary('row_maps');

    return result;
  }

  static List<String> _buildPurchaseWarnings(List<PurchaseRow> rows) {
    final warnings = <String>[];

    final zeroBasic = rows.where((e) => e.basicAmount <= 0).length;
    if (zeroBasic > 0) {
      warnings.add(
        '$zeroBasic purchase rows have zero or negative Basic Amount.',
      );
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
        .where(
          (e) => e.panNumber.trim().isNotEmpty && !_isValidPan(e.panNumber),
        )
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
        .where(
          (e) => e.panNumber.trim().isNotEmpty && !_isValidPan(e.panNumber),
        )
        .length;
    if (invalidPan > 0) {
      warnings.add('$invalidPan 26Q rows have invalid PAN format.');
    }

    final missingMonth = rows.where((e) => e.month.trim().isEmpty).length;
    if (missingMonth > 0) {
      warnings.add('$missingMonth 26Q rows have unreadable Date / Month.');
    }

    final zeroAmounts = rows
        .where((e) => e.deductedAmount <= 0 && e.tds <= 0)
        .length;
    if (zeroAmounts > 0) {
      warnings.add(
        '$zeroAmounts 26Q rows have both Amount Paid and TDS Amount as zero.',
      );
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

  static ({List<PurchaseRow> rows, List<ImportAuditRecord> auditRecords})
  _dedupeImportedPurchaseRows(
    List<({PurchaseRow row, int rowNumber})> rows, {
    required String sourceFileName,
    required String sheetName,
  }) {
    final map = <String, PurchaseRow>{};
    final auditRecords = <ImportAuditRecord>[];

    for (final entry in rows) {
      final row = entry.row;
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

      if (map.containsKey(key)) {
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: entry.rowNumber,
            rowType: ImportAuditRowType.ledgerSource,
            sectionBucket: '194Q',
            reason: ImportAuditReason.duplicateIgnored,
            message: 'Duplicate purchase/source row ignored during import.',
          ),
        );
        continue;
      }

      map[key] = row;
    }

    return (rows: map.values.toList(), auditRecords: auditRecords);
  }

  static ({List<Tds26QRow> rows, List<ImportAuditRecord> auditRecords})
  _dedupeImportedTdsRows(
    List<_ImportedRowCandidate> rows, {
    required String sourceFileName,
    required String sheetName,
  }) {
    final map = <String, Tds26QRow>{};
    final auditRecords = <ImportAuditRecord>[];

    for (final candidate in rows) {
      final row = Tds26QRow.fromMap(candidate.rowMap);
      final key = [
        row.month.trim().toUpperCase(),
        row.deducteeName.trim().toUpperCase(),
        row.panNumber.trim().toUpperCase(),
        row.deductedAmount.toStringAsFixed(2),
        row.tds.toStringAsFixed(2),
        row.section.trim().toUpperCase(),
      ].join('|');

      if (map.containsKey(key)) {
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: candidate.rowNumber,
            rowType: ImportAuditRowType.tds26q,
            sectionBucket: '',
            reason: ImportAuditReason.duplicateIgnored,
            message: 'Duplicate 26Q row ignored during import.',
          ),
        );
        continue;
      }

      map[key] = row;
    }

    return (rows: map.values.toList(), auditRecords: auditRecords);
  }

  static ({
    List<NormalizedLedgerRow> rows,
    List<ImportAuditRecord> auditRecords,
  })
  _dedupeImportedNormalizedLedgerRows(
    List<({NormalizedLedgerRow row, int rowNumber})> rows, {
    required String sourceFileName,
    required String sheetName,
    required String sectionBucket,
  }) {
    final map = <String, NormalizedLedgerRow>{};
    final auditRecords = <ImportAuditRecord>[];

    for (final entry in rows) {
      final row = entry.row;
      final key = [
        row.sectionCode.trim().toUpperCase(),
        row.month.trim().toUpperCase(),
        row.partyName.trim().toUpperCase(),
        row.panNumber.trim().toUpperCase(),
        row.documentNo.trim().toUpperCase(),
        row.amount.toStringAsFixed(2),
        row.tdsAmount.toStringAsFixed(2),
      ].join('|');

      if (map.containsKey(key)) {
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: entry.rowNumber,
            rowType: ImportAuditRowType.ledgerSource,
            sectionBucket: sectionBucket,
            reason: ImportAuditReason.duplicateIgnored,
            message: 'Duplicate ledger/source row ignored during import.',
          ),
        );
        continue;
      }

      map[key] = row;
    }

    return (rows: map.values.toList(), auditRecords: auditRecords);
  }

  static ({
    List<_ImportedRowCandidate> rows,
    List<ImportAuditRecord> auditRecords,
  })
  _prepareGenericLedgerAuditRows(
    List<_ImportedRowCandidate> rawRows, {
    required String sourceFileName,
    required String sheetName,
    required String sectionBucket,
  }) {
    final preparedRows = <_ImportedRowCandidate>[];
    final auditRecords = <ImportAuditRecord>[];

    for (int i = 0; i < rawRows.length; i++) {
      final rawCandidate = rawRows[i];
      final currentRow = Map<String, dynamic>.from(rawCandidate.rowMap);
      final classification = _classifyGenericLedgerRow(currentRow);

      if (classification == _GenericLedgerRowType.continuation) {
        if (preparedRows.isNotEmpty) {
          final previous = preparedRows.last;
          previous.rowMap['description'] = _appendGenericLedgerNarration(
            previous.rowMap['description']?.toString() ?? '',
            _extractContinuationNarration(currentRow),
          );
          auditRecords.add(
            ImportAuditRecord(
              sourceFileName: sourceFileName,
              sheetName: sheetName,
              rowNumber: rawCandidate.rowNumber,
              rowType: ImportAuditRowType.ledgerSource,
              sectionBucket: sectionBucket,
              reason: ImportAuditReason.continuationMerged,
              message:
                  'Narration-only continuation row merged into the previous ledger transaction.',
            ),
          );
          continue;
        }

        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: rawCandidate.rowNumber,
            rowType: ImportAuditRowType.ledgerSource,
            sectionBucket: sectionBucket,
            reason: ImportAuditReason.invalidRowSkipped,
            message:
                'Narration-only continuation row was skipped because there was no previous transaction to merge into.',
          ),
        );
        continue;
      }

      if (classification == _GenericLedgerRowType.invalid) {
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: rawCandidate.rowNumber,
            rowType: ImportAuditRowType.ledgerSource,
            sectionBucket: sectionBucket,
            reason: ImportAuditReason.invalidRowSkipped,
            message:
                'Row skipped because it did not contain a usable amount or meaningful narration.',
          ),
        );
        continue;
      }

      if (_isSuspiciousPlaceholderLedgerDate(
        readAny(currentRow, ['date']) ?? '',
      )) {
        final rawDate = (readAny(currentRow, ['date']) ?? '').trim();
        currentRow['date'] = '';
        currentRow['description'] = _appendGenericLedgerNarration(
          currentRow['description']?.toString() ?? '',
          'Placeholder date requires review: $rawDate',
        );
        auditRecords.add(
          ImportAuditRecord(
            sourceFileName: sourceFileName,
            sheetName: sheetName,
            rowNumber: rawCandidate.rowNumber,
            rowType: ImportAuditRowType.ledgerSource,
            sectionBucket: sectionBucket,
            reason: ImportAuditReason.suspiciousReviewNote,
            message:
                'Suspicious placeholder date was cleared and preserved as a review note in the narration.',
          ),
        );
      }

      preparedRows.add(
        _ImportedRowCandidate(
          rowMap: currentRow,
          rowNumber: rawCandidate.rowNumber,
        ),
      );
    }

    return (rows: preparedRows, auditRecords: auditRecords);
  }

  static _GenericLedgerRowType _classifyGenericLedgerRow(
    Map<String, dynamic> row,
  ) {
    final rawDate = (readAny(row, ['date']) ?? '').trim();
    final amount = parseDouble(readAny(row, ['amount']) ?? '');
    final hasAmount = amount.abs() > 0.0001;
    final hasValidDate =
        rawDate.isNotEmpty && !_isSuspiciousPlaceholderLedgerDate(rawDate);
    final hasSuspiciousPlaceholderDate = _isSuspiciousPlaceholderLedgerDate(
      rawDate,
    );
    final hasNarration = _extractContinuationNarration(row).isNotEmpty;

    if (!hasAmount &&
        hasNarration &&
        (!hasValidDate || hasSuspiciousPlaceholderDate)) {
      return _GenericLedgerRowType.continuation;
    }

    if (hasAmount) {
      return _GenericLedgerRowType.transaction;
    }

    if (hasValidDate && hasNarration) {
      return _GenericLedgerRowType.transaction;
    }

    return _GenericLedgerRowType.invalid;
  }

  static bool _isSuspiciousPlaceholderLedgerDate(String rawDate) {
    final value = rawDate.trim();
    if (value.isEmpty) return false;

    final parsed = _tryParseDate(value);
    if (parsed == null) return false;

    if (parsed.year <= 1900) return true;

    return value == '31/01/1900' ||
        value == '31-01-1900' ||
        value == '1900-01-31';
  }

  static String _extractContinuationNarration(Map<String, dynamic> row) {
    final parts = <String>[
      (readAny(row, ['party_name']) ?? '').trim(),
      (readAny(row, ['description']) ?? '').trim(),
      (readAny(row, ['bill_no']) ?? '').trim(),
    ].where((value) => value.isNotEmpty).toList();

    final uniqueParts = <String>[];
    for (final part in parts) {
      if (!uniqueParts.any(
        (existing) => existing.toLowerCase() == part.toLowerCase(),
      )) {
        uniqueParts.add(part);
      }
    }

    return uniqueParts.join(' | ');
  }

  static String _appendGenericLedgerNarration(
    String existing,
    String addition,
  ) {
    final normalizedExisting = existing.trim();
    final normalizedAddition = addition.trim();

    if (normalizedAddition.isEmpty) return normalizedExisting;
    if (normalizedExisting.isEmpty) return normalizedAddition;

    final lowerExisting = normalizedExisting.toLowerCase();
    final lowerAddition = normalizedAddition.toLowerCase();
    if (lowerExisting.contains(lowerAddition)) {
      return normalizedExisting;
    }

    return '$normalizedExisting | $normalizedAddition';
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    if (value is num) {
      if (_looksLikeExcelDate(value)) {
        final date = _excelSerialToDate(value);
        return DateTime(date.year, date.month, date.day);
      }
      return null;
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final direct = DateTime.tryParse(text);
    if (direct != null) {
      return DateTime(direct.year, direct.month, direct.day);
    }

    final numeric = double.tryParse(text);
    if (numeric != null && _looksLikeExcelDate(numeric)) {
      final date = _excelSerialToDate(numeric);
      return DateTime(date.year, date.month, date.day);
    }

    final normalized = text.replaceAll('/', '-').replaceAll('.', '-');
    final parts = normalized.split('-');
    if (parts.length != 3) return null;

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) return null;

    if (first > 1900) {
      return DateTime(first, second, third);
    }

    if (third > 1900) {
      return DateTime(third, second, first);
    }

    return null;
  }

  static void _logGenericLedgerImportAudit(
    ({
      List<Map<String, dynamic>> rows,
      int sourceRowCount,
      int parsedTransactionCount,
      int continuationMergedCount,
      int invalidRowsSkippedCount,
    })
    audit,
  ) {
    AppLogger.debug(
      'GENERIC LEDGER IMPORT AUDIT => '
      'sourceRows=${audit.sourceRowCount} '
      'parsedTransactions=${audit.parsedTransactionCount} '
      'continuationMerged=${audit.continuationMergedCount} '
      'invalidSkipped=${audit.invalidRowsSkippedCount}',
    );
  }

  static dynamic _normalizeCellValue(dynamic value, {String? canonicalField}) {
    if (value == null) return '';

    final field = canonicalField?.trim() ?? '';
    final forceNumeric =
        field.isNotEmpty && ImportMappingService.isAmountField(field);
    final forceDate =
        field.isNotEmpty && ImportMappingService.isDateField(field);

    if (value is DateTime) {
      if (forceNumeric) {
        _recordForcedNumericDateAvoidance(field);
        return value.toString().trim();
      }
      if (forceDate) {
        return _formatDate(value);
      }
      return value.toString().trim();
    }

    if (value is num) {
      if (forceNumeric && _looksLikeExcelDate(value)) {
        _recordForcedNumericDateAvoidance(field);
      }

      if (forceDate && _looksLikeExcelDate(value)) {
        return _convertExcelDate(value);
      }

      if (value == value.roundToDouble()) {
        return value.toInt().toString();
      }

      return value.toString();
    }

    if (forceNumeric) {
      return value.toString().trim();
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
    'eom': ['eom', 'end of month', 'month end'],
    'party_name': [
      'party name',
      'party_name',
      'party',
      'particulars',
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
      'gstin no',
      'gstin number',
      'gst',
    ],
    'pan_number': ['pan', 'pan no', 'pan no.', 'pan number', 'panno'],
    'productname': [
      'product name',
      'productname',
      'item name',
      'item',
      'description',
    ],
    'basic_amount': [
      'basic amount',
      'taxable amount',
      'taxable value',
      'product amount',
      'product_amount',
      'item bill amount',
      'debit',
      'dr',
      'debit amount',
      'dr amount',
    ],
    'bill_amount': [
      'bill amount',
      'bill_amount',
      'amount',
      'total amount',
      'gross amount',
      'net amount',
      'invoice amount',
      'debit',
      'dr',
      'debit amount',
      'dr amount',
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
    'pan_number': ['pan', 'pan no', 'pan number', 'panno', 'deductee pan'],
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
    'challan': ['challan', 'chalan', 'challan id no details', 'challan id no'],
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
      'particulars',
      'party name',
      'party',
      'ledger name',
      'account name',
      'seller name',
      'vendor name',
      'supplier name',
      'name',
    ],
    'pan_number': ['pan', 'pan no', 'pan number', 'panno'],
    'gst_no': ['gst no', 'gst number', 'gstin', 'gst'],
    'bill_no': [
      'doc chq no',
      'doc/chq no',
      'doc no',
      'document no',
      'chq no',
      'cheque no',
      'bill no',
      'bill number',
      'invoice no',
      'voucher no',
      'ref no',
      'reference no',
    ],
    'amount': [
      'amount',
      'bill amount',
      'total amount',
      'taxable amount',
      'basic amount',
      'gross amount',
      'invoice amount',
      'ledger amount',
      'transaction amount',
      'debit',
      'credit',
      'dr',
      'cr',
      'dr amount',
      'cr amount',
      'debit amount',
      'credit amount',
    ],
    'description': [
      'description',
      'narration',
      'remarks',
      'particulars',
      'product name',
    ],
  };

  static ({int headerRowIndex, int score, bool headersTrusted})?
  _detectGenericLedgerHeaderCandidate(
    List<List<dynamic>> rows, {
    required String sheetName,
    int scanLimit = _defaultStructuredHeaderScanRowLimit,
  }) {
    final candidates = _collectStructuredHeaderCandidates(
      rows,
      type: ExcelImportType.genericLedger,
      fileLabel: sheetName,
      scanLimit: scanLimit,
    );
    if (candidates.isEmpty) {
      return null;
    }

    final best = candidates.first;
    return (
      headerRowIndex: best.headerRowIndex,
      score: best.score,
      headersTrusted: true,
    );
  }
}

enum ExcelImportType { purchase, tds26q, genericLedger }

enum _GenericLedgerRowType { transaction, continuation, invalid }

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
  final ExcelImportDecision decision;

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
    required this.decision,
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
      decision: requiresManualMapping
          ? ExcelImportDecision.manualReview
          : ExcelImportDecision.autoImport,
    );
  }

  factory ExcelValidationResult.manualReview({
    required String detectedSheet,
    required int headerRowIndex,
    required ExcelImportType detectedType,
    required Map<String, String> mappedColumns,
    List<String> warnings = const [],
    double confidenceScore = 0.0,
    String message = 'Column mapping review is recommended before import.',
    List<String> unmappedRawHeaders = const [],
  }) {
    return ExcelValidationResult(
      isValid: true,
      message: message,
      detectedSheet: detectedSheet,
      headerRowIndex: headerRowIndex,
      detectedType: detectedType,
      mappedColumns: mappedColumns,
      warnings: warnings,
      confidenceScore: confidenceScore,
      requiresManualMapping: true,
      requiresUserSelection: false,
      candidateSheets: const [],
      unmappedRawHeaders: unmappedRawHeaders,
      decision: ExcelImportDecision.manualReview,
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
      decision: ExcelImportDecision.invalidMapping,
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
      decision: ExcelImportDecision.invalidMapping,
    );
  }
}

enum ExcelImportDecision { autoImport, manualReview, invalidMapping }

Future<List<Map<String, dynamic>>> _parsePurchaseRowsInIsolate(
  Uint8List bytes,
) async {
  return ExcelService._serializePurchaseRowsForIsolate(
    ExcelService.parsePurchaseRows(bytes),
  );
}

Future<List<Map<String, dynamic>>> _parseTds26QRowsInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeTdsRowsForIsolate(
    ExcelService.parseTds26QRows(
      payload['bytes'] as Uint8List,
      sheetName: payload['sheetName'] as String?,
    ),
  );
}

Future<List<Map<String, dynamic>>> _parseGenericLedgerRowsInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeNormalizedLedgerRowsForIsolate(
    ExcelService.parseGenericLedgerRows(
      payload['bytes'] as Uint8List,
      defaultSection: payload['defaultSection'] as String,
      sourceFileName: payload['sourceFileName'] as String? ?? '',
      sheetName: payload['sheetName'] as String?,
    ),
  );
}

Future<List<Map<String, dynamic>>> _parseGenericLedgerRowsWithProfileInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeNormalizedLedgerRowsForIsolate(
    ExcelService.parseGenericLedgerRowsWithProfile(
      payload['bytes'] as Uint8List,
      sheetName: payload['sheetName'] as String,
      headerRowIndex: payload['headerRowIndex'] as int,
      headersTrusted: payload['headersTrusted'] as bool,
      columnMapping: Map<String, String>.from(payload['columnMapping'] as Map),
      defaultSection: payload['defaultSection'] as String,
      sourceFileName: payload['sourceFileName'] as String? ?? '',
    ),
  );
}

Future<Map<String, dynamic>> _validatePurchaseFileInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeValidationForIsolate(
    ExcelService.validatePurchaseFile(
      payload['bytes'] as Uint8List,
      preferredSheetName: payload['preferredSheetName'] as String?,
    ),
  );
}

Future<Map<String, dynamic>> _validateTds26QFileInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeValidationForIsolate(
    ExcelService.validateTds26QFile(
      payload['bytes'] as Uint8List,
      preferredSheetName: payload['preferredSheetName'] as String?,
    ),
  );
}

Future<Map<String, dynamic>> _validateGenericLedgerFileInIsolate(
  Map<String, dynamic> payload,
) async {
  return ExcelService._serializeValidationForIsolate(
    ExcelService.validateGenericLedgerFile(
      payload['bytes'] as Uint8List,
      preferredSheetName: payload['preferredSheetName'] as String?,
      expectedSection: payload['expectedSection'] as String?,
      sourceFileName: payload['sourceFileName'] as String? ?? '',
    ),
  );
}

Future<List<String>> _list26QSelectableSheetsInIsolate(Uint8List bytes) async {
  return ExcelService.list26QSelectableSheets(bytes);
}

Future<List<String>> _listWorkbookSheetNamesInIsolate(Uint8List bytes) async {
  return ExcelService.listWorkbookSheetNames(bytes);
}
