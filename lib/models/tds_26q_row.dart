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
    String nature = (map['nature_of_payment'] ?? map['section'] ?? '').toString();
    final amountPaid = _toDouble(map['amount_paid'] ?? map['deducted_amount']);
    final tdsAmount = _toDouble(map['tds_amount'] ?? map['tds']);

    String finalSection = rawSection;

    if (finalSection.isEmpty || finalSection == '-' || finalSection == 'Unknown') {
      finalSection = _extractSectionFromText(nature);
    }

    if (finalSection.isEmpty ||
        finalSection == '-' ||
        finalSection.toUpperCase() == 'UNKNOWN') {
      finalSection = _inferSection(
        amount: amountPaid,
        tds: tdsAmount,
        sectionHint: rawSection,
        textHint: nature,
      );
    }

    return Tds26QRow(
      month: map['date_month']?.toString() ?? map['month']?.toString() ?? '',
      financialYear: map['financial_year']?.toString() ?? '',
      deducteeName:
          map['party_name']?.toString() ?? map['deductee_name']?.toString() ?? '',
      panNumber: map['pan_number']?.toString() ?? map['pan']?.toString() ?? '',
      deductedAmount: amountPaid,
      tds: tdsAmount,
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

  static String _inferSection({
    required double amount,
    required double tds,
    String? sectionHint,
    String? textHint,
  }) {
    final normalizedHint = normalizeSection(sectionHint ?? '');
    if (_isKnownSection(normalizedHint)) {
      return normalizedHint;
    }

    final extractedHint = normalizeSection(_extractSectionFromText(textHint ?? ''));
    if (_isKnownSection(extractedHint)) {
      return extractedHint;
    }

    if (amount <= 0 || tds <= 0) return 'UNKNOWN';

    final rate = (tds / amount) * 100;

    if (rate >= 0.05 && rate <= 0.2 && amount >= 10000) {
      return '194Q';
    }
    if (rate >= 0.5 && rate <= 2.5 && amount >= 1000) {
      return '194C';
    }
    if (rate >= 8 && rate <= 12 && amount >= 1000) {
      return '194J';
    }

    return 'UNKNOWN';
  }

  static bool _isKnownSection(String value) {
    return value == '194Q' ||
        value == '194C' ||
        value == '194J' ||
        value == '194I' ||
        value == '194A' ||
        value == '194H';
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is num) return value.toDouble();

    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    return parsed ?? 0.0;
  }
}
