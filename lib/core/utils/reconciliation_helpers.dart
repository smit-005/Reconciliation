import '../../features/reconciliation/models/reconciliation_row.dart';
import '../../core/utils/normalize_utils.dart';

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
