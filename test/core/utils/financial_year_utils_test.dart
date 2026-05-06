import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/core/utils/financial_year_utils.dart';

void main() {
  group('currentIndianFinancialYearLabel', () {
    test('uses previous year before April', () {
      expect(
        currentIndianFinancialYearLabel(now: DateTime(2026, 3, 31)),
        '2025-26',
      );
    });

    test('uses current year from April', () {
      expect(
        currentIndianFinancialYearLabel(now: DateTime(2026, 4, 1)),
        '2026-27',
      );
    });
  });
}
