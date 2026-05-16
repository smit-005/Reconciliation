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
  static final List<_TechnicalExportColumn> _technicalDetailColumns = [
    _TechnicalExportColumn('26Q Amount', (row) => row.tds26QAmount),
    _TechnicalExportColumn('Actual TDS', (row) => row.actualTds),
    _TechnicalExportColumn('Amount Difference', (row) => row.amountDifference),
    _TechnicalExportColumn('Applicable Amount', (row) => row.applicableAmount),
    _TechnicalExportColumn('Basic Amount', (row) => row.basicAmount),
    _TechnicalExportColumn('Buyer Name', (row) => row.buyerName),
    _TechnicalExportColumn('Buyer PAN', (row) => row.buyerPan),
    _TechnicalExportColumn(
      'Calculation Remark',
      (row) => row.calculationRemark,
    ),
    _TechnicalExportColumn(
      'Closing Timing Balance',
      (row) => row.closingTimingBalance,
    ),
    _TechnicalExportColumn(
      'Debug Applicable Reason',
      (row) => row.debugInfo.applicableAmountReason,
    ),
    _TechnicalExportColumn(
      'Debug Cumulative After',
      (row) => row.debugInfo.cumulativePurchaseAfterRow,
    ),
    _TechnicalExportColumn(
      'Debug Cumulative Before',
      (row) => row.debugInfo.cumulativePurchaseBeforeRow,
    ),
    _TechnicalExportColumn(
      'Debug Expected TDS Reason',
      (row) => row.debugInfo.expectedTdsReason,
    ),
    _TechnicalExportColumn('Debug FY', (row) => row.debugInfo.financialYear),
    _TechnicalExportColumn(
      'Debug Final Status Reason',
      (row) => row.debugInfo.finalStatusReason,
    ),
    _TechnicalExportColumn(
      'Debug Identity Flags',
      (row) => row.debugInfo.identityFlags.join(', '),
    ),
    _TechnicalExportColumn(
      'Debug Identity Notes',
      (row) => row.debugInfo.identityNotes,
    ),
    _TechnicalExportColumn(
      'Debug Identity Source',
      (row) => row.debugInfo.resolvedIdentitySource,
    ),
    _TechnicalExportColumn(
      'Debug Mapping Attempted',
      (row) => row.debugInfo.mappingAttempted ? 'Yes' : 'No',
    ),
    _TechnicalExportColumn(
      'Debug Mapping Hit',
      (row) => row.debugInfo.mappingHit,
    ),
    _TechnicalExportColumn(
      'Debug Mapping Section Used',
      (row) => row.debugInfo.mappingSectionUsed,
    ),
    _TechnicalExportColumn(
      'Debug Normalized Seller Names',
      (row) => row.debugInfo.normalizedSellerNames.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Original PANs',
      (row) => row.debugInfo.originalPans.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Original Seller Names',
      (row) => row.debugInfo.originalSellerNames.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Resolved Seller Id',
      (row) => row.debugInfo.resolvedSellerId,
    ),
    _TechnicalExportColumn('Debug Section', (row) => row.debugInfo.section),
    _TechnicalExportColumn(
      'Debug Source Ledger Files',
      (row) => row.debugInfo.sourceLedgerFileNames.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Source Ledger IDs',
      (row) => row.debugInfo.sourceLedgerFileIds.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Source Upload Timestamps',
      (row) => row.debugInfo.sourceLedgerUploadedAtIso.join(' | '),
    ),
    _TechnicalExportColumn(
      'Debug Threshold Crossed',
      (row) => row.debugInfo.thresholdCrossed ? 'Yes' : 'No',
    ),
    _TechnicalExportColumn('Expected TDS', (row) => row.expectedTds),
    _TechnicalExportColumn('Financial Year', (row) => row.financialYear),
    _TechnicalExportColumn(
      'Identity Confidence',
      (row) => row.identityConfidence,
    ),
    _TechnicalExportColumn('Identity Notes', (row) => row.identityNotes),
    _TechnicalExportColumn('Identity Source', (row) => row.identitySource),
    _TechnicalExportColumn('Month', (row) => row.month),
    _TechnicalExportColumn(
      'Month TDS Difference',
      (row) => row.monthTdsDifference,
    ),
    _TechnicalExportColumn(
      'Opening Timing Balance',
      (row) => row.openingTimingBalance,
    ),
    _TechnicalExportColumn('Remarks', (row) => row.remarks),
    _TechnicalExportColumn('Resolved PAN', (row) => row.resolvedPan),
    _TechnicalExportColumn('Resolved Seller Id', (row) => row.resolvedSellerId),
    _TechnicalExportColumn(
      'Resolved Seller Name',
      (row) => row.resolvedSellerName,
    ),
    _TechnicalExportColumn('Section', (row) => row.section),
    _TechnicalExportColumn('Seller Name', (row) => row.sellerName),
    _TechnicalExportColumn('Seller PAN', (row) => row.sellerPan),
    _TechnicalExportColumn(
      'Source Ledger File IDs',
      (row) => row.sourceLedgerFileIds.join(' | '),
    ),
    _TechnicalExportColumn(
      'Source Ledger Files',
      (row) => row.sourceLedgerFileNames.join(' | '),
    ),
    _TechnicalExportColumn(
      'Source Ledger Uploaded At',
      (row) => row.sourceLedgerUploadedAtIso.join(' | '),
    ),
    _TechnicalExportColumn('Status', (row) => row.status),
    _TechnicalExportColumn('TDS Difference', (row) => row.tdsDifference),
  ];

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

  static void _writeTimedSheet(
    xlsio.Worksheet sheet,
    String label,
    void Function() write,
  ) {
    final sheetWatch = Stopwatch()..start();
    write();
    sheetWatch.stop();
    _logPerformance(
      'sheet_write',
      sheetWatch,
      details: 'sheet=${sheet.name} label=$label',
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
    final totalExportWatch = Stopwatch()..start();
    final fileName = buildExportFileName(
      mode: mode,
      buyerName: buyerName,
      financialYear: financialYear,
      section: section ?? _sectionLabelFromRows(rows),
    );
    debugPrint(
      'EXPORT TIMING => export_start mode=${mode.name} name=$fileName rows=${rows.length}',
    );
    debugPrint('EXPORT PERF => step=rows_count rows=${rows.length}');
    final workbookWatch = Stopwatch()..start();
    final workbook = xlsio.Workbook();
    workbookWatch.stop();
    _logPerformance('workbook_creation', workbookWatch);

    try {
      final workbookBuildWatch = Stopwatch()..start();
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
      workbookBuildWatch.stop();
      debugPrint(
        'EXPORT TIMING => workbook_build_ms=${workbookBuildWatch.elapsedMilliseconds} mode=${mode.name} name=$fileName',
      );

      final saveWatch = Stopwatch()..start();
      final path = await _saveWorkbook(
        workbook,
        fileName: fileName,
        outputFolderPath: outputFolderPath,
      );
      saveWatch.stop();
      totalExportWatch.stop();
      debugPrint(
        'EXPORT TIMING => save_ms=${saveWatch.elapsedMilliseconds} mode=${mode.name} name=$fileName',
      );
      debugPrint(
        'EXPORT TIMING => total_export_ms=${totalExportWatch.elapsedMilliseconds} mode=${mode.name} name=$fileName path=$path',
      );
      return path;
    } catch (e) {
      if (totalExportWatch.isRunning) {
        totalExportWatch.stop();
      }
      debugPrint(
        'EXPORT TIMING => total_export_ms=${totalExportWatch.elapsedMilliseconds} mode=${mode.name} name=$fileName status=failed error=$e',
      );
      rethrow;
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
    _writeTimedSheet(summarySheet, 'compact_summary', () {
      summarySheet.name = 'Summary';
      _writeCompactSummarySheet(
        summarySheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
        title: 'Working View Summary',
      );
    });

    final pivotSheet = workbook.worksheets.addWithName('Pivot');
    _writeTimedSheet(
      pivotSheet,
      'pivot',
      () => _writeTimedPivotSummarySheet(
        pivotSheet,
        rows: rows,
        title: 'WORKING VIEW PIVOT',
      ),
    );

    final missingSheet = workbook.worksheets.addWithName('Missing_In_Books');
    _writeTimedSheet(
      missingSheet,
      'filtered_detail',
      () => _writeFilteredDetailSheet(
        missingSheet,
        rows: rows,
        title: 'MISSING IN BOOKS',
        predicate: _isMissingInBooksRow,
      ),
    );

    final detailSheet = workbook.worksheets.addWithName('Raw_Data');
    _writeTimedSheet(detailSheet, 'detail', () {
      _writeTitle(detailSheet, 'WORKING VIEW RAW DATA');
      _writeSummarySection(
        detailSheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );
      _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);
    });

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTimedSheet(
      infoSheet,
      'tds_section_info',
      () => _writeTdsSectionInfoSheet(infoSheet),
    );
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
    _writeTimedSheet(sectionSummarySheet, 'section_summary', () {
      sectionSummarySheet.name = 'Section_Summary';
      _writeSectionSummarySheet(
        sectionSummarySheet,
        grouped: grouped,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );
    });

    final pivotSheet = workbook.worksheets.addWithName('Section_Pivot');
    _writeTimedSheet(
      pivotSheet,
      'pivot',
      () => _writeTimedPivotSummarySheet(
        pivotSheet,
        rows: rows,
        title: 'SECTION $section SELLER PIVOT',
      ),
    );

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeTimedSheet(
      ledgerPivotSheet,
      'ledger_pivot',
      () => _writeLedgerPivotSheet(
        ledgerPivotSheet,
        rows: rows,
        title: 'SECTION $section LEDGER PIVOT',
      ),
    );

    final missingSheet = workbook.worksheets.addWithName('Missing_In_Books');
    _writeTimedSheet(
      missingSheet,
      'filtered_detail',
      () => _writeFilteredDetailSheet(
        missingSheet,
        rows: rows,
        title: 'MISSING IN BOOKS',
        predicate: _isMissingInBooksRow,
      ),
    );

    final exceptionsSheet = workbook.worksheets.addWithName('Exceptions');
    _writeTimedSheet(
      exceptionsSheet,
      'exceptions',
      () => _writeExceptionsSheet(
        exceptionsSheet,
        rows: rows,
        remainingOnly: true,
      ),
    );

    final detailSheet = workbook.worksheets.addWithName('Raw_Data');
    _writeTimedSheet(detailSheet, 'detail', () {
      _writeTitle(detailSheet, 'SECTION $section DETAIL');
      _writeSummarySection(
        detailSheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );
      _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);
    });

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTimedSheet(
      infoSheet,
      'tds_section_info',
      () => _writeTdsSectionInfoSheet(infoSheet),
    );
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
    _writeTimedSheet(workbookSummarySheet, 'compact_summary', () {
      workbookSummarySheet.name = 'Master_Summary';
      _writeCompactSummarySheet(
        workbookSummarySheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
        title: 'Master Summary',
      );
    });

    final sectionSummarySheet = workbook.worksheets.addWithName(
      'Section_Summary',
    );
    _writeTimedSheet(
      sectionSummarySheet,
      'section_summary',
      () => _writeSectionSummarySheet(
        sectionSummarySheet,
        grouped: grouped,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      ),
    );

    _writeSectionPivotSheets(workbook, grouped: grouped);

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeTimedSheet(
      ledgerPivotSheet,
      'ledger_pivot',
      () => _writeLedgerPivotSheet(
        ledgerPivotSheet,
        rows: rows,
        title: 'FINAL LEDGER PIVOT',
      ),
    );

    final finalMissingSheet = workbook.worksheets.addWithName(
      'Final_Missing_In_Books',
    );
    _writeTimedSheet(
      finalMissingSheet,
      'filtered_detail',
      () => _writeFilteredDetailSheet(
        finalMissingSheet,
        rows: rows,
        title: 'FINAL MISSING IN BOOKS',
        predicate: _isMissingInBooksRow,
      ),
    );

    final exceptionSummarySheet = workbook.worksheets.addWithName(
      'Exception_Summary',
    );
    _writeTimedSheet(
      exceptionSummarySheet,
      'exception_summary',
      () => _writeExceptionSummarySheet(exceptionSummarySheet, rows: rows),
    );

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTimedSheet(
      infoSheet,
      'tds_section_info',
      () => _writeTdsSectionInfoSheet(infoSheet),
    );
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
    _writeTimedSheet(workbookSummarySheet, 'compact_summary', () {
      workbookSummarySheet.name = 'Master_Summary';
      _writeCompactSummarySheet(
        workbookSummarySheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
        title: 'Master Summary',
      );
    });

    final sectionSummarySheet = workbook.worksheets.addWithName(
      'Section_Summary',
    );
    _writeTimedSheet(
      sectionSummarySheet,
      'section_summary',
      () => _writeSectionSummarySheet(
        sectionSummarySheet,
        grouped: grouped,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      ),
    );

    _writeSectionPivotSheets(workbook, grouped: grouped);

    final ledgerPivotSheet = workbook.worksheets.addWithName('Ledger_Pivot');
    _writeTimedSheet(
      ledgerPivotSheet,
      'ledger_pivot',
      () => _writeLedgerPivotSheet(
        ledgerPivotSheet,
        rows: rows,
        title: 'FINAL LEDGER PIVOT',
      ),
    );

    final finalMissingSheet = workbook.worksheets.addWithName(
      'Final_Missing_In_Books',
    );
    _writeTimedSheet(
      finalMissingSheet,
      'filtered_detail',
      () => _writeFilteredDetailSheet(
        finalMissingSheet,
        rows: rows,
        title: 'FINAL MISSING IN BOOKS',
        predicate: _isMissingInBooksRow,
      ),
    );

    final exceptionSummarySheet = workbook.worksheets.addWithName(
      'Exception_Summary',
    );
    _writeTimedSheet(
      exceptionSummarySheet,
      'exception_summary',
      () => _writeExceptionSummarySheet(exceptionSummarySheet, rows: rows),
    );

    final detailSheet = workbook.worksheets.addWithName('Raw_Reconciliation');
    _writeTimedSheet(detailSheet, 'detail', () {
      _writeTitle(detailSheet, 'RAW RECONCILIATION');
      _writeSummarySection(
        detailSheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );
      _writeTimedDetailTable(detailSheet, rows: rows, startRow: 8);
    });

    final infoSheet = workbook.worksheets.addWithName('TDS_Section_Info');
    _writeTimedSheet(
      infoSheet,
      'tds_section_info',
      () => _writeTdsSectionInfoSheet(infoSheet),
    );
  }

  // Reserved for a future advanced/debug export mode.
  // ignore: unused_element
  static void _writeAdvancedDebugSheets(
    xlsio.Workbook workbook, {
    required List<ReconciliationRow> rows,
  }) {
    final exceptionDetailsSheet = workbook.worksheets.addWithName(
      'Exception_Details',
    );
    _writeTimedSheet(
      exceptionDetailsSheet,
      'exceptions',
      () => _writeExceptionsSheet(
        exceptionDetailsSheet,
        rows: rows,
        remainingOnly: false,
      ),
    );

    final technicalDetailsSheet = workbook.worksheets.addWithName(
      'Technical_Details',
    );
    _writeTimedSheet(
      technicalDetailsSheet,
      'technical_details',
      () => _writeTechnicalDetailsSheet(technicalDetailsSheet, rows: rows),
    );
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
      _writeTimedSheet(
        sheet,
        'section_pivot',
        () => _writeTimedPivotSummarySheet(
          sheet,
          rows: sectionRows,
          title: '$cleanSection PIVOT',
        ),
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
      final summary = _ExportRowSummary.fromRows(groupRows);
      sheet.getRangeByIndex(rowIndex, 1).setText(group.ledgerName);
      sheet.getRangeByIndex(rowIndex, 2).setText(group.section);
      sheet.getRangeByIndex(rowIndex, 3).setText(group.sellerName);
      sheet.getRangeByIndex(rowIndex, 4).setText(group.financialYear);
      sheet.getRangeByIndex(rowIndex, 5).setNumber(summary.rowCount.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(_round2(summary.basicAmount));
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setNumber(_round2(summary.applicableAmount));
      sheet
          .getRangeByIndex(rowIndex, 8)
          .setNumber(_round2(summary.tds26QAmount));
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(summary.expectedTds));
      sheet.getRangeByIndex(rowIndex, 10).setNumber(_round2(summary.actualTds));
      sheet
          .getRangeByIndex(rowIndex, 11)
          .setNumber(_round2(summary.tdsDifference));
      sheet
          .getRangeByIndex(rowIndex, 12)
          .setNumber(_round2(summary.amountDifference));
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
    _applyFixedLedgerPivotColumnWidths(sheet);
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
    final summary = _ExportRowSummary.fromRows(rows);
    final totalBasic = _round2(summary.basicAmount);
    final totalApplicable = _round2(summary.applicableAmount);
    final total26QAmount = _round2(summary.tds26QAmount);
    final totalExpectedTds = _round2(summary.expectedTds);
    final totalActualTds = _round2(summary.actualTds);
    final totalTdsDifference = _round2(summary.tdsDifference);
    final totalAmountDifference = _round2(summary.amountDifference);
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

    final summary = _ExportRowSummary.fromRows(rows);

    sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
    sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;

    sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(summary.basicAmount));
    sheet
        .getRangeByIndex(rowIndex, 9)
        .setNumber(_round2(summary.applicableAmount));
    sheet
        .getRangeByIndex(rowIndex, 10)
        .setNumber(_round2(summary.tds26QAmount));
    sheet.getRangeByIndex(rowIndex, 11).setNumber(_round2(summary.expectedTds));
    sheet.getRangeByIndex(rowIndex, 12).setNumber(_round2(summary.actualTds));
    sheet.getRangeByIndex(rowIndex, 13).setText('');
    sheet
        .getRangeByIndex(rowIndex, 14)
        .setNumber(_round2(summary.tdsDifference));
    sheet
        .getRangeByIndex(rowIndex, 15)
        .setNumber(_round2(summary.amountDifference));

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
    if (_usesFixedDetailWidths(sheet.name)) {
      _applyFixedDetailColumnWidths(sheet);
    } else {
      _autoFitUsefulColumns(sheet, 21);
    }
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

    final summary = _ExportRowSummary.fromRows(
      rows,
      includeStatusCounts: true,
      includeDerivedCounts: true,
    );
    final totalBasic = _round2(summary.basicAmount);
    final totalApplicable = _round2(summary.applicableAmount);
    final total26QAmount = _round2(summary.tds26QAmount);
    final totalExpectedTds = _round2(summary.expectedTds);
    final totalActualTds = _round2(summary.actualTds);
    final totalTdsDifference = _round2(summary.tdsDifference);
    final totalAmountDifference = _round2(summary.amountDifference);
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
      summary.statusCount(ReconciliationStatus.matched).toString(),
      summary.statusCount(ReconciliationStatus.timingDifference).toString(),
      summary.statusCount(ReconciliationStatus.shortDeduction).toString(),
      summary.statusCount(ReconciliationStatus.excessDeduction).toString(),
      summary.statusCount(ReconciliationStatus.purchaseOnly).toString(),
      summary.statusCount(ReconciliationStatus.onlyIn26Q).toString(),
      summary.applicableButNo26QRows.toString(),
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
      final summary = _ExportRowSummary.fromRows(
        rows,
        includeDerivedCounts: true,
      );

      sheet.getRangeByIndex(rowIndex, 1).setText(section);
      sheet
          .getRangeByIndex(rowIndex, 2)
          .setText(SectionRuleExportText.summaryTextForSections([section]));
      sheet.getRangeByIndex(rowIndex, 3).setNumber(summary.rowCount.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 4)
          .setNumber(_round2(summary.basicAmount));
      sheet
          .getRangeByIndex(rowIndex, 5)
          .setNumber(_round2(summary.applicableAmount));
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(_round2(summary.tds26QAmount));
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setNumber(_round2(summary.expectedTds));
      sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(summary.actualTds));
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(summary.tdsDifference));
      sheet
          .getRangeByIndex(rowIndex, 10)
          .setNumber(_round2(summary.amountDifference));
      sheet
          .getRangeByIndex(rowIndex, 11)
          .setNumber(summary.nonMatchedRows.toDouble());

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
      final summary = _ExportRowSummary.fromRows(statusRows);
      sheet.getRangeByIndex(rowIndex, 1).setText(status);
      sheet.getRangeByIndex(rowIndex, 2).setNumber(summary.rowCount.toDouble());
      sheet
          .getRangeByIndex(rowIndex, 3)
          .setNumber(_round2(summary.basicAmount));
      sheet
          .getRangeByIndex(rowIndex, 4)
          .setNumber(_round2(summary.applicableAmount));
      sheet
          .getRangeByIndex(rowIndex, 5)
          .setNumber(_round2(summary.tds26QAmount));
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setNumber(_round2(summary.expectedTds));
      sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(summary.actualTds));
      sheet
          .getRangeByIndex(rowIndex, 8)
          .setNumber(_round2(summary.tdsDifference));
      sheet
          .getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(summary.amountDifference));

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
    sheet.getRangeByName('A1:Z1').merge();
    sheet.getRangeByName('A1').setText('Technical Details');
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 16;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    const startRow = 3;
    final columns = _technicalDetailColumns;
    final headers = columns
        .map((column) => column.header)
        .toList(growable: false);

    for (var i = 0; i < columns.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(columns[i].header);
    }

    final headerRange = sheet.getRangeByIndex(
      startRow,
      1,
      startRow,
      columns.length,
    );
    headerRange.cellStyle.bold = true;
    headerRange.cellStyle.backColor = '#D9EAF7';
    headerRange.cellStyle.hAlign = xlsio.HAlignType.center;
    headerRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    for (var rowOffset = 0; rowOffset < rows.length; rowOffset++) {
      final rowIndex = startRow + 1 + rowOffset;
      final row = rows[rowOffset];
      for (var col = 0; col < columns.length; col++) {
        final value = columns[col].valueFor(row);
        final cell = sheet.getRangeByIndex(rowIndex, col + 1);
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }
      }
    }

    if (columns.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        startRow,
        1,
        startRow,
        columns.length,
      );
      _applyFixedTechnicalColumnWidths(sheet, headers);
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
      final ledgerContext = showLedgerSourceInSellerHeader
          ? _ledgerSourceContextForRows(fyMap.values.expand((rows) => rows))
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

        final fySummary = _ExportRowSummary.fromRows(fyRows);
        final fyBasic = fySummary.basicAmount;
        final fyApplicable = fySummary.applicableAmount;
        final fy26Q = fySummary.tds26QAmount;
        final fyExpected = fySummary.expectedTds;
        final fyActual = fySummary.actualTds;
        final fyTdsDiff = fySummary.tdsDifference;
        final fyAmtDiff = fySummary.amountDifference;

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

  static String _ledgerSourceContextForRows(Iterable<ReconciliationRow> rows) {
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
      details: 'sheet=${sheet.name} columns=$totalColumns',
    );
  }

  static bool _usesFixedDetailWidths(String sheetName) {
    return const {
      'Raw_Data',
      'Raw_Reconciliation',
      'Exceptions',
      'Exception_Details',
      'Final_Missing_In_Books',
      'Missing_In_Books',
    }.contains(sheetName);
  }

  static void _applyFixedDetailColumnWidths(xlsio.Worksheet sheet) {
    final widthWatch = Stopwatch()..start();
    const widths = <int>[
      170, // Buyer Name
      115, // Buyer PAN
      90, // Financial Year
      80, // Month
      80, // Section
      220, // Seller Name
      115, // Seller PAN
      115, // Basic Amount
      125, // Applicable Amount
      105, // 26Q Amount
      115, // Expected TDS
      105, // Actual TDS
      90, // TDS Rate Used
      110, // TDS Difference
      120, // Amount Difference
      150, // Status
      90, // Risk Level
      170, // Source Ledger File IDs
      220, // Source Ledger Files
      180, // Source Ledger Uploaded At
      260, // Remarks
    ];

    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidthInPixels(i + 1, widths[i]);
    }
    widthWatch.stop();
    _logPerformance(
      'fixed_column_widths',
      widthWatch,
      details: 'sheet=${sheet.name} columns=${widths.length}',
    );
  }

  static void _applyFixedLedgerPivotColumnWidths(xlsio.Worksheet sheet) {
    final widthWatch = Stopwatch()..start();
    const widths = <int>[
      220, // Ledger
      85, // Section
      230, // Seller Name
      100, // Financial Year
      70, // Rows
      115, // Basic Amount
      125, // Applicable Amount
      105, // 26Q Amount
      115, // Expected TDS
      105, // Actual TDS
      110, // TDS Difference
      120, // Amount Difference
      220, // Statuses
    ];

    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidthInPixels(i + 1, widths[i]);
    }
    widthWatch.stop();
    _logPerformance(
      'fixed_column_widths',
      widthWatch,
      details: 'sheet=${sheet.name} columns=${widths.length}',
    );
  }

  static void _applyFixedTechnicalColumnWidths(
    xlsio.Worksheet sheet,
    List<String> headers,
  ) {
    final widthWatch = Stopwatch()..start();
    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnWidthInPixels(i + 1, _technicalColumnWidth(headers[i]));
    }
    widthWatch.stop();
    _logPerformance(
      'fixed_column_widths',
      widthWatch,
      details: 'sheet=${sheet.name} columns=${headers.length}',
    );
  }

  static int _technicalColumnWidth(String header) {
    final normalized = header.toLowerCase();
    if (normalized.contains('remark') || normalized.contains('reason')) {
      return 260;
    }
    if (normalized.contains('file') ||
        normalized.contains('source') ||
        normalized.contains('ledger')) {
      return 220;
    }
    if (normalized.contains('name')) {
      return 210;
    }
    if (normalized.contains('date') ||
        normalized.contains('month') ||
        normalized.contains('uploaded')) {
      return 150;
    }
    if (normalized.contains('pan') ||
        normalized.contains('gst') ||
        normalized.contains('section')) {
      return 115;
    }
    if (normalized.contains('amount') ||
        normalized.contains('tds') ||
        normalized.contains('difference')) {
      return 125;
    }
    if (normalized.contains('rate')) {
      return 90;
    }
    if (normalized.contains('status')) {
      return 150;
    }
    return 140;
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

class _TechnicalExportColumn {
  final String header;
  final Object? Function(ReconciliationRow row) valueFor;

  const _TechnicalExportColumn(this.header, this.valueFor);
}

class _ExportRowSummary {
  final int rowCount;
  final double basicAmount;
  final double applicableAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double tdsDifference;
  final double amountDifference;
  final int nonMatchedRows;
  final int applicableButNo26QRows;
  final Map<String, int> statusCounts;

  const _ExportRowSummary._({
    required this.rowCount,
    required this.basicAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.tdsDifference,
    required this.amountDifference,
    required this.nonMatchedRows,
    required this.applicableButNo26QRows,
    required this.statusCounts,
  });

  factory _ExportRowSummary.fromRows(
    Iterable<ReconciliationRow> rows, {
    bool includeStatusCounts = false,
    bool includeDerivedCounts = false,
  }) {
    var rowCount = 0;
    var basicAmount = 0.0;
    var applicableAmount = 0.0;
    var tds26QAmount = 0.0;
    var expectedTds = 0.0;
    var actualTds = 0.0;
    var tdsDifference = 0.0;
    var amountDifference = 0.0;
    var nonMatchedRows = 0;
    var applicableButNo26QRows = 0;
    final statusCounts = includeStatusCounts ? <String, int>{} : null;

    for (final row in rows) {
      rowCount++;
      basicAmount += row.basicAmount;
      applicableAmount += row.applicableAmount;
      tds26QAmount += row.tds26QAmount;
      expectedTds += row.expectedTds;
      actualTds += row.actualTds;
      tdsDifference += row.tdsDifference;
      amountDifference += row.amountDifference;
      if (includeDerivedCounts && row.status != ReconciliationStatus.matched) {
        nonMatchedRows++;
      }
      if (includeDerivedCounts &&
          row.applicableAmount > 0 &&
          row.tds26QAmount == 0 &&
          row.actualTds == 0) {
        applicableButNo26QRows++;
      }
      if (statusCounts != null) {
        statusCounts[row.status] = (statusCounts[row.status] ?? 0) + 1;
      }
    }

    return _ExportRowSummary._(
      rowCount: rowCount,
      basicAmount: basicAmount,
      applicableAmount: applicableAmount,
      tds26QAmount: tds26QAmount,
      expectedTds: expectedTds,
      actualTds: actualTds,
      tdsDifference: tdsDifference,
      amountDifference: amountDifference,
      nonMatchedRows: nonMatchedRows,
      applicableButNo26QRows: applicableButNo26QRows,
      statusCounts: statusCounts ?? const <String, int>{},
    );
  }

  int statusCount(String status) => statusCounts[status] ?? 0;
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
