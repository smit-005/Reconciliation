import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/reconciliation_screen.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/tds_26q_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/excel_upload_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DBHelper.debugResetForTest(
      databaseName: 'upload_workflow_smoke_integration_test.db',
    );
  });

  tearDownAll(() async {
    await DBHelper.debugResetForTest();
  });

  testWidgets(
    'upload workflow gates mapping review, seller review, and reconciliation',
    (tester) async {
      await _pumpUploadScreen(tester);

      expect(
        _buttonByKey<OutlinedButton>('review_mapping_button').onPressed,
        isNull,
      );
      expect(
        find.byKey(const ValueKey('review_seller_mappings_button')),
        findsNothing,
      );
      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNull,
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));

      state.setState(() {
        state.tdsRows = [_tdsRow()];
        state.tdsUploadFile = _tdsFile(rows: state.tdsRows);
      });
      await tester.pump();

      expect(
        _buttonByKey<OutlinedButton>('review_mapping_button').onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('review_seller_mappings_button')),
        findsOneWidget,
      );
      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNull,
      );

      final sourceRow = _ledgerRow();
      state.setState(() {
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [_ledgerFile(sourceRow)];
        state.ledgerRowsBySection['194C'] = [sourceRow];
      });
      await tester.pump();

      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('review_seller_mappings_button')),
      );
      await tester.pump();
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('seller_mapping_save_button')),
      );

      expect(
        _buttonByKey<FilledButton>('seller_mapping_save_button').onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('seller_mapping_save_button')),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            _buttonByKey<FilledButton>(
              'open_reconciliation_button',
            ).onPressed !=
            null,
      );

      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'review all mappings stays enabled only for workspace content and blocks seller review until mappings are confirmed',
    (tester) async {
      await _pumpUploadScreen(tester);

      expect(
        _buttonByKey<OutlinedButton>('review_mapping_button').onPressed,
        isNull,
      );

      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      final sourceRow = _ledgerRow();

      state.setState(() {
        state.tdsRows = [_tdsRow()];
        state.tdsUploadFile = _tdsFile(rows: state.tdsRows);
        state.selectedSections.add('194C');
        state.sectionFiles['194C'] = [
          _ledgerFile(
            sourceRow,
            mappingStatus: UploadMappingStatus.needsReview,
          ),
        ];
        state.ledgerRowsBySection['194C'] = [sourceRow];
      });
      await tester.pump();

      expect(
        _buttonByKey<OutlinedButton>('review_mapping_button').onPressed,
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('review_seller_mappings_button')),
        findsNothing,
      );
      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNull,
      );

      state.setState(() {
        state.sectionFiles['194C'] = [_ledgerFile(sourceRow)];
      });
      await tester.pump();

      expect(
        find.byKey(const ValueKey('review_seller_mappings_button')),
        findsOneWidget,
      );
      expect(
        _buttonByKey<FilledButton>('open_reconciliation_button').onPressed,
        isNull,
      );
    },
  );

  testWidgets('seller mapping saved review remains resolved after reopen', (
    tester,
  ) async {
    await _pumpUploadScreen(tester);
    final dynamic state = tester.state(find.byType(ExcelUploadScreen));
    _seedConfirmedWorkspace(state);
    await tester.pump();

    await _openSellerMapping(tester);
    expect(
      find.text(
        'All identity review items and unmatched 26Q exceptions are reviewed.',
      ),
      findsOneWidget,
    );
    expect(
      _buttonByKey<FilledButton>('seller_mapping_save_button').onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('seller_mapping_save_button')));
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          _buttonByKey<FilledButton>('open_reconciliation_button').onPressed !=
          null,
    );

    await _openSellerMapping(tester);
    expect(
      find.text(
        'All identity review items and unmatched 26Q exceptions are reviewed.',
      ),
      findsOneWidget,
    );
    expect(
      _buttonByKey<FilledButton>('seller_mapping_save_button').onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'reconciliation opens after confirmed upload and saved seller mapping',
    (tester) async {
      await _pumpUploadScreen(tester);
      final dynamic state = tester.state(find.byType(ExcelUploadScreen));
      _seedConfirmedWorkspace(state);
      await tester.pump();

      await _openSellerMapping(tester);
      await tester.tap(
        find.byKey(const ValueKey('seller_mapping_save_button')),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            _buttonByKey<FilledButton>(
              'open_reconciliation_button',
            ).onPressed !=
            null,
      );

      await tester.tap(
        find.byKey(const ValueKey('open_reconciliation_button')),
      );
      await tester.pump();
      await _pumpUntilFound(tester, find.byType(ReconciliationScreen));
      await _pumpUntilFound(tester, find.text('194C'));

      expect(find.text('Reconciliation - FY 2024-25'), findsOneWidget);
      expect(find.text('Buyer One'), findsOneWidget);
      expect(find.text('FY 2024-25', findRichText: true), findsWidgets);
      expect(find.text('194C'), findsWidgets);
    },
  );
}

Future<void> _pumpUploadScreen(WidgetTester tester) async {
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
        selectedFinancialYearId: 'fy-1',
        selectedFinancialYearLabel: '2024-25',
      ),
    ),
  );
}

T _buttonByKey<T extends ButtonStyleButton>(String key) {
  return find.byKey(ValueKey(key)).evaluate().single.widget as T;
}

Future<void> _openSellerMapping(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('review_seller_mappings_button')));
  await tester.pump();
  await _pumpUntilFound(
    tester,
    find.byKey(const ValueKey('seller_mapping_save_button')),
  );
}

void _seedConfirmedWorkspace(dynamic state) {
  final sourceRow = _ledgerRow();
  state.setState(() {
    state.tdsRows = [_tdsRow()];
    state.tdsUploadFile = _tdsFile(rows: state.tdsRows);
    state.selectedSections.add('194C');
    state.sectionFiles['194C'] = [_ledgerFile(sourceRow)];
    state.ledgerRowsBySection['194C'] = [sourceRow];
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    maxPumps: maxPumps,
  );
  expect(finder, findsWidgets);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }

  expect(condition(), isTrue);
}

LedgerUploadFile _ledgerFile(
  NormalizedLedgerRow row, {
  UploadMappingStatus mappingStatus = UploadMappingStatus.confirmed,
}) {
  return LedgerUploadFile(
    id: 'file-1',
    sectionCode: '194C',
    fileName: 'ledger.xlsx',
    bytes: const <int>[1, 2, 3],
    rowCount: 1,
    uploadedAt: DateTime(2026, 4, 24, 10),
    parserType: 'genericLedger',
    rows: [row],
    mappingStatus: mappingStatus,
    wasManuallyMapped: mappingStatus.isConfirmed,
    columnMapping: const {
      'date': 'Date',
      'party_name': 'Particulars',
      'amount': 'Debit',
    },
  );
}

Tds26QUploadFile _tdsFile({required List<Tds26QRow> rows}) {
  return Tds26QUploadFile(
    fileName: '26q.xlsx',
    bytes: const <int>[1, 2, 3],
    rowCount: rows.length,
    uploadedAt: DateTime(2026, 4, 24, 9),
    rows: rows,
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
}

NormalizedLedgerRow _ledgerRow() {
  return NormalizedLedgerRow(
    sourceType: 'generic_ledger',
    sourceFileName: 'ledger.xlsx',
    sectionCode: '194C',
    transactionDateRaw: '2024-04-15',
    month: 'Apr-2024',
    financialYear: '2024-25',
    partyName: 'Mapped Vendor',
    panNumber: 'ABCDE1234F',
    gstNo: '',
    documentNo: 'DOC-1',
    description: 'Ledger row',
    amount: 1200,
    taxableAmount: 1200,
    tdsAmount: 0,
    section: '194C',
  );
}

Tds26QRow _tdsRow() {
  return Tds26QRow(
    month: 'Apr-2024',
    financialYear: '2024-25',
    deducteeName: 'Mapped Vendor',
    panNumber: 'ABCDE1234F',
    deductedAmount: 1200,
    tds: 120,
    section: '194C',
    normalizedMonth: 'Apr-2024',
    normalizedSection: '194C',
  );
}
