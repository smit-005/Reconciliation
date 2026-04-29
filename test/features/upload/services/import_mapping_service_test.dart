import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';

void main() {
  group('ImportMappingService.validateSelections', () {
    test('26Q requires both party name and PAN', () {
      final errors = ImportMappingService.validateSelections(
        fileType: ImportMappingService.tds26qFileType,
        rawToCanonical: const {
          'Deductee Name': 'party_name',
          'Date': 'date_month',
          'Amount Paid': 'amount_paid',
          'TDS': 'tds_amount',
          'Section': 'section',
        },
      );

      expect(errors, contains('PAN Number is required'));
      expect(errors, isNot(contains('Party Name is required')));
    });

    test('26Q passes when required columns are all mapped', () {
      final errors = ImportMappingService.validateSelections(
        fileType: ImportMappingService.tds26qFileType,
        rawToCanonical: const {
          'Deductee Name': 'party_name',
          'PAN': 'pan_number',
          'Date': 'date_month',
          'Amount Paid': 'amount_paid',
          'TDS': 'tds_amount',
          'Section': 'section',
        },
      );

      expect(errors, isEmpty);
    });

    test(
      'generic ledger does not require PAN or GST when date party and amount exist',
      () {
        final errors = ImportMappingService.validateSelections(
          fileType: ImportMappingService.genericLedgerFileType,
          rawToCanonical: const {
            'Date': 'date',
            'Party Name': 'party_name',
            'Amount': 'amount',
          },
        );

        expect(errors, isEmpty);
      },
    );
  });

  group('ImportMappingService.dedupeSourceColumns', () {
    test('same source column cannot satisfy party name and amount', () {
      final deduped = ImportMappingService.dedupeSourceColumns(const {
        'date': 'Date',
        'party_name': 'Party Name',
        'amount': 'Party Name',
      });

      expect(deduped['date'], 'Date');
      expect(deduped['party_name'], 'Party Name');
      expect(deduped.containsKey('amount'), isFalse);
    });
  });
}
