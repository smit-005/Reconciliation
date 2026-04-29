import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

void main() {
  group('ExcelService generic ledger mapping', () {
    test(
      'generic ledger with Date Party Name and Amount maps all 3 correctly',
      () {
        final bytes = _buildWorkbook(
          sheetName: 'Ledger',
          rows: const [
            ['Date', 'Party Name', 'Amount'],
            ['2024-04-01', 'Vendor A', 1200],
            ['2024-04-02', 'Vendor B', 1800],
          ],
        );

        final validation = ExcelService.validateGenericLedgerFile(bytes);

        expect(validation.isValid, isTrue);
        expect(validation.decision, ExcelImportDecision.autoImport);
        expect(validation.mappedColumns, containsPair('Date', 'date'));
        expect(
          validation.mappedColumns,
          containsPair('Party Name', 'party_name'),
        );
        expect(validation.mappedColumns, containsPair('Amount', 'amount'));
      },
    );

    test('amount never maps to Party Name', () {
      final bytes = _buildWorkbook(
        sheetName: 'Ledger',
        rows: const [
          ['Date', 'Party Name', 'Narration'],
          ['2024-04-01', 'Vendor A', 'Invoice one'],
          ['2024-04-02', 'Vendor B', 'Invoice two'],
        ],
      );

      final validation = ExcelService.validateGenericLedgerFile(bytes);

      expect(validation.decision, ExcelImportDecision.manualReview);
      expect(validation.mappedColumns['Party Name'], 'party_name');
      expect(
        validation.mappedColumns.entries.any(
          (entry) => entry.key == 'Party Name' && entry.value == 'amount',
        ),
        isFalse,
      );
    });

    test('low-confidence amount mapping becomes review required', () {
      final bytes = _buildWorkbook(
        sheetName: 'Ledger',
        rows: const [
          ['Date', 'Party Name', 'Value'],
          ['2024-04-01', 'Vendor A', 1200],
          ['2024-04-02', 'Vendor B', 1800],
        ],
      );

      final validation = ExcelService.validateGenericLedgerFile(bytes);

      expect(validation.isValid, isTrue);
      expect(validation.decision, ExcelImportDecision.manualReview);
      expect(validation.requiresManualMapping, isTrue);
    });

    test(
      'generic ledger rejects party bill number and tds amount false positives',
      () {
        final bytes = _buildWorkbook(
          sheetName: 'Ledger',
          rows: const [
            [
              'Date',
              'Party Bill No',
              'Party Name',
              'TDS Amount',
              'Gross Amount',
            ],
            ['2024-04-01', 'PB-1001', 'Vendor A', 120, 1200],
            ['2024-04-02', 'PB-1002', 'Vendor B', 180, 1800],
          ],
        );

        final validation = ExcelService.validateGenericLedgerFile(bytes);

        expect(validation.isValid, isTrue);
        expect(validation.decision, ExcelImportDecision.autoImport);
        expect(
          validation.mappedColumns,
          containsPair('Party Name', 'party_name'),
        );
        expect(
          validation.mappedColumns,
          containsPair('Gross Amount', 'amount'),
        );
        expect(validation.mappedColumns['Party Bill No'], isNot('party_name'));
        expect(
          validation.mappedColumns.entries.any(
            (entry) => entry.key == 'TDS Amount' && entry.value == 'amount',
          ),
          isFalse,
        );
      },
    );

    test('seller-like alphabetic header is rejected as amount candidate', () {
      final bytes = _buildWorkbook(
        sheetName: 'Ledger',
        rows: const [
          ['Date', 'Party Name', 'L. A. CREATIONS - MORBI'],
          ['2024-04-01', 'Vendor A', 1200],
          ['2024-04-02', 'Vendor B', 1800],
        ],
      );

      final validation = ExcelService.validateGenericLedgerFile(bytes);

      expect(validation.isValid, isTrue);
      expect(validation.decision, ExcelImportDecision.manualReview);
      expect(
        validation.mappedColumns.entries.any(
          (entry) =>
              entry.key == 'L. A. CREATIONS - MORBI' &&
              entry.value == 'amount',
        ),
        isFalse,
      );
    });

    test('multi-row ledger prefers gross amount over tds amount', () {
      final bytes = _buildWorkbook(
        sheetName: 'Ledger',
        rows: const [
          ['ABC Traders Pvt Ltd'],
          ['FY 2024-25'],
          [],
          ['Prepared for review'],
          ['Date', 'Party Name', 'TDS Amount', 'Gross Amount'],
          ['2024-04-01', 'Vendor A', 120, 1200],
          ['2024-04-02', 'Vendor B', 180, 1800],
        ],
      );

      final validation = ExcelService.validateGenericLedgerFile(bytes);

      expect(validation.isValid, isTrue);
      expect(validation.decision, ExcelImportDecision.autoImport);
      expect(validation.headerRowIndex, 4);
      expect(validation.mappedColumns, containsPair('Gross Amount', 'amount'));
      expect(
        validation.mappedColumns.entries.any(
          (entry) => entry.key == 'TDS Amount' && entry.value == 'amount',
        ),
        isFalse,
      );
    });
  });
}

Uint8List _buildWorkbook({
  required String sheetName,
  required List<List<Object?>> rows,
}) {
  final workbook = xlsio.Workbook();
  try {
    final sheet = workbook.worksheets[0];
    sheet.name = sheetName;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        final value = row[columnIndex];
        if (value == null) continue;

        final cell = sheet.getRangeByIndex(rowIndex + 1, columnIndex + 1);
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }
      }
    }

    return Uint8List.fromList(workbook.saveAsStream());
  } finally {
    workbook.dispose();
  }
}
