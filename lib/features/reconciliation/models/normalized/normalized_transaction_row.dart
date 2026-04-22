import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';

class NormalizedTransactionRow {
  final String sourceType;
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
  final String normalizedName;
  final String normalizedPan;
  final String normalizedMonth;
  final String normalizedSection;

  NormalizedTransactionRow({
    required this.sourceType,
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
    String? normalizedName,
    String? normalizedPan,
    String? normalizedMonth,
    String? normalizedSection,
  }) : normalizedName = normalizedName ?? normalizeName(partyName),
       normalizedPan = normalizedPan ?? normalizePan(panNumber),
       normalizedMonth = normalizedMonth ?? month.trim(),
       normalizedSection = normalizedSection ?? normalizeSection(section);

  factory NormalizedTransactionRow.fromPurchaseRow(PurchaseRow row) {
    return NormalizedTransactionRow(
      sourceType: 'purchase',
      transactionDateRaw: row.date,
      month: row.month,
      financialYear: financialYearFromMonthKey(row.month),
      partyName: row.partyName,
      panNumber: row.panNumber,
      gstNo: row.gstNo,
      documentNo: row.billNo,
      description: row.productName,
      amount: row.billAmount,
      taxableAmount: row.basicAmount,
      tdsAmount: 0.0,
      section: '',
      normalizedName: row.normalizedName,
      normalizedPan: row.normalizedPan,
      normalizedMonth: row.normalizedMonth,
      normalizedSection: row.normalizedSection,
    );
  }

  factory NormalizedTransactionRow.fromTds26QRow(Tds26QRow row) {
    return NormalizedTransactionRow(
      sourceType: 'tds26q',
      transactionDateRaw: row.month,
      month: row.month,
      financialYear: row.financialYear,
      partyName: row.deducteeName,
      panNumber: row.panNumber,
      gstNo: '',
      documentNo: '',
      description: '',
      amount: row.deductedAmount,
      taxableAmount: row.deductedAmount,
      tdsAmount: row.tds,
      section: row.section,
      normalizedName: row.normalizedName,
      normalizedPan: row.normalizedPan,
      normalizedMonth: row.normalizedMonth,
      normalizedSection: row.normalizedSection,
    );
  }

  factory NormalizedTransactionRow.fromNormalizedLedgerRow(
    NormalizedLedgerRow row,
  ) {
    return NormalizedTransactionRow(
      sourceType: row.sourceType,
      transactionDateRaw: row.transactionDateRaw,
      month: row.month,
      financialYear: row.financialYear,
      partyName: row.partyName,
      panNumber: row.panNumber,
      gstNo: row.gstNo,
      documentNo: row.documentNo,
      description: row.description,
      amount: row.amount,
      taxableAmount: row.taxableAmount,
      tdsAmount: row.tdsAmount,
      section: row.section,
      normalizedName: normalizeName(row.partyName),
      normalizedPan: normalizePan(row.panNumber),
      normalizedMonth: row.month.trim(),
      normalizedSection: normalizeSection(row.section),
    );
  }

  NormalizedTransactionRow copyWith({
    String? sourceType,
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
    String? normalizedName,
    String? normalizedPan,
    String? normalizedMonth,
    String? normalizedSection,
  }) {
    return NormalizedTransactionRow(
      sourceType: sourceType ?? this.sourceType,
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
      normalizedName: normalizedName ?? this.normalizedName,
      normalizedPan: normalizedPan ?? this.normalizedPan,
      normalizedMonth: normalizedMonth ?? this.normalizedMonth,
      normalizedSection: normalizedSection ?? this.normalizedSection,
    );
  }
}
