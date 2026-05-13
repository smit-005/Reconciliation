import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/parse_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';

class NormalizedLedgerRow {
  final String sourceType;
  final String sourceFileName;
  final String sourceLedgerFileId;
  final DateTime? sourceLedgerUploadedAt;
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
    this.sourceLedgerFileId = '',
    this.sourceLedgerUploadedAt,
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
    String sourceLedgerFileId = '',
    DateTime? sourceLedgerUploadedAt,
    String sectionCode = '194Q',
  }) {
    return NormalizedLedgerRow(
      sourceType: 'purchase',
      sourceFileName: sourceFileName,
      sourceLedgerFileId: sourceLedgerFileId,
      sourceLedgerUploadedAt: sourceLedgerUploadedAt,
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
    String sourceLedgerFileId = '',
    DateTime? sourceLedgerUploadedAt,
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
      sourceLedgerFileId: sourceLedgerFileId,
      sourceLedgerUploadedAt: sourceLedgerUploadedAt,
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

  NormalizedLedgerRow copyWith({
    String? sourceType,
    String? sourceFileName,
    String? sourceLedgerFileId,
    DateTime? sourceLedgerUploadedAt,
    String? sectionCode,
    String? transactionDateRaw,
    String? month,
    String? financialYear,
    String? partyName,
    String? panNumber,
    String? gstNo,
    String? documentNo,
    String? description,
    double? amount,
    double? taxableAmount,
    double? tdsAmount,
    String? section,
  }) {
    return NormalizedLedgerRow(
      sourceType: sourceType ?? this.sourceType,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      sourceLedgerFileId: sourceLedgerFileId ?? this.sourceLedgerFileId,
      sourceLedgerUploadedAt:
          sourceLedgerUploadedAt ?? this.sourceLedgerUploadedAt,
      sectionCode: sectionCode ?? this.sectionCode,
      transactionDateRaw: transactionDateRaw ?? this.transactionDateRaw,
      month: month ?? this.month,
      financialYear: financialYear ?? this.financialYear,
      partyName: partyName ?? this.partyName,
      panNumber: panNumber ?? this.panNumber,
      gstNo: gstNo ?? this.gstNo,
      documentNo: documentNo ?? this.documentNo,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      taxableAmount: taxableAmount ?? this.taxableAmount,
      tdsAmount: tdsAmount ?? this.tdsAmount,
      section: section ?? this.section,
    );
  }
}
