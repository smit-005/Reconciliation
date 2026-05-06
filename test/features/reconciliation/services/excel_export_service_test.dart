import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';

void main() {
  test('builds pivot report filename with second-level timestamp', () {
    final fileName = ExcelExportService.buildPivotReportFileName(
      buyerName: 'Radha Industries',
      financialYear: '2026-27',
      generatedAt: DateTime(2026, 5, 6, 18, 44, 55),
    );

    expect(
      fileName,
      'Pivot_Report_Radha_Industries_FY_2026-27_20260506_184455.xlsx',
    );
  });

  test('sanitizes pivot report filename segments', () {
    final fileName = ExcelExportService.buildPivotReportFileName(
      buyerName: 'Radha/Industries',
      sellerName: 'A:B Traders',
      financialYear: 'FY 2026-27',
      generatedAt: DateTime(2026, 5, 6, 18, 44, 55),
    );

    expect(
      fileName,
      'Pivot_Report_Radha_Industries_A_B_Traders_FY_2026-27_20260506_184455.xlsx',
    );
  });
}
