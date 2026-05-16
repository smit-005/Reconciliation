import 'package:reconciliation_app/core/config/tds_section_catalog.dart';

const String unsupportedReconciliationSectionTab = 'Unsupported';
const String unsupportedReconciliationStatusFilter = 'Unsupported Section';

bool isUnsupportedReconciliationSection(String section) {
  final trimmed = section.trim();
  if (trimmed.isEmpty) return true;

  final normalized = TdsSectionCatalog.normalizeCode(trimmed);
  return !TdsSectionCatalog.supportedSectionCodeSet.contains(normalized);
}

String unsupportedSectionDisplayLabel(String section) {
  final trimmed = section.trim();
  return trimmed.isEmpty ? 'Unsupported: UNKNOWN' : 'Unsupported: $trimmed';
}

List<String> reconciliationSectionTabsForRows(Iterable<String> sections) {
  final hasUnsupportedRows = sections.any(isUnsupportedReconciliationSection);
  return [
    'All',
    ...TdsSectionCatalog.supportedSectionCodes,
    if (hasUnsupportedRows) unsupportedReconciliationSectionTab,
  ];
}
