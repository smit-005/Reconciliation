enum TdsSectionUploadMode { purchase, genericLedger }

class TdsSectionDefinition {
  final String code;
  final String displayLabel;
  final int sortOrder;
  final TdsSectionUploadMode uploadMode;

  const TdsSectionDefinition({
    required this.code,
    required this.displayLabel,
    required this.sortOrder,
    required this.uploadMode,
  });
}

class TdsSectionCatalog {
  static const List<TdsSectionDefinition> definitions = [
    TdsSectionDefinition(
      code: '194Q',
      displayLabel: '194Q',
      sortOrder: 10,
      uploadMode: TdsSectionUploadMode.purchase,
    ),
    TdsSectionDefinition(
      code: '194A',
      displayLabel: '194A',
      sortOrder: 15,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194C',
      displayLabel: '194C',
      sortOrder: 20,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194H',
      displayLabel: '194H',
      sortOrder: 30,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194I_A',
      displayLabel: '194I(a) Machinery / Plant / Equipment Rent',
      sortOrder: 40,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194I_B',
      displayLabel: '194I(b) Land / Building / Furniture Rent',
      sortOrder: 50,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194J_A',
      displayLabel: '194J(a) Technical Services',
      sortOrder: 60,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
    TdsSectionDefinition(
      code: '194J_B',
      displayLabel: '194J(b) Professional Services',
      sortOrder: 70,
      uploadMode: TdsSectionUploadMode.genericLedger,
    ),
  ];

  static const List<String> supportedSectionCodes = [
    '194Q',
    '194A',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
  ];

  static const Set<String> supportedSectionCodeSet = {
    '194Q',
    '194A',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
  };

  static const Set<String> _legacyUnsupportedCompacts = <String>{};

  static TdsSectionDefinition? definitionFor(String code) {
    final normalized = normalizeCode(code);
    if (normalized.isEmpty) return null;
    for (final definition in definitions) {
      if (definition.code == normalized) return definition;
    }
    return null;
  }

  static bool isSupported(String code) => definitionFor(code) != null;

  static TdsSectionUploadMode uploadModeFor(String code) {
    return definitionFor(code)?.uploadMode ??
        TdsSectionUploadMode.genericLedger;
  }

  static String displayLabel(String code) {
    return definitionFor(code)?.displayLabel ?? code.trim();
  }

  static String normalizeCode(String value) {
    final upper = value.trim().toUpperCase();
    final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (compact.isEmpty) return '';

    if (compact.contains('194IA')) return '194I_A';
    if (compact.contains('194IB')) return '194I_B';
    if (compact.contains('194JA')) return '194J_A';
    if (compact.contains('194JB')) return '194J_B';

    final is194IA =
        upper.contains('194I(A)') ||
        upper.contains('194I A') ||
        upper.contains('194I_A') ||
        (upper.contains('194I') &&
            (upper.contains('MACHINERY') ||
                upper.contains('PLANT') ||
                upper.contains('EQUIPMENT')));
    if (is194IA) return '194I_A';

    final is194IB =
        upper.contains('194I(B)') ||
        upper.contains('194I B') ||
        upper.contains('194I_B') ||
        (upper.contains('194I') &&
            (upper.contains('LAND') ||
                upper.contains('BUILDING') ||
                upper.contains('FURNITURE')));
    if (is194IB) return '194I_B';

    final is194JA =
        upper.contains('194J(A)') ||
        upper.contains('194J A') ||
        upper.contains('194J_A') ||
        (upper.contains('194J') && upper.contains('TECHNICAL'));
    if (is194JA) return '194J_A';

    final is194JB =
        upper.contains('194J(B)') ||
        upper.contains('194J B') ||
        upper.contains('194J_B') ||
        (upper.contains('194J') && upper.contains('PROFESSIONAL'));
    if (is194JB) return '194J_B';

    if (compact.contains('194I')) return '194I';
    if (compact.contains('194Q')) return '194Q';
    if (compact.contains('194A')) return '194A';
    if (compact.contains('194C')) return '194C';
    if (compact.contains('194H')) return '194H';
    if (compact.contains('194J')) return '194J';

    return '';
  }

  static bool isLegacyUnsupportedSection(String value) {
    final compact = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return _legacyUnsupportedCompacts.any(compact.contains);
  }

  static int compare(String a, String b) {
    final aOrder = _sortOrderFor(a);
    final bOrder = _sortOrderFor(b);
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);
    return a.compareTo(b);
  }

  static String sortKey(String value) {
    final normalized = normalizeCode(value);
    final code = normalized.isEmpty ? value.trim() : normalized;
    final order = _sortOrderFor(code);
    if (order >= 9000) return 'Z:$code';
    return 'A:${order.toString().padLeft(4, '0')}:$code';
  }

  static int _sortOrderFor(String value) {
    final normalized = normalizeCode(value);
    final code = normalized.isEmpty ? value.trim() : normalized;
    for (final definition in definitions) {
      if (definition.code == code) return definition.sortOrder;
    }
    if (code.toUpperCase() == 'NO SECTION') return 8000;
    return 9000;
  }
}
