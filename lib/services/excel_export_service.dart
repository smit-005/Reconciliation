import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../models/reconciliation_row.dart';
import 'reconciliation_service.dart';

class ExcelExportService {
  static const double _thresholdAmount = 5000000;

  static Future<String> exportReconciliationExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
    String? sellerName,
  }) async {
    final workbook = xlsio.Workbook();

    try {
      final detailSheet = workbook.worksheets[0];
      detailSheet.name = 'Reconciliation';

      _writeTitle(
        detailSheet,
        buyerName.isEmpty ? 'RECONCILIATION REPORT' : buyerName.toUpperCase(),
      );

      _writeSummarySection(
        detailSheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );

      _writeDetailTable(
        detailSheet,
        rows: rows,
        startRow: 8,
      );

      final summarySheet = workbook.worksheets.addWithName('Summary');
      _writeCompactSummarySheet(
        summarySheet,
        rows: rows,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );

      final pivotSheet = workbook.worksheets.addWithName('Pivot Summary');
      _writePivotSummarySheet(
        pivotSheet,
        rows: rows,
      );

      final sectionGrouped = _groupBySection(rows);

      final sectionSummarySheet =
      workbook.worksheets.addWithName('Section Summary');
      _writeSectionSummarySheet(
        sectionSummarySheet,
        grouped: sectionGrouped,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );

      final sortedSections = sectionGrouped.keys.toList()..sort();
      for (final section in sortedSections) {
        final sectionRows = sectionGrouped[section]!;
        final cleanSection = section.trim().toUpperCase();

        if (cleanSection == 'NO SECTION') continue;

        final safeName = _safeSheetName(cleanSection);

        final sheet = workbook.worksheets.addWithName(safeName);

        _writeTitle(sheet, 'SECTION: $section');
        _writeSummarySection(
          sheet,
          rows: sectionRows,
          buyerName: buyerName,
          buyerPan: buyerPan,
          gstNo: gstNo,
        );
        _writeDetailTable(
          sheet,
          rows: sectionRows,
          startRow: 8,
        );
      }

      final infoSheet = workbook.worksheets.addWithName('TDS Section Info');
      _writeTdsSectionInfoSheet(infoSheet);

      final bytes = workbook.saveAsStream();
      final fileName = _buildExportFileName(
        buyerName: buyerName,
        sellerName: sellerName,
        financialYear: financialYear,
        isPivot: false,
      );

      final folderPath = outputFolderPath ?? _getDownloadsPath();
      final fullPath = p.join(folderPath, fileName);

      final file = File(fullPath);
      await file.writeAsBytes(bytes, flush: true);

      return fullPath;
    } finally {
      workbook.dispose();
    }
  }

  static Future<String> exportPivotSummaryExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    required String buyerPan,
    String gstNo = '',
    String? outputFolderPath,
    String? financialYear,
    String? sellerName,
  }) async {
    final workbook = xlsio.Workbook();

    try {
      final pivotSheet = workbook.worksheets[0];
      pivotSheet.name = 'Pivot Summary';

      _writePivotSummarySheet(
        pivotSheet,
        rows: rows,
        title: 'PIVOT SUMMARY: ${buyerName.toUpperCase()}',
      );

      final sectionGrouped = _groupBySection(rows);

      final sortedSections = sectionGrouped.keys.toList()..sort();

      for (final section in sortedSections) {
        final sectionRows = sectionGrouped[section]!;

        final cleanSection = section.trim().toUpperCase();
        if (cleanSection == 'NO SECTION') continue;

        final safeName = _safeSheetName(cleanSection);

        final sheet = workbook.worksheets.addWithName(safeName);

        _writePivotSummarySheet(
          sheet,
          rows: sectionRows,
          title: 'SECTION $cleanSection - ${buyerName.toUpperCase()}',
        );
      }

      final sectionSummarySheet =
      workbook.worksheets.addWithName('Section Summary');

      _writeSectionSummarySheet(
        sectionSummarySheet,
        grouped: sectionGrouped,
        buyerName: buyerName,
        buyerPan: buyerPan,
        gstNo: gstNo,
      );

      final infoSheet = workbook.worksheets.addWithName('TDS Section Info');
      _writeTdsSectionInfoSheet(infoSheet);

      final bytes = workbook.saveAsStream();
      final fileName = _buildExportFileName(
        buyerName: buyerName,
        sellerName: sellerName,
        financialYear: financialYear,
        isPivot: true,
      );

      final folderPath = outputFolderPath ?? _getDownloadsPath();
      final fullPath = p.join(folderPath, fileName);

      final file = File(fullPath);
      await file.writeAsBytes(bytes, flush: true);

      return fullPath;
    } finally {
      workbook.dispose();
    }
  }

  static Map<String, List<ReconciliationRow>> _groupBySection(
      List<ReconciliationRow> rows,
      ) {
    final grouped = <String, List<ReconciliationRow>>{};

    for (final row in rows) {
      final section = _normalizeSection(row.section);
      grouped.putIfAbsent(section, () => []);
      grouped[section]!.add(row);
    }

    return grouped;
  }

  static void _writeTitle(xlsio.Worksheet sheet, String title) {
    sheet.getRangeByName('A1:Q1').merge();
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

    sheet.getRangeByName('A3').setText('Buyer Name');
    sheet.getRangeByName('B3').setText(buyerName.isEmpty ? '-' : buyerName);

    sheet.getRangeByName('D3').setText('Buyer PAN');
    sheet.getRangeByName('E3').setText(buyerPan.isEmpty ? '-' : buyerPan);

    sheet.getRangeByName('G3').setText('GST No');
    sheet.getRangeByName('H3').setText(gstNo.isEmpty ? '-' : gstNo);

    sheet.getRangeByName('A4').setText('Threshold');
    sheet.getRangeByName('B4').setNumber(_thresholdAmount);

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
      'TDS Difference',
      'Amount Difference',
      'Status',
      'Risk Level',
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

    sheet.autoFilters.filterRange =
        sheet.getRangeByIndex(startRow, 1, startRow, headers.length);

    int rowIndex = startRow + 1;

    for (final row in rows) {
      sheet.getRangeByIndex(rowIndex, 1).setText(row.buyerName);
      sheet.getRangeByIndex(rowIndex, 2).setText(row.buyerPan);
      sheet.getRangeByIndex(rowIndex, 3).setText(row.financialYear);
      sheet.getRangeByIndex(rowIndex, 4).setText(row.month);
      sheet.getRangeByIndex(rowIndex, 5).setText(_normalizeSection(row.section));
      sheet.getRangeByIndex(rowIndex, 6).setText(row.sellerName);
      sheet.getRangeByIndex(rowIndex, 7).setText(row.sellerPan);
      sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(row.basicAmount));
      sheet.getRangeByIndex(rowIndex, 9).setNumber(_round2(row.applicableAmount));
      sheet.getRangeByIndex(rowIndex, 10).setNumber(_round2(row.tds26QAmount));
      sheet.getRangeByIndex(rowIndex, 11).setNumber(_round2(row.expectedTds));
      sheet.getRangeByIndex(rowIndex, 12).setNumber(_round2(row.actualTds));
      sheet.getRangeByIndex(rowIndex, 13).setNumber(_round2(row.tdsDifference));
      sheet.getRangeByIndex(rowIndex, 14).setNumber(_round2(row.amountDifference));
      sheet.getRangeByIndex(rowIndex, 15).setText(row.status);
      sheet.getRangeByIndex(rowIndex, 16).setText(getRiskLevel(row.status));
      sheet.getRangeByIndex(rowIndex, 17).setText(
        row.remarks.trim().isEmpty ? '-' : row.remarks,
      );

      final rowRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 17);
      rowRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

      if (row.status == 'Matched') {
        rowRange.cellStyle.backColor = '#E8F5E9';
      } else if (row.status == 'Timing Difference') {
        rowRange.cellStyle.backColor = '#E3F2FD';
      } else if (row.status == 'Short Deduction') {
        rowRange.cellStyle.backColor = '#FFF3E0';
      } else if (row.status == 'Excess Deduction') {
        rowRange.cellStyle.backColor = '#FFEBEE';
      } else if (row.status == 'Purchase Only') {
        rowRange.cellStyle.backColor = '#EAF3FF';
      } else if (row.status == '26Q Only') {
        rowRange.cellStyle.backColor = '#F3E5F5';
      } else {
        rowRange.cellStyle.backColor = '#FFF0F0';
      }

      rowIndex++;
    }

    sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
    sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;

    sheet.getRangeByIndex(rowIndex, 8).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.basicAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 9).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.applicableAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 10).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.tds26QAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 11).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.expectedTds)),
    );
    sheet.getRangeByIndex(rowIndex, 12).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.actualTds)),
    );
    sheet.getRangeByIndex(rowIndex, 13).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.tdsDifference)),
    );
    sheet.getRangeByIndex(rowIndex, 14).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.amountDifference)),
    );

    final totalRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 17);
    totalRange.cellStyle.bold = true;
    totalRange.cellStyle.backColor = '#FFF3CD';
    totalRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    _applyNumberFormat(
      sheet,
      startRow + 1,
      rowIndex,
      [8, 9, 10, 11, 12, 13, 14],
    );
    _autoFitUsefulColumns(sheet, 17);
  }

  static void _writeCompactSummarySheet(
      xlsio.Worksheet sheet, {
        required List<ReconciliationRow> rows,
        required String buyerName,
        required String buyerPan,
        required String gstNo,
      }) {
    sheet.getRangeByName('A1:H1').merge();
    sheet.getRangeByName('A1').setText('Reconciliation Summary');
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

    final labels = [
      'Buyer Name',
      'Buyer PAN',
      'GST No',
      'Threshold',
      'Total Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
      'Matched Rows',
      'Timing Difference Rows',
      'Short Deduction Rows',
      'Excess Deduction Rows',
      'Purchase Only Rows',
      '26Q Only Rows',
      'Applicable but no 26Q',
    ];

    final values = [
      buyerName.isEmpty ? '-' : buyerName,
      buyerPan.isEmpty ? '-' : buyerPan,
      gstNo.isEmpty ? '-' : gstNo,
      _thresholdAmount.toStringAsFixed(2),
      totalBasic.toStringAsFixed(2),
      totalApplicable.toStringAsFixed(2),
      total26QAmount.toStringAsFixed(2),
      totalExpectedTds.toStringAsFixed(2),
      totalActualTds.toStringAsFixed(2),
      totalTdsDifference.toStringAsFixed(2),
      totalAmountDifference.toStringAsFixed(2),
      rows.where((e) => e.status == 'Matched').length.toString(),
      rows.where((e) => e.status == 'Timing Difference').length.toString(),
      rows.where((e) => e.status == 'Short Deduction').length.toString(),
      rows.where((e) => e.status == 'Excess Deduction').length.toString(),
      rows.where((e) => e.status == 'Purchase Only').length.toString(),
      rows.where((e) => e.status == '26Q Only').length.toString(),
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
    sheet.getRangeByName('A1:J1').merge();
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
      'Rows',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Expected TDS',
      'Actual TDS',
      'TDS Difference',
      'Amount Difference',
      'Mismatch Rows',
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
      sheet.getRangeByIndex(rowIndex, 2).setNumber(rows.length.toDouble());
      sheet.getRangeByIndex(rowIndex, 3)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.basicAmount)));
      sheet.getRangeByIndex(rowIndex, 4)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.applicableAmount)));
      sheet.getRangeByIndex(rowIndex, 5)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.tds26QAmount)));
      sheet.getRangeByIndex(rowIndex, 6)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.expectedTds)));
      sheet.getRangeByIndex(rowIndex, 7)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.actualTds)));
      sheet.getRangeByIndex(rowIndex, 8)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.tdsDifference)));
      sheet.getRangeByIndex(rowIndex, 9)
          .setNumber(_round2(rows.fold(0.0, (s, r) => s + r.amountDifference)));
      sheet.getRangeByIndex(rowIndex, 10).setNumber(
        rows.where((e) => e.status != 'Matched').length.toDouble(),
      );

      final rowRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
      rowRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

      rowIndex++;
    }

    _applyNumberFormat(sheet, startRow + 1, rowIndex - 1, [3, 4, 5, 6, 7, 8, 9]);
    _autoFitUsefulColumns(sheet, 10);
  }

  static void _writeTdsSectionInfoSheet(xlsio.Worksheet sheet) {
    final headers = [
      'Section',
      'Nature of Payment',
      'Limit / Threshold',
      'Rate of TDS',
      'Who Deducts? (Payer)',
    ];

    final data = [
      [
        '194Q',
        'Purchase of Goods',
        'Exceeding ₹50 Lakhs in FY',
        '0.1% (5% if no PAN)',
        'Buyer > ₹10 Cr Turnover',
      ],
      [
        '194C',
        'Payment to Contractors',
        'Single > ₹30k / Annual > ₹1L',
        '1% (Ind/HUF) / 2% (Other)',
        'Any payer',
      ],
      [
        '194J',
        'Professional/Tech Services',
        'Exceeding ₹30,000',
        '2% / 10%',
        'Any payer',
      ],
      [
        '194I',
        'Rent (Plant & Machinery)',
        'Exceeding ₹2.4 Lakhs',
        '2%',
        'Any payer',
      ],
      [
        '194I',
        'Rent (Land & Building)',
        'Exceeding ₹2.4 Lakhs',
        '10%',
        'Any payer',
      ],
      [
        '194H',
        'Commission/Brokerage',
        'Exceeding ₹15,000',
        '5%',
        'Any payer',
      ],
    ];

    sheet.getRangeByName('A1:E1').merge();
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
      for (int j = 0; j < data[i].length; j++) {
        final cell = sheet.getRangeByIndex(i + 4, j + 1);
        cell.setText(data[i][j]);
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      }
    }

    _autoFitUsefulColumns(sheet, 5);
  }

  static void _writePivotSummarySheet(
      xlsio.Worksheet sheet, {
        required List<ReconciliationRow> rows,
        String? title,
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

    sheet.getRangeByName('A1:J1').merge();
    sheet.getRangeByName('A1').setText(
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

    sheet.getRangeByName('A2:J2').merge();
    sheet.getRangeByName('A2').setText(
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

      sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).merge();
      sheet.getRangeByIndex(rowIndex, 1).setText(seller.toUpperCase());
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.fontSize = 15;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign = xlsio.HAlignType.left;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.vAlign = xlsio.VAlignType.center;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#E2EFDA';
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.borders.all.lineStyle =
          xlsio.LineStyle.thin;
      sheet.getRangeByIndex(rowIndex, 1).rowHeight = 24;
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

        sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).merge();
        sheet.getRangeByIndex(rowIndex, 1).setText('FY $fy');
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.fontSize = 12;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign = xlsio.HAlignType.left;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#EDEDED';
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.borders.all.lineStyle =
            xlsio.LineStyle.thin;
        rowIndex++;

        _writePivotHeader(sheet, rowIndex);
        rowIndex++;

        for (final r in fyRows) {
          sheet.getRangeByIndex(rowIndex, 1).setText(r.month);
          sheet.getRangeByIndex(rowIndex, 2).setNumber(_round2(r.basicAmount));
          sheet.getRangeByIndex(rowIndex, 3).setNumber(_round2(r.applicableAmount));
          sheet.getRangeByIndex(rowIndex, 4).setNumber(_round2(r.tds26QAmount));
          sheet.getRangeByIndex(rowIndex, 5).setNumber(_round2(r.amountDifference));
          sheet.getRangeByIndex(rowIndex, 6).setNumber(_round2(r.expectedTds));
          sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(r.actualTds));
          sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(r.tdsDifference));
          sheet.getRangeByIndex(rowIndex, 9).setText(r.status);
          sheet.getRangeByIndex(rowIndex, 10)
              .setText(r.remarks.trim().isEmpty ? '-' : r.remarks);

          final range = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
          sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).rowHeight = 20;
          if (r.status == 'Matched') {
            range.cellStyle.backColor = '#E2F0D9';
          } else if (r.status == 'Short Deduction') {
            range.cellStyle.backColor = '#FCE4D6';
          } else if (r.status == 'Excess Deduction') {
            range.cellStyle.backColor = '#F4CCCC';
          } else if (r.status == 'Timing Difference') {
            range.cellStyle.backColor = '#DDEBF7';
          } else if (r.status == 'Purchase Only') {
            range.cellStyle.backColor = '#EAF3FF';
          } else if (r.status == '26Q Only') {
            range.cellStyle.backColor = '#F1E6FF';
          } else {
            range.cellStyle.backColor = '#F5F5F5';
          }

          range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
          range.cellStyle.vAlign = xlsio.VAlignType.center;

          for (int col = 2; col <= 8; col++) {
            sheet.getRangeByIndex(rowIndex, col).cellStyle.hAlign =
                xlsio.HAlignType.right;
          }

          sheet.getRangeByIndex(rowIndex, 1).cellStyle.hAlign =
              xlsio.HAlignType.left;
          sheet.getRangeByIndex(rowIndex, 9).cellStyle.hAlign =
              xlsio.HAlignType.center;
          sheet.getRangeByIndex(rowIndex, 10).cellStyle.hAlign =
              xlsio.HAlignType.left;

          if (r.tdsDifference < 0) {
            sheet.getRangeByIndex(rowIndex, 8).cellStyle.fontColor = '#FF0000';
          } else if (r.tdsDifference > 0) {
            sheet.getRangeByIndex(rowIndex, 8).cellStyle.fontColor = '#008000';
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
        sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(fyTdsDiff));

        final totalRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
        totalRange.cellStyle.bold = true;
        totalRange.cellStyle.fontSize = 11;
        totalRange.cellStyle.backColor = '#FFF2CC';
        totalRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).rowHeight = 22;

        for (int col = 2; col <= 8; col++) {
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
    sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(grandTdsDiff));

    final grandRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
    grandRange.cellStyle.bold = true;
    grandRange.cellStyle.fontSize = 12;
    grandRange.cellStyle.backColor = '#FFD966';
    grandRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).rowHeight = 24;

    for (int col = 2; col <= 8; col++) {
      sheet.getRangeByIndex(rowIndex, col).cellStyle.hAlign =
          xlsio.HAlignType.right;
    }

    _applyNumberFormat(sheet, 1, rowIndex, [2, 3, 4, 5, 6, 7, 8]);
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

  static void _writePivotHeader(xlsio.Worksheet sheet, int row) {
    final headers = [
      'Month',
      'Basic Amount',
      'Applicable Amount',
      '26Q Amount',
      'Amount Diff',
      'Expected TDS',
      'Actual TDS',
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
    sheet.setColumnWidthInPixels(1, 100);  // Month
    sheet.setColumnWidthInPixels(2, 105);  // Basic
    sheet.setColumnWidthInPixels(3, 115);  // Applicable
    sheet.setColumnWidthInPixels(4, 100);  // 26Q
    sheet.setColumnWidthInPixels(5, 95);   // Amt Diff
    sheet.setColumnWidthInPixels(6, 100);  // Exp TDS
    sheet.setColumnWidthInPixels(7, 95);   // Actual TDS
    sheet.setColumnWidthInPixels(8, 90);   // TDS Diff
    sheet.setColumnWidthInPixels(9, 130);  // Status
    sheet.setColumnWidthInPixels(10, 280); // Remarks
  }

  static String getRiskLevel(String status) {
    switch (status) {
      case 'Applicable but no 26Q':
      case 'Section Missing':
        return 'HIGH';
      case 'Short Deduction':
      case '26Q Only':
      case 'Purchase Only':
        return 'MEDIUM';
      case 'Excess Deduction':
      case 'Timing Difference':
        return 'LOW';
      case 'Matched':
      default:
        return 'OK';
    }
  }

  static List<String> getUniqueSections(List<ReconciliationRow> rows) {
    final sections = rows
        .map((e) => _normalizeSection(e.section))
        .where((e) => e.isNotEmpty && e.toUpperCase() != 'NO SECTION')
        .toSet()
        .toList()
      ..sort();
    return sections;
  }

  static String _normalizeSection(String value) {
    final section = value.trim();
    if (section.isEmpty || section == '-') return 'No Section';
    return section;
  }

  static void _applyNumberFormat(
      xlsio.Worksheet sheet,
      int fromRow,
      int toRow,
      List<int> columns,
      ) {
    for (final col in columns) {
      sheet.getRangeByIndex(fromRow, col, toRow, col).numberFormat = '#,##0.00';
    }
  }

  static void _autoFitUsefulColumns(xlsio.Worksheet sheet, int totalColumns) {
    for (int col = 1; col <= totalColumns; col++) {
      sheet.autoFitColumn(col);
    }
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

  static String _buildExportFileName({
    required String buyerName,
    String? sellerName,
    String? financialYear,
    required bool isPivot,
  }) {
    final safeBuyerName = _safeFileName(
      buyerName.isEmpty ? 'buyer' : buyerName,
    );

    final hasSeller = sellerName != null &&
        sellerName.trim().isNotEmpty &&
        sellerName.trim() != 'All Sellers';

    final hasFy = financialYear != null &&
        financialYear.trim().isNotEmpty &&
        financialYear.trim() != 'All FY';

    String fileName;

    if (isPivot) {
      if (hasSeller && hasFy) {
        fileName =
        '${safeBuyerName}_pivot_${_safeFileName(sellerName!.trim())}_${_safeFileName(financialYear!.trim())}.xlsx';
      } else if (hasFy) {
        fileName =
        '${safeBuyerName}_pivot_${_safeFileName(financialYear!.trim())}.xlsx';
      } else if (hasSeller) {
        fileName =
        '${safeBuyerName}_pivot_${_safeFileName(sellerName!.trim())}.xlsx';
      } else {
        fileName = '${safeBuyerName}_pivot_summary.xlsx';
      }
    } else {
      if (hasSeller && hasFy) {
        fileName =
        '${safeBuyerName}_${_safeFileName(sellerName!.trim())}_${_safeFileName(financialYear!.trim())}.xlsx';
      } else if (hasFy) {
        fileName =
        '${safeBuyerName}_${_safeFileName(financialYear!.trim())}.xlsx';
      } else if (hasSeller) {
        fileName =
        '${safeBuyerName}_${_safeFileName(sellerName!.trim())}.xlsx';
      } else {
        fileName = '${safeBuyerName}_reconciliation.xlsx';
      }
    }

    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    return fileName.replaceAll('.xlsx', '_$timestamp.xlsx');
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