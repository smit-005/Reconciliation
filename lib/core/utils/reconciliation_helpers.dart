import '../../models/reconciliation_row.dart';

String normalizeName(String name) {
  return name
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String normalizePan(String pan) {
  final value = pan.trim().toUpperCase();
  if (value.isEmpty || value == '-' || value == 'NA' || value == 'N/A') {
    return '';
  }
  return value;
}

String normalizeSection(String section) {
  final value = section.trim().toUpperCase();
  if (value.isEmpty || value == '-' || value == 'NA' || value == 'N/A') {
    return 'No Section';
  }
  return value;
}

void sortSections(List<String> sections) {
  const preferredOrder = ['194Q', '194C', '194J', '194I', '194H', 'No Section'];

  sections.sort((a, b) {
    final aIndex = preferredOrder.indexOf(a);
    final bIndex = preferredOrder.indexOf(b);

    if (aIndex != -1 && bIndex != -1) {
      return aIndex.compareTo(bIndex);
    }
    if (aIndex != -1) return -1;
    if (bIndex != -1) return 1;
    return a.compareTo(b);
  });
}

String buildSellerDisplayKey(ReconciliationRow row) {
  final pan = normalizePan(row.sellerPan);
  if (pan.isNotEmpty) {
    return 'PAN:$pan';
  }
  return 'NAME:${normalizeName(row.sellerName)}';
}