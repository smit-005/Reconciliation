import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/upload/models/import_audit_record.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

void main() {
  group('ExcelService import audit generation', () {
    test('generic ledger parsing records exception-first audit events', () {
      final bytes = _buildWorkbook(
        sheetName: 'Ledger',
        rows: const [
          ['Date', 'Party', 'Debit', 'Narration', 'Ref'],
          ['2024-04-10', 'Vendor A', 1000, 'Main txn', 'INV-1'],
          ['', '', '', 'extra line', ''],
          ['2024-04-11', '', '', '', ''],
          ['1900-01-31', 'Vendor B', 500, 'Placeholder txn', 'INV-2'],
          ['2024-04-10', 'Vendor A', 1000, 'Main txn', 'INV-1'],
          ['', '', '', '', ''],
        ],
      );

      final result = ExcelService.parseGenericLedgerRowsWithAudit(
        bytes,
        sourceFileName: 'ledger.xlsx',
        defaultSection: '194C',
        sheetName: 'Ledger',
        headerRowIndex: 0,
        headersTrusted: true,
        columnMapping: const {
          'date': 'Date',
          'party_name': 'Party',
          'amount': 'Debit',
          'description': 'Narration',
          'bill_no': 'Ref',
        },
      );

      expect(result.rows, hasLength(2));
      expect(result.rows.first.description, contains('extra line'));

      final reasons = result.auditRecords
          .map((record) => record.reason)
          .toList();
      expect(reasons, contains(ImportAuditReason.continuationMerged));
      expect(reasons, contains(ImportAuditReason.invalidRowSkipped));
      expect(reasons, contains(ImportAuditReason.suspiciousReviewNote));
      expect(reasons, contains(ImportAuditReason.duplicateIgnored));
      expect(reasons, contains(ImportAuditReason.emptyRowIgnored));

      final continuation = result.auditRecords.firstWhere(
        (record) => record.reason == ImportAuditReason.continuationMerged,
      );
      expect(continuation.sourceFileName, 'ledger.xlsx');
      expect(continuation.sheetName, 'Ledger');
      expect(continuation.rowNumber, 3);
      expect(continuation.rowType, ImportAuditRowType.ledgerSource);
      expect(continuation.sectionBucket, '194C');

      final suspicious = result.auditRecords.firstWhere(
        (record) => record.reason == ImportAuditReason.suspiciousReviewNote,
      );
      expect(suspicious.rowNumber, 5);
      expect(suspicious.sectionBucket, '194C');

      final blankRows = result.auditRecords
          .where((record) => record.reason.isSecondary)
          .toList();
      expect(blankRows, hasLength(1));
      expect(blankRows.single.rowNumber, 7);
    });

    test('purchase parsing records duplicate ignored audit rows', () {
      final bytes = _buildWorkbook(
        sheetName: 'Purchase',
        rows: const [
          ['Date', 'Bill No', 'Party', 'Basic', 'Bill'],
          ['2024-04-01', 'B-1', 'Vendor A', 1000, 1000],
          ['2024-04-01', 'B-1', 'Vendor A', 1000, 1000],
        ],
      );

      final result = ExcelService.parsePurchaseRowsWithAudit(
        bytes,
        sourceFileName: 'purchase.xlsx',
        sheetName: 'Purchase',
        headerRowIndex: 0,
        headersTrusted: true,
        columnMapping: const {
          'date': 'Date',
          'bill_no': 'Bill No',
          'party_name': 'Party',
          'basic_amount': 'Basic',
          'bill_amount': 'Bill',
        },
      );

      expect(result.rows, hasLength(1));
      final duplicate = result.auditRecords.singleWhere(
        (record) => record.reason == ImportAuditReason.duplicateIgnored,
      );
      expect(duplicate.sourceFileName, 'purchase.xlsx');
      expect(duplicate.sheetName, 'Purchase');
      expect(duplicate.rowNumber, 3);
      expect(duplicate.rowType, ImportAuditRowType.ledgerSource);
      expect(duplicate.sectionBucket, '194Q');
    });

    test('26Q parsing records duplicate ignored audit rows', () {
      final bytes = _buildWorkbook(
        sheetName: '26Q',
        rows: const [
          ['Month', 'Deductee', 'PAN', 'Amount', 'TDS', 'Section'],
          ['Apr-2024', 'Vendor A', 'ABCDE1234F', 1000, 100, '194C'],
          ['Apr-2024', 'Vendor A', 'ABCDE1234F', 1000, 100, '194C'],
        ],
      );

      final result = ExcelService.parseTds26QRowsWithAudit(
        bytes,
        sourceFileName: '26q.xlsx',
        sheetName: '26Q',
        headerRowIndex: 0,
        headersTrusted: true,
        columnMapping: const {
          'date_month': 'Month',
          'party_name': 'Deductee',
          'pan_number': 'PAN',
          'amount_paid': 'Amount',
          'tds_amount': 'TDS',
          'section': 'Section',
        },
      );

      expect(result.rows, hasLength(1));
      final duplicate = result.auditRecords.singleWhere(
        (record) => record.reason == ImportAuditReason.duplicateIgnored,
      );
      expect(duplicate.sourceFileName, '26q.xlsx');
      expect(duplicate.sheetName, '26Q');
      expect(duplicate.rowNumber, 3);
      expect(duplicate.rowType, ImportAuditRowType.tds26q);
      expect(duplicate.sectionBucket, isEmpty);
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
