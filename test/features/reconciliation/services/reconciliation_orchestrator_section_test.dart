import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/ledger_source_visibility.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CalculationService section-aware reconciliation', () {
    test(
      'same seller + same FY/month + different sections stay separate',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'ZZZZZ9999Z',
          sourceRows: [
            _sourceRow(section: '194Q', amount: 6000000),
            _sourceRow(section: '194C', amount: 50000),
          ],
          tdsRows: [
            _tdsRow(section: '194Q', deductedAmount: 1000000, tds: 1000),
            _tdsRow(section: '194C', deductedAmount: 50000, tds: 500),
          ],
        );

        expect(rows.rows, hasLength(2));

        final bySection = {for (final row in rows.rows) row.section: row};

        expect(bySection.keys, containsAll(<String>['194Q', '194C']));
        expect(bySection['194Q']!.tds26QAmount, 1000000);
        expect(bySection['194Q']!.actualTds, 1000);
        expect(bySection['194Q']!.status, ReconciliationStatus.matched);
        expect(bySection['194C']!.tds26QAmount, 50000);
        expect(bySection['194C']!.actualTds, 500);
        expect(bySection['194C']!.status, ReconciliationStatus.matched);
      },
    );

    test('194A participates in section-aware grouping', () async {
      final rows = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'AINTS1234A',
        sourceRows: [
          _sourceRow(section: '194A', amount: 25000),
          _sourceRow(section: '194C', amount: 50000),
        ],
        tdsRows: [
          _tdsRow(section: '194A', deductedAmount: 25000, tds: 0),
          _tdsRow(section: '194C', deductedAmount: 50000, tds: 500),
        ],
      );

      final bySection = {for (final row in rows.rows) row.section: row};

      expect(bySection.keys, containsAll(<String>['194A', '194C']));
      expect(bySection['194A']!.purchasePresent, isTrue);
      expect(bySection['194A']!.tdsPresent, isTrue);
      expect(bySection['194A']!.tds26QAmount, 25000);
      expect(bySection['194C']!.tds26QAmount, 50000);
    });

    test(
      'same seller + same FY/month + same section still aggregates',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'YYYYY8888Y',
          sourceRows: [
            _sourceRow(section: '194C', amount: 50000, documentNo: 'BILL-1'),
            _sourceRow(section: '194C', amount: 50000, documentNo: 'BILL-2'),
          ],
          tdsRows: [
            _tdsRow(section: '194C', deductedAmount: 50000, tds: 500),
            _tdsRow(section: '194C', deductedAmount: 50000, tds: 500),
          ],
        );

        expect(rows.rows, hasLength(1));
        final row = rows.rows.single;
        expect(row.section, '194C');
        expect(row.basicAmount, 100000);
        expect(row.applicableAmount, 100000);
        expect(row.tds26QAmount, 100000);
        expect(row.expectedTds, 1000);
        expect(row.actualTds, 1000);
        expect(row.status, ReconciliationStatus.matched);
      },
    );

    test(
      'multi-ledger same-section aggregation keeps source visibility metadata',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'SRCID1234A',
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 40000,
              documentNo: 'BILL-A',
              sourceLedgerFileId: 'ledger-a-id',
              sourceLedgerFileName: 'contractor-april.xlsx',
            ),
            _sourceRow(
              section: '194C',
              amount: 70000,
              documentNo: 'BILL-B',
              sourceLedgerFileId: 'ledger-b-id',
              sourceLedgerFileName: 'contractor-may.xlsx',
            ),
          ],
          tdsRows: [
            _tdsRow(section: '194C', deductedAmount: 110000, tds: 1100),
          ],
        );

        expect(rows.rows, hasLength(1));
        final row = rows.rows.single;
        expect(row.basicAmount, 110000);
        expect(row.applicableAmount, 110000);
        expect(
          row.sourceLedgerFileIds,
          containsAll(['ledger-a-id', 'ledger-b-id']),
        );
        expect(
          row.sourceLedgerFileNames,
          containsAll(['contractor-april.xlsx', 'contractor-may.xlsx']),
        );
        expect(
          reconciliationRowMatchesLedgerSource(row, 'ledger-a-id'),
          isTrue,
        );
        expect(
          reconciliationRowMatchesLedgerSource(row, 'ledger-b-id'),
          isTrue,
        );
        expect(
          row.basicAmount,
          110000,
          reason: 'Ledger source filtering is a visibility layer only.',
        );
      },
    );

    test('194I threshold scope resets per month', () async {
      final rows = await CalculationService.reconcileSectionWise(
        buyerName: 'Test Buyer',
        buyerPan: 'RENTM1234A',
        sourceRows: [
          _sourceRow(section: '194I_A', amount: 30000, month: 'Apr-2024'),
          _sourceRow(section: '194I_A', amount: 30000, month: 'May-2024'),
        ],
        tdsRows: const [],
      );

      expect(rows.rows, hasLength(2));
      expect(rows.rows.every((row) => row.section == '194I_A'), isTrue);
      expect(rows.rows.every((row) => row.applicableAmount == 0), isTrue);
      expect(rows.rows.every((row) => row.expectedTds == 0), isTrue);
      expect(
        rows.rows.every(
          (row) => row.status == ReconciliationStatus.belowThreshold,
        ),
        isTrue,
      );
    });

    test(
      'final matching flow does not cross-match different sections',
      () async {
        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: 'XXXXX7777X',
          sourceRows: [_sourceRow(section: '194C', amount: 50000)],
          tdsRows: [
            _tdsRow(section: '194Q', deductedAmount: 1000000, tds: 1000),
          ],
        );

        expect(rows.rows, hasLength(2));

        final bySection = {for (final row in rows.rows) row.section: row};

        expect(
          bySection['194C']!.status,
          ReconciliationStatus.applicableButNo26Q,
        );
        expect(bySection['194C']!.purchasePresent, isTrue);
        expect(bySection['194C']!.tdsPresent, isFalse);

        expect(bySection['194Q']!.status, ReconciliationStatus.onlyIn26Q);
        expect(bySection['194Q']!.purchasePresent, isFalse);
        expect(bySection['194Q']!.tdsPresent, isTrue);
      },
    );

    test(
      'manual name mapping prefers section key over alias fallback',
      () async {
        const buyerPan = 'SECTM1111A';
        await _clearMappings(buyerPan);

        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: buyerPan,
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 50000,
              partyName: 'Shared Alias Vendor',
              panNumber: '',
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
              deducteeName: 'Correct Contract Vendor',
              panNumber: 'AAAAA1111A',
            ),
            _tdsRow(
              section: '194C',
              deductedAmount: 75000,
              tds: 750,
              deducteeName: 'Wrong Fallback Vendor',
              panNumber: 'BBBBB2222B',
            ),
          ],
          nameMapping: const {
            'SHAREDALIASVENDOR': 'Wrong Fallback Vendor',
            'SHAREDALIASVENDOR|194C': 'Correct Contract Vendor',
          },
        );

        final purchaseOnly = rows.rows.singleWhere(
          (row) =>
              row.purchasePresent &&
              !row.tdsPresent &&
              row.sellerName == 'Correct Contract Vendor',
        );
        expect(purchaseOnly.section, '194C');
        expect(purchaseOnly.sellerPan, isEmpty);
        expect(
          purchaseOnly.identitySource,
          anyOf('legal_name_suggestion', 'name_suggestion'),
        );
        expect(
          purchaseOnly.debugInfo.identityFlags,
          contains('unresolved_identity'),
        );

        expect(
          rows.rows.any(
            (row) =>
                row.purchasePresent &&
                row.sellerName == 'Wrong Fallback Vendor',
          ),
          isFalse,
        );
        expect(
          rows.rows.any(
            (row) =>
                row.purchasePresent &&
                row.tdsPresent &&
                row.sellerName == 'Correct Contract Vendor',
          ),
          isFalse,
        );
        expect(
          rows.rows.any(
            (row) =>
                !row.purchasePresent &&
                row.tdsPresent &&
                row.sellerName == 'Correct Contract Vendor' &&
                row.sellerPan == 'AAAAA1111A',
          ),
          isTrue,
        );
      },
    );

    test(
      'saved section seller mapping with PAN safely reconciles no-PAN source',
      () async {
        const buyerPan = 'SECTM3333C';
        await _clearMappings(buyerPan);
        await SellerMappingService.saveMappings(<SellerMapping>[
          SellerMapping(
            buyerName: 'Test Buyer',
            buyerPan: buyerPan,
            aliasName: 'Shared Alias Vendor',
            sectionCode: 'ALL',
            mappedPan: 'BBBBB2222B',
            mappedName: 'Wrong Fallback Vendor',
          ),
          SellerMapping(
            buyerName: 'Test Buyer',
            buyerPan: buyerPan,
            aliasName: 'Shared Alias Vendor',
            sectionCode: '194C',
            mappedPan: 'AAAAA1111A',
            mappedName: 'Correct Contract Vendor',
          ),
        ]);

        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: buyerPan,
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 50000,
              partyName: 'Shared Alias Vendor',
              panNumber: '',
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
              deducteeName: 'Correct Contract Vendor',
              panNumber: 'AAAAA1111A',
            ),
            _tdsRow(
              section: '194C',
              deductedAmount: 75000,
              tds: 750,
              deducteeName: 'Wrong Fallback Vendor',
              panNumber: 'BBBBB2222B',
            ),
          ],
        );

        final matched = rows.rows.singleWhere(
          (row) =>
              row.purchasePresent &&
              row.tdsPresent &&
              row.sellerName == 'Correct Contract Vendor',
        );
        expect(matched.section, '194C');
        expect(matched.sellerPan, 'AAAAA1111A');
        expect(matched.identitySource, 'mapping_exact');
        expect(matched.debugInfo.mappingHit, 'exact');
      },
    );

    test(
      'saved exception marker mappings are not treated as seller names',
      () async {
        const buyerPan = 'SECTM2222B';
        await _clearMappings(buyerPan);
        await SellerMappingService.saveMapping(
          SellerMapping(
            buyerName: 'Test Buyer',
            buyerPan: buyerPan,
            aliasName: 'Exception Alias Vendor',
            sectionCode: '194C',
            mappedPan: '',
            mappedName: '__TIMING_DIFFERENCE__:EXCEPTIONALIASVENDOR|194C|0',
          ),
        );

        final rows = await CalculationService.reconcileSectionWise(
          buyerName: 'Test Buyer',
          buyerPan: buyerPan,
          sourceRows: [
            _sourceRow(
              section: '194C',
              amount: 50000,
              partyName: 'Exception Alias Vendor',
              panNumber: '',
            ),
          ],
          tdsRows: [
            _tdsRow(
              section: '194C',
              deductedAmount: 50000,
              tds: 500,
              deducteeName: 'Original 26Q Vendor',
              panNumber: 'CCCCC3333C',
            ),
          ],
        );

        expect(
          rows.rows.where((row) => row.sellerName.contains('__')),
          isEmpty,
        );
        expect(
          rows.rows.any(
            (row) =>
                row.tdsPresent &&
                !row.purchasePresent &&
                row.sellerName == 'Original 26Q Vendor' &&
                row.sellerPan == 'CCCCC3333C',
          ),
          isTrue,
        );
      },
    );
  });
}

NormalizedTransactionRow _sourceRow({
  required String section,
  required double amount,
  String documentNo = 'BILL-DEFAULT',
  String partyName = 'Acme Traders',
  String panNumber = 'ABCPD1234F',
  String month = 'Apr-2024',
  String sourceLedgerFileId = '',
  String sourceLedgerFileName = '',
}) {
  return NormalizedTransactionRow(
    sourceType: 'purchase',
    sourceLedgerFileId: sourceLedgerFileId,
    sourceLedgerFileName: sourceLedgerFileName,
    transactionDateRaw: '2024-04-15',
    month: month,
    financialYear: '2024-25',
    partyName: partyName,
    panNumber: panNumber,
    gstNo: '',
    documentNo: documentNo,
    description: 'Test row',
    amount: amount,
    taxableAmount: amount,
    tdsAmount: 0,
    section: section,
    normalizedMonth: month,
    normalizedSection: section,
  );
}

Tds26QRow _tdsRow({
  required String section,
  required double deductedAmount,
  required double tds,
  String deducteeName = 'Acme Traders',
  String panNumber = 'ABCPD1234F',
}) {
  return Tds26QRow(
    month: 'Apr-2024',
    financialYear: '2024-25',
    deducteeName: deducteeName,
    panNumber: panNumber,
    deductedAmount: deductedAmount,
    tds: tds,
    section: section,
    normalizedMonth: 'Apr-2024',
    normalizedSection: section,
  );
}

Future<void> _clearMappings(String buyerPan) async {
  final db = await DBHelper.database;
  await db.delete(
    'seller_mappings',
    where: 'buyer_pan = ?',
    whereArgs: [buyerPan.trim().toUpperCase()],
  );
}
