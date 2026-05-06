import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';

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

String _normalizeMappingKey(String value) {
  final parts = value.split('|');
  final aliasKey = normalizeName(parts.first.trim());
  if (aliasKey.isEmpty || parts.length < 2) return aliasKey;

  final sectionCode = normalizeSellerMappingSectionCode(parts[1]);
  if (sectionCode.isEmpty || sectionCode == 'ALL') return aliasKey;
  return '$aliasKey|$sectionCode';
}
