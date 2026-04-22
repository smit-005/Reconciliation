import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('26Q section handling in live reconciliation flow', () {
    test('explicit supported section is normalized from section field', () {
      final row = Tds26QRow.fromMap({
        'month': 'Apr-2024',
        'financial_year': '2024-25',
        'party_name': 'Acme Traders',
        'pan_number': 'ABCPD1234F',
        'amount_paid': 1000000,
        'tds_amount': 1000,
        'section': 'Section 194Q',
      });

      expect(row.section, '194Q');
      expect(row.normalizedSection, '194Q');
    });

    test('text-based extraction uses nature_of_payment when section is empty', () {
      final row = Tds26QRow.fromMap({
        'month': 'Apr-2024',
        'financial_year': '2024-25',
        'party_name': 'Acme Traders',
        'pan_number': 'ABCPD1234F',
        'amount_paid': 50000,
        'tds_amount': 500,
        'section': '',
        'nature_of_payment': 'Contract payment under section 194C',
      });

      expect(row.section, '194C');
      expect(row.normalizedSection, '194C');
    });

    test('empty section falls back to UNKNOWN in final reconciliation', () async {
      final result = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'ZZZZZ9999Z',
        sourceRows: const [],
        tdsRows: [
          Tds26QRow.fromMap({
            'month': 'Apr-2024',
            'financial_year': '2024-25',
            'party_name': 'Acme Traders',
            'pan_number': 'ABCPD1234F',
            'amount_paid': 50000,
            'tds_amount': 500,
            'section': '',
            'nature_of_payment': '',
          }),
        ],
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.section, 'UNKNOWN');
      expect(row.status, ReconciliationStatus.sectionMissing);
      expect(row.applicableAmount, 0);
      expect(row.expectedTds, 0);
      expect(row.tds26QAmount, 50000);
      expect(row.actualTds, 500);
    });

    test('unsupported explicit section stays conservative in final reconciliation', () async {
      final result = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'YYYYY8888Y',
        sourceRows: const [],
        tdsRows: [
          Tds26QRow.fromMap({
            'month': 'Apr-2024',
            'financial_year': '2024-25',
            'party_name': 'Acme Traders',
            'pan_number': 'ABCPD1234F',
            'amount_paid': 25000,
            'tds_amount': 250,
            'section': '194A',
          }),
        ],
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.section, 'UNKNOWN');
      expect(row.status, ReconciliationStatus.sectionMissing);
      expect(row.applicableAmount, 0);
      expect(row.expectedTds, 0);
      expect(row.tds26QAmount, 25000);
      expect(row.actualTds, 250);
    });
  });
}
