import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/ledger_source_visibility.dart';

void main() {
  test('source metadata propagates from ledger row to transaction row', () {
    final uploadedAt = DateTime(2026, 5, 13, 10, 30);
    final ledgerRow = NormalizedLedgerRow(
      sourceType: 'generic_ledger',
      sourceFileName: 'contractor-ledger.xlsx',
      sourceLedgerFileId: 'ledger-file-1',
      sourceLedgerUploadedAt: uploadedAt,
      sectionCode: '194C',
      transactionDateRaw: '2026-04-20',
      month: 'Apr-2026',
      financialYear: '2026-27',
      partyName: 'Contractor A',
      panNumber: 'AAAAA1111A',
      gstNo: '',
      documentNo: 'B-1',
      description: '',
      amount: 50000,
      taxableAmount: 50000,
      tdsAmount: 0,
      section: '194C',
    );

    final transactionRow = NormalizedTransactionRow.fromNormalizedLedgerRow(
      ledgerRow,
    );

    expect(transactionRow.sourceLedgerFileId, 'ledger-file-1');
    expect(transactionRow.sourceLedgerFileName, 'contractor-ledger.xlsx');
    expect(transactionRow.sourceLedgerUploadedAt, uploadedAt);
  });

  test('ledger source options are scoped to the active section', () {
    final labels = ledgerSourceLabelsForSections(
      sourceRowsBySection: {
        '194C': [
          _sourceRow(
            section: '194C',
            sourceLedgerFileId: 'ledger-194c',
            sourceLedgerFileName: 'contractors.xlsx',
          ),
        ],
        '194J': [
          _sourceRow(
            section: '194J',
            sourceLedgerFileId: 'ledger-194j',
            sourceLedgerFileName: 'professional.xlsx',
          ),
        ],
      },
      activeSection: '194C',
    );

    expect(labels.keys, ['ledger-194c']);
    expect(labels['ledger-194c'], 'contractors.xlsx');
  });

  test('ledger filter matches visible rows without changing row amounts', () {
    final row = _reconciliationRow(
      sourceLedgerFileIds: const ['ledger-1', 'ledger-2'],
      sourceLedgerFileNames: const ['first.xlsx', 'second.xlsx'],
      basicAmount: 125000,
    );

    expect(reconciliationRowMatchesLedgerSource(row, 'ledger-1'), isTrue);
    expect(reconciliationRowMatchesLedgerSource(row, 'ledger-2'), isTrue);
    expect(reconciliationRowMatchesLedgerSource(row, 'ledger-3'), isFalse);
    expect(row.basicAmount, 125000);
  });
}

NormalizedTransactionRow _sourceRow({
  required String section,
  required String sourceLedgerFileId,
  required String sourceLedgerFileName,
}) {
  return NormalizedTransactionRow(
    sourceType: 'generic_ledger',
    sourceLedgerFileId: sourceLedgerFileId,
    sourceLedgerFileName: sourceLedgerFileName,
    transactionDateRaw: '2026-04-20',
    month: 'Apr-2026',
    financialYear: '2026-27',
    partyName: 'Vendor',
    panNumber: '',
    gstNo: '',
    documentNo: '',
    description: '',
    amount: 100,
    taxableAmount: 100,
    tdsAmount: 0,
    section: section,
  );
}

ReconciliationRow _reconciliationRow({
  required List<String> sourceLedgerFileIds,
  required List<String> sourceLedgerFileNames,
  required double basicAmount,
}) {
  return ReconciliationRow(
    buyerName: 'Buyer',
    buyerPan: 'AAAAA1111A',
    financialYear: '2026-27',
    month: 'Apr-2026',
    sellerName: 'Vendor',
    sellerPan: '',
    section: '194C',
    sourceLedgerFileIds: sourceLedgerFileIds,
    sourceLedgerFileNames: sourceLedgerFileNames,
    basicAmount: basicAmount,
    applicableAmount: basicAmount,
    tds26QAmount: 0,
    expectedTds: 0,
    actualTds: 0,
    tdsRateUsed: 0,
    amountDifference: basicAmount,
    tdsDifference: 0,
    status: 'Below Threshold',
    remarks: '',
    purchasePresent: true,
    tdsPresent: false,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
