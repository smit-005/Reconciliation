import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/resolved_seller_identity.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_identity_resolver.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_preflight_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SellerMappingPreflightService', () {
    test(
      'counts dangerous review items by 26Q seller instead of ledger-only aliases',
      () async {
        const buyerPan = 'PREFT1111A';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer One',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'ABCDE1234F',
              section: '194C',
            ),
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'PQRSX6789L',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Dual PAN Vendor', pan: '', section: '194C'),
              _sourceRow(name: 'Mystery Supplies', pan: '', section: '194C'),
            ],
          },
        );

        expect(result.isSafeForReconciliation, isFalse);
        expect(result.pendingReviewCount, 1);
        expect(
          result.reviewRows.where((row) => row.requiresDangerousReview).length,
          1,
        );
        expect(
          result.reviewRows
              .where((row) => row.requiresDangerousReview)
              .single
              .preflightReasonCode,
          anyOf('ambiguous_identity', 'conflicting_pan'),
        );
        expect(
          result.reviewRows.any(
            (row) => row.purchasePartyDisplayName == 'Mystery Supplies',
          ),
          isTrue,
        );
      },
    );

    test(
      'ledger-only sellers do not block preflight when there is no 26Q seller to review',
      () async {
        const buyerPan = 'PREFT4444D';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Four',
          buyerPan: buyerPan,
          tdsRows: <Tds26QRow>[],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Ledger Only Vendor', pan: '', section: '194C'),
            ],
          },
        );

        expect(result.isSafeForReconciliation, isTrue);
        expect(result.pendingReviewCount, 0);
        expect(result.reviewRows, isNotEmpty);
        expect(
          result.reviewRows.any((row) => row.requiresDangerousReview),
          isFalse,
        );
      },
    );

    test(
      'auto-resolved sellers and known aliases do not block reconciliation',
      () async {
        const buyerPan = 'PREFT2222B';
        await _clearMappings(buyerPan);

        await SellerMappingService.saveMapping(
          SellerMapping(
            buyerName: 'Buyer Two',
            buyerPan: buyerPan,
            aliasName: 'Known Alias Vendor',
            sectionCode: '194C',
            mappedPan: 'AAAAA1111A',
            mappedName: 'Known Vendor Pvt Ltd',
          ),
        );

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Two',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Known Vendor Pvt Ltd',
              pan: 'AAAAA1111A',
              section: '194C',
            ),
            _tdsRow(name: 'Auto Vendor', pan: 'BBBBB2222B', section: '194H'),
            _tdsRow(name: 'Auto Vendor', pan: 'BBBBB2222B', section: '194H'),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Known Alias Vendor', pan: '', section: '194C'),
            ],
            '194H': [_sourceRow(name: 'Auto Vendor', pan: '', section: '194H')],
          },
        );

        expect(result.isSafeForReconciliation, isTrue);
        expect(result.pendingReviewCount, 0);
        expect(
          result.reviewRows.where((row) => row.requiresDangerousReview),
          isEmpty,
        );
      },
    );

    test(
      'multiple source aliases can safely point to one 26Q seller when PAN agrees',
      () async {
        const buyerPan = 'PREFT5555E';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Five',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(name: 'Shared Vendor', pan: 'AAAAA1111A', section: '194C'),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(
                name: 'Shared Vendor Main',
                pan: 'AAAAA1111A',
                section: '194C',
              ),
              _sourceRow(
                name: 'Shared Vendor Branch',
                pan: 'AAAAA1111A',
                section: '194C',
              ),
            ],
          },
        );

        expect(result.isSafeForReconciliation, isTrue);
        expect(result.pendingReviewCount, 0);
        expect(result.reviewRows, hasLength(2));
        expect(
          result.reviewRows.where((row) => row.requiresDangerousReview),
          isEmpty,
        );
      },
    );

    test(
      'analysis stays read-only until user explicitly saves mappings',
      () async {
        const buyerPan = 'PREFT3333C';
        await _clearMappings(buyerPan);

        final before = await SellerMappingService.getAllMappings(buyerPan);
        expect(before, isEmpty);

        await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Three',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'No Auto Save Vendor',
              pan: 'CCCCC3333C',
              section: '194J_A',
            ),
          ],
          sourceRowsBySection: {
            '194J_A': [
              _sourceRow(
                name: 'No Auto Save Alias',
                pan: '',
                section: '194J_A',
              ),
            ],
          },
        );

        final after = await SellerMappingService.getAllMappings(buyerPan);
        expect(after, isEmpty);
      },
    );

    test(
      '26Q-only preflight rows keep source pan blank and 26Q pan on suggestion side',
      () async {
        const buyerPan = 'PREFT6666F';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Six',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Standalone 26Q Vendor',
              pan: 'ZZZZZ9999Z',
              section: '194J_A',
            ),
          ],
          sourceRowsBySection: {'194J_A': <NormalizedTransactionRow>[]},
        );

        expect(result.reviewRows, hasLength(1));
        final row = result.reviewRows.single;
        expect(row.isReadOnly, isTrue);
        expect(row.purchasePan, isEmpty);
        expect(row.resolvedSuggestion?.mappedPan, 'ZZZZZ9999Z');
      },
    );

    test(
      '26Q-only unresolved rows still appear without scanning unrelated section candidates',
      () async {
        const buyerPan = 'PREFT6611F';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Six B',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(name: 'Unresolved 26Q Vendor', pan: '', section: '194C'),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(
                name: 'Unrelated Ledger Vendor',
                pan: '',
                section: '194C',
              ),
            ],
          },
        );

        final tdsOnlyRow = result.reviewRows.singleWhere(
          (row) => row.purchasePartyDisplayName == 'Unresolved 26Q Vendor',
        );
        expect(tdsOnlyRow.is26QUnmatched, isTrue);
        expect(tdsOnlyRow.sourceRowCount, 0);
        expect(tdsOnlyRow.preflightReasonCode, 'unresolved_identity');
        expect(
          result.reviewRows.any(
            (row) =>
                row.purchasePartyDisplayName == 'Unrelated Ledger Vendor' &&
                row.isPurchaseOnly,
          ),
          isTrue,
        );
      },
    );

    test(
      'reviewed separate same-section source aliases keep empty-candidate 26Q sellers safe',
      () async {
        const buyerPan = 'PREFT6622F';
        await _clearMappings(buyerPan);
        await SellerMappingService.saveMapping(
          SellerMapping(
            buyerName: 'Buyer Six C',
            buyerPan: buyerPan,
            aliasName: 'Reviewed Separate Ledger',
            sectionCode: '194C',
            mappedPan: '',
            mappedName: '__SEPARATE__:Reviewed Separate Ledger',
          ),
        );

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Six C',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(name: 'Unmatched Reviewed 26Q', pan: '', section: '194C'),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(
                name: 'Reviewed Separate Ledger',
                pan: '',
                section: '194C',
              ),
            ],
          },
        );

        final row = result.reviewRows.singleWhere(
          (row) => row.purchasePartyDisplayName == 'Unmatched Reviewed 26Q',
        );
        expect(row.is26QUnmatched, isTrue);
        expect(row.requiresDangerousReview, isFalse);
        expect(
          row.preflightReasonDetail,
          contains('explicitly reviewed and kept separate'),
        );
        expect(result.pendingReviewCount, 0);
      },
    );

    test(
      'same seller name in another section does not become a source candidate',
      () async {
        const buyerPan = 'PREFT6633F';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Six D',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Cross Section Vendor',
              pan: 'ABCDE1234F',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194H': [
              _sourceRow(
                name: 'Cross Section Vendor',
                pan: 'ABCDE1234F',
                section: '194H',
              ),
            ],
          },
        );

        final tdsOnlyRow = result.reviewRows.singleWhere(
          (row) =>
              row.purchasePartyDisplayName == 'Cross Section Vendor' &&
              row.sectionCode == '194C',
        );
        expect(tdsOnlyRow.is26QUnmatched, isTrue);
        expect(tdsOnlyRow.sourceRowCount, 0);
        expect(
          result.reviewRows.any(
            (row) =>
                row.sectionCode == '194H' &&
                row.purchasePartyDisplayName == 'Cross Section Vendor' &&
                row.tdsDisplayName == 'Cross Section Vendor',
          ),
          isFalse,
        );
      },
    );

    test(
      'same-section name match still appears as a reviewable candidate',
      () async {
        const buyerPan = 'PREFT6644F';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Six E',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Same Section Vendor',
              pan: 'ABCDE1234F',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Same Section Vendor', pan: '', section: '194C'),
            ],
          },
        );

        final row = result.reviewRows.singleWhere(
          (row) => row.purchasePartyDisplayName == 'Same Section Vendor',
        );
        expect(row.is26QUnmatched, isFalse);
        expect(row.sourceRowCount, 1);
        expect(row.tdsDisplayName, 'Same Section Vendor');
        expect(row.requiresDangerousReview, isTrue);
        expect(row.preflightReasonCode, 'unresolved_identity');
      },
    );

    test(
      'numeric and date-like source seller keys are dropped before preflight grouping',
      () async {
        const buyerPan = 'PREFT7777G';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Seven',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Valid Vendor Pvt Ltd',
              pan: 'AAAAA1111A',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(
                name: 'Valid Vendor Pvt Ltd',
                pan: 'AAAAA1111A',
                section: '194C',
              ),
              _sourceRow(name: '000018', pan: '', section: '194C'),
              _sourceRow(name: '06.09.24', pan: '', section: '194C'),
              _sourceRow(name: '1010241606325', pan: '', section: '194C'),
            ],
          },
        );

        expect(result.isSafeForReconciliation, isTrue);
        expect(
          result.reviewRows.any(
            (row) => row.purchasePartyDisplayName == '000018',
          ),
          isFalse,
        );
        expect(
          result.reviewRows.any(
            (row) => row.purchasePartyDisplayName == '06.09.24',
          ),
          isFalse,
        );
        expect(
          result.reviewRows.any(
            (row) => row.purchasePartyDisplayName == '1010241606325',
          ),
          isFalse,
        );
        expect(
          result.reviewRows.any(
            (row) => row.purchasePartyDisplayName == 'Valid Vendor Pvt Ltd',
          ),
          isTrue,
        );
      },
    );

    test(
      'duplicate raw source rows preserve dangerous review parity after compaction',
      () async {
        const buyerPan = 'PREFT8888H';
        await _clearMappings(buyerPan);

        final duplicateResult = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Eight',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'ABCDE1234F',
              section: '194C',
            ),
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'PQRSX6789L',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Dual PAN Vendor', pan: '', section: '194C'),
              _sourceRow(name: 'Dual PAN Vendor', pan: '', section: '194C'),
            ],
          },
        );

        final singleResult = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Eight',
          buyerPan: buyerPan,
          tdsRows: [
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'ABCDE1234F',
              section: '194C',
            ),
            _tdsRow(
              name: 'Dual PAN Vendor',
              pan: 'PQRSX6789L',
              section: '194C',
            ),
          ],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(name: 'Dual PAN Vendor', pan: '', section: '194C'),
            ],
          },
        );

        expect(
          duplicateResult.pendingReviewCount,
          singleResult.pendingReviewCount,
        );
        expect(
          duplicateResult.reviewRows
              .where((row) => row.requiresDangerousReview)
              .map((row) => row.preflightReasonCode)
              .toList(),
          singleResult.reviewRows
              .where((row) => row.requiresDangerousReview)
              .map((row) => row.preflightReasonCode)
              .toList(),
        );
      },
    );

    test(
      'same ledger alias and section exposes multiple PAN variant count',
      () async {
        const buyerPan = 'PREFT1010J';
        await _clearMappings(buyerPan);

        final result = await SellerMappingPreflightService.analyze(
          buyerName: 'Buyer Ten',
          buyerPan: buyerPan,
          tdsRows: <Tds26QRow>[],
          sourceRowsBySection: {
            '194C': [
              _sourceRow(
                name: 'Multi PAN Ledger Vendor',
                pan: 'AAAAA1111A',
                section: '194C',
              ),
              _sourceRow(
                name: 'Multi PAN Ledger Vendor',
                pan: 'BBBBB2222B',
                section: '194C',
              ),
            ],
          },
        );

        final row = result.reviewRows.singleWhere(
          (row) => row.purchasePartyDisplayName == 'Multi PAN Ledger Vendor',
        );
        expect(row.ledgerPanVariantsCount, 2);
      },
    );

    test(
      'weighted observations preserve unresolved identity threshold behavior',
      () {
        ResolvedSellerIdentity resolveWithCount(int observationCount) {
          final resolver = SellerIdentityResolver.build(
            observations: [
              SellerIdentityObservation(
                originalName: 'Evidence Vendor',
                mappedName: 'Evidence Vendor',
                normalizedName: 'EVIDENCE VENDOR',
                originalPan: 'AAAAA1111A',
                normalizedPan: 'AAAAA1111A',
                observationCount: observationCount,
              ),
            ],
            savedMappings: const <SellerMapping>[],
            savedAliasToPan: const <String, String>{},
          );

          return resolver.resolve(
            buyerPan: 'PREFT9999I',
            originalName: 'Evidence Vendor',
            mappedName: 'Evidence Vendor',
            originalPan: '',
            sectionCode: '194C',
          );
        }

        final weakEvidence = resolveWithCount(1);
        final strongEvidence = resolveWithCount(2);

        expect(weakEvidence.identityFlags, contains('unresolved_identity'));
        expect(weakEvidence.resolvedPan, isEmpty);

        expect(
          strongEvidence.identityFlags,
          isNot(contains('unresolved_identity')),
        );
        expect(strongEvidence.resolvedPan, 'AAAAA1111A');
      },
    );
  });
}

Future<void> _clearMappings(String buyerPan) async {
  final db = await DBHelper.database;
  await db.delete(
    'seller_mappings',
    where: 'buyer_pan = ?',
    whereArgs: [buyerPan.trim().toUpperCase()],
  );
}

NormalizedTransactionRow _sourceRow({
  required String name,
  required String pan,
  required String section,
}) {
  return NormalizedTransactionRow(
    sourceType: 'generic_ledger',
    transactionDateRaw: '2024-04-15',
    month: 'Apr-2024',
    financialYear: '2024-25',
    partyName: name,
    panNumber: pan,
    gstNo: '',
    documentNo: 'DOC-1',
    description: 'Source row',
    amount: 1200,
    taxableAmount: 1200,
    tdsAmount: 0,
    section: section,
    normalizedMonth: 'Apr-2024',
    normalizedSection: section,
  );
}

Tds26QRow _tdsRow({
  required String name,
  required String pan,
  required String section,
}) {
  return Tds26QRow(
    month: 'Apr-2024',
    financialYear: '2024-25',
    deducteeName: name,
    panNumber: pan,
    deductedAmount: 1200,
    tds: 120,
    section: section,
    normalizedMonth: 'Apr-2024',
    normalizedSection: section,
  );
}
