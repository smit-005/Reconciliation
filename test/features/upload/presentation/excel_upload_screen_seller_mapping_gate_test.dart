import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/tds_26q_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/excel_upload_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'seller mapping financial year label handles empty and short values safely',
    () {
      expect(
        formatSellerMappingFinancialYearLabel(const <Tds26QRow>[]),
        'FY Unknown',
      );

      expect(
        formatSellerMappingFinancialYearLabel(<Tds26QRow>[
          _tdsRow(financialYear: ''),
        ]),
        'FY Unknown',
      );

      expect(
        formatSellerMappingFinancialYearLabel(<Tds26QRow>[
          _tdsRow(financialYear: '2024-25'),
        ]),
        'FY 2024-25',
      );

      expect(
        formatSellerMappingFinancialYearLabel(<Tds26QRow>[
          _tdsRow(financialYear: '202425'),
        ]),
        'FY 2024-25',
      );
    },
  );

  testWidgets(
    'Open Reconciliation stays disabled until seller mapping review is safe',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ExcelUploadScreen(
            selectedBuyerId: 'buyer-1',
            selectedBuyerName: 'Buyer One',
            selectedBuyerPan: 'ABCDE1234F',
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      final ledgerRow = _ledgerRow();
      final ledgerFile = LedgerUploadFile(
        id: 'file-1',
        sectionCode: '194C',
        fileName: 'ledger.xlsx',
        bytes: const <int>[1, 2, 3],
        rowCount: 1,
        uploadedAt: DateTime(2026, 4, 24, 10, 0),
        parserType: 'genericLedger',
        rows: [ledgerRow],
        mappingStatus: UploadMappingStatus.confirmed,
        wasManuallyMapped: true,
        columnMapping: const {
          'date': 'Date',
          'party_name': 'Particulars',
          'amount': 'Debit',
        },
      );

      state.setState(() {
        state.tdsRows = [_tdsRow()];
        state.tdsUploadFile = Tds26QUploadFile(
          fileName: '26q.xlsx',
          bytes: const <int>[1, 2, 3],
          rowCount: 1,
          uploadedAt: DateTime(2026, 4, 24, 9, 0),
          rows: state.tdsRows,
          mappingStatus: UploadMappingStatus.confirmed,
          wasManuallyMapped: true,
          columnMapping: const {
            'party_name': 'Deductee Name',
            'pan_number': 'PAN',
            'section': 'Section',
            'amount_paid': 'Amount Paid',
            'tds_amount': 'TDS',
            'date_month': 'Month',
          },
        );
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [ledgerFile];
        state.ledgerRowsBySection['194C'] = [ledgerRow];
      });

      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open Reconciliation').last,
      );

      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'seller mapping preflight refresh enables Open Reconciliation after saving review',
    (tester) async {
      await _clearMappings('ABCDE1234F');

      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ExcelUploadScreen(
            selectedBuyerId: 'buyer-1',
            selectedBuyerName: 'Buyer One',
            selectedBuyerPan: 'ABCDE1234F',
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      final ledgerRow = _ledgerRow(partyName: 'Alias Vendor');
      final ledgerFile = LedgerUploadFile(
        id: 'file-1',
        sectionCode: '194C',
        fileName: 'ledger.xlsx',
        bytes: const <int>[1, 2, 3],
        rowCount: 1,
        uploadedAt: DateTime(2026, 4, 24, 10, 0),
        parserType: 'genericLedger',
        rows: [ledgerRow],
        mappingStatus: UploadMappingStatus.confirmed,
        wasManuallyMapped: true,
        columnMapping: const {
          'date': 'Date',
          'party_name': 'Particulars',
          'amount': 'Debit',
        },
      );

      state.setState(() {
        state.tdsRows = [_tdsRow(name: 'Mapped Vendor')];
        state.tdsUploadFile = Tds26QUploadFile(
          fileName: '26q.xlsx',
          bytes: const <int>[1, 2, 3],
          rowCount: 1,
          uploadedAt: DateTime(2026, 4, 24, 9, 0),
          rows: state.tdsRows,
          mappingStatus: UploadMappingStatus.confirmed,
          wasManuallyMapped: true,
          columnMapping: const {
            'party_name': 'Deductee Name',
            'pan_number': 'PAN',
            'section': 'Section',
            'amount_paid': 'Amount Paid',
            'tds_amount': 'TDS',
            'date_month': 'Month',
          },
        );
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [ledgerFile];
        state.ledgerRowsBySection['194C'] = [ledgerRow];
      });

      await tester.pumpAndSettle();

      expect(state.canOpenReconciliation, isFalse);

      await SellerMappingService.saveMapping(
        SellerMapping(
          buyerName: 'Buyer One',
          buyerPan: 'ABCDE1234F',
          aliasName: 'Alias Vendor',
          sectionCode: '194C',
          mappedPan: 'ABCDE1234F',
          mappedName: 'Mapped Vendor',
        ),
      );

      await state.refreshSellerMappingPreflightForTest();
      await tester.pumpAndSettle();

      expect(state.canOpenReconciliation, isTrue);
      expect(state.isSellerMappingConfirmedForTest, isTrue);
    },
  );

  testWidgets(
    'Review All Mappings lists uploaded files and confirms safe mappings in one place',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ExcelUploadScreen(
            selectedBuyerId: 'buyer-1',
            selectedBuyerName: 'Buyer One',
            selectedBuyerPan: 'ABCDE1234F',
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      final ledgerRow = _ledgerRow();
      final ledgerFile = LedgerUploadFile(
        id: 'file-1',
        sectionCode: '194C',
        fileName: 'ledger.xlsx',
        bytes: const <int>[1, 2, 3],
        rowCount: 1,
        uploadedAt: DateTime(2026, 4, 24, 10, 0),
        parserType: 'genericLedger',
        rows: [ledgerRow],
        mappingStatus: UploadMappingStatus.autoMapped,
        wasManuallyMapped: false,
        columnMapping: const {
          'date': 'Date',
          'party_name': 'Particulars',
          'amount': 'Debit',
        },
      );

      state.setState(() {
        state.tdsRows = [_tdsRow()];
        state.tdsUploadFile = Tds26QUploadFile(
          fileName: '26q.xlsx',
          bytes: const <int>[1, 2, 3],
          rowCount: 1,
          uploadedAt: DateTime(2026, 4, 24, 9, 0),
          rows: state.tdsRows,
          mappingStatus: UploadMappingStatus.autoMapped,
          wasManuallyMapped: false,
          columnMapping: const {
            'party_name': 'Deductee Name',
            'pan_number': 'PAN',
            'section': 'Section',
            'amount_paid': 'Amount Paid',
            'tds_amount': 'TDS',
            'date_month': 'Month',
          },
        );
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [ledgerFile];
        state.ledgerRowsBySection['194C'] = [ledgerRow];
      });

      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Review All Mappings').first);
      await tester.pumpAndSettle();

      expect(find.text('Review All Mappings'), findsWidgets);
      expect(find.text('26q.xlsx'), findsOneWidget);
      expect(find.text('ledger.xlsx'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm All Safe Mappings'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Back to Upload'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Review Seller Mappings'), findsWidgets);
    },
  );

  testWidgets(
    'Review All Mappings keeps seller mapping blocked when any file still needs review',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ExcelUploadScreen(
            selectedBuyerId: 'buyer-1',
            selectedBuyerName: 'Buyer One',
            selectedBuyerPan: 'ABCDE1234F',
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      final ledgerRow = _ledgerRow();
      final ledgerFile = LedgerUploadFile(
        id: 'file-1',
        sectionCode: '194C',
        fileName: 'ledger.xlsx',
        bytes: const <int>[1, 2, 3],
        rowCount: 1,
        uploadedAt: DateTime(2026, 4, 24, 10, 0),
        parserType: 'genericLedger',
        rows: [ledgerRow],
        mappingStatus: UploadMappingStatus.needsReview,
        wasManuallyMapped: false,
        columnMapping: const {
          'date': 'Date',
          'party_name': 'Particulars',
        },
      );

      state.setState(() {
        state.tdsRows = [_tdsRow()];
        state.tdsUploadFile = Tds26QUploadFile(
          fileName: '26q.xlsx',
          bytes: const <int>[1, 2, 3],
          rowCount: 1,
          uploadedAt: DateTime(2026, 4, 24, 9, 0),
          rows: state.tdsRows,
          mappingStatus: UploadMappingStatus.confirmed,
          wasManuallyMapped: true,
          columnMapping: const {
            'party_name': 'Deductee Name',
            'pan_number': 'PAN',
            'section': 'Section',
            'amount_paid': 'Amount Paid',
            'tds_amount': 'TDS',
            'date_month': 'Month',
          },
        );
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [ledgerFile];
        state.ledgerRowsBySection['194C'] = [ledgerRow];
      });

      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Review Seller Mappings'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Review All Mappings').first);
      await tester.pumpAndSettle();

      expect(find.text('ledger.xlsx'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Review'), findsWidgets);
      final confirmAllButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm All Safe Mappings'),
      );
      expect(confirmAllButton.onPressed, isNull);
    },
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

NormalizedLedgerRow _ledgerRow({String partyName = 'Ledger Vendor'}) {
  return NormalizedLedgerRow(
    sourceType: 'generic_ledger',
    sourceFileName: 'ledger.xlsx',
    sectionCode: '194C',
    transactionDateRaw: '2024-04-15',
    month: 'Apr-2024',
    financialYear: '2024-25',
    partyName: partyName,
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

Tds26QRow _tdsRow({
  String financialYear = '2024-25',
  String name = '26Q Vendor',
}) {
  return Tds26QRow(
    month: 'Apr-2024',
    financialYear: financialYear,
    deducteeName: name,
    panNumber: 'ABCDE1234F',
    deductedAmount: 1200,
    tds: 120,
    section: '194C',
    normalizedMonth: 'Apr-2024',
    normalizedSection: '194C',
  );
}
