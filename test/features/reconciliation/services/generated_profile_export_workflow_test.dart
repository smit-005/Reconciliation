import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_preflight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await DBHelper.debugResetForTest();
  });

  test(
    'export_test generated dataset completes non-manual reconciliation and export validation',
    () async {
      await DBHelper.debugResetForTest(
        databaseName: 'generated_profile_export_workflow_test.db',
      );

      const sections = <String>[
        '194Q',
        '194C',
        '194H',
        '194A',
        '194I_A',
        '194I_B',
        '194J_A',
        '194J_B',
      ];
      const buyerName = 'Generated Export Test Buyer';
      const buyerPan = 'AAAAA0000A';
      const financialYear = '2025-26';

      final tempRoot = await Directory.systemTemp.createTemp(
        'ledgermatch_export_profile_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final datasetOutputRoot = Directory(p.join(tempRoot.path, 'datasets'));
      final exportOutputDir = Directory(p.join(tempRoot.path, 'exports'));
      await exportOutputDir.create(recursive: true);

      final metrics = <String, int>{};
      final generationWatch = Stopwatch()..start();
      final generation = await Process.run('python', [
        'tools/generate_ledger_match_test_datasets.py',
        '--profile',
        'export_test',
        '--rows-per-section',
        '1000',
        '--sections',
        sections.join(','),
        '--output',
        datasetOutputRoot.path,
      ], workingDirectory: Directory.current.path);
      generationWatch.stop();
      metrics['dataset_generation_ms'] = generationWatch.elapsedMilliseconds;

      expect(
        generation.exitCode,
        0,
        reason:
            'Dataset generator failed.\nstdout:\n${generation.stdout}\nstderr:\n${generation.stderr}',
      );

      final datasetDir = Directory(
        p.join(
          datasetOutputRoot.path,
          'export_test_custom_1000_per_section_all_sections',
        ),
      );
      expect(
        await datasetDir.exists(),
        isTrue,
        reason: 'Expected generated dataset at ${datasetDir.path}',
      );

      final importWatch = Stopwatch()..start();
      final imported = _importGeneratedDataset(datasetDir, sections);
      importWatch.stop();
      metrics['import_parse_ms'] = importWatch.elapsedMilliseconds;

      expect(imported.tdsRows, hasLength(8000));
      for (final section in sections) {
        expect(
          imported.tdsRows.where((row) => row.section == section),
          hasLength(1000),
          reason: 'Generated 26Q rows should contain 1000 rows for $section.',
        );
        expect(
          imported.sourceRowsBySection[section],
          isNotEmpty,
          reason: 'Expected generated source rows for $section.',
        );
      }

      final preflightWatch = Stopwatch()..start();
      final preflight = await SellerMappingPreflightService.analyze(
        buyerName: buyerName,
        buyerPan: buyerPan,
        tdsRows: imported.tdsRows,
        sourceRowsBySection: imported.sourceRowsBySection,
      );
      preflightWatch.stop();
      metrics['seller_preflight_ms'] = preflightWatch.elapsedMilliseconds;

      expect(
        preflight.pendingReviewCount,
        0,
        reason:
            'export_test profile should not create dangerous seller-mapping blockers.',
      );

      final reconciliationWatch = Stopwatch()..start();
      final result = await CalculationService.reconcileSectionWise(
        buyerName: buyerName,
        buyerPan: buyerPan,
        sourceRows: imported.sourceRows,
        tdsRows: imported.tdsRows,
        sections: sections,
      );
      reconciliationWatch.stop();
      metrics['reconciliation_ms'] = reconciliationWatch.elapsedMilliseconds;

      expect(result.rows, isNotEmpty);
      for (final section in sections) {
        expect(
          result.rowsBySection[section],
          isNotEmpty,
          reason: 'Expected reconciled rows for $section.',
        );
      }
      expect(
        result.rows.where(
          (row) => row.status == ReconciliationStatus.onlyIn26Q,
        ),
        isNotEmpty,
        reason: 'export_test should produce Missing in Books / 26Q-only rows.',
      );
      final timingStatusCount = result.rows
          .where((row) => row.status == ReconciliationStatus.timingDifference)
          .length;
      metrics['timing_status_rows'] = timingStatusCount;

      final exportPaths = <String, String>{};
      exportPaths['working'] = await _timedExport(
        metrics,
        'working_export_with_save_ms',
        () => ExcelExportService.exportCurrentViewExcel(
          rows: result.rows,
          buyerName: buyerName,
          buyerPan: buyerPan,
          outputFolderPath: exportOutputDir.path,
          financialYear: financialYear,
        ),
      );
      exportPaths['section_194C'] = await _timedExport(
        metrics,
        'section_export_with_save_ms',
        () => ExcelExportService.exportSectionExcel(
          rows: result.rowsBySection['194C'] ?? const <ReconciliationRow>[],
          section: '194C',
          buyerName: buyerName,
          buyerPan: buyerPan,
          outputFolderPath: exportOutputDir.path,
          financialYear: financialYear,
        ),
      );
      exportPaths['final'] = await _timedExport(
        metrics,
        'final_export_with_save_ms',
        () => ExcelExportService.exportPivotReportExcel(
          rows: result.rows,
          buyerName: buyerName,
          buyerPan: buyerPan,
          outputFolderPath: exportOutputDir.path,
          financialYear: financialYear,
        ),
      );
      exportPaths['detailed'] = await _timedExport(
        metrics,
        'detailed_export_with_save_ms',
        () => ExcelExportService.exportDetailedReportExcel(
          rows: result.rows,
          buyerName: buyerName,
          buyerPan: buyerPan,
          outputFolderPath: exportOutputDir.path,
          financialYear: financialYear,
        ),
      );

      final validationWatch = Stopwatch()..start();
      _validateWorkingViewWorkbook(exportPaths['working']!);
      _validateSectionWorkbook(exportPaths['section_194C']!);
      _validateFinalWorkbook(exportPaths['final']!, sections);
      _validateDetailedWorkbook(exportPaths['detailed']!, sections);
      validationWatch.stop();
      metrics['workbook_open_validate_ms'] =
          validationWatch.elapsedMilliseconds;

      // Keep a concise machine-readable breadcrumb in the test log for CI.
      // Export timings include Syncfusion workbook generation and file save.
      // The validation timing covers opening and inspecting saved workbooks.
      // ignore: avoid_print
      print('LEDGERMATCH_EXPORT_WORKFLOW_METRICS $metrics');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<String> _timedExport(
  Map<String, int> metrics,
  String key,
  Future<String> Function() action,
) async {
  final watch = Stopwatch()..start();
  final path = await action();
  watch.stop();
  metrics[key] = watch.elapsedMilliseconds;
  expect(File(path).existsSync(), isTrue, reason: 'Missing export file $path');
  return path;
}

_ImportedDataset _importGeneratedDataset(
  Directory datasetDir,
  List<String> sections,
) {
  final tdsRows = _readWorkbookRows(File(p.join(datasetDir.path, '26Q.xlsx')))
      .map((row) {
        final month = normalizeMonth(_text(row, 'Date / Month'));
        return Tds26QRow(
          month: month,
          financialYear: financialYearFromMonthKey(month),
          deducteeName: _text(row, 'Party Name'),
          panNumber: _text(row, 'PAN Number'),
          deductedAmount: _number(row, 'Amount Paid'),
          tds: _number(row, 'TDS Amount'),
          section: _text(row, 'Section'),
        );
      })
      .toList();

  final sourceRows = <NormalizedTransactionRow>[];
  final sourceRowsBySection = <String, List<NormalizedTransactionRow>>{};
  for (final section in sections) {
    final sectionDir = Directory(p.join(datasetDir.path, 'ledgers', section));
    final files =
        sectionDir
            .listSync()
            .whereType<File>()
            .where((file) => p.extension(file.path).toLowerCase() == '.xlsx')
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final rows = _readWorkbookRows(file);
      for (final row in rows) {
        final rawDate = section == '194Q'
            ? _text(row, 'Bill Date')
            : _text(row, 'Date');
        final month = normalizeMonth(rawDate);
        final amount = section == '194Q'
            ? _number(row, 'Basic Amount')
            : _number(row, 'Amount');
        final sourceRow = NormalizedTransactionRow(
          sourceType: section == '194Q' ? 'purchase' : 'generic_ledger',
          sourceLedgerFileId: p.basenameWithoutExtension(file.path),
          sourceLedgerFileName: p.basename(file.path),
          transactionDateRaw: rawDate,
          month: month,
          financialYear: financialYearFromMonthKey(month),
          partyName: _text(row, 'Party Name'),
          panNumber: _text(row, 'PAN Number'),
          gstNo: _text(row, 'GST No'),
          documentNo: _text(row, 'Bill No'),
          description: _text(row, 'Description'),
          amount: amount,
          taxableAmount: amount,
          tdsAmount: _number(row, 'TDS Amount'),
          section: _text(row, 'Section'),
        );
        sourceRows.add(sourceRow);
        sourceRowsBySection
            .putIfAbsent(section, () => <NormalizedTransactionRow>[])
            .add(sourceRow);
      }
    }
  }

  return _ImportedDataset(
    tdsRows: tdsRows,
    sourceRows: sourceRows,
    sourceRowsBySection: sourceRowsBySection,
  );
}

void _validateWorkingViewWorkbook(String path) {
  final workbook = _openWorkbook(path);
  _expectSheets(workbook, [
    'Summary',
    'Pivot',
    'Missing_In_Books',
    'Raw_Data',
    'TDS_Section_Info',
  ]);
  _expectSheetHasRows(workbook, 'Pivot');
  _expectSheetHasRows(workbook, 'Missing_In_Books');
  _expectSheetMissing(workbook, 'Timing_Difference');
  _expectSheetHasRows(workbook, 'Raw_Data');
}

void _validateSectionWorkbook(String path) {
  final workbook = _openWorkbook(path);
  _expectSheets(workbook, [
    'Section_Summary',
    'Section_Pivot',
    'Ledger_Pivot',
    'Missing_In_Books',
    'Exceptions',
    'Raw_Data',
    'TDS_Section_Info',
  ]);
  _expectSheetHasRows(workbook, 'Section_Pivot');
  _expectSheetHasRows(workbook, 'Ledger_Pivot');
  _expectSheetHasRows(workbook, 'Missing_In_Books');
  _expectSheetMissing(workbook, 'Timing_Difference');
  _expectSheetHasRows(workbook, 'Raw_Data');
}

void _validateFinalWorkbook(String path, List<String> sections) {
  final workbook = _openWorkbook(path);
  _expectSheets(workbook, [
    'Master_Summary',
    'Section_Summary',
    for (final section in sections) '$section Pivot',
    'Ledger_Pivot',
    'Final_Missing_In_Books',
    'Exception_Summary',
    'TDS_Section_Info',
  ]);
  _expectSheetHasRows(workbook, 'Section_Summary');
  _expectSheetHasRows(workbook, 'Ledger_Pivot');
  _expectSheetHasRows(workbook, 'Final_Missing_In_Books');
  _expectSheetMissing(workbook, 'Final_Timing_Difference');
  for (final section in sections) {
    _expectSheetHasRows(workbook, '$section Pivot');
  }
}

void _validateDetailedWorkbook(String path, List<String> sections) {
  final workbook = _openWorkbook(path);
  _expectSheets(workbook, [
    'Master_Summary',
    'Section_Summary',
    for (final section in sections) '$section Pivot',
    'Ledger_Pivot',
    'Final_Missing_In_Books',
    'Exception_Summary',
    'Raw_Reconciliation',
    'TDS_Section_Info',
  ]);
  _expectSheetHasRows(workbook, 'Section_Summary');
  _expectSheetHasRows(workbook, 'Ledger_Pivot');
  _expectSheetHasRows(workbook, 'Final_Missing_In_Books');
  _expectSheetHasRows(workbook, 'Exception_Summary');
  _expectSheetHasRows(workbook, 'Raw_Reconciliation');
  for (final section in sections) {
    _expectSheetHasRows(workbook, '$section Pivot');
  }
  _expectSheetMissing(workbook, 'Exception_Details');
  _expectSheetMissing(workbook, 'Technical_Details');
  _expectSheetMissing(workbook, 'Final_Timing_Difference');
}

SpreadsheetDecoder _openWorkbook(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Workbook does not exist: $path');
  return SpreadsheetDecoder.decodeBytes(file.readAsBytesSync());
}

void _expectSheets(SpreadsheetDecoder workbook, List<String> expectedSheets) {
  expect(workbook.tables.keys, containsAll(expectedSheets));
}

void _expectSheetHasRows(SpreadsheetDecoder workbook, String sheetName) {
  final table = workbook.tables[sheetName];
  expect(table, isNotNull, reason: 'Missing sheet $sheetName');
  expect(
    table!.rows.length,
    greaterThan(1),
    reason: 'Expected non-empty content in $sheetName.',
  );
}

void _expectSheetMissing(SpreadsheetDecoder workbook, String sheetName) {
  expect(
    workbook.tables[sheetName],
    isNull,
    reason: 'Unexpected hidden workflow sheet $sheetName',
  );
}

List<Map<String, dynamic>> _readWorkbookRows(File file) {
  final excel = Excel.decodeBytes(file.readAsBytesSync());
  final sheet = excel.tables.values.first;
  if (sheet.rows.isEmpty) {
    return const <Map<String, dynamic>>[];
  }
  final headers = sheet.rows.first
      .map((cell) => _cellText(cell?.value))
      .toList(growable: false);
  return sheet.rows.skip(1).map((row) {
    return {
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < row.length ? _cellDynamic(row[i]?.value) : '',
    };
  }).toList();
}

dynamic _cellDynamic(dynamic value) {
  if (value == null) return '';
  if (value is num) return value;
  final text = _cellText(value);
  return num.tryParse(text) ?? text;
}

String _cellText(dynamic value) {
  if (value == null) return '';
  final text = value.toString();
  final match = RegExp(r'^[A-Za-z]+CellValue\("?(.*?)"?\)$').firstMatch(text);
  return match?.group(1) ?? text;
}

String _text(Map<String, dynamic> row, String key) =>
    '${row[key] ?? ''}'.trim();

double _number(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.replaceAll(',', '')) ?? 0.0;
}

class _ImportedDataset {
  final List<Tds26QRow> tdsRows;
  final List<NormalizedTransactionRow> sourceRows;
  final Map<String, List<NormalizedTransactionRow>> sourceRowsBySection;

  const _ImportedDataset({
    required this.tdsRows,
    required this.sourceRows,
    required this.sourceRowsBySection,
  });
}
