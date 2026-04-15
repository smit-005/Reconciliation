import 'package:flutter/cupertino.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import '../core/utils/calculation.dart';

class ExcelService {
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
    final rawHeaderRow = table.rows[headerRowIndex];

    final mappedHeaders = _buildMappedHeaders(
      rawHeaderRow,
      forcedType: sheetInfo.detectedType,
    );

    final rows = <Map<String, dynamic>>[];

    for (int i = headerRowIndex + 1; i < table.rows.length; i++) {
      final row = table.rows[i];

      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (int j = 0; j < mappedHeaders.length; j++) {
        final header = mappedHeaders[j];
        if (header == null || header.isEmpty) continue;

        final value = j < row.length ? row[j] : null;
        final textValue = value?.toString().trim() ?? '';

        if (textValue.isNotEmpty) {
          isEmptyRow = false;
        }

        rowMap[header] = textValue;
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

    final parsed = mapList.map((row) => PurchaseRow.fromMap(row)).toList();

    for (final row in parsed.take(10)) {
      debugPrint(
        'DEBUG PURCHASE => party=${row.partyName}, gst=${row.gstNo}, pan=${row.panNumber}, basic=${row.basicAmount}, bill=${row.billAmount}',
      );
    }


    return parsed;
  }

  static List<Tds26QRow> parseTds26QRows(List<int> bytes) {
    final mapList = excelToMapList(
      bytes,
      forcedType: ExcelImportType.tds26q,
    );

    final parsed = mapList.map((row) => Tds26QRow.fromMap(row)).toList();

    for (final row in parsed.take(5)) {
      debugPrint(
        'DEBUG 26Q => month=${row.month}, party=${row.deducteeName}, '
            'pan=${row.panNumber}, deducted=${row.deductedAmount}, tds=${row.tds}',
      );
    }

    return parsed;
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
    final mappedHeaders = _buildMappedHeaders(
      rawHeaderRow,
      forcedType: ExcelImportType.purchase,
    );

    final presentHeaders = mappedHeaders.whereType<String>().toSet();

    final missing = <String>[
      if (!presentHeaders.contains('date')) 'Date',
      if (!presentHeaders.contains('party_name')) 'Party Name',
      if (!presentHeaders.contains('bill_no')) 'Bill No',
      if (!presentHeaders.contains('basic_amount')) 'Basic Amount',
    ];

    if (missing.isNotEmpty) {
      return ExcelValidationResult.invalid(
        'Missing required purchase columns: ${missing.join(', ')}',
      );
    }

    if (_hasSuspiciousAmountCollision(mappedHeaders, rawHeaderRow)) {
      return ExcelValidationResult.invalid(
        'Suspicious amount column mapping detected. Please make sure Basic Amount and Bill Amount columns are clearly named.',
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
        'Basic Amount column could not be read correctly. All values are zero.',
      );
    }

    final billAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.billAmount);
    final basicAmountSum = parsed.fold<double>(0.0, (s, e) => s + e.basicAmount);

    if (billAmountSum > 0 && (billAmountSum - basicAmountSum).abs() < 1) {
      return ExcelValidationResult.invalid(
        'Basic Amount and Bill Amount look identical. Wrong column mapping detected.',
      );
    }

    return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: _headerPreviewMap(rawHeaderRow, mappedHeaders),
      warnings: _buildPurchaseWarnings(parsed),
    );
  }

  static ExcelValidationResult validateTds26QFile(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return ExcelValidationResult.invalid(
        'No sheets found in the Excel file.',
      );
    }

    final sheetInfo = _findBestSheetAndHeader(
      decoder,
      forcedType: ExcelImportType.tds26q,
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

    final mappedHeaders = _buildMappedHeaders(
      table.rows[sheetInfo.headerRowIndex],
      forcedType: ExcelImportType.tds26q,
    );

    final presentHeaders = mappedHeaders.whereType<String>().toSet();

    final missing = <String>[
      if (!presentHeaders.contains('date_month')) 'Date / Month',
      if (!presentHeaders.contains('pan_number')) 'PAN',
      if (!presentHeaders.contains('deducted_amount')) 'Deducted Amount',
      if (!presentHeaders.contains('tds')) 'TDS',
    ];

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
        'Deducted Amount / TDS columns could not be read correctly. All values are zero.',
      );
    }

    return ExcelValidationResult.valid(
      detectedSheet: sheetInfo.sheetName,
      headerRowIndex: sheetInfo.headerRowIndex,
      detectedType: sheetInfo.detectedType,
      mappedColumns: _headerPreviewMap(
        table.rows[sheetInfo.headerRowIndex],
        mappedHeaders,
      ),
      warnings: _buildTdsWarnings(parsed),
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

    final mappedHeaders = _buildMappedHeaders(
      table.rows[sheetInfo.headerRowIndex],
      forcedType: sheetInfo.detectedType,
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

  static ({String sheetName, int headerRowIndex, ExcelImportType detectedType})?
  _findBestSheetAndHeader(
      SpreadsheetDecoder decoder, {
        ExcelImportType? forcedType,
      }) {
    ({String sheetName, int headerRowIndex, ExcelImportType detectedType, int score})?
    best;

    for (final entry in decoder.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;

      if (table.rows.isEmpty) continue;

      for (int i = 0; i < table.rows.length && i < 15; i++) {
        final row = table.rows[i];

        final purchaseScore = _scoreHeaderRow(
          row,
          type: ExcelImportType.purchase,
        );

        final tdsScore = _scoreHeaderRow(
          row,
          type: ExcelImportType.tds26q,
        );

        if (forcedType == ExcelImportType.purchase) {
          if (purchaseScore >= 40 &&
              (best == null || purchaseScore > best.score)) {
            best = (
            sheetName: sheetName,
            headerRowIndex: i,
            detectedType: ExcelImportType.purchase,
            score: purchaseScore,
            );
          }
        } else if (forcedType == ExcelImportType.tds26q) {
          if (tdsScore >= 40 && (best == null || tdsScore > best.score)) {
            best = (
            sheetName: sheetName,
            headerRowIndex: i,
            detectedType: ExcelImportType.tds26q,
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
            score: purchaseScore,
            );
          }

          if (tdsScore >= 40 && (best == null || tdsScore > best.score)) {
            best = (
            sheetName: sheetName,
            headerRowIndex: i,
            detectedType: ExcelImportType.tds26q,
            score: tdsScore,
            );
          }
        }
      }
    }

    if (best == null) return null;

    return (
    sheetName: best.sheetName,
    headerRowIndex: best.headerRowIndex,
    detectedType: best.detectedType,
    );
  }

  static int _scoreHeaderRow(
      List<dynamic> row, {
        required ExcelImportType type,
      }) {
    final mappedHeaders = _buildMappedHeaders(
      row,
      forcedType: type,
    );

    final headers = mappedHeaders.whereType<String>().toSet();

    if (type == ExcelImportType.purchase) {
      int score = 0;
      if (headers.contains('date')) score += 20;
      if (headers.contains('party_name')) score += 20;
      if (headers.contains('bill_no')) score += 20;
      if (headers.contains('basic_amount')) score += 25;
      if (headers.contains('bill_amount')) score += 10;
      if (headers.contains('gst_no')) score += 5;
      return score;
    }

    int score = 0;
    if (headers.contains('date_month')) score += 20;
    if (headers.contains('pan_number')) score += 20;
    if (headers.contains('deducted_amount')) score += 25;
    if (headers.contains('tds')) score += 25;
    if (headers.contains('party_name')) score += 10;
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

    if (normalized == 'amount') return null;

    final dictionary = type == ExcelImportType.purchase
        ? _purchaseHeaderDictionary
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

    return warnings;
  }

  static List<String> _buildTdsWarnings(List<Tds26QRow> rows) {
    final warnings = <String>[];

    final missingPan = rows.where((e) => e.panNumber.trim().isEmpty).length;
    if (missingPan > 0) {
      warnings.add('$missingPan 26Q rows have missing PAN.');
    }

    final missingMonth = rows.where((e) => e.month.trim().isEmpty).length;
    if (missingMonth > 0) {
      warnings.add('$missingMonth 26Q rows have unreadable Date / Month.');
    }

    final zeroAmounts =
        rows.where((e) => e.deductedAmount <= 0 && e.tds <= 0).length;
    if (zeroAmounts > 0) {
      warnings.add('$zeroAmounts 26Q rows have both Deducted Amount and TDS as zero.');
    }

    return warnings;
  }

  static String _normalizeLooseText(String value) {
    var text = value.trim().toLowerCase();

    text = text.replaceAll('\n', ' ');
    text = text.replaceAll('\r', ' ');
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
      'bill number',
      'invoice no',
      'invoice number',
      'voucher no',
      'doc no',
    ],
    'date': [
      'date',
      'bill date',
      'invoice date',
      'voucher date',
      'document date',
    ],
    'party_name': [
      'party name',
      'party',
      'vendor',
      'supplier',
      'name',
      'seller name',
    ],
    'gst_no': [
      'gst no',
      'gst number',
      'gstin',
      'gst',
    ],
    'pan_number': [
      'pan',
      'pan no',
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
      'basic amt',
      'taxable amount',
      'taxable amt',
      'product amount',
      'assessable value',
      'taxable value',
    ],
    'bill_amount': [
      'bill amount',
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
      'name',
      'deductee name',
      'deductee',
      'vendor name',
    ],
    'pan_number': [
      'pan',
      'pan no',
      'pan number',
      'panno',
      'deductee pan',
    ],
    'deducted_amount': [
      'deducted amount',
      'deducted amt',
      'amount paid credited',
      'amount paid or credited',
      'amount paid',
      'credited amount',
      'payment amount',
    ],
    'tds': [
      'tds',
      'tax',
      'deducted and deposited tax',
      'deducted deposited tax',
      'tds amount',
      'tax deducted',
    ],
    'challan': [
      'challan',
      'chalan',
      'challan id no details',
      'challan id no',
    ],
  };
}

enum ExcelImportType {
  purchase,
  tds26q,
}

class ExcelValidationResult {
  final bool isValid;
  final String message;
  final String? detectedSheet;
  final int? headerRowIndex;
  final ExcelImportType? detectedType;
  final Map<String, String> mappedColumns;
  final List<String> warnings;

  ExcelValidationResult({
    required this.isValid,
    required this.message,
    required this.detectedSheet,
    required this.headerRowIndex,
    required this.detectedType,
    required this.mappedColumns,
    required this.warnings,
  });

  factory ExcelValidationResult.valid({
    required String detectedSheet,
    required int headerRowIndex,
    required ExcelImportType detectedType,
    required Map<String, String> mappedColumns,
    List<String> warnings = const [],
  }) {
    return ExcelValidationResult(
      isValid: true,
      message: 'File validated successfully.',
      detectedSheet: detectedSheet,
      headerRowIndex: headerRowIndex,
      detectedType: detectedType,
      mappedColumns: mappedColumns,
      warnings: warnings,
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
    );
  }
}