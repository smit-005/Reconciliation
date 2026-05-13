import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';

const String allLedgerSourcesFilterValue = '__ALL_LEDGER_SOURCES__';

String ledgerSourceKeyForTransactionRow(NormalizedTransactionRow row) {
  final id = row.sourceLedgerFileId.trim();
  if (id.isNotEmpty) return id;
  return row.sourceLedgerFileName.trim();
}

String ledgerSourceLabelForRow(ReconciliationRow row) {
  final names =
      row.sourceLedgerFileNames
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (names.isEmpty) return '-';
  return names.join(' | ');
}

bool reconciliationRowMatchesLedgerSource(
  ReconciliationRow row,
  String selectedLedgerSource,
) {
  final selected = selectedLedgerSource.trim();
  if (selected.isEmpty || selected == allLedgerSourcesFilterValue) {
    return true;
  }

  return row.sourceLedgerFileIds.contains(selected) ||
      row.sourceLedgerFileNames.contains(selected);
}

Map<String, String> ledgerSourceLabelsForSections({
  required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
  required String activeSection,
}) {
  final entries = <String, String>{};
  final sectionRows = activeSection == 'All'
      ? sourceRowsBySection.values.expand((rows) => rows)
      : sourceRowsBySection[activeSection] ??
            const <NormalizedTransactionRow>[];

  for (final row in sectionRows) {
    final key = ledgerSourceKeyForTransactionRow(row);
    final label = row.sourceLedgerFileName.trim();
    if (key.isEmpty || label.isEmpty) continue;
    entries.putIfAbsent(key, () => label);
  }

  final sorted = entries.entries.toList()
    ..sort((a, b) {
      final labelCompare = a.value.toUpperCase().compareTo(
        b.value.toUpperCase(),
      );
      if (labelCompare != 0) return labelCompare;
      return a.key.compareTo(b.key);
    });

  return {for (final entry in sorted) entry.key: entry.value};
}
