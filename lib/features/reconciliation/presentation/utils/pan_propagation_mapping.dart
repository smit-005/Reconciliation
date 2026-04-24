import 'package:reconciliation_app/core/utils/normalize_utils.dart';

Map<String, String> buildPanPropagationMapping({
  required Iterable<MapEntry<String, String>> manualMappings,
  required Iterable<({String purchaseParty, String mappedTdsParty})> autoMappings,
}) {
  final propagation = <String, String>{};

  for (final entry in manualMappings) {
    final aliasKey = normalizeName(entry.key.trim());
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
