import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/parse_utils.dart';
class PurchaseRow {
  final String date;
  final String month;
  final String billNo;
  final String partyName;
  final String gstNo;
  final String panNumber;
  final String productName;
  final double basicAmount;
  final double billAmount;
  final String normalizedName;
  final String normalizedPan;
  final String normalizedMonth;
  final String normalizedSection;

  PurchaseRow({
    required this.date,
    required this.month,
    required this.billNo,
    required this.partyName,
    required this.gstNo,
    required this.panNumber,
    required this.productName,
    required this.basicAmount,
    required this.billAmount,
    String? normalizedName,
    String? normalizedPan,
    String? normalizedMonth,
    this.normalizedSection = '194Q',
  }) : normalizedName = normalizedName ?? normalizeName(partyName),
       normalizedPan = normalizedPan ?? normalizePan(panNumber),
       normalizedMonth = normalizedMonth ?? month.trim();

  factory PurchaseRow.fromMap(Map<String, dynamic> map) {
    final rawDate = readAny(map, ['date', 'eom']) ?? '';
    final rawGst = (readAny(map, ['gst_no']) ?? '').trim().toUpperCase();
    final rawPan = normalizePan(readAny(map, ['pan_number']) ?? '');
    final finalPan = rawPan.isNotEmpty ? rawPan : extractPanFromGstin(rawGst);

    return PurchaseRow(
      date: rawDate,
      month: normalizeMonth(rawDate),
      billNo: (readAny(map, ['bill_no']) ?? '').trim(),
      partyName: (readAny(map, ['party_name']) ?? '').trim(),
      gstNo: rawGst,
      panNumber: finalPan,
      productName: (readAny(map, ['productname']) ?? '').trim(),
      basicAmount: parseDouble(
        readAny(map, ['product_amount', 'basic_amount']),
      ),
      billAmount: parseDouble(
        readAny(map, ['bill_amount', 'total_amount', 'gross_amount']),
      ),
    );
  }
}
