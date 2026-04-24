part of 'reconciliation_orchestrator.dart';

String _debugSectionCounts(
  Map<String, List<dynamic>> sections, {
  Map<String, List<dynamic>> extra = const {},
}) {
  final parts = <String>[
    for (final entry in sections.entries) '${entry.key}:${entry.value.length}',
    for (final entry in extra.entries) '${entry.key}:${entry.value.length}',
  ];
  if (parts.isEmpty) return 'none';
  parts.sort();
  return parts.join(', ');
}

String _debugSummaryMap(
  Map<String, ReconciliationSummary> summaries,
) {
  if (summaries.isEmpty) return 'none';

  final parts = summaries.entries
      .map(
        (entry) =>
            '${entry.key}(rows:${entry.value.totalRows}, mismatch:${entry.value.mismatchRows}, '
            'source:${entry.value.sourceAmount.toStringAsFixed(2)}, '
            'tds:${entry.value.actualTds.toStringAsFixed(2)})',
      )
      .toList()
    ..sort();

  return parts.join(', ');
}

Map<String, List<dynamic>> _debugResolvedSectionCounts(
  List<_ResolvedSourceRow> rows,
) {
  final map = <String, List<dynamic>>{};
  for (final row in rows) {
    map.putIfAbsent(row.section, () => <dynamic>[]).add(row);
  }
  return map;
}

void _debugDuplicateSourceSectionLeakage(
  List<_ResolvedSourceRow> rows,
) {
  final sectionsByFingerprint = <String, Set<String>>{};

  for (final row in rows) {
    final fingerprint = [
      row.sourceType.trim().toUpperCase(),
      normalizeName(row.originalSellerName),
      normalizePan(row.originalPan),
      row.financialYear.trim().toUpperCase(),
      row.month.trim().toUpperCase(),
      row.amount.toStringAsFixed(2),
    ].join('|');
    sectionsByFingerprint.putIfAbsent(fingerprint, () => <String>{});
    sectionsByFingerprint[fingerprint]!.add(row.section.trim());
  }

  final leaked = sectionsByFingerprint.entries
      .where((entry) => entry.value.length > 1)
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  if (leaked.isEmpty) {
    debugPrint('DUPLICATE SOURCE CHECK => no cross-section source duplication detected');
    return;
  }

  for (final entry in leaked.take(20)) {
    final sections = entry.value.toList()..sort();
    debugPrint(
      'DUPLICATE SOURCE CHECK => fingerprint=${entry.key} emitted sections=[${sections.join(', ')}]',
    );
  }
}
