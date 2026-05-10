import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';

class Tds26QRow {
  final String month;
  final String financialYear;
  final String deducteeName;
  final String panNumber;
  final double deductedAmount;
  final double tds;
  final String section;
  final String normalizedName;
  final String normalizedPan;
  final String normalizedMonth;
  final String normalizedSection;

  Tds26QRow({
    required this.month,
    required this.financialYear,
    required this.deducteeName,
    required this.panNumber,
    required this.deductedAmount,
    required this.tds,
    required this.section,
    String? normalizedName,
    String? normalizedPan,
    String? normalizedMonth,
    String? normalizedSection,
  }) : normalizedName = normalizedName ?? normalizeName(deducteeName),
       normalizedPan = normalizedPan ?? normalizePan(panNumber),
       normalizedMonth = normalizedMonth ?? normalizeMonth(month),
       normalizedSection = normalizedSection ?? normalizeSection(section);

  factory Tds26QRow.fromMap(Map<String, dynamic> map) {
    String rawSection = (map['section'] ?? '').toString();
    String nature = (map['nature_of_payment'] ?? map['section'] ?? '')
        .toString();
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
    final fallbackSection = explicitSection.isNotEmpty
        ? explicitSection
        : inferredSection;
    final storedSection = resolvedSection.isNotEmpty
        ? resolvedSection
        : (isLegacyUnsupportedSection(fallbackSection)
              ? '194IB'
              : fallbackSection.trim().toUpperCase());

    return Tds26QRow(
      month: map['date_month']?.toString() ?? map['month']?.toString() ?? '',
      financialYear: map['financial_year']?.toString() ?? '',
      deducteeName:
          map['party_name']?.toString() ??
          map['deductee_name']?.toString() ??
          '',
      panNumber: map['pan_number']?.toString() ?? map['pan']?.toString() ?? '',
      deductedAmount: amountPaid,
      tds: tdsAmount,
      section: storedSection,
    );
  }

  static String _extractSectionFromText(String text) {
    final t = text.toUpperCase();

    if (t.contains('194I(A)') ||
        t.contains('194I A') ||
        t.contains('194I_A') ||
        (t.contains('194I') &&
            (t.contains('MACHINERY') ||
                t.contains('PLANT') ||
                t.contains('EQUIPMENT')))) {
      return '194I_A';
    }
    if (t.contains('194I(B)') ||
        t.contains('194I B') ||
        t.contains('194I_B') ||
        (t.contains('194I') &&
            (t.contains('LAND') ||
                t.contains('BUILDING') ||
                t.contains('FURNITURE')))) {
      return '194I_B';
    }
    if (t.contains('194J(A)') ||
        t.contains('194J A') ||
        t.contains('194J_A') ||
        (t.contains('194J') && t.contains('TECHNICAL'))) {
      return '194J_A';
    }
    if (t.contains('194J(B)') ||
        t.contains('194J B') ||
        t.contains('194J_B') ||
        (t.contains('194J') && t.contains('PROFESSIONAL'))) {
      return '194J_B';
    }
    if (t.contains('194IB')) return '194IB';

    final normalized = TdsSectionCatalog.normalizeCode(t);
    if (TdsSectionCatalog.supportedSectionCodeSet.contains(normalized) ||
        normalized == '194I' ||
        normalized == '194J') {
      return normalized;
    }

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
    final normalized = TdsSectionCatalog.normalizeCode(value);
    return TdsSectionCatalog.supportedSectionCodeSet.contains(normalized) ||
        normalized == '194I' ||
        normalized == '194J' ||
        value.trim().toUpperCase() == '194IB';
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is num) return value.toDouble();

    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    return parsed ?? 0.0;
  }
}
