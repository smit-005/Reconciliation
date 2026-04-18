import '../core/utils/date_utils.dart';
import '../core/utils/normalize_utils.dart';
import '../core/utils/parse_utils.dart';
import 'purchase_row.dart';

class NormalizedLedgerRow {
  final String sourceType;
  final String sourceFileName;
  final String sectionCode;
  final String transactionDateRaw;
  final String month;
  final String financialYear;
  final String partyName;
  final String panNumber;
  final String gstNo;
  final String documentNo;
  final String description;
  final double amount;
  final double taxableAmount;
  final double tdsAmount;
  final String section;

  const NormalizedLedgerRow({
    required this.sourceType,
    required this.sourceFileName,
    required this.sectionCode,
    required this.transactionDateRaw,
    required this.month,
    required this.financialYear,
    required this.partyName,
    required this.panNumber,
    required this.gstNo,
    required this.documentNo,
    required this.description,
    required this.amount,
    required this.taxableAmount,
    required this.tdsAmount,
    required this.section,
  });

  factory NormalizedLedgerRow.fromPurchaseRow(
    PurchaseRow row, {
    required String sourceFileName,
    String sectionCode = '194Q',
  }) {
    return NormalizedLedgerRow(
      sourceType: 'purchase',
      sourceFileName: sourceFileName,
      sectionCode: sectionCode,
      transactionDateRaw: row.date,
      month: row.month,
      financialYear: financialYearFromMonthKey(row.month),
      partyName: row.partyName,
      panNumber: normalizePan(row.panNumber),
      gstNo: row.gstNo,
      documentNo: row.billNo,
      description: row.productName,
      amount: row.billAmount,
      taxableAmount: row.basicAmount,
      tdsAmount: 0.0,
      section: sectionCode,
    );
  }

  factory NormalizedLedgerRow.fromMap(
    Map<String, dynamic> map, {
    required String sourceFileName,
    required String defaultSection,
  }) {
    final rawDate = readAny(map, ['date', 'date_month', 'eom']) ?? '';
    final rawGst = (readAny(map, ['gst_no']) ?? '').trim().toUpperCase();
    final rawPan = normalizePan(readAny(map, ['pan_number']) ?? '');
    final finalPan = rawPan.isNotEmpty ? rawPan : extractPanFromGstin(rawGst);
    final amount = parseDouble(
      readAny(map, ['amount', 'amount_paid', 'bill_amount', 'basic_amount']),
    );
    final month = normalizeMonth(rawDate);

    return NormalizedLedgerRow(
      sourceType: 'generic_ledger',
      sourceFileName: sourceFileName,
      sectionCode: defaultSection,
      transactionDateRaw: rawDate,
      month: month,
      financialYear: financialYearFromMonthKey(month),
      partyName: (readAny(map, ['party_name']) ?? '').trim(),
      panNumber: finalPan,
      gstNo: rawGst,
      documentNo: (readAny(map, ['bill_no']) ?? '').trim(),
      description: (readAny(map, ['description', 'productname']) ?? '').trim(),
      amount: amount,
      taxableAmount: amount,
      tdsAmount: 0.0,
      section: normalizeSection(defaultSection),
    );
  }
}
