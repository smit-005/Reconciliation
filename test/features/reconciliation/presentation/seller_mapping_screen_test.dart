import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';

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
