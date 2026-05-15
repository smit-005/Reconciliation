import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/section_rule_export_text.dart';
import 'package:reconciliation_app/features/reconciliation/services/section_rule_registry.dart';

void main() {
  test('export rule text is sourced from SectionRuleRegistry', () {
    final ruleInfo = {
      for (final info in SectionRuleExportText.allRules()) info.section: info,
    };

    expect(ruleInfo.keys.toSet(), SectionRuleRegistry.rules.keys.toSet());

    for (final entry in SectionRuleRegistry.rules.entries) {
      final info = ruleInfo[entry.key];
      expect(info, isNotNull);
      expect(
        info!.thresholdText,
        SectionRuleExportText.thresholdText(entry.value),
      );
      expect(
        info.rateText,
        SectionRuleExportText.rateText(entry.value.rateConfig),
      );
      expect(
        info.applicabilityText,
        SectionRuleExportText.applicabilityText(entry.value.applicabilityMode),
      );
    }
  });

  test('builds readable export filenames without timestamps', () {
    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.currentView,
        buyerName: 'Radha Industries',
        financialYear: 'FY 2025-26',
      ),
      'Radha_Industries_Working_View_FY_2025-26.xlsx',
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
      'Radha_Industries_Final_Export_FY_2025-26.xlsx',
    );

    expect(
      ExcelExportService.buildExportFileName(
        mode: ExcelExportMode.detailedReport,
        buyerName: 'Radha Industries',
        financialYear: '2025-26',
      ),
      'Radha_Industries_Detailed_Audit_Export_FY_2025-26.xlsx',
    );
  });

  test('legacy pivot filename builder uses readable final export name', () {
    final fileName = ExcelExportService.buildPivotReportFileName(
      buyerName: 'Radha Industries',
      financialYear: '2026-27',
      generatedAt: DateTime(2026, 5, 6, 18, 44, 55),
    );

    expect(fileName, 'Radha_Industries_Final_Export_FY_2026-27.xlsx');
  });

  test('working view export contains working package sheets', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportCurrentViewExcel(
      rows: [_row(section: '194A')],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    expect(p.basename(path), 'Radha_Industries_Working_View_FY_2025-26.xlsx');

    final sheets = await _sheetNames(path);
    expect(
      sheets,
      orderedEquals([
        'Summary',
        'Pivot',
        'Missing_In_Books',
        'Raw_Data',
        'TDS_Section_Info',
      ]),
    );
    expect(sheets, isNot(contains('Timing_Difference')));
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194A')));
    expect(sheets, isNot(contains('194A Pivot')));
  });

  test(
    'current view export contains exactly supplied visible table rows',
    () async {
      final outputDir = await _tempDir();
      final visibleRows = [
        _row(section: '194C', sellerName: 'Visible Contractor A'),
        _row(section: '194C', sellerName: 'Visible Contractor B'),
      ];

      final path = await ExcelExportService.exportCurrentViewExcel(
        rows: visibleRows,
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      final currentViewRows = await _sheetRows(path, 'Raw_Data');
      expect(
        _sheetContainsText(currentViewRows, 'Visible Contractor A'),
        isTrue,
      );
      expect(
        _sheetContainsText(currentViewRows, 'Visible Contractor B'),
        isTrue,
      );
      expect(_sheetContainsText(currentViewRows, 'Hidden Contractor'), isFalse);
      expect(_detailDataRowCount(currentViewRows, header: 'Buyer Name'), 2);
    },
  );

  test(
    'current view export includes visible ledger-filtered source rows',
    () async {
      final outputDir = await _tempDir();
      final visibleRows = [
        _row(
          section: '194C',
          sellerName: 'Visible Contractor A',
          sourceLedgerFileIds: const ['ledger-a'],
          sourceLedgerFileNames: const ['contractors-a.xlsx'],
        ),
      ];

      final path = await ExcelExportService.exportCurrentViewExcel(
        rows: visibleRows,
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        gstNo: '27ABCDE1234F1Z5',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      final currentViewRows = await _sheetRows(path, 'Raw_Data');
      expect(
        _sheetContainsText(currentViewRows, 'Visible Contractor A'),
        isTrue,
      );
      expect(_sheetContainsText(currentViewRows, 'ledger-a'), isTrue);
      expect(_sheetContainsText(currentViewRows, 'contractors-a.xlsx'), isTrue);
    },
  );

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
        'Section_Summary',
        'Section_Pivot',
        'Ledger_Pivot',
        'Missing_In_Books',
        'Exceptions',
        'Raw_Data',
        'TDS_Section_Info',
      ]),
    );
    expect(sheets, isNot(contains('Timing_Difference')));
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194C')));
  });

  test('below-threshold 194C row appears in Export Section Detail', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportSectionExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'Below Threshold Contractor',
          status: ReconciliationStatus.belowThreshold,
          basicAmount: 25000,
          applicableAmount: 0,
          expectedTds: 0,
          actualTds: 0,
          tds26QAmount: 0,
          tdsDifference: 0,
          tdsPresent: false,
        ),
        _row(section: '194C', sellerName: 'Applicable Contractor'),
      ],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final detailRows = await _sheetRows(path, 'Raw_Data');
    expect(
      _sheetContainsText(detailRows, 'Below Threshold Contractor'),
      isTrue,
    );
    expect(
      _sheetContainsText(detailRows, ReconciliationStatus.belowThreshold),
      isTrue,
    );
  });

  test(
    'final export keeps summary pivots and omits raw reconciliation',
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

      expect(p.basename(path), 'Radha_Industries_Final_Export_FY_2025-26.xlsx');

      final sheets = await _sheetNames(path);
      expect(
        sheets,
        containsAll([
          'Master_Summary',
          'Section_Summary',
          '194A Pivot',
          '194C Pivot',
          'Ledger_Pivot',
          'Final_Missing_In_Books',
          'Exception_Summary',
          'TDS_Section_Info',
        ]),
      );
      expect(sheets, isNot(contains('Final_Timing_Difference')));
      expect(sheets, isNot(contains('Pivot Summary')));
      expect(sheets, isNot(contains('194A')));
      expect(sheets, isNot(contains('194C')));
      expect(sheets, isNot(contains('Raw_Reconciliation')));
    },
  );

  test('pivot report section sheets include below-threshold rows', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportPivotReportExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'Below Threshold Contractor',
          status: ReconciliationStatus.belowThreshold,
          basicAmount: 25000,
          applicableAmount: 0,
          expectedTds: 0,
          actualTds: 0,
          tds26QAmount: 0,
          tdsDifference: 0,
          tdsPresent: false,
        ),
        _row(section: '194C', sellerName: 'Applicable Contractor'),
      ],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final pivotRows = await _sheetRows(path, '194C Pivot');
    expect(_sheetContainsText(pivotRows, 'BELOW THRESHOLD CONTRACTOR'), isTrue);
    expect(
      _sheetContainsText(pivotRows, ReconciliationStatus.belowThreshold),
      isTrue,
    );
  });

  test('final export includes ledger pivot grouped by source ledger', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportPivotReportExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'Transport Only Contractor',
          sourceLedgerFileIds: const ['ledger-transport'],
          sourceLedgerFileNames: const ['Transport_April.xlsx'],
        ),
        _row(
          section: '194C',
          sellerName: 'Labour Only Contractor',
          sourceLedgerFileIds: const ['ledger-labour'],
          sourceLedgerFileNames: const ['Labour_Contractor.xlsx'],
        ),
        _row(
          section: '194C',
          sellerName: 'Multi Source Contractor',
          sourceLedgerFileIds: const ['ledger-transport', 'ledger-labour'],
          sourceLedgerFileNames: const [
            'Transport_April.xlsx',
            'Labour_Contractor.xlsx',
          ],
        ),
      ],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final sheets = await _sheetNames(path);
    expect(sheets, contains('194C Pivot'));
    expect(sheets, contains('Ledger_Pivot'));
    expect(sheets, isNot(contains('194C_Transport_April')));
    expect(sheets, isNot(contains('194C_Labour_Contractor')));

    final sectionPivotRows = await _sheetRows(path, '194C Pivot');
    expect(
      _sheetContainsTextContaining(
        sectionPivotRows,
        'Ledger: Transport_April.xlsx',
      ),
      isTrue,
    );
    expect(
      _sheetContainsTextContaining(sectionPivotRows, '2 ledgers:'),
      isTrue,
    );
    expect(
      _sheetContainsTextContaining(sectionPivotRows, 'Labour_Contractor.xlsx'),
      isTrue,
    );
    expect(
      _sheetContainsText(sectionPivotRows, 'Source Ledger Files'),
      isFalse,
    );

    final ledgerRows = await _sheetRows(path, 'Ledger_Pivot');
    expect(_sheetContainsText(ledgerRows, 'Transport_April.xlsx'), isTrue);
    expect(_sheetContainsText(ledgerRows, 'Labour_Contractor.xlsx'), isTrue);
    expect(_sheetContainsText(ledgerRows, 'Transport Only Contractor'), isTrue);
    expect(_sheetContainsText(ledgerRows, 'Multi Source Contractor'), isTrue);
  });

  test(
    'final export keeps one ledger pivot sheet for sanitized ledger names',
    () async {
      final outputDir = await _tempDir();

      final path = await ExcelExportService.exportPivotReportExcel(
        rows: [
          _row(
            section: '194C',
            sellerName: 'Sanitized Contractor A',
            sourceLedgerFileIds: const ['ledger-invalid-a'],
            sourceLedgerFileNames: const [
              'Transport:April Very Very Long Name.xlsx',
            ],
          ),
          _row(
            section: '194C',
            sellerName: 'Sanitized Contractor B',
            sourceLedgerFileIds: const ['ledger-invalid-b'],
            sourceLedgerFileNames: const [
              'Transport?April Very Very Long Name.xlsx',
            ],
          ),
        ],
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      final sheets = await _sheetNames(path);
      expect(sheets.where((sheet) => sheet == 'Ledger_Pivot'), hasLength(1));
      expect(
        sheets.where((sheet) => sheet.startsWith('194C_Transport_April')),
        isEmpty,
      );

      final ledgerRows = await _sheetRows(path, 'Ledger_Pivot');
      expect(
        _sheetContainsText(
          ledgerRows,
          'Transport:April Very Very Long Name.xlsx',
        ),
        isTrue,
      );
      expect(
        _sheetContainsText(
          ledgerRows,
          'Transport?April Very Very Long Name.xlsx',
        ),
        isTrue,
      );
    },
  );

  test(
    'ledger pivot sheet is generated for section and final-style exports',
    () async {
      final outputDir = await _tempDir();
      final rows = [
        _row(
          section: '194C',
          sellerName: 'Transport Only Contractor',
          sourceLedgerFileIds: const ['ledger-transport'],
          sourceLedgerFileNames: const ['Transport_April.xlsx'],
        ),
      ];

      final currentViewPath = await ExcelExportService.exportCurrentViewExcel(
        rows: rows,
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );
      final sectionPath = await ExcelExportService.exportSectionExcel(
        rows: rows,
        section: '194C',
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );
      final detailedPath = await ExcelExportService.exportDetailedReportExcel(
        rows: rows,
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      expect(
        await _sheetNames(currentViewPath),
        isNot(contains('Ledger_Pivot')),
      );
      expect(await _sheetNames(sectionPath), contains('Ledger_Pivot'));
      expect(await _sheetNames(detailedPath), contains('Ledger_Pivot'));
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
      'Radha_Industries_Detailed_Audit_Export_FY_2025-26.xlsx',
    );

    final sheets = await _sheetNames(path);
    expect(
      sheets,
      containsAll([
        'Master_Summary',
        'Section_Summary',
        '194A Pivot',
        '194C Pivot',
        'Ledger_Pivot',
        'Final_Missing_In_Books',
        'Exception_Summary',
        'Raw_Reconciliation',
        'Exception_Details',
        'Technical_Details',
        'TDS_Section_Info',
      ]),
    );
    expect(sheets, isNot(contains('Final_Timing_Difference')));
    expect(sheets, isNot(contains('Pivot Summary')));
    expect(sheets, isNot(contains('194A')));
    expect(sheets, isNot(contains('194C')));
  });

  test(
    'below-threshold row appears in Detailed Report Raw Reconciliation',
    () async {
      final outputDir = await _tempDir();

      final path = await ExcelExportService.exportDetailedReportExcel(
        rows: [
          _row(
            section: '194C',
            sellerName: 'Below Threshold Contractor',
            status: ReconciliationStatus.belowThreshold,
            basicAmount: 25000,
            applicableAmount: 0,
            expectedTds: 0,
            actualTds: 0,
            tds26QAmount: 0,
            tdsDifference: 0,
            tdsPresent: false,
          ),
          _row(section: '194A', sellerName: 'Interest Vendor'),
        ],
        buyerName: 'Radha Industries',
        buyerPan: 'ABCDE1234F',
        outputFolderPath: outputDir.path,
        financialYear: '2025-26',
      );

      final rawRows = await _sheetRows(path, 'Raw_Reconciliation');
      expect(_sheetContainsText(rawRows, 'Below Threshold Contractor'), isTrue);
      expect(
        _sheetContainsText(rawRows, ReconciliationStatus.belowThreshold),
        isTrue,
      );
    },
  );

  test('detail and pivot exports include TDS Rate Used', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportSectionExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'One Percent Contractor',
          tdsRateUsed: 0.01,
        ),
      ],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final detailRows = await _sheetRows(path, 'Raw_Data');
    final pivotRows = await _sheetRows(path, 'Section_Pivot');

    expect(_sheetContainsText(detailRows, 'TDS Rate Used'), isTrue);
    expect(_sheetContainsText(pivotRows, 'TDS Rate Used'), isTrue);
    expect(_sheetContainsValue(detailRows, 0.01), isTrue);
    expect(_sheetContainsValue(pivotRows, 0.01), isTrue);
  });

  test('section detail export includes ledger source columns', () async {
    final outputDir = await _tempDir();
    final path = await ExcelExportService.exportSectionExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'Source Contractor',
          sourceLedgerFileIds: const ['ledger-c'],
          sourceLedgerFileNames: const ['contractors-c.xlsx'],
          sourceLedgerUploadedAtIso: const ['2026-05-13T10:30:00.000'],
        ),
      ],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      gstNo: '27ABCDE1234F1Z5',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final detailRows = await _sheetRows(path, 'Raw_Data');
    expect(_sheetContainsText(detailRows, 'Source Ledger File IDs'), isTrue);
    expect(_sheetContainsText(detailRows, 'Source Ledger Files'), isTrue);
    expect(_sheetContainsText(detailRows, 'Source Ledger Uploaded At'), isTrue);
    expect(_sheetContainsText(detailRows, 'ledger-c'), isTrue);
    expect(_sheetContainsText(detailRows, 'contractors-c.xlsx'), isTrue);
  });

  test('detailed report raw export keeps ledger source columns', () async {
    final outputDir = await _tempDir();
    final path = await ExcelExportService.exportDetailedReportExcel(
      rows: [
        _row(
          section: '194C',
          sellerName: 'Raw Source Contractor',
          sourceLedgerFileIds: const ['ledger-raw'],
          sourceLedgerFileNames: const ['raw-source.xlsx'],
        ),
      ],
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      gstNo: '27ABCDE1234F1Z5',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final rawRows = await _sheetRows(path, 'Raw_Reconciliation');
    expect(_sheetContainsText(rawRows, 'Source Ledger File IDs'), isTrue);
    expect(_sheetContainsText(rawRows, 'Source Ledger Files'), isTrue);
    expect(_sheetContainsText(rawRows, 'ledger-raw'), isTrue);
    expect(_sheetContainsText(rawRows, 'raw-source.xlsx'), isTrue);
  });

  test('section summary uses non-matched terminology', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportSectionExcel(
      rows: [
        _row(section: '194C', status: ReconciliationStatus.matched),
        _row(section: '194C', status: ReconciliationStatus.belowThreshold),
      ],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final summaryRows = await _sheetRows(path, 'Section_Summary');
    expect(_sheetContainsText(summaryRows, 'Non-Matched Rows'), isTrue);
    expect(_sheetContainsText(summaryRows, 'Mismatch Rows'), isFalse);
  });

  test('194C summaries do not leak generic 194Q threshold value', () async {
    final outputDir = await _tempDir();

    final path = await ExcelExportService.exportSectionExcel(
      rows: [_row(section: '194C')],
      section: '194C',
      buyerName: 'Radha Industries',
      buyerPan: 'ABCDE1234F',
      outputFolderPath: outputDir.path,
      financialYear: '2025-26',
    );

    final detailRows = await _sheetRows(path, 'Raw_Data');
    final sectionSummaryRows = await _sheetRows(path, 'Section_Summary');

    expect(_sheetContainsText(detailRows, 'Rule Text'), isTrue);
    expect(_sheetContainsText(detailRows, 'Threshold'), isFalse);
    expect(_sheetContainsText(detailRows, '5000000.00'), isFalse);
    expect(_sheetContainsText(sectionSummaryRows, '5000000.00'), isFalse);
    expect(
      _sheetContainsText(
        sectionSummaryRows,
        SectionRuleExportText.summaryTextForSections(['194C']),
      ),
      isTrue,
    );
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

Future<List<List<dynamic>>> _sheetRows(String path, String sheetName) async {
  final bytes = await File(path).readAsBytes();
  final workbook = SpreadsheetDecoder.decodeBytes(bytes);
  final sheet = workbook.tables[sheetName];
  expect(sheet, isNotNull, reason: 'Expected sheet $sheetName to exist');
  return sheet!.rows;
}

bool _sheetContainsText(List<List<dynamic>> rows, String value) {
  return rows.any((row) => row.any((cell) => cell?.toString().trim() == value));
}

bool _sheetContainsTextContaining(List<List<dynamic>> rows, String value) {
  return rows.any(
    (row) => row.any((cell) => cell?.toString().contains(value) ?? false),
  );
}

bool _sheetContainsValue(List<List<dynamic>> rows, num value) {
  return rows.any(
    (row) => row.any((cell) => cell is num && (cell - value).abs() < 0.000001),
  );
}

int _detailDataRowCount(List<List<dynamic>> rows, {required String header}) {
  final headerIndex = rows.indexWhere(
    (row) =>
        row.any((cell) => cell?.toString().trim() == header) &&
        row.any((cell) => cell?.toString().trim() == 'Financial Year'),
  );
  expect(headerIndex, isNonNegative, reason: 'Expected header $header');

  var count = 0;
  for (var i = headerIndex + 1; i < rows.length; i++) {
    final firstCell = rows[i].isEmpty ? null : rows[i].first;
    final text = firstCell?.toString().trim() ?? '';
    if (text.isEmpty) continue;
    if (text == 'TOTAL') break;
    count++;
  }
  return count;
}

ReconciliationRow _row({
  required String section,
  String sellerName = 'Interest Vendor',
  String financialYear = '2025-26',
  String month = 'Apr-2025',
  String status = ReconciliationStatus.onlyIn26Q,
  double basicAmount = 25000,
  double? applicableAmount,
  double? tds26QAmount,
  double? expectedTds,
  double? actualTds,
  double? tdsDifference,
  double tdsRateUsed = 0.10,
  bool purchasePresent = true,
  bool tdsPresent = true,
  List<String> sourceLedgerFileIds = const [],
  List<String> sourceLedgerFileNames = const [],
  List<String> sourceLedgerUploadedAtIso = const [],
}) {
  final resolvedApplicableAmount = applicableAmount ?? basicAmount;
  final resolvedTds26QAmount = tds26QAmount ?? basicAmount;
  final resolvedExpectedTds = expectedTds ?? resolvedApplicableAmount * 0.10;
  final resolvedActualTds =
      actualTds ?? (status == ReconciliationStatus.matched ? 2500 : 0);
  final resolvedTdsDifference =
      tdsDifference ?? (status == ReconciliationStatus.matched ? 0 : 2500);

  return ReconciliationRow(
    buyerName: 'Radha Industries',
    buyerPan: 'ABCDE1234F',
    financialYear: financialYear,
    month: month,
    sellerName: sellerName,
    sellerPan: 'AAAAA1111A',
    section: section,
    sourceLedgerFileIds: sourceLedgerFileIds,
    sourceLedgerFileNames: sourceLedgerFileNames,
    sourceLedgerUploadedAtIso: sourceLedgerUploadedAtIso,
    resolvedSellerId: 'PAN:AAAAA1111A',
    resolvedSellerName: sellerName,
    resolvedPan: 'AAAAA1111A',
    basicAmount: basicAmount,
    applicableAmount: resolvedApplicableAmount,
    tds26QAmount: resolvedTds26QAmount,
    expectedTds: resolvedExpectedTds,
    actualTds: resolvedActualTds,
    tdsRateUsed: tdsRateUsed,
    amountDifference: 0,
    tdsDifference: resolvedTdsDifference,
    status: status,
    remarks: '',
    purchasePresent: purchasePresent,
    tdsPresent: tdsPresent,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
