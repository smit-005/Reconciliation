import '../core/utils/normalize_utils.dart';

class Tds26QRow {
  final String month;
  final String financialYear;
  final String deducteeName;
  final String panNumber;
  final double deductedAmount;
  final double tds;
  final String section;

  Tds26QRow({
    required this.month,
    required this.financialYear,
    required this.deducteeName,
    required this.panNumber,
    required this.deductedAmount,
    required this.tds,
    required this.section,
  });

  factory Tds26QRow.fromMap(Map<String, dynamic> map) {
    String rawSection = (map['section'] ?? '').toString();
    String nature = (map['nature_of_payment'] ?? '').toString();

    String finalSection = rawSection;

    if (finalSection.isEmpty || finalSection == '-' || finalSection == 'Unknown') {
      finalSection = _extractSectionFromText(nature);
    }

    return Tds26QRow(
      month: map['month']?.toString() ?? '',
      financialYear: map['financial_year']?.toString() ?? '',
      deducteeName: map['deductee_name']?.toString() ?? '',
      panNumber: map['pan']?.toString() ?? '',
      deductedAmount: _toDouble(map['amount']),
      tds: _toDouble(map['tds']),
      section: normalizeSection(finalSection),
    );
  }

  static String _extractSectionFromText(String text) {
    final t = text.toUpperCase();

    if (t.contains('194Q')) return '194Q';
    if (t.contains('194C')) return '194C';
    if (t.contains('194J')) return '194J';
    if (t.contains('194I')) return '194I';
    if (t.contains('194A')) return '194A';
    if (t.contains('194H')) return '194H';

    return '';
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is num) return value.toDouble();

    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    return parsed ?? 0.0;
  }
}