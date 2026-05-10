import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';

void sortSections(List<String> sections) {
  sections.sort(TdsSectionCatalog.compare);
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
