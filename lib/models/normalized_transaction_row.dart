import '../core/utils/date_utils.dart';
import 'purchase_row.dart';
import 'tds_26q_row.dart';

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

  const NormalizedTransactionRow({
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
  });

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
    );
  }
}
