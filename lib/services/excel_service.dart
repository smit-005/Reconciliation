import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import '../core/utils/calculation.dart';

class ExcelService {
  static List<Map<String, dynamic>> excelToMapList(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return [];
    }

    final sheetInfo = _findBestSheetAndHeader(decoder);
    if (sheetInfo == null) {
      return [];
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    final headerRowIndex = sheetInfo.headerRowIndex;

    final rawHeaders = table.rows[headerRowIndex]
        .map((cell) => cell?.toString().trim() ?? '')
        .toList();

    final headers = rawHeaders.map(_normalizeHeader).toList();

    final rows = <Map<String, dynamic>>[];

    for (int i = headerRowIndex + 1; i < table.rows.length; i++) {
      final row = table.rows[i];

      bool isEmptyRow = true;
      final rowMap = <String, dynamic>{};

      for (int j = 0; j < headers.length; j++) {
        final key = headers[j];
        final value = j < row.length ? row[j] : null;
        final textValue = value?.toString().trim() ?? '';

        if (textValue.isNotEmpty) {
          isEmptyRow = false;
        }

        if (key.isNotEmpty) {
          rowMap[key] = textValue;
        }
      }

      if (!isEmptyRow) {
        rows.add(rowMap);
      }
    }

    return rows;
  }

  static List<PurchaseRow> parsePurchaseRows(List<int> bytes) {
    final mapList = excelToMapList(bytes);
    return mapList.map((row) => PurchaseRow.fromMap(row)).toList();
  }

  static List<Tds26QRow> parseTds26QRows(List<int> bytes) {
    final mapList = excelToMapList(bytes);
    return mapList.map((row) => Tds26QRow.fromMap(row)).toList();
  }

  static String? detectBuyerNameFromSheet(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) return null;

    final table = decoder.tables.values.first;
    if (table == null || table.rows.isEmpty) return null;

    // Check first 5 rows (top section)
    for (int i = 0; i < table.rows.length && i < 5; i++) {
      final row = table.rows[i];

      for (final cell in row) {
        final text = cell?.toString().trim();

        if (text != null && text.isNotEmpty) {
          // Skip header-like values
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

  static List<String> getSheetHeaders(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

    if (decoder.tables.isEmpty) {
      return [];
    }

    final sheetInfo = _findBestSheetAndHeader(decoder);
    if (sheetInfo == null) {
      return [];
    }

    final table = decoder.tables[sheetInfo.sheetName];
    if (table == null || table.rows.isEmpty) {
      return [];
    }

    return table.rows[sheetInfo.headerRowIndex]
        .map((cell) => _normalizeHeader(cell?.toString() ?? ''))
        .toList();
  }

  static bool isPurchaseRegisterFormat(List<int> bytes) {
    final headers = getSheetHeaders(bytes);
    print('Purchase headers => $headers');

    final hasDate = headers.contains('date');
    final hasParty = headers.contains('party_name');
    final hasBillNo = headers.contains('bill_no');
    final hasAmount =
        headers.contains('bill_amount') || headers.contains('basic_amount');

    return hasDate && hasParty && hasBillNo && hasAmount;
  }

  static bool isTds26QFormat(List<int> bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    print('26Q sheets => ${decoder.tables.keys.toList()}');

    final headers = getSheetHeaders(bytes);
    print('26Q headers => $headers');

    final hasPan = headers.contains('pan_number');
    final hasAmount = headers.contains('deducted_amount');
    final hasDate = headers.contains('date_month') || headers.contains('date');
    final hasTds = headers.contains('tds');

    return hasPan && hasAmount && hasDate && hasTds;
  }

  static ({String sheetName, int headerRowIndex})? _findBestSheetAndHeader(
      SpreadsheetDecoder decoder,
      ) {
    for (final entry in decoder.tables.entries) {
      final sheetName = entry.key;
      final table = entry.value;

      if (table == null || table.rows.isEmpty) continue;

      final headerRowIndex = _findHeaderRowIndex(table.rows);

      final headers = table.rows[headerRowIndex]
          .map((cell) => _normalizeHeader(cell?.toString() ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();

      if (_isPurchaseHeader(headers) || _isTdsHeader(headers)) {
        return (sheetName: sheetName, headerRowIndex: headerRowIndex);
      }
    }

    return null;
  }

  static int _findHeaderRowIndex(List<List<dynamic>> rows) {
    for (int i = 0; i < rows.length; i++) {
      final normalized = rows[i]
          .map((cell) => _normalizeHeader(cell?.toString() ?? ''))
          .where((value) => value.isNotEmpty)
          .toList();

      if (normalized.isEmpty) continue;

      final purchaseLike = _isPurchaseHeader(normalized);
      final tdsLike = _isTdsHeader(normalized);

      if (purchaseLike || tdsLike) {
        return i;
      }
    }

    return 0;
  }

  static bool _isPurchaseHeader(List<String> headers) {
    final hasDate = headers.contains('date');
    final hasParty = headers.contains('party_name');
    final hasBillNo = headers.contains('bill_no');
    final hasAmount =
        headers.contains('bill_amount') || headers.contains('basic_amount');

    return hasDate && hasParty && hasBillNo && hasAmount;
  }

  static bool _isTdsHeader(List<String> headers) {
    final hasPan = headers.contains('pan_number');
    final hasAmount = headers.contains('deducted_amount');
    final hasDate = headers.contains('date_month') || headers.contains('date');
    final hasTds = headers.contains('tds');

    return hasPan && hasAmount && hasDate && hasTds;
  }

  static String _normalizeHeader(String value) {
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

    const replacements = {
      'bill no': 'bill_no',
      'bill number': 'bill_no',
      'invoice no': 'bill_no',
      'invoice number': 'bill_no',

      'date': 'date',
      'bill date': 'date',
      'invoice date': 'date',

      'party name': 'party_name',
      'party': 'party_name',
      'name': 'party_name',
      'vendor': 'party_name',
      'buyer': 'party_name',

      'gst no': 'gst_no',
      'gst number': 'gst_no',
      'gstin': 'gst_no',
      'gst': 'gst_no',

      'pan': 'pan_number',
      'pan no': 'pan_number',
      'pan number': 'pan_number',
      'panno': 'pan_number',

      'product name': 'productname',
      'productname': 'productname',
      'item name': 'productname',
      'item': 'productname',

      'basic amount': 'basic_amount',
      'basic amt': 'basic_amount',
      'product amount': 'basic_amount',
      'taxable amount': 'basic_amount',
      'amount': 'basic_amount',

      'sgst': 'sgst',
      'cgst': 'cgst',
      'igst': 'igst',

      'bill amount': 'bill_amount',
      'total amount': 'bill_amount',
      'gross amount': 'bill_amount',
      'net amount': 'bill_amount',
      'bill amt': 'bill_amount',

      'date month': 'date_month',
      'month': 'date_month',
      'paid credited date': 'date_month',
      'paid credited dt': 'date_month',

      'deducted amount': 'deducted_amount',
      'deducted amt': 'deducted_amount',
      'amount paid credited': 'deducted_amount',
      'amount paid or credited': 'deducted_amount',

      'tds': 'tds',
      'tax': 'tds',
      'deducted and deposited tax': 'tds',
      'deducted deposited tax': 'tds',

      'challan': 'challan',
      'chalan': 'challan',
      'challan id no details': 'challan',
      'challan id no': 'challan',
    };

    return replacements[text] ?? text.replaceAll(' ', '_');
  }
}