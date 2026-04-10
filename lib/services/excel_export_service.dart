import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../core/utils/calculation.dart';

class ExcelExportService {
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

    final detailSheet = workbook.worksheets[0];
    detailSheet.name = 'Reconciliation';

    _writeTitle(detailSheet, buyerName);
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

    final bytes = workbook.saveAsStream();
    workbook.dispose();

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

    if (hasSeller && hasFy) {
      fileName =
      '${safeBuyerName}_${_safeFileName(sellerName!.trim())}_${_safeFileName(financialYear!.trim())}.xlsx';
    } else if (hasFy) {
      fileName = '${safeBuyerName}_${_safeFileName(financialYear!.trim())}.xlsx';
    } else if (hasSeller) {
      fileName = '${safeBuyerName}_${_safeFileName(sellerName!.trim())}.xlsx';
    } else {
      fileName = '${safeBuyerName}_reconciliation.xlsx';
    }

    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    fileName = fileName.replaceAll('.xlsx', '_$timestamp.xlsx');

    final folderPath = outputFolderPath ?? _getDownloadsPath();
    final fullPath = p.join(folderPath, fileName);

    final file = File(fullPath);
    await file.writeAsBytes(bytes, flush: true);

    return fullPath;
  }

  static Future<String> exportPivotSummaryExcel({
    required List<ReconciliationRow> rows,
    required String buyerName,
    String? outputFolderPath,
    String? financialYear,
    String? sellerName,
  }) async {
    final workbook = xlsio.Workbook();

    final pivotSheet = workbook.worksheets[0];
    pivotSheet.name = 'Pivot Summary';

    _writePivotSummarySheet(
      pivotSheet,
      rows: rows,
    );

    final bytes = workbook.saveAsStream();
    workbook.dispose();

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

    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    fileName = fileName.replaceAll('.xlsx', '_$timestamp.xlsx');

    final folderPath = outputFolderPath ?? _getDownloadsPath();
    final fullPath = p.join(folderPath, fileName);

    final file = File(fullPath);
    await file.writeAsBytes(bytes, flush: true);

    return fullPath;
  }

  static String _getDownloadsPath() {
    final userProfile = Platform.environment['USERPROFILE'];

    if (userProfile != null && userProfile.isNotEmpty) {
      return '$userProfile\\Downloads';
    }

    return Directory.systemTemp.path;
  }

  static void _writeTitle(xlsio.Worksheet sheet, String buyerName) {
    sheet.getRangeByName('A1:O1').merge();
    sheet.getRangeByName('A1').setText(
      buyerName.isEmpty ? 'RECONCILIATION REPORT' : buyerName.toUpperCase(),
    );
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
    sheet.getRangeByName('B4').setNumber(5000000);

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
      'Remarks',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#D9EAF7';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
    }

    sheet.autoFilters.filterRange =
        sheet.getRangeByIndex(startRow, 1, startRow, headers.length);

    int rowIndex = startRow + 1;

    for (final row in rows) {
      sheet.getRangeByIndex(rowIndex, 1).setText(row.buyerName);
      sheet.getRangeByIndex(rowIndex, 2).setText(row.buyerPan);
      sheet.getRangeByIndex(rowIndex, 3).setText(row.financialYear);
      sheet.getRangeByIndex(rowIndex, 4).setText(row.month);
      sheet.getRangeByIndex(rowIndex, 5).setText(row.sellerName);
      sheet.getRangeByIndex(rowIndex, 6).setText(row.sellerPan);
      sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(row.basicAmount));
      sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(row.applicableAmount));
      sheet.getRangeByIndex(rowIndex, 9).setNumber(_round2(row.tds26QAmount));
      sheet.getRangeByIndex(rowIndex, 10).setNumber(_round2(row.expectedTds));
      sheet.getRangeByIndex(rowIndex, 11).setNumber(_round2(row.actualTds));
      sheet.getRangeByIndex(rowIndex, 12).setNumber(_round2(row.tdsDifference));
      sheet.getRangeByIndex(rowIndex, 13).setNumber(_round2(row.amountDifference));
      sheet.getRangeByIndex(rowIndex, 14).setText(row.status);
      sheet.getRangeByIndex(rowIndex, 15).setText(row.remarks.isEmpty ? '-' : row.remarks);

      final rowRange = sheet.getRangeByName('A$rowIndex:O$rowIndex');
      if (row.tdsDifference.abs() > 0.0 ||
          row.amountDifference.abs() > 0.0 ||
          row.status != 'Matched') {
        rowRange.cellStyle.backColor = '#FFF0F0';
      } else {
        rowRange.cellStyle.backColor = '#E8F5E9';
      }

      rowIndex++;
    }

    sheet.getRangeByIndex(rowIndex, 1).setText('TOTAL');
    sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;

    sheet.getRangeByIndex(rowIndex, 7).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.basicAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 8).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.applicableAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 9).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.tds26QAmount)),
    );
    sheet.getRangeByIndex(rowIndex, 10).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.expectedTds)),
    );
    sheet.getRangeByIndex(rowIndex, 11).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.actualTds)),
    );
    sheet.getRangeByIndex(rowIndex, 12).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.tdsDifference)),
    );
    sheet.getRangeByIndex(rowIndex, 13).setNumber(
      _round2(rows.fold(0.0, (sum, row) => sum + row.amountDifference)),
    );

    final totalRange = sheet.getRangeByName('A$rowIndex:O$rowIndex');
    totalRange.cellStyle.bold = true;
    totalRange.cellStyle.backColor = '#FFF3CD';

    _applyNumberFormat(sheet, startRow + 1, rowIndex, [7, 8, 9, 10, 11, 12, 13]);
    _autoFitUsefulColumns(sheet, 15);
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
      'Short Deduction Rows',
      'Excess Deduction Rows',
      'Purchase Only Rows',
      '26Q Only Rows',
    ];

    final values = [
      buyerName.isEmpty ? '-' : buyerName,
      buyerPan.isEmpty ? '-' : buyerPan,
      gstNo.isEmpty ? '-' : gstNo,
      '5000000',
      totalBasic.toStringAsFixed(2),
      totalApplicable.toStringAsFixed(2),
      total26QAmount.toStringAsFixed(2),
      totalExpectedTds.toStringAsFixed(2),
      totalActualTds.toStringAsFixed(2),
      totalTdsDifference.toStringAsFixed(2),
      totalAmountDifference.toStringAsFixed(2),
      rows.where((e) => e.status == 'Matched').length.toString(),
      rows.where((e) => e.status == 'Short Deduction').length.toString(),
      rows.where((e) => e.status == 'Excess Deduction').length.toString(),
      rows.where((e) => e.status == 'Purchase Only').length.toString(),
      rows.where((e) => e.status == '26Q Only').length.toString(),
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

// ===================== NEW PIVOT SUMMARY =====================

  static void _writePivotSummarySheet(
      xlsio.Worksheet sheet, {
        required List<ReconciliationRow> rows,
      }) {
    final sortedRows = List<ReconciliationRow>.from(rows)
      ..sort((a, b) {
        final sellerCompare = a.sellerName.compareTo(b.sellerName);
        if (sellerCompare != 0) return sellerCompare;

        final fyCompare = a.financialYear.compareTo(b.financialYear);
        if (fyCompare != 0) return fyCompare;

        return CalculationService.compareMonthLabels(a.month, b.month);
      });

    final grouped = _groupRows(sortedRows);

    // ===== HEADER =====
    sheet.getRangeByName('A1:J1').merge();
    sheet.getRangeByName('A1').setText(
      rows.isNotEmpty ? rows.first.buyerName.toUpperCase() : 'PIVOT SUMMARY',
    );
    sheet.getRangeByName('A1').cellStyle.bold = true;
    sheet.getRangeByName('A1').cellStyle.fontSize = 18;
    sheet.getRangeByName('A1').cellStyle.hAlign = xlsio.HAlignType.center;
    sheet.getRangeByName('A1').cellStyle.backColor = '#EDE7F6';

    int rowIndex = 3;

    double grandBasic = 0;
    double grandApplicable = 0;
    double grand26Q = 0;
    double grandExpected = 0;
    double grandActual = 0;
    double grandTdsDiff = 0;
    double grandAmtDiff = 0;

    for (final seller in grouped.keys) {
      final fyMap = grouped[seller]!;

      // ===== SELLER HEADER =====
      sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).merge();
      sheet.getRangeByIndex(rowIndex, 1).setText(seller.toUpperCase());
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.fontSize = 14;
      sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#D9EAD3';
      rowIndex++;

      for (final fy in fyMap.keys) {
        final rows = fyMap[fy]!;

        final fyBasic = rows.fold(0.0, (s, r) => s + r.basicAmount);
        final fyApplicable = rows.fold(0.0, (s, r) => s + r.applicableAmount);
        final fy26Q = rows.fold(0.0, (s, r) => s + r.tds26QAmount);
        final fyExpected = rows.fold(0.0, (s, r) => s + r.expectedTds);
        final fyActual = rows.fold(0.0, (s, r) => s + r.actualTds);
        final fyTdsDiff = rows.fold(0.0, (s, r) => s + r.tdsDifference);
        final fyAmtDiff = rows.fold(0.0, (s, r) => s + r.amountDifference);

        grandBasic += fyBasic;
        grandApplicable += fyApplicable;
        grand26Q += fy26Q;
        grandExpected += fyExpected;
        grandActual += fyActual;
        grandTdsDiff += fyTdsDiff;
        grandAmtDiff += fyAmtDiff;

        // ===== FY HEADER =====
        sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10).merge();
        sheet.getRangeByIndex(rowIndex, 1).setText("FY $fy");
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.bold = true;
        sheet.getRangeByIndex(rowIndex, 1).cellStyle.backColor = '#EEEEEE';
        rowIndex++;

        _writeHeader(sheet, rowIndex);
        rowIndex++;

        for (final r in rows) {
          sheet.getRangeByIndex(rowIndex, 1).setText(r.month);
          sheet.getRangeByIndex(rowIndex, 2).setNumber(_round2(r.basicAmount));
          sheet.getRangeByIndex(rowIndex, 3).setNumber(_round2(r.applicableAmount));
          sheet.getRangeByIndex(rowIndex, 4).setNumber(_round2(r.tds26QAmount));
          sheet.getRangeByIndex(rowIndex, 5).setNumber(_round2(r.amountDifference));
          sheet.getRangeByIndex(rowIndex, 6).setNumber(_round2(r.expectedTds));
          sheet.getRangeByIndex(rowIndex, 7).setNumber(_round2(r.actualTds));
          sheet.getRangeByIndex(rowIndex, 8).setNumber(_round2(r.tdsDifference));
          sheet.getRangeByIndex(rowIndex, 9).setText(r.status);
          sheet.getRangeByIndex(rowIndex, 10).setText(r.remarks);

          final range = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);

          // 🎯 COLOR LOGIC
          if (r.status == 'Matched') {
            range.cellStyle.backColor = '#E2F0D9';
          } else if (r.status == 'Short Deduction') {
            range.cellStyle.backColor = '#FCE4D6';
          } else if (r.status == 'Excess Deduction') {
            range.cellStyle.backColor = '#F4CCCC';
          } else if (r.status == 'Timing Difference') {
            range.cellStyle.backColor = '#DDEBF7';
          } else {
            range.cellStyle.backColor = '#F5F5F5';
          }

          // 🔴 NEGATIVE DIFF RED
          if (r.tdsDifference < 0) {
            sheet.getRangeByIndex(rowIndex, 8).cellStyle.fontColor = '#FF0000';
          }

          // 🟢 POSITIVE DIFF GREEN
          if (r.tdsDifference > 0) {
            sheet.getRangeByIndex(rowIndex, 8).cellStyle.fontColor = '#008000';
          }

          rowIndex++;
        }

        // ===== TOTAL ROW =====
        sheet.getRangeByIndex(rowIndex, 1).setText("TOTAL");
        sheet.getRangeByIndex(rowIndex, 2).setNumber(fyBasic);
        sheet.getRangeByIndex(rowIndex, 3).setNumber(fyApplicable);
        sheet.getRangeByIndex(rowIndex, 4).setNumber(fy26Q);
        sheet.getRangeByIndex(rowIndex, 5).setNumber(fyAmtDiff);
        sheet.getRangeByIndex(rowIndex, 6).setNumber(fyExpected);
        sheet.getRangeByIndex(rowIndex, 7).setNumber(fyActual);
        sheet.getRangeByIndex(rowIndex, 8).setNumber(fyTdsDiff);

        final totalRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
        totalRange.cellStyle.bold = true;
        totalRange.cellStyle.backColor = '#FFF2CC';

        rowIndex += 2;
      }
    }

    // ===== GRAND TOTAL =====
    sheet.getRangeByIndex(rowIndex, 1).setText("GRAND TOTAL");
    sheet.getRangeByIndex(rowIndex, 2).setNumber(grandBasic);
    sheet.getRangeByIndex(rowIndex, 3).setNumber(grandApplicable);
    sheet.getRangeByIndex(rowIndex, 4).setNumber(grand26Q);
    sheet.getRangeByIndex(rowIndex, 5).setNumber(grandAmtDiff);
    sheet.getRangeByIndex(rowIndex, 6).setNumber(grandExpected);
    sheet.getRangeByIndex(rowIndex, 7).setNumber(grandActual);
    sheet.getRangeByIndex(rowIndex, 8).setNumber(grandTdsDiff);

    final grandRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, 10);
    grandRange.cellStyle.bold = true;
    grandRange.cellStyle.backColor = '#FFD966';

    _autoFitPivot(sheet);
  }

// ===================== HELPERS =====================

  static Map<String, Map<String, List<ReconciliationRow>>> _groupRows(
      List<ReconciliationRow> rows) {
    final map = <String, Map<String, List<ReconciliationRow>>>{};

    for (final r in rows) {
      map.putIfAbsent(r.sellerName, () => {});
      map[r.sellerName]!.putIfAbsent(r.financialYear, () => []);
      map[r.sellerName]![r.financialYear]!.add(r);
    }

    return map;
  }

  static void _writeHeader(xlsio.Worksheet sheet, int row) {
    final headers = [
      'Month',
      'Product',
      'Applicable',
      'Deducted',
      'Diff',
      'App TDS',
      'Ded TDS',
      'TDS Diff',
      'Status',
      'Remarks'
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(row, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#BDD7EE';
    }
  }

  static void _autoFitPivot(xlsio.Worksheet sheet) {
    for (int i = 1; i <= 10; i++) {
      sheet.autoFitColumn(i);
    }
  }

  static void _applyNumberFormat(
      xlsio.Worksheet sheet,
      int fromRow,
      int toRow,
      List<int> columns,
      ) {
    for (final col in columns) {
      sheet
          .getRangeByIndex(fromRow, col, toRow, col)
          .numberFormat = '#,##0.00';
    }
  }

  static void _autoFitUsefulColumns(xlsio.Worksheet sheet, int totalColumns) {
    for (int col = 1; col <= totalColumns; col++) {
      sheet.autoFitColumn(col);
    }
  }

  static String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  static double _round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}