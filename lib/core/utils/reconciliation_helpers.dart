import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';

void sortSections(List<String> sections) {
  const preferredOrder = [
    '194Q',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
    'No Section',
  ];

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
  final resolvedSellerId = row.resolvedSellerId.trim();
  if (resolvedSellerId.isNotEmpty) {
    return resolvedSellerId;
  }
  final pan = normalizePan(row.sellerPan);
  if (pan.isNotEmpty) {
    return 'PAN:$pan';
  }
  return 'NAME:${normalizeName(row.sellerName)}';
}

String buildSellerSectionDisplayKey(ReconciliationRow row) {
  final sellerKey = buildSellerDisplayKey(row);
  final sectionKey = normalizeSection(row.section).isNotEmpty
      ? normalizeSection(row.section)
      : row.section.trim().toUpperCase();
  if (sellerKey.isEmpty) {
    return sectionKey;
  }
  return '$sellerKey|$sectionKey';
}
