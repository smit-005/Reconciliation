import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

class Parsed26QRow {
  final String partyName;
  final String pan;
  final String panStatus;
  final String section;
  final String sectionCode;
  final DateTime? transactionDate;
  final String monthLabel;
  final String fyLabel;
  final double amountPaidCredited;
  final double totalTaxDeducted;
  final double deductionRate;
  final String deductionReason;
  final String certificateNumber;
  final String rawNatureOfPayment;
  final Map<String, dynamic> raw;

  Parsed26QRow({
    required this.partyName,
    required this.pan,
    required this.panStatus,
    required this.section,
    required this.sectionCode,
    required this.transactionDate,
    required this.monthLabel,
    required this.fyLabel,
    required this.amountPaidCredited,
    required this.totalTaxDeducted,
    required this.deductionRate,
    required this.deductionReason,
    required this.certificateNumber,
    required this.rawNatureOfPayment,
    required this.raw,
  });

  Map<String, dynamic> toMap() {
    return {
      'partyName': partyName,
      'pan': pan,
      'panStatus': panStatus,
      'section': section,
      'sectionCode': sectionCode,
      'transactionDate': transactionDate?.toIso8601String(),
      'monthLabel': monthLabel,
      'fyLabel': fyLabel,
      'amountPaidCredited': amountPaidCredited,
      'totalTaxDeducted': totalTaxDeducted,
      'deductionRate': deductionRate,
      'deductionReason': deductionReason,
      'certificateNumber': certificateNumber,
      'rawNatureOfPayment': rawNatureOfPayment,
      'raw': raw,
    };
  }
}

class Tds26QParserResult {
  final List<Parsed26QRow> rows;
  final List<String> warnings;

  Tds26QParserResult({
    required this.rows,
    required this.warnings,
  });
}

class Tds26QParser {
  static Tds26QParserResult parseFromFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('26Q file not found: $filePath');
    }

    final bytes = file.readAsBytesSync();
    return parseBytes(bytes);
  }

  static Tds26QParserResult parseBytes(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);

    final sheetName = _findDeductionSheetName(excel);
    if (sheetName == null) {
      throw Exception(
        'Deduction sheet not found in 26Q file. Available sheets: ${excel.tables.keys.join(", ")}',
      );
    }

    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('Deduction sheet is empty.');
    }

    final warnings = <String>[];

    final headerRowIndex = _findHeaderRowIndex(sheet.rows);
    if (headerRowIndex == -1) {
      throw Exception('Could not detect header row in Deduction sheet.');
    }

    final headers = _buildIndexedHeaders(sheet.rows[headerRowIndex]);
    final normalizedHeaderMap = _buildNormalizedHeaderMap(headers);
    final columnIndexes = _resolveColumnIndexes(normalizedHeaderMap);

    if (columnIndexes.partyNameIndex == null) {
      warnings.add('Could not confidently detect deductee/party name column.');
    }

    if (columnIndexes.panIndex == null) {
      warnings.add('Could not confidently detect PAN column.');
    }

    if (columnIndexes.amountPaidIndex == null) {
      warnings.add('Could not confidently detect amount paid/credited column.');
    }

    if (columnIndexes.totalTaxIndex == null) {
      warnings.add('Could not confidently detect TDS/total tax deducted column.');
    }

    if (columnIndexes.sectionIndex == null &&
        columnIndexes.natureOfPaymentIndex == null) {
      warnings.add(
        'Could not confidently detect section / nature of payment column.',
      );
    }

    final parsedRows = <Parsed26QRow>[];

    for (int r = headerRowIndex + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (_isCompletelyEmptyRow(row)) continue;

      final partyName = _cellString(row, columnIndexes.partyNameIndex).trim();
      final pan = _normalizePan(_cellString(row, columnIndexes.panIndex));
      final panStatus = _cellString(row, columnIndexes.panStatusIndex).trim();

      final rawSectionText = _pickBestSectionText(row, columnIndexes);
      final normalizedSectionText = _normalizeSpaces(rawSectionText);
      final sectionCode = _extractSectionCode(normalizedSectionText);
      final finalSection = sectionCode.isEmpty ? 'Unknown' : sectionCode;

      final txnDate = _parseExcelDate(_cellValue(row, columnIndexes.dateIndex));
      final monthLabel = _formatMonthLabel(txnDate);
      final fyLabel = _formatFinancialYear(txnDate);

      final amountPaidCredited =
      _parseDouble(_cellValue(row, columnIndexes.amountPaidIndex));
      final totalTaxDeducted =
      _parseDouble(_cellValue(row, columnIndexes.totalTaxIndex));
      final deductionRate =
      _parseDouble(_cellValue(row, columnIndexes.rateIndex));
      final deductionReason =
      _cellString(row, columnIndexes.reasonIndex).trim();
      final certificateNumber =
      _cellString(row, columnIndexes.certificateNumberIndex).trim();

      final rawMap = <String, dynamic>{};
      for (int c = 0; c < headers.length; c++) {
        rawMap[headers[c]] = c < row.length ? row[c]?.value : null;
      }

      final hasMeaningfulData =
          partyName.isNotEmpty ||
              pan.isNotEmpty ||
              amountPaidCredited > 0 ||
              totalTaxDeducted > 0 ||
              normalizedSectionText.isNotEmpty;

      if (!hasMeaningfulData) continue;

      parsedRows.add(
        Parsed26QRow(
          partyName: partyName,
          pan: pan,
          panStatus: panStatus,
          section: finalSection,
          sectionCode: finalSection,
          transactionDate: txnDate,
          monthLabel: monthLabel,
          fyLabel: fyLabel,
          amountPaidCredited: amountPaidCredited,
          totalTaxDeducted: totalTaxDeducted,
          deductionRate: deductionRate,
          deductionReason: deductionReason,
          certificateNumber: certificateNumber,
          rawNatureOfPayment: normalizedSectionText,
          raw: rawMap,
        ),
      );
    }

    return Tds26QParserResult(
      rows: parsedRows,
      warnings: warnings,
    );
  }

  static String? _findDeductionSheetName(Excel excel) {
    final sheetNames = excel.tables.keys.toList();

    for (final name in sheetNames) {
      final n = name.toLowerCase().trim();
      if (n == 'deduction') return name;
    }

    for (final name in sheetNames) {
      final n = name.toLowerCase().trim();
      if (n.contains('deduction')) return name;
    }

    return null;
  }

  static int _findHeaderRowIndex(List<List<Data?>> rows) {
    for (int i = 0; i < rows.length && i < 15; i++) {
      final rowTexts = rows[i]
          .map((e) => _normalizeHeader((e?.value ?? '').toString()))
          .toList();

      final rowJoined = rowTexts.join(' | ');

      final looksLikeHeader =
          rowJoined.contains('amount paid') ||
              rowJoined.contains('paid / credited') ||
              rowJoined.contains('amount paid / credited') ||
              rowJoined.contains('pan status') ||
              rowJoined.contains('deduction rate') ||
              rowJoined.contains('nature of payment') ||
              rowJoined.contains('deduction reason') ||
              rowJoined.contains('certificate number') ||
              rowJoined.contains('total tax deducted') ||
              rowJoined.contains('tax deducted') ||
              rowJoined.contains('tds amount');

      if (looksLikeHeader) return i;
    }
    return -1;
  }

  static List<String> _buildIndexedHeaders(List<Data?> headerRow) {
    final counts = <String, int>{};
    final result = <String>[];

    for (final cell in headerRow) {
      final raw = (cell?.value ?? '').toString().trim();
      final header = raw.isEmpty ? 'col' : raw;
      final count = (counts[header] ?? 0) + 1;
      counts[header] = count;

      if (count == 1) {
        result.add(header);
      } else {
        result.add('$header#$count');
      }
    }

    return result;
  }

  static Map<String, int> _buildNormalizedHeaderMap(List<String> headers) {
    final map = <String, int>{};
    for (int i = 0; i < headers.length; i++) {
      map[_normalizeHeader(headers[i])] = i;
    }
    return map;
  }

  static _ResolvedIndexes _resolveColumnIndexes(Map<String, int> headerMap) {
    int? find(List<String> keys) {
      int? exact;
      int? contains;

      for (final key in keys) {
        final normalizedKey = _normalizeHeader(key);

        if (headerMap.containsKey(normalizedKey)) {
          exact ??= headerMap[normalizedKey];
        }
      }

      if (exact != null) return exact;

      for (final entry in headerMap.entries) {
        for (final key in keys) {
          final normalizedKey = _normalizeHeader(key);

          if (entry.key.contains(normalizedKey) ||
              normalizedKey.contains(entry.key)) {
            contains ??= entry.value;
          }
        }
      }

      return contains;
    }

    int? findSectionColumn() {
      final candidates = <MapEntry<String, int>>[];

      headerMap.forEach((k, v) {
        if (k.startsWith('section')) {
          candidates.add(MapEntry(k, v));
        }
      });

      if (candidates.isEmpty) return null;

      candidates.sort((a, b) => a.value.compareTo(b.value));

      if (candidates.length == 1) return candidates.first.value;

      return candidates.last.value;
    }

    return _ResolvedIndexes(
      partyNameIndex: find([
        'deductee name',
        'name of deductee',
        'party name',
        'deductee',
        'name',
      ]),
      panIndex: find([
        'pan of deductee',
        'deductee pan',
        'pan',
        'permanent account number',
      ]),
      panStatusIndex: find([
        'pan status',
      ]),
      amountPaidIndex: find([
        'amount paid / credited',
        'amount paid/credited',
        'paid / credited',
        'paid/credited',
        'amount paid',
        'amount credited',
        'amount paid credited',
        'paid credited',
      ]),
      dateIndex: find([
        'paid / credited date',
        'paid/credited date',
        'date of payment',
        'date',
      ]),
      totalTaxIndex: find([
        'total tax deducted',
        'total tax deducted and deposited',
        'tax deducted and deposited',
        'total tax',
        'tax deducted',
        'tds amount',
        'tds',
        'total tds',
      ]),
      rateIndex: find([
        'deduction rate',
        'rate',
        'rate of deduction',
      ]),
      reasonIndex: find([
        'deduction reason for lower/ no deduction',
        'deduction reason',
        'reason for lower/no deduction',
      ]),
      certificateNumberIndex: find([
        'certificate number u/s 197',
        'certificate number u/s197',
        'certificate no',
      ]),
      natureOfPaymentIndex: find([
        'nature of payment',
        'nature payment',
      ]),
      sectionIndex: findSectionColumn(),
    );
  }

  static String _pickBestSectionText(
      List<Data?> row,
      _ResolvedIndexes indexes,
      ) {
    final nature = _cellString(row, indexes.natureOfPaymentIndex).trim();
    final section = _cellString(row, indexes.sectionIndex).trim();

    final natureHasRealSection = _containsRealTdsSection(nature);
    final sectionHasRealSection = _containsRealTdsSection(section);

    if (natureHasRealSection) return nature;
    if (sectionHasRealSection) return section;

    if (nature.isNotEmpty) return nature;
    if (section.isNotEmpty) return section;

    return '';
  }

  static bool _containsRealTdsSection(String value) {
    final v = value.toUpperCase();
    return v.contains('194Q') ||
        v.contains('194C') ||
        v.contains('194J') ||
        v.contains('194I') ||
        v.contains('194A') ||
        v.contains('194H') ||
        v.contains('194D') ||
        v.contains('194B') ||
        v.contains('194IA') ||
        v.contains('194IB') ||
        v.contains('194M') ||
        v.contains('194N') ||
        v.contains('206C') ||
        v.contains('206AB');
  }

  static String _extractSectionCode(String input) {
    if (input.trim().isEmpty) return '';

    final upper = input.toUpperCase().replaceAll(' ', '');

    final patterns = [
      '194Q',
      '194C',
      '194J',
      '194I',
      '194A',
      '194H',
      '194D',
      '194B',
      '194IA',
      '194IB',
      '194M',
      '194N',
      '206AB',
      '206C',
    ];

    for (final p in patterns) {
      if (upper.contains(p)) return p;
    }

    final regex = RegExp(r'(19\d{2}[A-Z]{0,2}|20\d{2}[A-Z]{0,2})');
    final match = regex.firstMatch(upper);
    return match?.group(0) ?? '';
  }

  static bool _isCompletelyEmptyRow(List<Data?> row) {
    for (final c in row) {
      final v = (c?.value ?? '').toString().trim();
      if (v.isNotEmpty) return false;
    }
    return true;
  }

  static dynamic _cellValue(List<Data?> row, int? index) {
    if (index == null) return null;
    if (index < 0 || index >= row.length) return null;
    return row[index]?.value;
  }

  static String _cellString(List<Data?> row, int? index) {
    final value = _cellValue(row, index);
    return value == null ? '' : value.toString();
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    final raw = value.toString().trim();
    if (raw.isEmpty) return 0.0;

    final cleaned = raw
        .replaceAll(',', '')
        .replaceAll('%', '')
        .replaceAll('(', '-')
        .replaceAll(')', '')
        .trim();

    return double.tryParse(cleaned) ?? 0.0;
  }

  static DateTime? _parseExcelDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    if (value is num) {
      try {
        final excelEpoch = DateTime(1899, 12, 30);
        return excelEpoch.add(Duration(days: value.toInt()));
      } catch (_) {
        return null;
      }
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final parsedDirect = DateTime.tryParse(raw);
    if (parsedDirect != null) return parsedDirect;

    final ddMmmYy = RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{2,4})$');
    final match = ddMmmYy.firstMatch(raw);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final monthStr = match.group(2)!.toLowerCase();
      final yearRaw = match.group(3)!;

      final monthMap = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };

      final month = monthMap[monthStr];
      if (day != null && month != null) {
        int year = int.tryParse(yearRaw) ?? 0;
        if (year < 100) {
          year += 2000;
        }
        return DateTime(year, month, day);
      }
    }

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
    final slashMatch = slash.firstMatch(raw);
    if (slashMatch != null) {
      final d = int.tryParse(slashMatch.group(1)!);
      final m = int.tryParse(slashMatch.group(2)!);
      int y = int.tryParse(slashMatch.group(3)!) ?? 0;
      if (y < 100) y += 2000;

      if (d != null && m != null && y > 0) {
        return DateTime(y, m, d);
      }
    }

    return null;
  }

  static String _formatMonthLabel(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]}-${date.year}';
  }

  static String _formatFinancialYear(DateTime? date) {
    if (date == null) return '';
    if (date.month >= 4) {
      return 'FY ${date.year}-${(date.year + 1).toString().substring(2)}';
    } else {
      return 'FY ${date.year - 1}-${date.year.toString().substring(2)}';
    }
  }

  static String _normalizePan(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll('#2', '')
        .replaceAll('#3', '')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeSpaces(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _ResolvedIndexes {
  final int? partyNameIndex;
  final int? panIndex;
  final int? panStatusIndex;
  final int? amountPaidIndex;
  final int? dateIndex;
  final int? totalTaxIndex;
  final int? rateIndex;
  final int? reasonIndex;
  final int? certificateNumberIndex;
  final int? natureOfPaymentIndex;
  final int? sectionIndex;

  _ResolvedIndexes({
    required this.partyNameIndex,
    required this.panIndex,
    required this.panStatusIndex,
    required this.amountPaidIndex,
    required this.dateIndex,
    required this.totalTaxIndex,
    required this.rateIndex,
    required this.reasonIndex,
    required this.certificateNumberIndex,
    required this.natureOfPaymentIndex,
    required this.sectionIndex,
  });
}