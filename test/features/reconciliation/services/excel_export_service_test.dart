import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
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

  test('exports a dedicated 194A section sheet', () async {
    final outputDir = await Directory.systemTemp.createTemp(
      'ledgermatch_194a_export_test_',
    );
    addTearDown(() async {
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }
    });

    final path = await ExcelExportService.exportReconciliationExcel(
      rows: [_row(section: '194A')],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2024-25',
    );

    final bytes = await File(path).readAsBytes();
    final workbook = SpreadsheetDecoder.decodeBytes(bytes);

    expect(workbook.tables.keys, contains('194A'));
  });
}

ReconciliationRow _row({required String section}) {
  return ReconciliationRow(
    buyerName: 'Radha Industries',
    buyerPan: 'ABCDE1234F',
    financialYear: '2024-25',
    month: 'Apr-2024',
    sellerName: 'Interest Vendor',
    sellerPan: 'AAAAA1111A',
    section: section,
    resolvedSellerId: 'PAN:AAAAA1111A',
    resolvedSellerName: 'Interest Vendor',
    resolvedPan: 'AAAAA1111A',
    basicAmount: 25000,
    applicableAmount: 0,
    tds26QAmount: 25000,
    expectedTds: 0,
    actualTds: 0,
    tdsRateUsed: 0,
    amountDifference: 25000,
    tdsDifference: 0,
    status: ReconciliationStatus.onlyIn26Q,
    remarks: '',
    purchasePresent: false,
    tdsPresent: true,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
