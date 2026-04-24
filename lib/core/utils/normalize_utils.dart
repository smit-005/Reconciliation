String normalizeName(String name) {
  var text = name.toUpperCase().trim();

  text = text.replaceAll('&', ' AND ');
  text = text.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
  text = text.replaceAll(RegExp(r'\bM/S\b'), ' ');
  text = text.replaceAll(RegExp(r'\bMS\b'), ' ');
  text = text.replaceAll(RegExp(r'\bPVT\b'), ' ');
  text = text.replaceAll(RegExp(r'\bPRIVATE\b'), ' ');
  text = text.replaceAll(RegExp(r'\bLTD\b'), ' ');
  text = text.replaceAll(RegExp(r'\bLIMITED\b'), ' ');
  text = text.replaceAll(RegExp(r'\bCO\b'), ' ');
  text = text.replaceAll(RegExp(r'\bCOMPANY\b'), ' ');
  text = text.replaceAll(RegExp(r'\bIND\b'), ' INDUSTRIES ');
  text = text.replaceAll(RegExp(r'\bINDUSTRY\b'), ' INDUSTRIES ');
  text = text.replaceAll(RegExp(r'\bLOGISTICS\b'), ' LOGISTICS ');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.trim();

  return text.replaceAll(' ', '');
}

String normalizePan(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

String normalizeSection(String value) {
  final upper = value.trim().toUpperCase();
  final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');

  if (compact.isEmpty) return '';

  final is194IA = upper.contains('194I(A)') ||
      upper.contains('194I A') ||
      upper.contains('194I_A') ||
      (upper.contains('194I') &&
          (upper.contains('MACHINERY') ||
              upper.contains('PLANT') ||
              upper.contains('EQUIPMENT')));
  if (is194IA) return '194I_A';

  final is194IB = upper.contains('194I(B)') ||
      upper.contains('194I B') ||
      upper.contains('194I_B') ||
      (upper.contains('194I') &&
          (upper.contains('LAND') ||
              upper.contains('BUILDING') ||
              upper.contains('FURNITURE')));
  if (is194IB) return '194I_B';

  final is194JA = upper.contains('194J(A)') ||
      upper.contains('194J A') ||
      upper.contains('194J_A') ||
      (upper.contains('194J') && upper.contains('TECHNICAL'));
  if (is194JA) return '194J_A';

  final is194JB = upper.contains('194J(B)') ||
      upper.contains('194J B') ||
      upper.contains('194J_B') ||
      (upper.contains('194J') && upper.contains('PROFESSIONAL'));
  if (is194JB) return '194J_B';

  if (compact.contains('194I')) return '194I';
  if (compact.contains('194Q')) return '194Q';
  if (compact.contains('194C')) return '194C';
  if (compact.contains('194H')) return '194H';
  if (compact.contains('194J')) return '194J';

  return '';
}

bool isLegacyUnsupportedSection(String value) {
  final compact = value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return compact.contains('194IB');
}

String sectionDisplayLabel(String value) {
  switch (value.trim()) {
    case '194Q':
      return '194Q';
    case '194C':
      return '194C';
    case '194H':
      return '194H';
    case '194I_A':
      return '194I(a) Machinery / Plant / Equipment Rent';
    case '194I_B':
      return '194I(b) Land / Building / Furniture Rent';
    case '194J_A':
      return '194J(a) Technical Services';
    case '194J_B':
      return '194J(b) Professional Services';
    default:
      return value.trim();
  }
}

bool looksLikePan(String value) {
  final text = value.trim().toUpperCase();
  final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  return panRegex.hasMatch(text);
}

String extractPanFromGstin(String gstin) {
  final clean = gstin.trim().toUpperCase();

  if (clean.length != 15) return '';

  final pan = clean.substring(2, 12);
  final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  return panRegex.hasMatch(pan) ? pan : '';
}
