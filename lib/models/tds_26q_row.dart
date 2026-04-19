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
    final explicitSection =
        rawSection.trim().isNotEmpty &&
            rawSection.trim() != '-' &&
            rawSection.trim().toUpperCase() != 'UNKNOWN'
        ? rawSection
        : '';
    final inferredSection = explicitSection.isEmpty
        ? (_extractSectionFromText(nature).isNotEmpty
              ? _extractSectionFromText(nature)
              : _inferSection(
                  amount: amountPaid,
                  tds: tdsAmount,
                  sectionHint: rawSection,
                  textHint: nature,
                ))
        : '';
    final resolvedSection = normalizeSection(
      explicitSection.isNotEmpty ? explicitSection : inferredSection,
    );

    return Tds26QRow(
      month: map['date_month']?.toString() ?? map['month']?.toString() ?? '',
      financialYear: map['financial_year']?.toString() ?? '',
      deducteeName:
          map['party_name']?.toString() ?? map['deductee_name']?.toString() ?? '',
      panNumber: map['pan_number']?.toString() ?? map['pan']?.toString() ?? '',
      deductedAmount: amountPaid,
      tds: tdsAmount,
      section: resolvedSection,
    );
  }

  static String _extractSectionFromText(String text) {
    final t = text.toUpperCase();

    if (t.contains('194IB')) return '194IB';
    if (t.contains('194Q')) return '194Q';
    if (t.contains('194C')) return '194C';
    if (t.contains('194H')) return '194H';
    if (t.contains('194J')) return '194J';

    return '';
  }

  static String _inferSection({
    required double amount,
    required double tds,
    String? sectionHint,
    String? textHint,
  }) {
    final rawHint = (sectionHint ?? '').trim().toUpperCase();
    if (_isKnownSection(rawHint)) {
      return rawHint;
    }

    final extractedHint = _extractSectionFromText(textHint ?? '');
    if (_isKnownSection(extractedHint)) {
      return extractedHint;
    }

    // Rate-based section inference is intentionally disabled for CA safety.
    return '';
  }

  static bool _isKnownSection(String value) {
    return value == '194Q' ||
        value == '194C' ||
        value == '194H' ||
        value == '194J' ||
        value == '194IB';
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is num) return value.toDouble();

    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    return parsed ?? 0.0;
  }
}
