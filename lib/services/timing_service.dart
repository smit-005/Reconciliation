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

      final totalExpected = round2(
        monthProcessed.fold(0.0, (sum, row) => sum + row.expectedTds),
      );

      final totalActual = round2(
        monthProcessed.fold(0.0, (sum, row) => sum + row.actualTds),
      );

      final totalDiff = round2(totalActual - totalExpected);

      final hasBothSideMismatch =
          monthProcessed.any((e) => e.monthTdsDifference > tolerance) &&
              monthProcessed.any((e) => e.monthTdsDifference < -tolerance);

      final canBeTiming = totalDiff.abs() <= tolerance && hasBothSideMismatch;

      for (final row in monthProcessed) {
        String finalStatus = row.status;
        String finalRemarks = row.remarks;

        if (!row.purchasePresent && row.tdsPresent) {
          finalStatus = '26Q Only';
        } else if (row.purchasePresent && !row.tdsPresent) {
          if (row.applicableAmount > tolerance) {
            finalStatus = 'Applicable but no 26Q';
          } else {
            finalStatus = 'Purchase Only';
          }
        } else if (row.purchasePresent && row.tdsPresent) {
          final isPartialDeduction =
              row.applicableAmount > tolerance &&
                  row.tds26QAmount > tolerance &&
                  row.tds26QAmount < (row.applicableAmount - tolerance);

          final deductedBaseAlignedWithTds =
              row.tdsRateUsed > 0 &&
                  row.actualTds > tolerance &&
                  (row.tds26QAmount * row.tdsRateUsed - row.actualTds).abs() <= 2.0;

          if (row.monthTdsDifference.abs() <= tolerance &&
              row.openingTimingBalance.abs() <= tolerance &&
              row.closingTimingBalance.abs() <= tolerance) {
            finalStatus = 'Matched';
          } else if (canBeTiming) {
            finalStatus = 'Timing Difference';
          } else if (isPartialDeduction && deductedBaseAlignedWithTds) {
            finalStatus = 'Timing Difference';
          } else {
            if (row.monthTdsDifference < -tolerance) {
              finalStatus = 'Short Deduction';
            } else if (row.monthTdsDifference > tolerance) {
              finalStatus = 'Excess Deduction';
            } else {
              finalStatus =
              totalDiff < 0 ? 'Short Deduction' : 'Excess Deduction';
            }
          }
        }

        finalRemarks = _rebuildRemarksWithTiming(
          originalRemarks: finalRemarks,
          finalStatus: finalStatus,
          openingTimingBalance: row.openingTimingBalance,
          closingTimingBalance: row.closingTimingBalance,
        );

        output.add(
          row.copyWith(
            status: finalStatus,
            remarks: finalRemarks,
          ),
        );
      }
    }

    return output;
  }

  static String _rebuildRemarksWithTiming({
    required String originalRemarks,
    required String finalStatus,
    required double openingTimingBalance,
    required double closingTimingBalance,
  }) {
    final parts = originalRemarks
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    parts.removeWhere(
          (e) =>
      e == 'TDS short' ||
          e == 'TDS excess' ||
          e == 'Timing adjusted' ||
          e == 'Partial deduction / timing difference' ||
          e.startsWith('Opening timing balance') ||
          e.startsWith('Closing timing balance'),
    );

    if (finalStatus == 'Timing Difference') {
      parts.add('Partial deduction / timing difference');

      if (openingTimingBalance.abs() > tolerance) {
        parts.add(
          'Opening timing balance: ${openingTimingBalance.toStringAsFixed(2)}',
        );
      }

      if (closingTimingBalance.abs() > tolerance) {
        parts.add(
          'Closing timing balance: ${closingTimingBalance.toStringAsFixed(2)}',
        );
      }
    } else if (finalStatus == 'Short Deduction') {
      parts.add('TDS short');
    } else if (finalStatus == 'Excess Deduction') {
      parts.add('TDS excess');
    }

    return parts.join(', ');
  }
}