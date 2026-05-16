import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_models.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_two_panel_body.dart';

void main() {
  testWidgets(
    'seller mapping screen returns dangerousRemaining 0 after save review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SellerMappingScreenResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerMappingLaunchHarness(
            onResult: (result) => capturedResult = result,
          ),
        ),
      );

      await tester.tap(find.text('Open Seller Mapping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Alias Vendor'), findsOneWidget);
      expect(find.text('Unresolved Identity'), findsWidgets);

      await tester.tap(find.text('Alias Vendor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Keep Separate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(FilledButton, 'Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.dangerousRemaining, 0);
      expect(capturedResult!.upserts, isNotEmpty);
    },
  );

  testWidgets(
    'seller mapping screen renders first 100 sellers and loads more on demand',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final purchaseRows = List<SellerMappingScreenRowData>.generate(150, (
        index,
      ) {
        final sellerNumber = index.toString().padLeft(3, '0');
        return SellerMappingScreenRowData(
          purchasePartyDisplayName: 'Seller $sellerNumber',
          normalizedAlias: 'Seller $sellerNumber',
          sectionCode: '194C',
          tdsDisplayName: 'Seller $sellerNumber',
          purchasePan: '',
          resolvedSuggestion: SellerMappingResolvedSuggestion(
            mappedName: 'Mapped Seller $sellerNumber',
            mappedPan: 'ABCDE1234F',
            source: 'backend_inferred',
          ),
          hasApplicableTdsImpact: true,
          preflightReasonCode: 'unresolved_identity',
          preflightReasonLabel: 'Unresolved Identity',
          preflightReasonDetail: 'Needs review',
          requiresDangerousReview: true,
        );
      });

      final tdsPartyPans = <String, List<String>>{
        for (var index = 0; index < 150; index++)
          'Mapped Seller ${index.toString().padLeft(3, '0')}': <String>[
            'ABCDE1234F',
          ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: purchaseRows,
              tdsParties: tdsPartyPans.keys.toList(),
              existingMappings: const <SellerMapping>[],
              blockedAliases: const <String>{},
              tdsPartyPans: tdsPartyPans,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final loadMoreButton = find.widgetWithText(
        FilledButton,
        'Load More (50)',
      );
      expect(loadMoreButton, findsOneWidget);

      await tester.tap(loadMoreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Load More'), findsNothing);
    },
  );

  testWidgets(
    'seller mapping screen search filter narrows cached rows without breaking pagination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final purchaseRows = List<SellerMappingScreenRowData>.generate(130, (
        index,
      ) {
        final sellerNumber = index.toString().padLeft(3, '0');
        return SellerMappingScreenRowData(
          purchasePartyDisplayName: 'Seller $sellerNumber',
          normalizedAlias: 'Seller $sellerNumber',
          sectionCode: '194C',
          tdsDisplayName: 'Seller $sellerNumber',
          purchasePan: '',
          resolvedSuggestion: SellerMappingResolvedSuggestion(
            mappedName: 'Mapped Seller $sellerNumber',
            mappedPan: 'ABCDE1234F',
            source: 'backend_inferred',
          ),
          hasApplicableTdsImpact: true,
          preflightReasonCode: 'unresolved_identity',
          preflightReasonLabel: 'Unresolved Identity',
          preflightReasonDetail: 'Needs review',
          requiresDangerousReview: true,
        );
      });

      final tdsPartyPans = <String, List<String>>{
        for (var index = 0; index < 130; index++)
          'Mapped Seller ${index.toString().padLeft(3, '0')}': <String>[
            'ABCDE1234F',
          ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: purchaseRows,
              tdsParties: tdsPartyPans.keys.toList(),
              existingMappings: const <SellerMapping>[],
              blockedAliases: const <String>{},
              tdsPartyPans: tdsPartyPans,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.widgetWithText(FilledButton, 'Load More (30)'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'Seller 129');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Seller 129'), findsWidgets);
      expect(find.text('Seller 128'), findsNothing);
      expect(find.textContaining('Load More'), findsNothing);
    },
  );

  testWidgets(
    'seller mapping advances two-panel selection after resolving selected needs-action row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: const <SellerMappingScreenRowData>[
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'First Vendor',
                  normalizedAlias: 'First Vendor',
                  sectionCode: '194C',
                  tdsDisplayName: 'First Vendor',
                  purchasePan: '',
                  hasApplicableTdsImpact: true,
                  preflightReasonCode: 'unresolved_identity',
                  preflightReasonLabel: 'Unresolved Identity',
                  preflightReasonDetail: 'First needs review',
                  requiresDangerousReview: true,
                ),
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'Second Vendor',
                  normalizedAlias: 'Second Vendor',
                  sectionCode: '194C',
                  tdsDisplayName: 'Second Vendor',
                  purchasePan: '',
                  hasApplicableTdsImpact: true,
                  preflightReasonCode: 'unresolved_identity',
                  preflightReasonLabel: 'Unresolved Identity',
                  preflightReasonDetail: 'Second needs review',
                  requiresDangerousReview: true,
                ),
              ],
              tdsParties: const <String>['First Vendor', 'Second Vendor'],
              existingMappings: const <SellerMapping>[],
              blockedAliases: const <String>{},
              tdsPartyPans: const <String, List<String>>{},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('First Vendor').first);
      await tester.pump();

      expect(find.text('First needs review'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Keep Separate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('First needs review'), findsNothing);
      expect(find.text('Second needs review'), findsOneWidget);
      expect(find.text('Select a seller to enable actions.'), findsNothing);
    },
  );

  testWidgets(
    'review view clear visible clears review-visible rows instead of working-filtered rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SellerMappingScreenResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerMappingDirectLaunchHarness(
            screen: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: const <SellerMappingScreenRowData>[
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'Mapped Vendor',
                  normalizedAlias: 'Mapped Vendor',
                  sectionCode: '194C',
                  tdsDisplayName: 'Mapped Vendor',
                  tdsPan: 'ABCDE1234F',
                  purchasePan: 'ABCDE1234F',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                  resolvedSuggestion: SellerMappingResolvedSuggestion(
                    mappedName: 'Mapped Vendor',
                    mappedPan: 'ABCDE1234F',
                    source: 'saved_exact',
                  ),
                ),
              ],
              tdsParties: const <String>['Mapped Vendor'],
              existingMappings: <SellerMapping>[
                SellerMapping(
                  buyerName: 'Buyer One',
                  buyerPan: 'ABCDE1234F',
                  aliasName: 'Mapped Vendor',
                  sectionCode: '194C',
                  mappedName: 'Mapped Vendor',
                  mappedPan: 'ABCDE1234F',
                ),
              ],
              blockedAliases: const <String>{},
              tdsPartyPans: const <String, List<String>>{
                'Mapped Vendor': <String>['ABCDE1234F'],
              },
            ),
            onResult: (result) => capturedResult = result,
          ),
        ),
      );

      await tester.tap(find.text('Open Seller Mapping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Review View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(TextButton, 'Clear Visible'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(FilledButton, 'Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.upserts, isEmpty);
      expect(
        capturedResult!.deleted,
        contains(
          predicate<Map<String, String>>(
            (item) =>
                item['sectionCode'] == '194C' &&
                (item['aliasName']?.isNotEmpty ?? false),
          ),
        ),
      );
    },
  );

  testWidgets('right ledger card warns when alias has multiple PAN variants', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const leftRow = SellerMappingRowVm(
      purchasePartyDisplayName: '',
      normalizedAlias: 'Vendor From 26Q',
      sectionCode: '194C',
      rowIndex: 0,
      tdsDisplayName: 'Vendor From 26Q',
      tdsPan: 'AAAAA1111A',
      purchasePan: '',
      purchaseGstNo: '',
      tdsRowCount: 1,
      is26QUnmatched: true,
    );
    const ledgerRow = SellerMappingRowVm(
      purchasePartyDisplayName: 'Ledger Vendor Alias',
      normalizedAlias: 'Ledger Vendor Alias',
      sectionCode: '194C',
      rowIndex: 1,
      purchasePan: 'AAAAA1111A',
      purchaseGstNo: '',
      ledgerPanVariantsCount: 2,
      sourceRowCount: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerMappingTwoPanelBody(
            visibleRows: const <SellerMappingRowVm>[leftRow],
            ledgerCandidateRows: const <SellerMappingRowVm>[ledgerRow],
            tdsParties: const <String>['Vendor From 26Q'],
            tdsPartyPans: const <String, List<String>>{
              'Vendor From 26Q': <String>['AAAAA1111A'],
            },
            selectedValueForRow: (_) => null,
            selectedPanForRow: (_) => '',
            statusForRow: (_) => '26Q Unmatched',
            helperMessagesForRow: (_) => const <String>[],
            canAcceptSuggestion: (_) => false,
            onAcceptSuggestion: (_) {},
            onLinkToTds: (row, tdsParty) {},
            onLinkToLedgerRow: (row, ledgerRow) {},
            onKeepSeparate: (_) {},
            onClear: (_) {},
            onMarkMissingInBooks: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Vendor From 26Q'));
    await tester.pump();

    expect(find.text('Multiple PANs: 2'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Missing in Books'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Timing Difference'),
      findsNothing,
    );
  });

  testWidgets(
    'seller mapping save allows same-section same-PAN aliases to share one 26Q seller',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SellerMappingScreenResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerMappingDirectLaunchHarness(
            screen: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: const <SellerMappingScreenRowData>[
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Morbi',
                  normalizedAlias: 'ABC Enterprise Morbi',
                  sectionCode: '194C',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'AAAAA1111A',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Rajkot',
                  normalizedAlias: 'ABC Enterprise Rajkot',
                  sectionCode: '194C',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'AAAAA1111A',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
              ],
              tdsParties: const <String>['ABC Enterprise'],
              existingMappings: <SellerMapping>[
                SellerMapping(
                  buyerName: 'Buyer One',
                  buyerPan: 'ABCDE1234F',
                  aliasName: 'ABC Enterprise Morbi',
                  sectionCode: '194C',
                  mappedName: 'ABC Enterprise',
                  mappedPan: 'AAAAA1111A',
                ),
              ],
              blockedAliases: const <String>{},
              tdsPartyPans: const <String, List<String>>{
                'ABC Enterprise': <String>['AAAAA1111A'],
              },
              initialSelectedMappings: const <String, String>{
                'ABCENTERPRISEMORBI|194C|0': 'ABC Enterprise',
                'ABCENTERPRISERAJKOT|194C|1': 'ABC Enterprise',
              },
            ),
            onResult: (result) => capturedResult = result,
          ),
        ),
      );

      await tester.tap(find.text('Open Seller Mapping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(FilledButton, 'Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.upserts, hasLength(2));
      expect(capturedResult!.deleted, isEmpty);
      expect(
        capturedResult!.upserts.map((row) => row['aliasName']).toSet(),
        containsAll(<String>{'ABCENTERPRISEMORBI', 'ABCENTERPRISERAJKOT'}),
      );
    },
  );

  testWidgets(
    'seller mapping save still dedupes same target with different PAN',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SellerMappingScreenResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerMappingDirectLaunchHarness(
            screen: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: const <SellerMappingScreenRowData>[
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Morbi',
                  normalizedAlias: 'ABC Enterprise Morbi',
                  sectionCode: '194C',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'AAAAA1111A',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Rajkot',
                  normalizedAlias: 'ABC Enterprise Rajkot',
                  sectionCode: '194C',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'BBBBB2222B',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
              ],
              tdsParties: const <String>['ABC Enterprise'],
              existingMappings: const <SellerMapping>[],
              blockedAliases: const <String>{},
              tdsPartyPans: const <String, List<String>>{
                'ABC Enterprise': <String>['AAAAA1111A'],
              },
              initialSelectedMappings: const <String, String>{
                'ABCENTERPRISEMORBI|194C|0': 'ABC Enterprise',
                'ABCENTERPRISERAJKOT|194C|1': 'ABC Enterprise',
              },
            ),
            onResult: (result) => capturedResult = result,
          ),
        ),
      );

      await tester.tap(find.text('Open Seller Mapping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(FilledButton, 'Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.upserts, hasLength(1));
    },
  );

  testWidgets(
    'seller mapping save keeps cross-section same-PAN mappings scoped',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SellerMappingScreenResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: _SellerMappingDirectLaunchHarness(
            screen: SellerMappingScreen(
              mode: SellerMappingScreenMode.preflight,
              buyerName: 'Buyer One',
              buyerPan: 'ABCDE1234F',
              financialYearLabel: 'FY 2024-25',
              selectedSectionLabel: '194C',
              initialViewMode: ReconciliationViewMode.summary,
              purchaseRows: const <SellerMappingScreenRowData>[
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Morbi',
                  normalizedAlias: 'ABC Enterprise Morbi',
                  sectionCode: '194C',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'AAAAA1111A',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
                SellerMappingScreenRowData(
                  purchasePartyDisplayName: 'ABC Enterprise Rajkot',
                  normalizedAlias: 'ABC Enterprise Rajkot',
                  sectionCode: '194J_B',
                  tdsDisplayName: 'ABC Enterprise',
                  tdsPan: 'AAAAA1111A',
                  purchasePan: 'AAAAA1111A',
                  sourceRowCount: 1,
                  tdsRowCount: 1,
                ),
              ],
              tdsParties: const <String>['ABC Enterprise'],
              existingMappings: const <SellerMapping>[],
              blockedAliases: const <String>{},
              tdsPartyPans: const <String, List<String>>{
                'ABC Enterprise': <String>['AAAAA1111A'],
              },
              initialSelectedMappings: const <String, String>{
                'ABCENTERPRISEMORBI|194C|0': 'ABC Enterprise',
                'ABCENTERPRISERAJKOT|194J_B|0': 'ABC Enterprise',
              },
            ),
            onResult: (result) => capturedResult = result,
          ),
        ),
      );

      await tester.tap(find.text('Open Seller Mapping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(FilledButton, 'Save & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.upserts, hasLength(2));
      expect(
        capturedResult!.upserts.map((row) => row['sectionCode']).toSet(),
        containsAll(<String>{'194C', '194J_B'}),
      );
    },
  );

  testWidgets(
    'two-panel selection clears when search hides the selected left seller',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const hiddenRow = SellerMappingRowVm(
        purchasePartyDisplayName: '',
        normalizedAlias: 'Hidden Vendor',
        sectionCode: '194C',
        rowIndex: 0,
        tdsDisplayName: 'Hidden Vendor',
        tdsPan: 'AAAAA1111A',
        purchasePan: '',
        purchaseGstNo: '',
        tdsRowCount: 1,
        is26QUnmatched: true,
      );
      const visibleRow = SellerMappingRowVm(
        purchasePartyDisplayName: '',
        normalizedAlias: 'Visible Vendor',
        sectionCode: '194C',
        rowIndex: 1,
        tdsDisplayName: 'Visible Vendor',
        tdsPan: 'BBBBB2222B',
        purchasePan: '',
        purchaseGstNo: '',
        tdsRowCount: 1,
        is26QUnmatched: true,
      );
      const ledgerRow = SellerMappingRowVm(
        purchasePartyDisplayName: 'Ledger Vendor',
        normalizedAlias: 'Ledger Vendor',
        sectionCode: '194C',
        rowIndex: 2,
        purchasePan: 'AAAAA1111A',
        purchaseGstNo: '',
        sourceRowCount: 1,
      );

      String? selectedLeftKey;
      final acceptedRows = <String>[];

      Widget buildBody(String searchQuery) {
        return MaterialApp(
          home: Scaffold(
            body: SellerMappingTwoPanelBody(
              visibleRows: const <SellerMappingRowVm>[hiddenRow, visibleRow],
              allLeftRows: const <SellerMappingRowVm>[hiddenRow, visibleRow],
              ledgerCandidateRows: const <SellerMappingRowVm>[ledgerRow],
              searchQuery: searchQuery,
              selectedLeftKey: selectedLeftKey,
              onSelectedLeftKeyChanged: (rowKey) {
                selectedLeftKey = rowKey;
              },
              tdsParties: const <String>['Hidden Vendor', 'Visible Vendor'],
              tdsPartyPans: const <String, List<String>>{
                'Hidden Vendor': <String>['AAAAA1111A'],
                'Visible Vendor': <String>['BBBBB2222B'],
              },
              selectedValueForRow: (_) => null,
              selectedPanForRow: (_) => '',
              statusForRow: (_) => '26Q Unmatched',
              helperMessagesForRow: (_) => const <String>[],
              canAcceptSuggestion: (_) => true,
              onAcceptSuggestion: (row) => acceptedRows.add(row.rowKey),
              onLinkToTds: (row, tdsParty) {},
              onLinkToLedgerRow: (row, ledgerRow) {},
              onKeepSeparate: (_) {},
              onClear: (_) {},
              onMarkMissingInBooks: (_) {},
            ),
          ),
        );
      }

      await tester.pumpWidget(buildBody(''));
      await tester.tap(find.text('Hidden Vendor').first);
      await tester.pump();

      expect(selectedLeftKey, hiddenRow.rowKey);

      await tester.pumpWidget(buildBody('Visible'));
      await tester.pump();

      expect(selectedLeftKey, isNull);
      expect(find.text('Select a seller to enable actions.'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Accept Suggestion'),
      );
      await tester.pump();

      expect(acceptedRows, isEmpty);
    },
  );

  testWidgets('seller mapping action column avoids compact height overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const leftRow = SellerMappingRowVm(
      purchasePartyDisplayName: '',
      normalizedAlias: 'Vendor From 26Q',
      sectionCode: '194C',
      rowIndex: 0,
      tdsDisplayName: 'Vendor From 26Q',
      tdsPan: 'AAAAA1111A',
      purchasePan: '',
      purchaseGstNo: '',
      tdsRowCount: 1,
      is26QUnmatched: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerMappingTwoPanelBody(
            visibleRows: const <SellerMappingRowVm>[leftRow],
            ledgerCandidateRows: const <SellerMappingRowVm>[],
            tdsParties: const <String>['Vendor From 26Q'],
            tdsPartyPans: const <String, List<String>>{
              'Vendor From 26Q': <String>['AAAAA1111A'],
            },
            selectedValueForRow: (_) => null,
            selectedPanForRow: (_) => '',
            statusForRow: (_) => '26Q Unmatched',
            helperMessagesForRow: (_) => const <String>[],
            canAcceptSuggestion: (_) => false,
            onAcceptSuggestion: (_) {},
            onLinkToTds: (row, tdsParty) {},
            onLinkToLedgerRow: (row, ledgerRow) {},
            onKeepSeparate: (_) {},
            onClear: (_) {},
            onMarkMissingInBooks: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Select a seller to enable actions.'), findsOneWidget);
  });
}

class _SellerMappingLaunchHarness extends StatelessWidget {
  final ValueChanged<SellerMappingScreenResult?> onResult;

  const _SellerMappingLaunchHarness({required this.onResult});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<SellerMappingScreenResult>(
                  MaterialPageRoute(
                    builder: (_) => SellerMappingScreen(
                      mode: SellerMappingScreenMode.preflight,
                      buyerName: 'Buyer One',
                      buyerPan: 'ABCDE1234F',
                      financialYearLabel: 'FY 2024-25',
                      selectedSectionLabel: '194C',
                      initialViewMode: ReconciliationViewMode.summary,
                      purchaseRows: const <SellerMappingScreenRowData>[
                        SellerMappingScreenRowData(
                          purchasePartyDisplayName: 'Alias Vendor',
                          normalizedAlias: 'Alias Vendor',
                          sectionCode: '194C',
                          tdsDisplayName: 'Alias Vendor',
                          purchasePan: '',
                          resolvedSuggestion: SellerMappingResolvedSuggestion(
                            mappedName: 'Mapped Vendor',
                            mappedPan: 'ABCDE1234F',
                            source: 'backend_inferred',
                            helperText: 'Suggested seller',
                          ),
                          hasApplicableTdsImpact: true,
                          preflightReasonCode: 'unresolved_identity',
                          preflightReasonLabel: 'Unresolved Identity',
                          preflightReasonDetail: 'Needs review',
                          requiresDangerousReview: true,
                        ),
                      ],
                      tdsParties: const <String>['Mapped Vendor'],
                      existingMappings: const <SellerMapping>[],
                      blockedAliases: const <String>{},
                      tdsPartyPans: const <String, List<String>>{
                        'Mapped Vendor': <String>['ABCDE1234F'],
                      },
                    ),
                  ),
                );
            onResult(result);
          },
          child: const Text('Open Seller Mapping'),
        ),
      ),
    );
  }
}

class _SellerMappingDirectLaunchHarness extends StatelessWidget {
  final SellerMappingScreen screen;
  final ValueChanged<SellerMappingScreenResult?> onResult;

  const _SellerMappingDirectLaunchHarness({
    required this.screen,
    required this.onResult,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<SellerMappingScreenResult>(
                  MaterialPageRoute(builder: (_) => screen),
                );
            onResult(result);
          },
          child: const Text('Open Seller Mapping'),
        ),
      ),
    );
  }
}
