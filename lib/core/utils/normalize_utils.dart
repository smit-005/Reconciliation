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
  return value.trim().toUpperCase();
}

String normalizeSection(String value) {
  final compact = value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  if (compact.isEmpty) return '';

  if (compact.contains('194IB')) return '194IB';
  if (compact.contains('194Q')) return '194Q';
  if (compact.contains('194C')) return '194C';
  if (compact.contains('194H')) return '194H';
  if (compact.contains('194J')) return '194J';

  return '';
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
