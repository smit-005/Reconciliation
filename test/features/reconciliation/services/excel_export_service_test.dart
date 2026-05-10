import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';

void main() {
  test('builds readable export filenames without timestamps', () {
    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.currentView,
        buyerName: 'Radha Industries',
        financialYear: 'FY 2025-26',
      ),
      'Radha_Industries_Current_View_FY_2025-26.xlsx',
    );

    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.section,
        buyerName: 'Radha/Industries',
        section: '194C',
        financialYear: '2025-26',
      ),
      'Radha_Industries_194C_FY_2025-26.xlsx',
    );

    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.pivotReport,
        buyerName: 'Radha Industries',
        financialYear: '2025-26',
      ),
      'Radha_Industries_Pivot_Report_FY_2025-26.xlsx',
    );

    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.detailedReport,
        buyerName: 'Radha Industries',
        financialYear: '2025-26',
      ),
      'Radha_Industries_Detailed_Report_FY_2025-26.xlsx',
    );
  });

  test('legacy pivot filename builder uses readable pivot report name', () {
    final fileName = ExcelExportService.buildPivotReportFileName(
      buyerName: 'Radha Industries',
      financialYear: '2026-27',
      generatedAt: DateTime(2026, 5, 6, 18, 44, 55),
    );

    expect(fileName, 'Radha_Industries_Pivot_Report_FY_2026-27.xlsx');
  });

  test('current view export contains only current view sheets', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportCurrentViewExcel(
      rows: [_row(section: '194A')],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    expect(p.basename(path), 'Radha_Industries_Current_View_FY_2025-26.xlsx');

    final sheets = await _sheetNames(path);
    expect(sheets, containsAll(['Current View', 'View Summary']));
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194A')));
    expect(sheets, isNot(contains('194A Pivot')));
  });

  test('section export uses section-oriented workbook structure', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportSectionExcel(
      rows: [
        _row(section: '194C', status: ReconciliationStatus.matched),
        _row(section: '194C', status: ReconciliationStatus.shortDeduction),
      ],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    expect(p.basename(path), 'Radha_Industries_194C_FY_2025-26.xlsx');

    final sheets = await _sheetNames(path);
    expect(
      sheets,
      containsAll([
        'Section Summary',
        'Seller Pivot',
        'Exceptions',
        'Detail',
        'TDS Section Info',
      ]),
    );
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194C')));
  });

  test(
    'pivot report omits combined pivot and raw section detail sheets',
    () async {
      final outputDir = await _tempDir();

      final path = await ExcelExportService.exportPivotReportExcel(
        rows: [
          _row(section: '194A', status: ReconciliationStatus.onlyIn26Q),
          _row(section: '194C', status: ReconciliationStatus.matched),
        ],
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      expect(p.basename(path), 'Radha_Industries_Pivot_Report_FY_2025-26.xlsx');

      final sheets = await _sheetNames(path);
      expect(
        sheets,
        containsAll([
          'Workbook Summary',
          'Section Summary',
          '194A Pivot',
          '194C Pivot',
          'Exceptions',
          'TDS Section Info',
        ]),
      );
      expect(sheets, isNot(contains('Pivot Summary')));
      expect(sheets, isNot(contains('194A')));
      expect(sheets, isNot(contains('194C')));
      expect(sheets, isNot(contains('Raw Reconciliation')));
    },
  );

  test('detailed report keeps one raw reconciliation sheet', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportDetailedReportExcel(
      rows: [
        _row(section: '194A'),
        _row(section: '194C'),
      ],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    expect(
      p.basename(path),
      'Radha_Industries_Detailed_Report_FY_2025-26.xlsx',
    );

    final sheets = await _sheetNames(path);
    expect(
      sheets,
      containsAll([
        'Workbook Summary',
        'Section Summary',
        '194A Pivot',
        '194C Pivot',
        'Raw Reconciliation',
        'TDS Section Info',
      ]),
    );
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194A')));
    expect(sheets, isNot(contains('194C')));
  });
}

Future<Directory> _tempDir() async {
  final outputDir = await Directory.systemTemp.createTemp(
    'ledgermatch_export_test_',
  );
  addTearDown(() async {
    if (await outputDir.exists()) {
      await outputDir.delete(recursive: true);
    }
  });
  return outputDir;
}

Future<List<String>> _sheetNames(String path) async {
  final bytes = await File(path).readAsBytes();
  final workbook = SpreadsheetDecoder.decodeBytes(bytes);
  return workbook.tables.keys.toList();
}

ReconciliationRow _row({
  required String section,
  String status = ReconciliationStatus.onlyIn26Q,
}) {
  return ReconciliationRow(
    buyerName: 'Radha Industries',
    buyerPan: 'ABCDE1234F',
    financialYear: '2025-26',
    month: 'Apr-2025',
    sellerName: 'Interest Vendor',
    sellerPan: 'AAAAA1111A',
    section: section,
    resolvedSellerId: 'PAN:AAAAA1111A',
    resolvedSellerName: 'Interest Vendor',
    resolvedPan: 'AAAAA1111A',
    basicAmount: 25000,
    applicableAmount: 25000,
    tds26QAmount: 25000,
    expectedTds: 2500,
    actualTds: status == ReconciliationStatus.matched ? 2500 : 0,
    tdsRateUsed: 0.10,
    amountDifference: 0,
    tdsDifference: status == ReconciliationStatus.matched ? 0 : 2500,
    status: status,
    remarks: '',
    purchasePresent: true,
    tdsPresent: true,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
