import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'reconciliation_orchestrator.dart';
import 'section_rule_export_text.dart';

enum ExcelExportMode { currentView, section, pivotReport, detailedReport }

class ExcelExportService {
  static void _logPerformance(
    String step,
    Stopwatch watch, {
    String details = '',
  }) {
    final suffix = details.trim().isEmpty ? '' : ' | $details';
    debugPrint(
      'EXPORT PERF => step=$step ms=${watch.elapsedMilliseconds}$suffix',
    );
  }

  static Future<String> exportCurrentViewExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
  }) async {
    return _exportWorkbook(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
      mode: ExcelExportMode.currentView,
    );
  }

  static Future<String> exportSectionExcel({
    required List<ReconciliationRow> rows,
    required String section,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
  }) async {
    return _exportWorkbook(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
      section: section,
      mode: ExcelExportMode.section,
    );
  }

  static Future<String> exportPivotReportExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
  }) async {
    return _exportWorkbook(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
      mode: ExcelExportMode.pivotReport,
    );
  }

  static Future<String> exportDetailedReportExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
  }) async {
    return _exportWorkbook(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
      mode: ExcelExportMode.detailedReport,
    );
  }

  static Future<String> exportReconciliationExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
    String? sellerName,
  }) {
    return exportDetailedReportExcel(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
    );
  }

  static Future<String> exportPivotSummaryExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
    String? sellerName,
  }) {
    return exportPivotReportExcel(
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      outputFolderPath: outputFolderPath,
      financialYear: financialYear,
    );
  }

  static Future<String> _exportWorkbook({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
    required ExcelExportMode mode,
    String? outputFolderPath,
    String? financialYear,
    String? section,
  }) async {
    debugPrint('EXPORT PERF => step=rows_count rows=${rows.length}');
    final workbookWatch = Stopwatch()..start();
    final workbook = xlsio.Workbook();
    workbookWatch.stop();
    _logPerformance('workbook_creation', workbookWatch);

    try {
      switch (mode) {
        case ExcelExportMode.currentView:
          _buildCurrentViewWorkbook(
            workbook,
            rows: rows,
            buyerName: buyerName,
            buyerPan: buyerPan,
            gstNo: gstNo,
          );
        case ExcelExportMode.section:
          _buildSectionWorkbook(
            workbook,
            rows: rows,
            section: section ?? _sectionLabelFromRows(rows),
            buyerName: buyerName,
            buyerPan: buyerPan,
            gstNo: gstNo,
          );
        case ExcelExportMode.pivotReport:
          _buildPivotReportWorkbook(
            workbook,
            rows: rows,
            buyerName: buyerName,
            buyerPan: buyerPan,
            gstNo: gstNo,
          );
        case ExcelExportMode.detailedReport:
          _buildDetailedReportWorkbook(
            workbook,
            rows: rows,
            buyerName: buyerName,
            buyerPan: buyerPan,
            gstNo: gstNo,
          );
      }

      final fileName = buildExportFileName(
        mode: mode,
        buyerName: buyerName,
        financialYear: financialYear,
        section: section ?? _sectionLabelFromRows(rows),
      );

      return _saveWorkbook(
        workbook,
        fileName: fileName,
        outputFolderPath: outputFolderPath,
      );
    } finally {
      workbook.dispose();
    }
  }

  static void _buildCurrentViewWorkbook(
    xlsio.Workbook workbook, {
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    final summarySheet = workbook.worksheets[0];
    summarySheet.name = 'Summary';
    _writeCompactSummarySheet(
      summarySheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      title: 'Working View Summary',
    );

    final pivotSheet = workbook.worksheets.addWithName('Pivot');
    _writeTimedPivotSummarySheet(
      pivotSheet,
      rows: rows,
      title: 'WORKING VIEW PIVOT',
    );

    _writeFilteredDetailSheet(
      workbook.worksheets.addWithName('Missing_In_Books'),
      rows: rows,
      title: 'MISSING IN BOOKS',
      predicate: _isMissingInBooksRow,
    );

    final detailSheet = workbook.worksheets.addWithName('Raw_Data');
    _writeTitle(detailSheet, 'WORKING VIEW RAW DATA');
    _writeSummarySection(
      detailSheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );
    _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTdsSectionInfoSheet(infoSheet);
  }

  static void _buildSectionWorkbook(
    xlsio.Workbook workbook, {
    required List<ReconciliationRow> rows,
    required String section,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    final grouped = _groupBySection(rows);
    final sectionSummarySheet = workbook.worksheets[0];
    sectionSummarySheet.name = 'Section_Summary';
    _writeSectionSummarySheet(
      sectionSummarySheet,
      grouped: grouped,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );

    final pivotSheet = workbook.worksheets.addWithName('Section_Pivot');
    _writeTimedPivotSummarySheet(
      pivotSheet,
      rows: rows,
      title: 'SECTION $section SELLER PIVOT',
    );

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeLedgerPivotSheet(
      ledgerPivotSheet,
      rows: rows,
      title: 'SECTION $section LEDGER PIVOT',
    );

    _writeFilteredDetailSheet(
      workbook.worksheets.addWithName('Missing_In_Books'),
      rows: rows,
      title: 'MISSING IN BOOKS',
      predicate: _isMissingInBooksRow,
    );

    final exceptionsSheet = workbook.worksheets.addWithName('Exceptions');
    _writeExceptionsSheet(exceptionsSheet, rows: rows, remainingOnly: true);

    final detailSheet = workbook.worksheets.addWithName('Raw_Data');
    _writeTitle(detailSheet, 'SECTION $section DETAIL');
    _writeSummarySection(
      detailSheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );
    _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTdsSectionInfoSheet(infoSheet);
  }

  static void _buildPivotReportWorkbook(
    xlsio.Workbook workbook, {
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    final grouped = _groupBySection(rows);
    final workbookSummarySheet = workbook.worksheets[0];
    workbookSummarySheet.name = 'Master_Summary';
    _writeCompactSummarySheet(
      workbookSummarySheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      title: 'Master Summary',
    );

    final sectionSummarySheet = workbook.worksheets.addWithName(
      'Section_Summary',
    );
    _writeSectionSummarySheet(
      sectionSummarySheet,
      grouped: grouped,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );

    _writeSectionPivotSheets(workbook, grouped: grouped);

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeLedgerPivotSheet(
      ledgerPivotSheet,
      rows: rows,
      title: 'FINAL LEDGER PIVOT',
    );

    _writeFilteredDetailSheet(
      workbook.worksheets.addWithName('Final_Missing_In_Books'),
      rows: rows,
      title: 'FINAL MISSING IN BOOKS',
      predicate: _isMissingInBooksRow,
    );

    final exceptionSummarySheet = workbook.worksheets.addWithName(
      'Exception_Summary',
    );
    _writeExceptionSummarySheet(exceptionSummarySheet, rows: rows);

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTdsSectionInfoSheet(infoSheet);
  }

  static void _buildDetailedReportWorkbook(
    xlsio.Workbook workbook, {
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    final grouped = _groupBySection(rows);
    final workbookSummarySheet = workbook.worksheets[0];
    workbookSummarySheet.name = 'Master_Summary';
    _writeCompactSummarySheet(
      workbookSummarySheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
      title: 'Master Summary',
    );

    final sectionSummarySheet = workbook.worksheets.addWithName(
      'Section_Summary',
    );
    _writeSectionSummarySheet(
      sectionSummarySheet,
      grouped: grouped,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );

    _writeSectionPivotSheets(workbook, grouped: grouped);

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeLedgerPivotSheet(
      ledgerPivotSheet,
      rows: rows,
      title: 'FINAL LEDGER PIVOT',
    );

    _writeFilteredDetailSheet(
      workbook.worksheets.addWithName('Final_Missing_In_Books'),
      rows: rows,
      title: 'FINAL MISSING IN BOOKS',
      predicate: _isMissingInBooksRow,
    );

    final exceptionSummarySheet = workbook.worksheets.addWithName(
      'Exception_Summary',
    );
    _writeExceptionSummarySheet(exceptionSummarySheet, rows: rows);

    final detailSheet = workbook.worksheets.addWithName('Raw_Reconciliation');
    _writeTitle(detailSheet, 'RAW RECONCILIATION');
    _writeSummarySection(
      detailSheet,
      rows: rows,
      buyerName: buyerName,
      buyerPan: buyerPan,
      gstNo: gstNo,
    );
    _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);

    final exceptionDetailsSheet = workbook.worksheets.addWithName(
      'Exception_Details',
    );
    _writeExceptionsSheet(
      exceptionDetailsSheet,
      rows: rows,
      remainingOnly: false,
    );

    final technicalDetailsSheet = workbook.worksheets.addWithName(
      'Technical_Details',
    );
    _writeTechnicalDetailsSheet(technicalDetailsSheet, rows: rows);

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTdsSectionInfoSheet(infoSheet);
  }

  static Set<String> _writeSectionPivotSheets(
    xlsio.Workbook workbook, {
    required Map<String, List<ReconciliationRow>> grouped,
  }) {
    final sheetNames = <String>{};
    final sortedSections = grouped.keys.toList()
      ..sort(TdsSectionCatalog.compare);

    for (final section in sortedSections) {
      final cleanSection = section.trim().toUpperCase();
      if (cleanSection == 'NO SECTION') continue;

      final sectionRows = grouped[section]!;
      final sheetName = _safeSheetName('$cleanSection Pivot');
      sheetNames.add(sheetName);
      final sheet = workbook.worksheets.addWithName(sheetName);
      _writeTimedPivotSummarySheet(
        sheet,
        rows: sectionRows,
        title: '$cleanSection PIVOT',
      );
    }

    return sheetNames;
  }

  static List<_LedgerSourceReference> _ledgerSourcesForRow(
    ReconciliationRow row,
  ) {
    final names = row.sourceLedgerFileNames
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final ids = row.sourceLedgerFileIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (names.isEmpty && ids.isEmpty) return const <_LedgerSourceReference>[];

    final sources = <_LedgerSourceReference>[];
    if (names.isNotEmpty) {
      for (var i = 0; i < names.length; i++) {
        final id = i < ids.length ? ids[i] : '';
        final name = names[i];
        sources.add(
          _LedgerSourceReference(
            sourceKey: id.isNotEmpty ? id : name,
            displayName: name,
          ),
        );
      }
    } else {
      for (final id in ids) {
        sources.add(_LedgerSourceReference(sourceKey: id, displayName: id));
      }
    }

    final unique = <String, _LedgerSourceReference>{};
    for (final source in sources) {
      unique[source.sourceKey] = source;
    }
    return unique.values.toList();
  }

  static void _writeLedgerPivotSheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required String title,
  }) {
    _writeTitle(sheet, title);

    final headers = [
      'Ledger',
      'Section',
      'Seller Name',
      'Financial Year',
      'Rows',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
      'Statuses',
    ];

    const headerRow = 3;
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(headerRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    final groups = <String, _LedgerPivotGroup>{};
    for (final row in rows) {
      final sources = _ledgerSourcesForRow(row);
      final rowSources = sources.isEmpty
          ? const [
              _LedgerSourceReference(
                sourceKey: 'NO_LEDGER_SOURCE',
                displayName: 'No Ledger Source',
              ),
            ]
          : sources;

      for (final source in rowSources) {
        final seller = _sellerLabel(row);
        final key = [
          source.sourceKey,
          row.section.trim(),
          seller,
          row.financialYear.trim(),
        ].join('\u0001');
        groups
            .putIfAbsent(
              key,
              () => _LedgerPivotGroup(
                ledgerName: source.displayName,
                section: row.section.trim().isEmpty
                    ? 'No Section'
                    : row.section.trim(),
                sellerName: seller,
                financialYear: row.financialYear.trim(),
              ),
            )
            .rows
            .add(row);
      }
    }

    final sortedGroups = groups.values.toList()
      ..sort((a, b) {
        final ledgerCompare = a.ledgerName.toUpperCase().compareTo(
          b.ledgerName.toUpperCase(),
        );
        if (ledgerCompare != 0) return ledgerCompare;

        final sectionCompare = TdsSectionCatalog.compare(a.section, b.section);
        if (sectionCompare != 0) return sectionCompare;

        final sellerCompare = a.sellerName.toUpperCase().compareTo(
          b.sellerName.toUpperCase(),
        );
        if (sellerCompare != 0) return sellerCompare;

        return a.financialYear.compareTo(b.financialYear);
      });

    var rowIndex = headerRow + 1;
    for (final group in sortedGroups) {
      final groupRows = group.rows;
      sheet.getRangeByIndex(rowIndex, 1).setText(group.ledgerName);
      sheet.getRangeByIndex(rowIndex, 2).setText(group.section);
      sheet.getRangeByIndex(rowIndex, 3).setText(group.sellerName);
      sheet.getRangeByIndex(rowIndex, 4).setText(group.financialYear);
      sheet.getRangeByIndex(rowIndex, 5).setNumber(groupRows.length.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(
            _round2(groupRows.fold(0.0, (sum, row) => sum + row.basicAmount)),
          );
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setNumber(
            _round2(
              groupRows.fold(0.0, (sum, row) => sum + row.applicableAmount),
            ),
          );
      sheet
          .getRangeByIndex(rowIndex, 8)
          .setNumber(
            _round2(groupRows.fold(0.0, (sum, row) => sum + row.tds26QAmount)),
          );
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(
            _round2(groupRows.fold(0.0, (sum, row) => sum + row.expectedTds)),
          );
      sheet
          .getRangeByIndex(rowIndex, 10)
          .setNumber(
            _round2(groupRows.fold(0.0, (sum, row) => sum + row.actualTds)),
          );
      sheet
          .getRangeByIndex(rowIndex, 11)
          .setNumber(
            _round2(groupRows.fold(0.0, (sum, row) => sum + row.tdsDifference)),
          );
      sheet
          .getRangeByIndex(rowIndex, 12)
          .setNumber(
            _round2(
              groupRows.fold(0.0, (sum, row) => sum + row.amountDifference),
            ),
          );
      sheet
          .getRangeByIndex(rowIndex, 13)
          .setText(
            groupRows
                .map((row) => row.status.trim())
                .where((status) => status.isNotEmpty)
                .toSet()
                .join(' | '),
          );

      final range = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 13);
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      rowIndex++;
    }

    sheet.autoFilters.filterRange = sheet.getRangeByIndex(
      headerRow,
      1,
      headerRow,
      headers.length,
    );
    _applyNumberFormat(sheet, headerRow + 1, rowIndex - 1, [
      6,
      7,
      8,
      9,
      10,
      11,
      12,
    ]);
    _autoFitUsefulColumns(sheet, headers.length);
  }

  static void _writeFilteredDetailSheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required String title,
    required bool Function(ReconciliationRow row) predicate,
  }) {
    final filteredRows = rows.where(predicate).toList();
    _writeTitle(sheet, title);
    _writeTimedDetailTable(sheet, rows: filteredRows, startRow: 3);
  }

  static void _writeExceptionsSheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    bool remainingOnly = false,
  }) {
    final exceptionRows = rows.where((row) {
      if (!_isExceptionRow(row)) return false;
      if (!remainingOnly) return true;
      return !_isMissingInBooksRow(row) && !_isTimingDifferenceRow(row);
    }).toList();
    _writeTitle(sheet, 'EXCEPTIONS');
    _writeTimedDetailTable(sheet, rows: exceptionRows, startRow: 3);
  }

  static bool _isExceptionRow(ReconciliationRow row) {
    final status = row.status.trim();
    return status != ReconciliationStatus.matched &&
        status != ReconciliationStatus.belowThreshold &&
        status != ReconciliationStatus.noDeductionRequired;
  }

  static bool _isMissingInBooksRow(ReconciliationRow row) {
    return row.status.trim() == ReconciliationStatus.onlyIn26Q ||
        (!row.purchasePresent && row.tdsPresent);
  }

  static bool _isTimingDifferenceRow(ReconciliationRow row) {
    return row.status.trim() == ReconciliationStatus.timingDifference;
  }

  static String _sellerLabel(ReconciliationRow row) {
    final resolved = row.resolvedSellerName.trim();
    return resolved.isEmpty ? row.sellerName.trim() : resolved;
  }

  static void _writeTimedDetailTable(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required int startRow,
  }) {
    final detailWatch = Stopwatch()..start();
    _writeDetailTable(sheet, rows: rows, startRow: startRow);
    detailWatch.stop();
    _logPerformance(
      'detail_sheet_writing',
      detailWatch,
      details: 'sheet=${sheet.name} rows=${rows.length}',
    );
  }

  static void _writeTimedPivotSummarySheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    String? title,
    bool showLedgerSourceInSellerHeader = true,
  }) {
    final pivotWatch = Stopwatch()..start();
    _writePivotSummarySheet(
      sheet,
      rows: rows,
      title: title,
      showLedgerSourceInSellerHeader: showLedgerSourceInSellerHeader,
    );
    pivotWatch.stop();
    _logPerformance(
      'pivot_writing',
      pivotWatch,
      details: 'sheet=${sheet.name} rows=${rows.length}',
    );
  }

  static String _sectionLabelFromRows(List<ReconciliationRow> rows) {
    final sections =
        rows
            .map((row) => row.section.trim())
            .where((section) => section.isNotEmpty)
            .toSet()
            .toList()
          ..sort(TdsSectionCatalog.compare);
    if (sections.length == 1) return sections.single;
    return 'All Sections';
  }

  static Future<String> _saveWorkbook(
    xlsio.Workbook workbook, {
    required String fileName,
    String? outputFolderPath,
  }) async {
    final saveStreamWatch = Stopwatch()..start();
    final bytes = workbook.saveAsStream();
    saveStreamWatch.stop();
    _logPerformance(
      'saveAsStream',
      saveStreamWatch,
      details: 'bytes=${bytes.length}',
    );

    final folderPath = outputFolderPath ?? _getDownloadsPath();
    await Directory(folderPath).create(recursive: true);
    final fullPath = await _resolveAvailableFilePath(folderPath, fileName);

    final file = File(fullPath);
    final fileWriteWatch = Stopwatch()..start();
    await file.writeAsBytes(bytes, flush: true);
    fileWriteWatch.stop();
    _logPerformance(
      'file_write',
      fileWriteWatch,
      details: 'bytes=${bytes.length} path=$fullPath',
    );

    return fullPath;
  }

  static Map<String, List<ReconciliationRow>> _groupBySection(
    List<ReconciliationRow> rows,
  ) {
    final grouped = <String, List<ReconciliationRow>>{};

    for (final row in rows) {
      final section = row.section.trim().isEmpty ? 'No Section' : row.section;
      grouped.putIfAbsent(section, () => []);
      grouped[section]!.add(row);
    }

    return grouped;
  }

  static void _writeTitle(xlsio.Worksheet sheet, String title) {
    sheet.getRangeByName('A1:U1').merge();
    sheet.getRangeByName('A1').setText(title);
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';
  }

  static void _writeSummarySection(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    final totalBasic = _round2(
      rows.fold(0.0, (sum, row) => sum + row.basicAmount),
    );
    final totalApplicable = _round2(
      rows.fold(0.0, (sum, row) => sum + row.applicableAmount),
    );
    final total26QAmount = _round2(
      rows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
    );
    final totalExpectedTds = _round2(
      rows.fold(0.0, (sum, row) => sum + row.expectedTds),
    );
    final totalActualTds = _round2(
      rows.fold(0.0, (sum, row) => sum + row.actualTds),
    );
    final totalTdsDifference = _round2(
      rows.fold(0.0, (sum, row) => sum + row.tdsDifference),
    );
    final totalAmountDifference = _round2(
      rows.fold(0.0, (sum, row) => sum + row.amountDifference),
    );
    final ruleText = SectionRuleExportText.summaryTextForSections(
      rows.map((row) => row.section),
    );

    sheet.getRangeByName('A3').setText('Buyer Name');
    sheet.getRangeByName('B3').setText(buyerName.isEmpty ? '-' : buyerName);

    sheet.getRangeByName('D3').setText('Buyer PAN');
    sheet.getRangeByName('E3').setText(buyerPan.isEmpty ? '-' : buyerPan);

    sheet.getRangeByName('G3').setText('GST No');
    sheet.getRangeByName('H3').setText(gstNo.isEmpty ? '-' : gstNo);

    sheet.getRangeByName('A4').setText('Rule Text');
    sheet.getRangeByName('B4').setText(ruleText);

    sheet.getRangeByName('D4').setText('Total Basic Amount');
    sheet.getRangeByName('E4').setNumber(totalBasic);

    sheet.getRangeByName('G4').setText('Total Applicable Amount');
    sheet.getRangeByName('H4').setNumber(totalApplicable);

    sheet.getRangeByName('A5').setText('Total 26Q Amount');
    sheet.getRangeByName('B5').setNumber(total26QAmount);

    sheet.getRangeByName('D5').setText('Expected TDS');
    sheet.getRangeByName('E5').setNumber(totalExpectedTds);

    sheet.getRangeByName('G5').setText('Actual TDS');
    sheet.getRangeByName('H5').setNumber(totalActualTds);

    sheet.getRangeByName('A6').setText('TDS Difference');
    sheet.getRangeByName('B6').setNumber(totalTdsDifference);

    sheet.getRangeByName('D6').setText('Amount Difference');
    sheet.getRangeByName('E6').setNumber(totalAmountDifference);

    for (final cell in [
      'A3',
      'D3',
      'G3',
      'A4',
      'D4',
      'G4',
      'A5',
      'D5',
      'G5',
      'A6',
      'D6',
    ]) {
      sheet.getRangeByName(cell).cellStyle.bold = true;
      sheet.getRangeByName(cell).cellStyle.backColor = '#F3F4F6';
    }

    _applyNumberFormat(sheet, 4, 6, [2, 5, 8]);
  }

  static void _writeDetailTable(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required int startRow,
  }) {
    final headers = [
      'Buyer Name',
      'Buyer PAN',
      'Financial Year',
      'Month',
      'Section',
      'Seller Name',
      'Seller PAN',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Rate Used',
      'TDS Difference',
      'Amount Difference',
      'Status',
      'Risk Level',
      'Source Ledger File IDs',
      'Source Ledger Files',
      'Source Ledger Uploaded At',
      'Remarks',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    sheet.autoFilters.filterRange = sheet.getRangeByIndex(
      startRow,
      1,
      startRow,
      headers.length,
    );

    int rowIndex = startRow + 1;

    for (final row in rows) {
      sheet.getRangeByIndex(rowIndex, 1).setText(row.buyerName);
      sheet.getRangeByIndex(rowIndex, 2).setText(row.buyerPan);
      sheet.getRangeByIndex(rowIndex, 3).setText(row.financialYear);
      sheet.getRangeByIndex(rowIndex, 4).setText(row.month);
      sheet
          .getRangeByIndex(rowIndex, 5)
          .setText(row.section.trim().isEmpty ? 'No Section' : row.section);
      sheet.getRangeByIndex(rowIndex, 6).setText(row.sellerName);
      sheet.getRangeByIndex(rowIndex, 7).setText(row.sellerPan);
      sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(row.basicAmount));
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(row.applicableAmount));
      sheet.getRangeByIndex(rowIndex, 10).setNumber(_round2(row.tds26QAmount));
      sheet.getRangeByIndex(rowIndex, 11).setNumber(_round2(row.expectedTds));
      sheet.getRangeByIndex(rowIndex, 12).setNumber(_round2(row.actualTds));
      sheet.getRangeByIndex(rowIndex, 13).setNumber(row.tdsRateUsed);
      sheet.getRangeByIndex(rowIndex, 14).setNumber(_round2(row.tdsDifference));
      sheet
          .getRangeByIndex(rowIndex, 15)
          .setNumber(_round2(row.amountDifference));
      sheet.getRangeByIndex(rowIndex, 16).setText(row.status);
      sheet.getRangeByIndex(rowIndex, 17).setText(getRiskLevel(row.status));
      sheet
          .getRangeByIndex(rowIndex, 18)
          .setText(row.sourceLedgerFileIds.join(' | '));
      sheet
          .getRangeByIndex(rowIndex, 19)
          .setText(row.sourceLedgerFileNames.join(' | '));
      sheet
          .getRangeByIndex(rowIndex, 20)
          .setText(row.sourceLedgerUploadedAtIso.join(' | '));
      sheet
          .getRangeByIndex(rowIndex, 21)
          .setText(row.remarks.trim().isEmpty ? '-' : row.remarks);

      final rowRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 21);
      rowRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

      if (row.status == ReconciliationStatus.matched) {
        rowRange.cellStyle.backColor = '#E8F5E9';
      } else if (row.status == ReconciliationStatus.timingDifference) {
        rowRange.cellStyle.backColor = '#E3F2FD';
      } else if (row.status == ReconciliationStatus.shortDeduction) {
        rowRange.cellStyle.backColor = '#FFF3E0';
      } else if (row.status == ReconciliationStatus.excessDeduction) {
        rowRange.cellStyle.backColor = '#FFEBEE';
      } else if (row.status == ReconciliationStatus.purchaseOnly) {
        rowRange.cellStyle.backColor = '#EAF3FF';
      } else if (row.status == ReconciliationStatus.onlyIn26Q) {
        rowRange.cellStyle.backColor = '#F3E5F5';
      } else {
        rowRange.cellStyle.backColor = '#FFF0F0';
      }

      rowIndex++;
    }

    sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
    sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;

    sheet
        .getRangeByIndex(rowIndex, 8)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.basicAmount)),
        );
    sheet
        .getRangeByIndex(rowIndex, 9)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.applicableAmount)),
        );
    sheet
        .getRangeByIndex(rowIndex, 10)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.tds26QAmount)),
        );
    sheet
        .getRangeByIndex(rowIndex, 11)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.expectedTds)),
        );
    sheet
        .getRangeByIndex(rowIndex, 12)
        .setNumber(_round2(rows.fold(0.0, (sum, row) => sum + row.actualTds)));
    sheet.getRangeByIndex(rowIndex, 13).setText('');
    sheet
        .getRangeByIndex(rowIndex, 14)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.tdsDifference)),
        );
    sheet
        .getRangeByIndex(rowIndex, 15)
        .setNumber(
          _round2(rows.fold(0.0, (sum, row) => sum + row.amountDifference)),
        );

    final totalRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 21);
    totalRange.cellStyle.bold = true;
    totalRange.cellStyle.backColor = '#FFF3CD';
    totalRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    _applyNumberFormat(sheet, startRow + 1, rowIndex, [
      8,
      9,
      10,
      11,
      12,
      14,
      15,
    ]);
    if (rows.isNotEmpty) {
      sheet.getRangeByIndex(startRow + 1, 13, rowIndex - 1, 13).numberFormat =
          '0.00%';
    }
    _autoFitUsefulColumns(sheet, 21);
  }

  static void _writeCompactSummarySheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
    String title = 'Reconciliation Summary',
  }) {
    sheet.getRangeByName('A1:H1').merge();
    sheet.getRangeByName('A1').setText(title);
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    final totalBasic = _round2(
      rows.fold(0.0, (sum, row) => sum + row.basicAmount),
    );
    final totalApplicable = _round2(
      rows.fold(0.0, (sum, row) => sum + row.applicableAmount),
    );
    final total26QAmount = _round2(
      rows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
    );
    final totalExpectedTds = _round2(
      rows.fold(0.0, (sum, row) => sum + row.expectedTds),
    );
    final totalActualTds = _round2(
      rows.fold(0.0, (sum, row) => sum + row.actualTds),
    );
    final totalTdsDifference = _round2(
      rows.fold(0.0, (sum, row) => sum + row.tdsDifference),
    );
    final totalAmountDifference = _round2(
      rows.fold(0.0, (sum, row) => sum + row.amountDifference),
    );
    final ruleText = SectionRuleExportText.summaryTextForSections(
      rows.map((row) => row.section),
    );

    final labels = [
      'Buyer Name',
      'Buyer PAN',
      'GST No',
      'Rule Text',
      'Total Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
      '${ReconciliationStatus.matched} Rows',
      '${ReconciliationStatus.timingDifference} Rows',
      '${ReconciliationStatus.shortDeduction} Rows',
      '${ReconciliationStatus.excessDeduction} Rows',
      '${ReconciliationStatus.purchaseOnly} Rows',
      '${ReconciliationStatus.onlyIn26Q} Rows',
      ReconciliationStatus.applicableButNo26Q,
    ];

    final values = [
      buyerName.isEmpty ? '-' : buyerName,
      buyerPan.isEmpty ? '-' : buyerPan,
      gstNo.isEmpty ? '-' : gstNo,
      ruleText,
      totalBasic.toStringAsFixed(2),
      totalApplicable.toStringAsFixed(2),
      total26QAmount.toStringAsFixed(2),
      totalExpectedTds.toStringAsFixed(2),
      totalActualTds.toStringAsFixed(2),
      totalTdsDifference.toStringAsFixed(2),
      totalAmountDifference.toStringAsFixed(2),
      rows
          .where((e) => e.status == ReconciliationStatus.matched)
          .length
          .toString(),
      rows
          .where((e) => e.status == ReconciliationStatus.timingDifference)
          .length
          .toString(),
      rows
          .where((e) => e.status == ReconciliationStatus.shortDeduction)
          .length
          .toString(),
      rows
          .where((e) => e.status == ReconciliationStatus.excessDeduction)
          .length
          .toString(),
      rows
          .where((e) => e.status == ReconciliationStatus.purchaseOnly)
          .length
          .toString(),
      rows
          .where((e) => e.status == ReconciliationStatus.onlyIn26Q)
          .length
          .toString(),
      rows
          .where(
            (e) =>
                e.applicableAmount > 0 &&
                e.tds26QAmount == 0 &&
                e.actualTds == 0,
          )
          .length
          .toString(),
    ];

    for (int i = 0; i < labels.length; i++) {
      final row = i + 3;
      sheet.getRangeByIndex(row, 1).setText(labels[i]);
      sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(row, 1).cellStyle.backColor = '#F3F4F6';
      sheet.getRangeByIndex(row, 2).setText(values[i]);
    }

    _autoFitUsefulColumns(sheet, 8);
  }

  static void _writeSectionSummarySheet(
    xlsio.Worksheet sheet, {
    required Map<String, List<ReconciliationRow>> grouped,
    required String buyerName,
    required String buyerPan,
    required String gstNo,
  }) {
    sheet.getRangeByName('A1:K1').merge();
    sheet.getRangeByName('A1').setText('Section-wise Summary');
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    sheet.getRangeByName('A3').setText('Buyer Name');
    sheet.getRangeByName('B3').setText(buyerName.isEmpty ? '-' : buyerName);

    sheet.getRangeByName('D3').setText('Buyer PAN');
    sheet.getRangeByName('E3').setText(buyerPan.isEmpty ? '-' : buyerPan);

    sheet.getRangeByName('G3').setText('GST No');
    sheet.getRangeByName('H3').setText(gstNo.isEmpty ? '-' : gstNo);

    for (final cell in ['A3', 'D3', 'G3']) {
      sheet.getRangeByName(cell).cellStyle.bold = true;
      sheet.getRangeByName(cell).cellStyle.backColor = '#F3F4F6';
    }

    final headers = [
      'Section',
      'Rule Text',
      'Rows',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
      'Non-Matched Rows',
    ];

    const startRow = 5;

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    int rowIndex = startRow + 1;
    final keys = grouped.keys.toList()..sort();

    for (final section in keys) {
      final rows = grouped[section]!;

      sheet.getRangeByIndex(rowIndex, 1).setText(section);
      sheet
          .getRangeByIndex(rowIndex, 2)
          .setText(SectionRuleExportText.summaryTextForSections([section]));
      sheet.getRangeByIndex(rowIndex, 3).setNumber(rows.length.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 4)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.basicAmount)));
      sheet
          .getRangeByIndex(rowIndex, 5)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.applicableAmount)));
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.tds26QAmount)));
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.expectedTds)));
      sheet
          .getRangeByIndex(rowIndex, 8)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.actualTds)));
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.tdsDifference)));
      sheet
          .getRangeByIndex(rowIndex, 10)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.amountDifference)));
      sheet
          .getRangeByIndex(rowIndex, 11)
          .setNumber(
            rows
                .where((e) => e.status != ReconciliationStatus.matched)
                .length
                .toDouble(),
          );

      final rowRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11);
      rowRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

      rowIndex++;
    }

    _applyNumberFormat(sheet, startRow + 1, rowIndex - 1, [
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
    _autoFitUsefulColumns(sheet, 11);
  }

  static void _writeExceptionSummarySheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
  }) {
    final exceptionRows = rows
        .where(
          (row) =>
              _isExceptionRow(row) &&
              !_isMissingInBooksRow(row) &&
              !_isTimingDifferenceRow(row),
        )
        .toList();
    final grouped = <String, List<ReconciliationRow>>{};
    for (final row in exceptionRows) {
      final status = row.status.trim().isEmpty ? 'Unclassified' : row.status;
      grouped.putIfAbsent(status, () => <ReconciliationRow>[]).add(row);
    }

    sheet.getRangeByName('A1:I1').merge();
    sheet.getRangeByName('A1').setText('Exception Summary');
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    final headers = [
      'Status',
      'Rows',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
    ];
    const startRow = 3;
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    var rowIndex = startRow + 1;
    final statuses = grouped.keys.toList()..sort();
    for (final status in statuses) {
      final statusRows = grouped[status]!;
      sheet.getRangeByIndex(rowIndex, 1).setText(status);
      sheet
          .getRangeByIndex(rowIndex, 2)
          .setNumber(statusRows.length.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 3)
          .setNumber(
            _round2(statusRows.fold(0.0, (sum, row) => sum + row.basicAmount)),
          );
      sheet
          .getRangeByIndex(rowIndex, 4)
          .setNumber(
            _round2(
              statusRows.fold(0.0, (sum, row) => sum + row.applicableAmount),
            ),
          );
      sheet
          .getRangeByIndex(rowIndex, 5)
          .setNumber(
            _round2(statusRows.fold(0.0, (sum, row) => sum + row.tds26QAmount)),
          );
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(
            _round2(statusRows.fold(0.0, (sum, row) => sum + row.expectedTds)),
          );
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setNumber(
            _round2(statusRows.fold(0.0, (sum, row) => sum + row.actualTds)),
          );
      sheet
          .getRangeByIndex(rowIndex, 8)
          .setNumber(
            _round2(
              statusRows.fold(0.0, (sum, row) => sum + row.tdsDifference),
            ),
          );
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(
            _round2(
              statusRows.fold(0.0, (sum, row) => sum + row.amountDifference),
            ),
          );

      sheet
              .getRangeByIndex(rowIndex, 1, rowIndex, headers.length)
              .cellStyle
              .borders
              .all
              .lineStyle =
          xlsio.LineStyle.thin;
      rowIndex++;
    }

    _applyNumberFormat(sheet, startRow + 1, rowIndex - 1, [
      3,
      4,
      5,
      6,
      7,
      8,
      9,
    ]);
    _autoFitUsefulColumns(sheet, headers.length);
  }

  static void _writeTechnicalDetailsSheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
  }) {
    final maps = rows.map((row) => row.toMap()).toList();
    final headers =
        maps
            .expand((map) => map.keys)
            .map((key) => key.toString())
            .toSet()
            .toList()
          ..sort();

    sheet.getRangeByName('A1:Z1').merge();
    sheet.getRangeByName('A1').setText('Technical Details');
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    const startRow = 3;
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    for (var rowOffset = 0; rowOffset < maps.length; rowOffset++) {
      final rowIndex = startRow + 1 + rowOffset;
      final map = maps[rowOffset];
      for (var col = 0; col < headers.length; col++) {
        final value = map[headers[col]];
        final cell = sheet.getRangeByIndex(rowIndex, col + 1);
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }
      }
      sheet
              .getRangeByIndex(rowIndex, 1, rowIndex, headers.length)
              .cellStyle
              .borders
              .all
              .lineStyle =
          xlsio.LineStyle.thin;
    }

    if (headers.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        startRow,
        1,
        startRow,
        headers.length,
      );
      _autoFitUsefulColumns(sheet, headers.length);
    }
  }

  static void _writeTdsSectionInfoSheet(xlsio.Worksheet sheet) {
    final headers = [
      'Section',
      'Nature of Payment',
      'Threshold Rule',
      'Rate of TDS',
      'Applicability',
      'Who Deducts? (Payer)',
    ];
    final data = SectionRuleExportText.allRules();

    sheet.getRangeByName('A1:F1').merge();
    sheet.getRangeByName('A1').setText('TDS Section Info');
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(3, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    for (int i = 0; i < data.length; i++) {
      final info = data[i];
      final row = i + 4;
      final values = [
        info.section,
        info.natureOfPayment,
        info.thresholdText,
        info.rateText,
        info.applicabilityText,
        info.deductorText,
      ];
      for (int j = 0; j < values.length; j++) {
        final cell = sheet.getRangeByIndex(row, j + 1);
        cell.setText(values[j]);
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      }
    }

    _autoFitUsefulColumns(sheet, 6);
  }

  static void _writePivotSummarySheet(
    xlsio.Worksheet sheet, {
    required List<ReconciliationRow> rows,
    String? title,
    bool showLedgerSourceInSellerHeader = true,
  }) {
    final sortedRows = List<ReconciliationRow>.from(rows)
      ..sort((a, b) {
        final sellerCompare = a.sellerName.compareTo(b.sellerName);
        if (sellerCompare != 0) return sellerCompare;

        final fyCompare = a.financialYear.compareTo(b.financialYear);
        if (fyCompare != 0) return fyCompare;

        return CalculationService.compareMonthLabels(a.month, b.month);
      });

    final grouped = _groupRowsForPivot(sortedRows);

    sheet.getRangeByName('A1:K1').merge();
    sheet
        .getRangeByName('A1')
        .setText(
          title ??
              (rows.isNotEmpty
                  ? rows.first.buyerName.toUpperCase()
                  : 'PIVOT SUMMARY'),
        );
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 20;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.vAlign = xlsio.VAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#D9E1F2';

    sheet.getRangeByName('A2:K2').merge();
    sheet
        .getRangeByName('A2')
        .setText(
          'Generated on ${DateTime.now().day.toString().padLeft(2, '0')}-'
          '${DateTime.now().month.toString().padLeft(2, '0')}-'
          '${DateTime.now().year}',
        );
    sheet.getRangeByName('A2').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A2').cellStyle.backColor = '#F3F4F6';
    sheet.getRangeByName('A2').cellStyle.bold = true;

    int rowIndex = 4;

    double grandBasic = 0;
    double grandApplicable = 0;
    double grand26Q = 0;
    double grandExpected = 0;
    double grandActual = 0;
    double grandTdsDiff = 0;
    double grandAmtDiff = 0;

    for (final seller in grouped.keys) {
      final fyMap = grouped[seller]!;
      final sellerRows = fyMap.values.expand((rows) => rows).toList();
      final ledgerContext = showLedgerSourceInSellerHeader
          ? _ledgerSourceContextForRows(sellerRows)
          : '';
      final sellerHeader = ledgerContext.isEmpty
          ? seller.toUpperCase()
          : '${seller.toUpperCase()}    $ledgerContext';

      sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11).merge();
      sheet.getRangeByIndex(rowIndex, 1).setText(sellerHeader);
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.fontSize = 15;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign =
          xlsio.HAlignType.left;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.vAlign =
          xlsio.VAlignType.center;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.wrapText = true;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#E2EFDA';
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin;
      sheet.getRangeByIndex(rowIndex, 1).rowHeight = ledgerContext.isEmpty
          ? 24
          : 30;
      rowIndex++;

      for (final fy in fyMap.keys) {
        final fyRows = fyMap[fy]!;

        final fyBasic = fyRows.fold(0.0, (s, r) => s + r.basicAmount);
        final fyApplicable = fyRows.fold(0.0, (s, r) => s + r.applicableAmount);
        final fy26Q = fyRows.fold(0.0, (s, r) => s + r.tds26QAmount);
        final fyExpected = fyRows.fold(0.0, (s, r) => s + r.expectedTds);
        final fyActual = fyRows.fold(0.0, (s, r) => s + r.actualTds);
        final fyTdsDiff = fyRows.fold(0.0, (s, r) => s + r.tdsDifference);
        final fyAmtDiff = fyRows.fold(0.0, (s, r) => s + r.amountDifference);

        grandBasic += fyBasic;
        grandApplicable += fyApplicable;
        grand26Q += fy26Q;
        grandExpected += fyExpected;
        grandActual += fyActual;
        grandTdsDiff += fyTdsDiff;
        grandAmtDiff += fyAmtDiff;

        sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11).merge();
        sheet.getRangeByIndex(rowIndex, 1).setText('FY $fy');
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.fontSize = 12;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign =
            xlsio.HAlignType.left;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#EDEDED';
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.borders.all.lineStyle =
            xlsio.LineStyle.thin;
        rowIndex++;

        _writePivotHeader(sheet, rowIndex);
        rowIndex++;

        for (final r in fyRows) {
          sheet.getRangeByIndex(rowIndex, 1).setText(r.month);
          sheet.getRangeByIndex(rowIndex, 2).setNumber(_round2(r.basicAmount));
          sheet
              .getRangeByIndex(rowIndex, 3)
              .setNumber(_round2(r.applicableAmount));
          sheet.getRangeByIndex(rowIndex, 4).setNumber(_round2(r.tds26QAmount));
          sheet
              .getRangeByIndex(rowIndex, 5)
              .setNumber(_round2(r.amountDifference));
          sheet.getRangeByIndex(rowIndex, 6).setNumber(_round2(r.expectedTds));
          sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(r.actualTds));
          sheet.getRangeByIndex(rowIndex, 8).setNumber(r.tdsRateUsed);
          sheet
              .getRangeByIndex(rowIndex, 9)
              .setNumber(_round2(r.tdsDifference));
          sheet.getRangeByIndex(rowIndex, 10).setText(r.status);
          sheet
              .getRangeByIndex(rowIndex, 11)
              .setText(r.remarks.trim().isEmpty ? '-' : r.remarks);

          final range = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11);
          sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11).rowHeight = 20;
          if (r.status == ReconciliationStatus.matched) {
            range.cellStyle.backColor = '#E2F0D9';
          } else if (r.status == ReconciliationStatus.shortDeduction) {
            range.cellStyle.backColor = '#FCE4D6';
          } else if (r.status == ReconciliationStatus.excessDeduction) {
            range.cellStyle.backColor = '#F4CCCC';
          } else if (r.status == ReconciliationStatus.timingDifference) {
            range.cellStyle.backColor = '#DDEBF7';
          } else if (r.status == ReconciliationStatus.purchaseOnly) {
            range.cellStyle.backColor = '#EAF3FF';
          } else if (r.status == ReconciliationStatus.onlyIn26Q) {
            range.cellStyle.backColor = '#F1E6FF';
          } else {
            range.cellStyle.backColor = '#F5F5F5';
          }

          range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
          range.cellStyle.vAlign = xlsio.VAlignType.center;

          for (int col = 2; col <= 9; col++) {
            sheet.getRangeByIndex(rowIndex, col).cellStyle.hAlign =
                xlsio.HAlignType.right;
          }

          sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign =
              xlsio.HAlignType.left;
          sheet.getRangeByIndex(rowIndex, 10).cellStyle.hAlign =
              xlsio.HAlignType.center;
          sheet.getRangeByIndex(rowIndex, 11).cellStyle.hAlign =
              xlsio.HAlignType.left;

          if (r.tdsDifference < 0) {
            sheet.getRangeByIndex(rowIndex, 9).cellStyle.fontColor = '#FF0000';
          } else if (r.tdsDifference > 0) {
            sheet.getRangeByIndex(rowIndex, 9).cellStyle.fontColor = '#008000';
          }
          if (r.amountDifference < 0) {
            sheet.getRangeByIndex(rowIndex, 5).cellStyle.fontColor = '#FF0000';
          } else if (r.amountDifference > 0) {
            sheet.getRangeByIndex(rowIndex, 5).cellStyle.fontColor = '#008000';
          }

          rowIndex++;
        }

        sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
        sheet.getRangeByIndex(rowIndex, 2).setNumber(_round2(fyBasic));
        sheet.getRangeByIndex(rowIndex, 3).setNumber(_round2(fyApplicable));
        sheet.getRangeByIndex(rowIndex, 4).setNumber(_round2(fy26Q));
        sheet.getRangeByIndex(rowIndex, 5).setNumber(_round2(fyAmtDiff));
        sheet.getRangeByIndex(rowIndex, 6).setNumber(_round2(fyExpected));
        sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(fyActual));
        sheet.getRangeByIndex(rowIndex, 8).setText('');
        sheet.getRangeByIndex(rowIndex, 9).setNumber(_round2(fyTdsDiff));

        final totalRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11);
        totalRange.cellStyle.bold = true;
        totalRange.cellStyle.fontSize = 11;
        totalRange.cellStyle.backColor = '#FFF2CC';
        totalRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11).rowHeight = 22;

        for (int col = 2; col <= 9; col++) {
          sheet.getRangeByIndex(rowIndex, col).cellStyle.hAlign =
              xlsio.HAlignType.right;
        }

        rowIndex += 3;
      }
    }

    sheet.getRangeByIndex(rowIndex, 1).setText('GRAND TOTAL');
    sheet.getRangeByIndex(rowIndex, 2).setNumber(_round2(grandBasic));
    sheet.getRangeByIndex(rowIndex, 3).setNumber(_round2(grandApplicable));
    sheet.getRangeByIndex(rowIndex, 4).setNumber(_round2(grand26Q));
    sheet.getRangeByIndex(rowIndex, 5).setNumber(_round2(grandAmtDiff));
    sheet.getRangeByIndex(rowIndex, 6).setNumber(_round2(grandExpected));
    sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(grandActual));
    sheet.getRangeByIndex(rowIndex, 8).setText('');
    sheet.getRangeByIndex(rowIndex, 9).setNumber(_round2(grandTdsDiff));

    final grandRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11);
    grandRange.cellStyle.bold = true;
    grandRange.cellStyle.fontSize = 12;
    grandRange.cellStyle.backColor = '#FFD966';
    grandRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    sheet.getRangeByIndex(rowIndex, 1, rowIndex, 11).rowHeight = 24;

    for (int col = 2; col <= 9; col++) {
      sheet.getRangeByIndex(rowIndex, col).cellStyle.hAlign =
          xlsio.HAlignType.right;
    }

    _applyNumberFormat(sheet, 1, rowIndex, [2, 3, 4, 5, 6, 7, 9]);
    sheet.getRangeByIndex(1, 8, rowIndex, 8).numberFormat = '0.00%';
    _autoFitPivot(sheet);
  }

  static Map<String, Map<String, List<ReconciliationRow>>> _groupRowsForPivot(
    List<ReconciliationRow> rows,
  ) {
    final map = <String, Map<String, List<ReconciliationRow>>>{};

    for (final r in rows) {
      map.putIfAbsent(r.sellerName, () => {});
      map[r.sellerName]!.putIfAbsent(r.financialYear, () => []);
      map[r.sellerName]![r.financialYear]!.add(r);
    }

    return map;
  }

  static String _ledgerSourceContextForRows(List<ReconciliationRow> rows) {
    final names =
        rows
            .expand((row) => row.sourceLedgerFileNames)
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toUpperCase().compareTo(b.toUpperCase()));

    if (names.isEmpty) return '';
    if (names.length == 1) return 'Ledger: ${names.single}';
    return '${names.length} ledgers: ${names.join(' | ')}';
  }

  static void _writePivotHeader(xlsio.Worksheet sheet, int row) {
    final headers = [
      'Month',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Amount Diff',
      'Expected TDS',
      'Actual TDS',
      'TDS Rate Used',
      'TDS Diff',
      'Status',
      'Remarks',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(row, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontSize = 11;
      cell.cellStyle.backColor = '#9DC3E6';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    sheet.getRangeByIndex(row, 1, row, headers.length).rowHeight = 24;
  }

  static void _autoFitPivot(xlsio.Worksheet sheet) {
    sheet.setColumnWidthInPixels(1, 100); // Month
    sheet.setColumnWidthInPixels(2, 105); // Basic
    sheet.setColumnWidthInPixels(3, 115); // Applicable
    sheet.setColumnWidthInPixels(4, 100); // 26Q
    sheet.setColumnWidthInPixels(5, 95); // Amt Diff
    sheet.setColumnWidthInPixels(6, 100); // Exp TDS
    sheet.setColumnWidthInPixels(7, 95); // Actual TDS
    sheet.setColumnWidthInPixels(8, 95); // Rate
    sheet.setColumnWidthInPixels(9, 90); // TDS Diff
    sheet.setColumnWidthInPixels(10, 130); // Status
    sheet.setColumnWidthInPixels(11, 280); // Remarks
  }

  static String getRiskLevel(String status) {
    switch (status) {
      case ReconciliationStatus.applicableButNo26Q:
      case ReconciliationStatus.sectionMissing:
        return 'HIGH';
      case ReconciliationStatus.shortDeduction:
      case ReconciliationStatus.onlyIn26Q:
      case ReconciliationStatus.purchaseOnly:
        return 'MEDIUM';
      case ReconciliationStatus.excessDeduction:
      case ReconciliationStatus.timingDifference:
        return 'LOW';
      case ReconciliationStatus.matched:
      default:
        return 'OK';
    }
  }

  static List<String> getUniqueSections(List<ReconciliationRow> rows) {
    final sections =
        rows
            .map((e) => e.section.trim().isEmpty ? 'No Section' : e.section)
            .where((e) => e.isNotEmpty && e.toUpperCase() != 'NO SECTION')
            .toSet()
            .toList()
          ..sort();
    return sections;
  }

  static void _applyNumberFormat(
    xlsio.Worksheet sheet,
    int fromRow,
    int toRow,
    List<int> columns,
  ) {
    if (toRow < fromRow) return;
    for (final col in columns) {
      sheet.getRangeByIndex(fromRow, col, toRow, col).numberFormat = '#,##0.00';
    }
  }

  static void _autoFitUsefulColumns(xlsio.Worksheet sheet, int totalColumns) {
    final autoFitWatch = Stopwatch()..start();
    for (int col = 1; col <= totalColumns; col++) {
      sheet.autoFitColumn(col);
    }
    autoFitWatch.stop();
    _logPerformance(
      'autoFitColumn',
      autoFitWatch,
      details: 'columns=$totalColumns',
    );
  }

  static String _safeSheetName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[:\\/?*\[\]]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) return 'Sheet';
    if (cleaned.length <= 31) return cleaned;
    return cleaned.substring(0, 31);
  }

  static String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  static String buildPivotReportFileName({
    required String buyerName,
    String? sellerName,
    String? financialYear,
    DateTime? generatedAt,
  }) {
    return buildExportFileName(
      mode: ExcelExportMode.pivotReport,
      buyerName: buyerName,
      financialYear: financialYear,
    );
  }

  static String buildExportFileName({
    required ExcelExportMode mode,
    required String buyerName,
    String? financialYear,
    String? section,
  }) {
    final segments = <String>[
      _safeFileName(buyerName.trim().isEmpty ? 'Buyer' : buyerName),
    ];

    switch (mode) {
      case ExcelExportMode.currentView:
        segments.add('Working_View');
      case ExcelExportMode.section:
        final sectionSegment = section?.trim() ?? '';
        segments.add(sectionSegment.isEmpty ? 'Section' : sectionSegment);
      case ExcelExportMode.pivotReport:
        segments.add('Final_Export');
      case ExcelExportMode.detailedReport:
        segments.add('Detailed_Audit_Export');
    }

    final fySegment = _financialYearFileSegment(financialYear ?? '');
    if (fySegment.isNotEmpty) {
      segments.add(fySegment);
    }

    return '${segments.map(_safeFileName).where((segment) => segment.trim().isNotEmpty).join('_')}.xlsx';
  }

  static String _financialYearFileSegment(String financialYear) {
    if (financialYear.trim().isEmpty || financialYear.trim() == 'All FY') {
      return '';
    }
    final stripped = financialYear.trim().replaceFirst(
      RegExp(r'^fy\s*', caseSensitive: false),
      '',
    );
    return 'FY_${_safeFileName(stripped)}';
  }

  static Future<String> _resolveAvailableFilePath(
    String folderPath,
    String fileName,
  ) async {
    final requestedPath = p.join(folderPath, fileName);
    if (!await File(requestedPath).exists()) {
      debugPrint(
        'EXPORT PATH => requested=$requestedPath resolved=$requestedPath',
      );
      return requestedPath;
    }

    final extension = p.extension(fileName);
    final baseName = p.basenameWithoutExtension(fileName);
    var index = 2;
    while (true) {
      final candidate = p.join(folderPath, '${baseName}_$index$extension');
      if (!await File(candidate).exists()) {
        debugPrint(
          'EXPORT PATH => requested=$requestedPath resolved=$candidate',
        );
        return candidate;
      }
      index++;
    }
  }

  static String _getDownloadsPath() {
    final userProfile = Platform.environment['USERPROFILE'];

    if (userProfile != null && userProfile.isNotEmpty) {
      return '$userProfile\\Downloads';
    }

    return Directory.systemTemp.path;
  }

  static double _round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}

class _LedgerSourceReference {
  final String sourceKey;
  final String displayName;

  const _LedgerSourceReference({
    required this.sourceKey,
    required this.displayName,
  });
}

class _LedgerPivotGroup {
  final String ledgerName;
  final String section;
  final String sellerName;
  final String financialYear;
  final List<ReconciliationRow> rows = <ReconciliationRow>[];

  _LedgerPivotGroup({
    required this.ledgerName,
    required this.section,
    required this.sellerName,
    required this.financialYear,
  });
}
