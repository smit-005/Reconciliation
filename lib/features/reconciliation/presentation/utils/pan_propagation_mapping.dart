import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';

typedef PanPropagationTdsPanCandidate = ({
  String sellerName,
  String panNumber,
  String sectionCode,
});

Map<String, String> buildPanPropagationMapping({
  required Iterable<MapEntry<String, String>> manualMappings,
  required Iterable<({String purchaseParty, String mappedTdsParty})>
  autoMappings,
}) {
  final propagation = <String, String>{};

  for (final entry in manualMappings) {
    final aliasKey = _normalizeMappingKey(entry.key);
    final mappedName = entry.value.trim();
    if (aliasKey.isEmpty || mappedName.isEmpty) continue;
    propagation[aliasKey] = mappedName;
  }

  for (final mapping in autoMappings) {
    final purchaseAlias = normalizeName(mapping.purchaseParty.trim());
    final mappedName = mapping.mappedTdsParty.trim();
    if (purchaseAlias.isEmpty || mappedName.isEmpty) continue;

    // PAN propagation should only happen on exact normalized-name matches.
    if (normalizeName(mapping.purchaseParty) != normalizeName(mappedName)) {
      continue;
    }

    propagation.putIfAbsent(purchaseAlias, () => mappedName);
  }

  return propagation;
}

Map<String, String> buildSectionAwarePanPropagationLookup({
  required Iterable<PanPropagationTdsPanCandidate> candidates,
  required bool normalizeSellerName,
}) {
  final panSets = <String, Set<String>>{};

  for (final candidate in candidates) {
    final lookupKey = buildPanPropagationLookupKey(
      sellerName: candidate.sellerName,
      sectionCode: candidate.sectionCode,
      normalizeSellerName: normalizeSellerName,
    );
    final pan = normalizePan(candidate.panNumber);
    if (lookupKey.isEmpty || pan.isEmpty) continue;

    panSets.putIfAbsent(lookupKey, () => <String>{}).add(pan);
  }

  return {
    for (final entry in panSets.entries)
      if (entry.value.length == 1) entry.key: entry.value.first,
  };
}

String resolveSectionAwarePanPropagation({
  required Map<String, String> exactTdsPanLookup,
  required Map<String, String> normalizedTdsPanLookup,
  required String mappedName,
  required String sectionCode,
}) {
  final pans = <String>{};

  final exactKey = buildPanPropagationLookupKey(
    sellerName: mappedName,
    sectionCode: sectionCode,
  );
  final exactPan = exactTdsPanLookup[exactKey];
  if (exactPan != null && exactPan.isNotEmpty) {
    pans.add(exactPan);
  }

  final normalizedKey = buildPanPropagationLookupKey(
    sellerName: mappedName,
    sectionCode: sectionCode,
    normalizeSellerName: true,
  );
  final normalizedPan = normalizedTdsPanLookup[normalizedKey];
  if (normalizedPan != null && normalizedPan.isNotEmpty) {
    pans.add(normalizedPan);
  }

  return pans.length == 1 ? pans.first : '';
}

String buildPanPropagationLookupKey({
  required String sellerName,
  required String sectionCode,
  bool normalizeSellerName = false,
}) {
  final sellerKey = normalizeSellerName
      ? normalizeName(sellerName)
      : sellerName.trim().toUpperCase();
  final sectionKey = normalizeSellerMappingSectionCode(sectionCode);
  if (sellerKey.isEmpty || sectionKey.isEmpty) return '';
  return '$sellerKey|$sectionKey';
}

String _normalizeMappingKey(String value) {
  final parts = value.split('|');
  final aliasKey = normalizeName(parts.first.trim());
  if (aliasKey.isEmpty || parts.length < 2) return aliasKey;

  final sectionCode = normalizeSellerMappingSectionCode(parts[1]);
  if (sectionCode.isEmpty || sectionCode == 'ALL') return aliasKey;
  return '$aliasKey|$sectionCode';
}
