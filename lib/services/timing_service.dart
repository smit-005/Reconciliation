import '../models/reconciliation_row.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/parse_utils.dart';

class TimingService {
  static const double tolerance = 1.0;

  static List<ReconciliationRow> applyTimingLogic(List<ReconciliationRow> rows) {
    if (rows.isEmpty) return rows;

    final sortedRows = [...rows]
      ..sort((a, b) {
        final fyCompare = a.financialYear.compareTo(b.financialYear);
        if (fyCompare != 0) return fyCompare;
        return compareMonthKeys(a.month, b.month);
      });

    final groupedByFy = <String, List<ReconciliationRow>>{};
    for (final row in sortedRows) {
      groupedByFy.putIfAbsent(row.financialYear, () => []).add(row);
    }

    final output = <ReconciliationRow>[];

    for (final fy in groupedByFy.keys.toList()..sort()) {
      final fyRows = groupedByFy[fy]!;
      double runningBalance = 0.0;

      final monthProcessed = <ReconciliationRow>[];

      for (final row in fyRows) {
        final openingBalance = runningBalance;
        final monthDiff = round2(row.actualTds - row.expectedTds);

        runningBalance = round2(runningBalance + monthDiff);
        final closingBalance = runningBalance;

        monthProcessed.add(
          row.copyWith(
            openingTimingBalance: openingBalance,
            monthTdsDifference: monthDiff,
            closingTimingBalance: closingBalance,
          ),
        );
      }

      for (final row in monthProcessed) {
        output.add(row);
      }
    }

    return output;
  }
}
