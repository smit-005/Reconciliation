import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/services/batch_mapping_review_service.dart';

void main() {
  test(
    'generic ledger manual save produces confirmed 3/3 row for batch review',
    () {
      final items = BatchMappingReviewService.buildItems(
        tdsFile: null,
        sectionFiles: <LedgerUploadFile>[
          LedgerUploadFile(
            id: 'file-1',
            sectionCode: '194C',
            fileName: 'ledger.xlsx',
            bytes: const <int>[1, 2, 3],
            rowCount: 1,
            uploadedAt: DateTime(2026, 4, 29, 10, 0),
            parserType: 'genericLedger',
            rows: <NormalizedLedgerRow>[_ledgerRow()],
            mappingStatus: UploadMappingStatus.confirmed,
            wasManuallyMapped: true,
            columnMapping: const <String, String>{
              'date': 'Date',
              'party_name': 'Party Name',
              'amount': 'Amount',
            },
          ),
        ],
      );

      expect(items, hasLength(1));
      expect(items.single.mappingStatus, UploadMappingStatus.confirmed);
      expect(items.single.mappedRequiredFieldsCount, 3);
      expect(items.single.requiredFieldsCount, 3);
      expect(items.single.issuesCount, 0);
      expect(items.single.primaryActionLabel, 'View');
    },
  );
}

NormalizedLedgerRow _ledgerRow() {
  return const NormalizedLedgerRow(
    sourceType: 'generic_ledger',
    sourceFileName: 'ledger.xlsx',
    sectionCode: '194C',
    transactionDateRaw: '2024-04-15',
    month: 'Apr-2024',
    financialYear: '2024-25',
    partyName: 'Ledger Vendor',
    panNumber: '',
    gstNo: '',
    documentNo: 'DOC-1',
    description: 'Ledger row',
    amount: 1200,
    taxableAmount: 1200,
    tdsAmount: 0,
    section: '194C',
  );
}
