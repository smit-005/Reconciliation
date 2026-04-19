part of 'reconciliation_service.dart';

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
