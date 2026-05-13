import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';

class ReconciliationExportRowScope {
  const ReconciliationExportRowScope._();

  static List<ReconciliationRow> currentViewRows({
    required List<ReconciliationRow> visibleTableRows,
  }) {
    return List<ReconciliationRow>.of(visibleTableRows);
  }

  static List<ReconciliationRow> sectionRows({
    required List<ReconciliationRow> allRows,
    required String? selectedSection,
    required String selectedFinancialYear,
  }) {
    final section = selectedSection?.trim();
    if (section == null || section.isEmpty) {
      return const <ReconciliationRow>[];
    }

    final exportRows = allRows.where((row) {
      if (row.section.trim() != section) return false;
      if (!_matchesFinancialYear(row, selectedFinancialYear)) return false;
      return true;
    }).toList();

    sortRows(exportRows);
    return exportRows;
  }

  static List<ReconciliationRow> reportRows({
    required List<ReconciliationRow> allRows,
    required String selectedFinancialYear,
  }) {
    final exportRows = allRows
        .where((row) => _matchesFinancialYear(row, selectedFinancialYear))
        .toList();

    sortRows(exportRows);
    return exportRows;
  }

  static void sortRows(List<ReconciliationRow> rows) {
    rows.sort((a, b) {
      final sectionCompare = TdsSectionCatalog.compare(
        a.section.trim(),
        b.section.trim(),
      );
      if (sectionCompare != 0) return sectionCompare;

      final sellerCompare = _sellerLabel(
        a,
      ).trim().toUpperCase().compareTo(_sellerLabel(b).trim().toUpperCase());
      if (sellerCompare != 0) return sellerCompare;

      final fyCompare = a.financialYear.trim().compareTo(
        b.financialYear.trim(),
      );
      if (fyCompare != 0) return fyCompare;

      return CalculationService.compareMonthLabels(a.month, b.month);
    });
  }

  static bool _matchesFinancialYear(
    ReconciliationRow row,
    String selectedFinancialYear,
  ) {
    final fy = selectedFinancialYear.trim();
    return fy == 'All FY' || row.financialYear.trim() == fy;
  }

  static String _sellerLabel(ReconciliationRow row) {
    final resolved = row.resolvedSellerName.trim();
    return resolved.isEmpty ? row.sellerName : resolved;
  }
}
