import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_preflight_service.dart';

const _sections = <String>[
  '194Q',
  '194C',
  '194H',
  '194A',
  '194I_A',
  '194I_B',
  '194J_A',
  '194J_B',
];

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
    'local stress_auto performance runner',
    () async {
      if (Platform.environment['LEDGERMATCH_PERF_RUN'] != '1') {
        // ignore: avoid_print
        print(
          'LEDGERMATCH_PERF_SKIPPED set LEDGERMATCH_PERF_RUN=1 to run locally.',
        );
        return;
      }

      await DBHelper.debugResetForTest(
        databaseName: 'local_performance_runner_test.db',
      );

      final rowsPerSection =
          int.tryParse(
            Platform.environment['LEDGERMATCH_PERF_ROWS_PER_SECTION'] ?? '',
          ) ??
          1000;
      final metrics = <String, Object>{
        'profile': 'stress_auto',
        'rows_per_section': rowsPerSection,
        'sections': _sections.length,
      };

      final tempRoot = await Directory.systemTemp.createTemp(
        'ledgermatch_local_perf_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final datasetOutputRoot = Directory(p.join(tempRoot.path, 'datasets'));
      final exportOutputDir = Directory(p.join(tempRoot.path, 'exports'));
      await exportOutputDir.create(recursive: true);

      await _time(metrics, 'dataset_generation_ms', () async {
        final generation = await Process.run('python', [
          'tools/generate_ledger_match_test_datasets.py',
          '--profile',
          'stress_auto',
          '--rows-per-section',
          rowsPerSection.toString(),
          '--sections',
          _sections.join(','),
          '--output',
          datasetOutputRoot.path,
        ], workingDirectory: Directory.current.path);

        expect(
          generation.exitCode,
          0,
          reason:
              'Dataset generator failed.\nstdout:\n${generation.stdout}\nstderr:\n${generation.stderr}',
        );
      });

      final datasetDir = Directory(
        p.join(
          datasetOutputRoot.path,
          'stress_auto_custom_${rowsPerSection}_per_section_all_sections',
        ),
      );
      expect(await datasetDir.exists(), isTrue);

      late _ImportedDataset imported;
      await _time(metrics, 'import_parse_ms', () async {
        imported = _importGeneratedDataset(datasetDir, _sections);
      });
      metrics['tds_rows'] = imported.tdsRows.length;
      metrics['source_rows'] = imported.sourceRows.length;

      await _time(metrics, 'seller_preflight_ms', () async {
        final preflight = await SellerMappingPreflightService.analyze(
          buyerName: 'Local Performance Buyer',
          buyerPan: 'AAAAA0000A',
          tdsRows: imported.tdsRows,
          sourceRowsBySection: imported.sourceRowsBySection,
        );
        metrics['pending_seller_review'] = preflight.pendingReviewCount;
      });

      late SectionReconciliationResult result;
      await _time(metrics, 'reconciliation_ms', () async {
        result = await CalculationService.reconcileSectionWise(
          buyerName: 'Local Performance Buyer',
          buyerPan: 'AAAAA0000A',
          sourceRows: imported.sourceRows,
          tdsRows: imported.tdsRows,
          sections: _sections,
        );
      });
      metrics['reconciled_rows'] = result.rows.length;

      await _time(metrics, 'pivot_export_ms', () async {
        final exportPath = await ExcelExportService.exportPivotReportExcel(
          rows: result.rows,
          buyerName: 'Local Performance Buyer',
          buyerPan: 'AAAAA0000A',
          outputFolderPath: exportOutputDir.path,
          financialYear: '2025-26',
        );
        final exportFile = File(exportPath);
        expect(exportFile.existsSync(), isTrue);
        metrics['pivot_export_bytes'] = exportFile.lengthSync();
      });

      // One line for easy copy/paste into notes or spreadsheets.
      // ignore: avoid_print
      print('LEDGERMATCH_LOCAL_PERF_METRICS $metrics');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _time(
  Map<String, Object> metrics,
  String key,
  Future<void> Function() action,
) async {
  final watch = Stopwatch()..start();
  await action();
  watch.stop();
  metrics[key] = watch.elapsedMilliseconds;
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
