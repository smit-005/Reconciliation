import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/data/local/db_helper.dart';
import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/import_format_profile.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';
import 'package:reconciliation_app/features/upload/services/import_profile_service.dart';
import 'package:reconciliation_app/features/upload/services/import_upload_flow_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUpAll(() async {
    await DBHelper.debugResetForTest(
      databaseName: 'tds_reconciliation_sheet_selection_test.db',
    );
  });

  tearDownAll(() async {
    await DBHelper.debugResetForTest();
  });

  setUp(() async {
    final db = await DBHelper.database;
    await db.delete('import_format_profiles');
    await db.delete('staged_purchase_rows');
    await db.delete('staged_26q_rows');
  });

  group('ImportUploadFlowService sheet selection', () {
    test('generic ledger safe auto-map is auto-confirmed', () async {
      final bytes = _buildWorkbook({
        'Ledger': const [
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      var mappingOpened = false;

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194C',
        bytes: bytes,
        fileName: 'safe-ledger.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingOpened, isFalse);
      expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
      expect(response.data!.wasAutoConfirmed, isTrue);
      expect(response.data!.wasManuallyMapped, isFalse);
    });

    test('explicit generic ledger section mismatch needs review', () async {
      final bytes = _buildWorkbook({
        'Ledger': const [
          ['Date', 'Party Name', 'Amount', 'Section'],
          ['2024-04-02', 'Selected Vendor', 222, '194C'],
        ],
      });

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194H',
        bytes: bytes,
        fileName: 'ledger.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.mappingStatus, UploadMappingStatus.needsReview);
      expect(response.data!.wasAutoConfirmed, isFalse);
      expect(response.data!.parsedRows.single.section, '194H');
    });

    test('mixed explicit generic ledger sections need review', () async {
      final bytes = _buildWorkbook({
        'Ledger': const [
          ['Date', 'Party Name', 'Amount', 'TDS Section'],
          ['2024-04-02', 'Selected Vendor', 222, '194C'],
          ['2024-04-03', 'Second Vendor', 333, '194H'],
        ],
      });

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194C',
        bytes: bytes,
        fileName: 'ledger.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.mappingStatus, UploadMappingStatus.needsReview);
      expect(response.data!.wasAutoConfirmed, isFalse);
      expect(
        response.data!.parsedRows.every((row) => row.section == '194C'),
        isTrue,
      );
    });

    test(
      'matching explicit generic ledger section can still auto-confirm',
      () async {
        final bytes = _buildWorkbook({
          'Ledger': const [
            ['Date', 'Party Name', 'Amount', 'Section Code'],
            ['2024-04-02', 'Selected Vendor', 222, '194C'],
          ],
        });

        final response =
            await ImportUploadFlowService.prepareGenericLedgerImport(
              buyerId: 'buyer-1',
              sectionCode: '194C',
              bytes: bytes,
              fileName: 'ledger.xlsx',
              preferredSheetName: 'Ledger',
              openColumnMapping: _unexpectedColumnMapping,
            );

        expect(response.isSuccess, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isTrue);
      },
    );

    test('generic ledger filename section mismatch needs review', () async {
      final bytes = _buildWorkbook({
        'Ledger': const [
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });

      final validation = ExcelService.validateGenericLedgerFile(
        bytes,
        preferredSheetName: 'Ledger',
        expectedSection: '194H',
        sourceFileName: 'ledger_194C.xlsx',
      );
      expect(validation.warnings, isNotEmpty);

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194H',
        bytes: bytes,
        fileName: 'ledger_194C.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.mappingStatus, UploadMappingStatus.needsReview);
      expect(response.data!.wasAutoConfirmed, isFalse);
    });

    test(
      'generic ledger with no section signal keeps existing auto-confirm behavior',
      () async {
        final bytes = _buildWorkbook({
          'Ledger': const [
            ['Date', 'Party Name', 'Amount'],
            ['2024-04-02', 'Selected Vendor', 222],
          ],
        });

        final validation = ExcelService.validateGenericLedgerFile(
          bytes,
          preferredSheetName: 'Ledger',
          expectedSection: '194H',
          sourceFileName: 'ledger.xlsx',
        );
        expect(validation.warnings, isEmpty);

        final response =
            await ImportUploadFlowService.prepareGenericLedgerImport(
              buyerId: 'buyer-1',
              sectionCode: '194H',
              bytes: bytes,
              fileName: 'ledger.xlsx',
              preferredSheetName: 'Ledger',
              openColumnMapping: _unexpectedColumnMapping,
            );

        expect(response.isSuccess, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isTrue);
      },
    );

    test(
      'saved generic ledger profile still needs review on section mismatch',
      () async {
        final bytes = _buildWorkbook({
          'Ledger': const [
            ['Date', 'Party Name', 'Amount', 'Section'],
            ['2024-04-02', 'Selected Vendor', 222, '194C'],
          ],
        });
        final sampleSignature = ExcelService.buildSampleSignature(
          'Ledger',
          const ['Date', 'Party Name', 'Amount', 'Section'],
        );
        await ImportProfileService.saveProfile(
          ImportFormatProfile(
            buyerId: 'buyer-1',
            fileType: ImportMappingService.genericLedgerFileType,
            sheetNamePattern: 'ledger',
            headerRowIndex: 0,
            headersTrusted: true,
            columnMapping: const {
              'date': 'Date',
              'party_name': 'Party Name',
              'amount': 'Amount',
            },
            sampleSignature: sampleSignature,
            lastUsedAt: DateTime(2026, 5, 16).toIso8601String(),
          ),
        );

        final response =
            await ImportUploadFlowService.prepareGenericLedgerImport(
              buyerId: 'buyer-1',
              sectionCode: '194H',
              bytes: bytes,
              fileName: 'ledger.xlsx',
              preferredSheetName: 'Ledger',
              openColumnMapping: _unexpectedColumnMapping,
            );

        expect(response.isSuccess, isTrue);
        expect(response.data!.usedSavedProfile, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.needsReview);
        expect(response.data!.wasAutoConfirmed, isFalse);
      },
    );

    test('194Q purchase safe auto-map requires basic amount', () async {
      final bytes = _buildWorkbook({
        'Purchase': const [
          ['Bill Date', 'Bill No', 'Party Name', 'Basic Amount'],
          ['2024-04-02', 'INV-1', 'Selected Vendor', 222],
        ],
      });
      var mappingOpened = false;

      final response = await ImportUploadFlowService.preparePurchaseImport(
        buyerId: 'buyer-1',
        bytes: bytes,
        fileName: 'safe-purchase.xlsx',
        preferredSheetName: 'Purchase',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingOpened, isFalse);
      expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
      expect(response.data!.wasAutoConfirmed, isTrue);
    });

    test(
      '194Q purchase with bill amount but no basic amount needs review',
      () async {
        final bytes = _buildWorkbook({
          'Purchase': const [
            ['Bill Date', 'Bill No', 'Party Name', 'Bill Amount'],
            ['2024-04-02', 'INV-1', 'Selected Vendor', 222],
          ],
        });

        final response = await ImportUploadFlowService.preparePurchaseImport(
          buyerId: 'buyer-1',
          bytes: bytes,
          fileName: 'bill-only-purchase.xlsx',
          preferredSheetName: 'Purchase',
          openColumnMapping:
              ({
                required bytes,
                required fileName,
                required fileType,
                required validation,
                sessionCache,
                preferredSheetName,
                preferredHeaderRowIndex,
                preferredHeadersTrusted,
                preferredColumnMapping,
              }) async {
                return null;
              },
        );

        expect(response.isSuccess, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.needsReview);
        expect(response.data!.wasAutoConfirmed, isFalse);
      },
    );

    test(
      'saved purchase sheet-name profile with reordered columns requires review',
      () async {
        await ImportProfileService.saveProfile(
          ImportFormatProfile(
            buyerId: 'buyer-1',
            fileType: ImportMappingService.purchaseFileType,
            sheetNamePattern: 'purchase',
            headerRowIndex: 0,
            headersTrusted: true,
            columnMapping: const {
              'date': 'COL_0',
              'party_name': 'COL_1',
              'basic_amount': 'COL_2',
            },
            sampleSignature: ExcelService.buildSampleSignature(
              'Purchase',
              const ['Bill Date', 'Party Name', 'Basic Amount'],
            ),
            lastUsedAt: DateTime(2026, 5, 16).toIso8601String(),
          ),
        );
        final bytes = _buildWorkbook({
          'Purchase': const [
            ['Party Name', 'Basic Amount', 'Bill Date'],
            ['Selected Vendor', 222, '2024-04-02'],
          ],
        });
        var mappingOpened = false;

        final response = await ImportUploadFlowService.preparePurchaseImport(
          buyerId: 'buyer-1',
          bytes: bytes,
          fileName: 'reordered-purchase.xlsx',
          preferredSheetName: 'Purchase',
          openColumnMapping:
              ({
                required bytes,
                required fileName,
                required fileType,
                required validation,
                sessionCache,
                preferredSheetName,
                preferredHeaderRowIndex,
                preferredHeadersTrusted,
                preferredColumnMapping,
              }) async {
                mappingOpened = true;
                expect(preferredColumnMapping, {
                  'date': 'COL_0',
                  'party_name': 'COL_1',
                  'basic_amount': 'COL_2',
                });
                return const ColumnMappingResult(
                  fileType: ImportMappingService.purchaseFileType,
                  sheetName: 'Purchase',
                  headerRowIndex: 0,
                  headersTrusted: true,
                  saveProfile: false,
                  rawToCanonicalMapping: {
                    'COL_0': 'party_name',
                    'COL_1': 'basic_amount',
                    'COL_2': 'date',
                  },
                  columnMapping: {
                    'party_name': 'COL_0',
                    'basic_amount': 'COL_1',
                    'date': 'COL_2',
                  },
                );
              },
        );

        expect(response.isSuccess, isTrue);
        expect(mappingOpened, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isFalse);
        expect(response.data!.wasManuallyMapped, isTrue);
        expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
      },
    );

    test('exact purchase saved profile still auto-confirms', () async {
      const headers = ['Bill Date', 'Party Name', 'Basic Amount'];
      final sampleSignature = ExcelService.buildSampleSignature(
        'Purchase',
        headers,
      );
      await ImportProfileService.saveProfile(
        ImportFormatProfile(
          buyerId: 'buyer-1',
          fileType: ImportMappingService.purchaseFileType,
          sheetNamePattern: 'purchase',
          headerRowIndex: 0,
          headersTrusted: true,
          columnMapping: const {
            'date': 'Bill Date',
            'party_name': 'Party Name',
            'basic_amount': 'Basic Amount',
          },
          sampleSignature: sampleSignature,
          lastUsedAt: DateTime(2026, 5, 16).toIso8601String(),
        ),
      );
      final bytes = _buildWorkbook({
        'Purchase': const [
          headers,
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      var mappingOpened = false;

      final response = await ImportUploadFlowService.preparePurchaseImport(
        buyerId: 'buyer-1',
        bytes: bytes,
        fileName: 'exact-purchase.xlsx',
        preferredSheetName: 'Purchase',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingOpened, isFalse);
      expect(response.data!.usedSavedProfile, isTrue);
      expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
      expect(response.data!.wasAutoConfirmed, isTrue);
      expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
    });

    test(
      'newer purchase sheet-name profile does not beat older exact profile',
      () async {
        const headers = ['Bill Date', 'Party Name', 'Basic Amount'];
        await ImportProfileService.saveProfile(
          ImportFormatProfile(
            buyerId: 'buyer-1',
            fileType: ImportMappingService.purchaseFileType,
            sheetNamePattern: 'purchase',
            headerRowIndex: 0,
            headersTrusted: true,
            columnMapping: const {
              'date': 'COL_0',
              'party_name': 'COL_1',
              'basic_amount': 'COL_2',
            },
            sampleSignature: ExcelService.buildSampleSignature(
              'Purchase',
              const ['Party Name', 'Basic Amount', 'Bill Date'],
            ),
            lastUsedAt: DateTime(2026, 5, 17).toIso8601String(),
          ),
        );
        await ImportProfileService.saveProfile(
          ImportFormatProfile(
            buyerId: 'buyer-1',
            fileType: ImportMappingService.purchaseFileType,
            sheetNamePattern: 'purchase',
            headerRowIndex: 0,
            headersTrusted: true,
            columnMapping: const {
              'date': 'Bill Date',
              'party_name': 'Party Name',
              'basic_amount': 'Basic Amount',
            },
            sampleSignature: ExcelService.buildSampleSignature(
              'Purchase',
              headers,
            ),
            lastUsedAt: DateTime(2026, 5, 16).toIso8601String(),
          ),
        );
        final bytes = _buildWorkbook({
          'Purchase': const [
            headers,
            ['2024-04-02', 'Selected Vendor', 222],
          ],
        });
        var mappingOpened = false;

        final response = await ImportUploadFlowService.preparePurchaseImport(
          buyerId: 'buyer-1',
          bytes: bytes,
          fileName: 'exact-over-newer-sheet-profile.xlsx',
          preferredSheetName: 'Purchase',
          openColumnMapping:
              ({
                required bytes,
                required fileName,
                required fileType,
                required validation,
                sessionCache,
                preferredSheetName,
                preferredHeaderRowIndex,
                preferredHeadersTrusted,
                preferredColumnMapping,
              }) async {
                mappingOpened = true;
                return null;
              },
        );

        expect(response.isSuccess, isTrue);
        expect(mappingOpened, isFalse);
        expect(response.data!.usedSavedProfile, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isTrue);
        expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
      },
    );

    test(
      'generic ledger sheet-name saved profile opens mapping review',
      () async {
        await ImportProfileService.saveProfile(
          ImportFormatProfile(
            buyerId: 'buyer-1',
            fileType: ImportMappingService.genericLedgerFileType,
            sheetNamePattern: 'ledger',
            headerRowIndex: 0,
            headersTrusted: true,
            columnMapping: const {
              'date': 'COL_0',
              'party_name': 'COL_1',
              'amount': 'COL_2',
            },
            sampleSignature: ExcelService.buildSampleSignature('Ledger', const [
              'Date',
              'Party Name',
              'Amount',
            ]),
            lastUsedAt: DateTime(2026, 5, 16).toIso8601String(),
          ),
        );
        final bytes = _buildWorkbook({
          'Ledger': const [
            ['Party Name', 'Amount', 'Date'],
            ['Selected Vendor', 222, '2024-04-02'],
          ],
        });
        var mappingOpened = false;

        final response =
            await ImportUploadFlowService.prepareGenericLedgerImport(
              buyerId: 'buyer-1',
              sectionCode: '194C',
              bytes: bytes,
              fileName: 'reordered-ledger.xlsx',
              preferredSheetName: 'Ledger',
              openColumnMapping:
                  ({
                    required bytes,
                    required fileName,
                    required fileType,
                    required validation,
                    sessionCache,
                    preferredSheetName,
                    preferredHeaderRowIndex,
                    preferredHeadersTrusted,
                    preferredColumnMapping,
                  }) async {
                    mappingOpened = true;
                    expect(preferredColumnMapping, {
                      'date': 'COL_0',
                      'party_name': 'COL_1',
                      'amount': 'COL_2',
                    });
                    return const ColumnMappingResult(
                      fileType: ImportMappingService.genericLedgerFileType,
                      sheetName: 'Ledger',
                      headerRowIndex: 0,
                      headersTrusted: true,
                      saveProfile: false,
                      rawToCanonicalMapping: {
                        'COL_0': 'party_name',
                        'COL_1': 'amount',
                        'COL_2': 'date',
                      },
                      columnMapping: {
                        'party_name': 'COL_0',
                        'amount': 'COL_1',
                        'date': 'COL_2',
                      },
                    );
                  },
            );

        expect(response.isSuccess, isTrue);
        expect(mappingOpened, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isFalse);
        expect(response.data!.wasManuallyMapped, isTrue);
        expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
      },
    );

    test('generic ledger selected sheet detects header at row 45', () async {
      final bytes = _buildWorkbook({
        'Ledger': [
          ..._decorativePrelude(44),
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194C',
        bytes: bytes,
        fileName: 'deep-ledger.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.sheetName, 'Ledger');
      expect(response.data!.headerRowIndex, 44);
      expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
    });

    test('purchase selected sheet skips decorative prelude', () async {
      final bytes = _buildWorkbook({
        'Purchase': [
          ..._decorativePrelude(52),
          ['Bill Date', 'Bill No', 'Party Name', 'Basic Amount'],
          ['2024-04-02', 'INV-1', 'Selected Vendor', 222],
        ],
      });

      final response = await ImportUploadFlowService.preparePurchaseImport(
        buyerId: 'buyer-1',
        bytes: bytes,
        fileName: 'deep-purchase.xlsx',
        preferredSheetName: 'Purchase',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.sheetName, 'Purchase');
      expect(response.data!.headerRowIndex, 52);
      expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
    });

    test('selected noise-only workbook still fails safely', () async {
      final bytes = _buildWorkbook({'Ledger': _decorativePrelude(70)});
      var mappingOpened = false;

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194C',
        bytes: bytes,
        fileName: 'noise-only.xlsx',
        preferredSheetName: 'Ledger',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isFailure, isTrue);
      expect(mappingOpened, isFalse);
    });

    test('26Q selected sheet detects delayed header', () async {
      final bytes = _buildWorkbook({
        '26Q': [
          ..._decorativePrelude(24),
          ['Date', 'Deductee Name', 'PAN', 'Amount Paid', 'TDS', 'Section'],
          ['Apr-24', 'Selected Vendor', 'ABCDE1234F', 2220, 222, '194C'],
        ],
      });
      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
        preferredSheetName: '26Q',
      );

      expect(validation.isValid, isTrue);
      expect(validation.headerRowIndex, 24);

      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: 'deep-26q.xlsx',
        validation: validation,
        preferredSheetName: '26Q',
        openColumnMapping: _unexpectedColumnMapping,
      );

      expect(response.isSuccess, isTrue);
      expect(response.data!.sheetName, '26Q');
      expect(response.data!.headerRowIndex, 24);
      expect(response.data!.parsedRows.single.deducteeName, 'Selected Vendor');
    });

    test('26Q safe auto-map is auto-confirmed', () async {
      final bytes = _buildWorkbook({
        '26Q': const [
          ['Date', 'Deductee Name', 'PAN', 'Amount Paid', 'TDS', 'Section'],
          ['Apr-24', 'Selected Vendor', 'ABCDE1234F', 2220, 222, '194C'],
        ],
      });
      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
        preferredSheetName: '26Q',
      );
      var mappingOpened = false;

      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: 'safe-26q.xlsx',
        validation: validation,
        preferredSheetName: '26Q',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingOpened, isFalse);
      expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
      expect(response.data!.wasAutoConfirmed, isTrue);
    });

    test(
      '26Q unusual plausible headers open mapping instead of failing',
      () async {
        final bytes = _buildWorkbook({
          '26Q': const [
            [
              'Month',
              'Deductee Name',
              'PAN',
              'Gross Payment',
              'Tax Deducted',
              'Section',
            ],
            ['Apr-24', 'Selected Vendor', 'ABCDE1234F', 2220, 222, '194C'],
          ],
        });
        final validation = await ImportUploadFlowService.validateTds26QImport(
          bytes,
          preferredSheetName: '26Q',
        );
        var mappingOpened = false;

        expect(validation.isValid, isTrue);
        expect(validation.decision, ExcelImportDecision.manualReview);
        expect(validation.message, contains('column detection is incomplete'));

        final response = await ImportUploadFlowService.prepareTds26QImport(
          bytes: bytes,
          fileName: 'unusual-26q.xlsx',
          validation: validation,
          preferredSheetName: '26Q',
          openColumnMapping:
              ({
                required bytes,
                required fileName,
                required fileType,
                required validation,
                sessionCache,
                preferredSheetName,
                preferredHeaderRowIndex,
                preferredHeadersTrusted,
                preferredColumnMapping,
              }) async {
                mappingOpened = true;
                expect(fileType, ExcelImportType.tds26q);
                expect(validation.detectedSheet, '26Q');
                return const ColumnMappingResult(
                  fileType: ImportMappingService.tds26qFileType,
                  sheetName: '26Q',
                  headerRowIndex: 0,
                  headersTrusted: true,
                  saveProfile: false,
                  rawToCanonicalMapping: {
                    'COL_0': 'date_month',
                    'COL_1': 'party_name',
                    'COL_2': 'pan_number',
                    'COL_3': 'amount_paid',
                    'COL_4': 'tds_amount',
                    'COL_5': 'section',
                  },
                  columnMapping: {
                    'date_month': 'COL_0',
                    'party_name': 'COL_1',
                    'pan_number': 'COL_2',
                    'amount_paid': 'COL_3',
                    'tds_amount': 'COL_4',
                    'section': 'COL_5',
                  },
                );
              },
        );

        expect(response.isSuccess, isTrue);
        expect(mappingOpened, isTrue);
        expect(response.data!.mappingStatus, UploadMappingStatus.confirmed);
        expect(response.data!.wasAutoConfirmed, isFalse);
        expect(response.data!.wasManuallyMapped, isTrue);
        expect(
          response.data!.parsedRows.single.deducteeName,
          'Selected Vendor',
        );
      },
    );

    test('26Q selected sheet with no plausible header still fails', () async {
      final bytes = _buildWorkbook({
        '26Q': const [
          ['Summary', 'Totals'],
          ['Not a deductee row', 'Still not 26Q'],
        ],
      });
      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
        preferredSheetName: '26Q',
      );
      var mappingOpened = false;

      expect(validation.isValid, isFalse);
      expect(validation.decision, ExcelImportDecision.invalidMapping);

      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: 'invalid-26q.xlsx',
        validation: validation,
        preferredSheetName: '26Q',
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingOpened = true;
              return null;
            },
      );

      expect(response.isFailure, isTrue);
      expect(mappingOpened, isFalse);
    });

    test('generic ledger uses selected sheet before forced mapping', () async {
      final bytes = _buildWorkbook({
        'Wrong First': const [
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-01', 'Wrong Vendor', 111],
        ],
        'Ledger': const [
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      final mappingCalls = <String?>[];

      final response = await ImportUploadFlowService.prepareGenericLedgerImport(
        buyerId: 'buyer-1',
        sectionCode: '194C',
        bytes: bytes,
        fileName: 'multi-ledger.xlsx',
        preferredSheetName: 'Ledger',
        forceColumnMapping: true,
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingCalls.add(preferredSheetName);
              expect(fileType, ExcelImportType.genericLedger);
              expect(validation.detectedSheet, 'Ledger');
              return const ColumnMappingResult(
                fileType: ImportMappingService.genericLedgerFileType,
                sheetName: 'Ledger',
                headerRowIndex: 0,
                headersTrusted: true,
                saveProfile: false,
                rawToCanonicalMapping: {
                  'COL_0': 'date',
                  'COL_1': 'party_name',
                  'COL_2': 'amount',
                },
                columnMapping: {
                  'date': 'COL_0',
                  'party_name': 'COL_1',
                  'amount': 'COL_2',
                },
              );
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingCalls, ['Ledger']);
      expect(response.data!.sheetName, 'Ledger');
      expect(response.data!.wasManuallyMapped, isTrue);
      expect(response.data!.parsedRows, hasLength(1));
      expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
    });

    test('194Q purchase uses selected sheet before forced mapping', () async {
      final bytes = _buildWorkbook({
        'Wrong First': const [
          ['Bill Date', 'Party Name', 'Basic Amount'],
          ['2024-04-01', 'Wrong Vendor', 111],
        ],
        'Purchase': const [
          ['Bill Date', 'Party Name', 'Basic Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      final mappingCalls = <String?>[];

      final response = await ImportUploadFlowService.preparePurchaseImport(
        buyerId: 'buyer-1',
        bytes: bytes,
        fileName: 'multi-purchase.xlsx',
        preferredSheetName: 'Purchase',
        forceColumnMapping: true,
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingCalls.add(preferredSheetName);
              expect(fileType, ExcelImportType.purchase);
              expect(validation.detectedSheet, 'Purchase');
              return const ColumnMappingResult(
                fileType: ImportMappingService.purchaseFileType,
                sheetName: 'Purchase',
                headerRowIndex: 0,
                headersTrusted: true,
                saveProfile: false,
                rawToCanonicalMapping: {
                  'COL_0': 'date',
                  'COL_1': 'party_name',
                  'COL_2': 'basic_amount',
                },
                columnMapping: {
                  'date': 'COL_0',
                  'party_name': 'COL_1',
                  'basic_amount': 'COL_2',
                },
              );
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingCalls, ['Purchase']);
      expect(response.data!.sheetName, 'Purchase');
      expect(response.data!.wasManuallyMapped, isTrue);
      expect(response.data!.parsedRows, hasLength(1));
      expect(response.data!.parsedRows.single.partyName, 'Selected Vendor');
    });

    test('26Q uses selected sheet before forced mapping', () async {
      final bytes = _buildWorkbook({
        'Wrong First': const [
          ['Date', 'Deductee Name', 'PAN', 'Amount Paid', 'TDS', 'Section'],
          ['Apr-24', 'Wrong Vendor', 'ABCDE1234F', 1110, 111, '194C'],
        ],
        '26Q': const [
          ['Date', 'Deductee Name', 'PAN', 'Amount Paid', 'TDS', 'Section'],
          ['Apr-24', 'Selected Vendor', 'ABCDE1234F', 2220, 222, '194C'],
        ],
      });
      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
        preferredSheetName: '26Q',
      );
      final mappingCalls = <String?>[];

      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: 'multi-26q.xlsx',
        validation: validation,
        preferredSheetName: '26Q',
        forceColumnMapping: true,
        openColumnMapping:
            ({
              required bytes,
              required fileName,
              required fileType,
              required validation,
              sessionCache,
              preferredSheetName,
              preferredHeaderRowIndex,
              preferredHeadersTrusted,
              preferredColumnMapping,
            }) async {
              mappingCalls.add(preferredSheetName);
              expect(fileType, ExcelImportType.tds26q);
              expect(validation.detectedSheet, '26Q');
              return const ColumnMappingResult(
                fileType: ImportMappingService.tds26qFileType,
                sheetName: '26Q',
                headerRowIndex: 0,
                headersTrusted: true,
                saveProfile: false,
                rawToCanonicalMapping: {
                  'COL_0': 'date_month',
                  'COL_1': 'party_name',
                  'COL_2': 'pan_number',
                  'COL_3': 'amount_paid',
                  'COL_4': 'tds_amount',
                  'COL_5': 'section',
                },
                columnMapping: {
                  'date_month': 'COL_0',
                  'party_name': 'COL_1',
                  'pan_number': 'COL_2',
                  'amount_paid': 'COL_3',
                  'tds_amount': 'COL_4',
                  'section': 'COL_5',
                },
              );
            },
      );

      expect(response.isSuccess, isTrue);
      expect(mappingCalls, ['26Q']);
      expect(response.data!.sheetName, '26Q');
      expect(response.data!.wasManuallyMapped, isTrue);
      expect(response.data!.parsedRows, hasLength(1));
      expect(response.data!.parsedRows.single.deducteeName, 'Selected Vendor');
    });

    test('remapped purchase file preserves source ledger metadata', () async {
      final uploadedAt = DateTime(2026, 5, 17, 10, 30);
      final bytes = _buildWorkbook({
        'Purchase': const [
          ['Bill Date', 'Party Name', 'Basic Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      final file = LedgerUploadFile(
        id: 'purchase-source-id',
        sectionCode: '194Q',
        fileName: 'original-purchase.xlsx',
        bytes: bytes,
        rowCount: 1,
        uploadedAt: uploadedAt,
        parserType: 'purchase',
        rows: const [],
        mappingStatus: UploadMappingStatus.needsReview,
        wasManuallyMapped: false,
        columnMapping: const {},
      );

      final response = await ImportUploadFlowService.prepareSectionFileRemap(
        file: file,
        columnMappingResult: const ColumnMappingResult(
          fileType: ImportMappingService.purchaseFileType,
          sheetName: 'Purchase',
          headerRowIndex: 0,
          headersTrusted: true,
          saveProfile: false,
          rawToCanonicalMapping: {
            'COL_0': 'date',
            'COL_1': 'party_name',
            'COL_2': 'basic_amount',
          },
          columnMapping: {
            'date': 'COL_0',
            'party_name': 'COL_1',
            'basic_amount': 'COL_2',
          },
        ),
      );

      expect(response.isSuccess, isTrue);
      final updatedFile = response.data!.updatedFile;
      expect(updatedFile.id, 'purchase-source-id');
      expect(updatedFile.fileName, 'original-purchase.xlsx');
      expect(updatedFile.uploadedAt, uploadedAt);
      expect(updatedFile.rows.single.sourceLedgerFileId, 'purchase-source-id');
      expect(updatedFile.rows.single.sourceFileName, 'original-purchase.xlsx');
      expect(updatedFile.rows.single.sourceLedgerUploadedAt, uploadedAt);
    });

    test('remapped generic ledger file preserves source metadata', () async {
      final uploadedAt = DateTime(2026, 5, 17, 11, 45);
      final bytes = _buildWorkbook({
        'Ledger': const [
          ['Date', 'Party Name', 'Amount'],
          ['2024-04-02', 'Selected Vendor', 222],
        ],
      });
      final file = LedgerUploadFile(
        id: 'generic-source-id',
        sectionCode: '194C',
        fileName: 'original-ledger.xlsx',
        bytes: bytes,
        rowCount: 1,
        uploadedAt: uploadedAt,
        parserType: 'genericLedger',
        rows: const [],
        mappingStatus: UploadMappingStatus.needsReview,
        wasManuallyMapped: false,
        columnMapping: const {},
      );

      final response = await ImportUploadFlowService.prepareSectionFileRemap(
        file: file,
        columnMappingResult: const ColumnMappingResult(
          fileType: ImportMappingService.genericLedgerFileType,
          sheetName: 'Ledger',
          headerRowIndex: 0,
          headersTrusted: true,
          saveProfile: false,
          rawToCanonicalMapping: {
            'COL_0': 'date',
            'COL_1': 'party_name',
            'COL_2': 'amount',
          },
          columnMapping: {
            'date': 'COL_0',
            'party_name': 'COL_1',
            'amount': 'COL_2',
          },
        ),
      );

      expect(response.isSuccess, isTrue);
      final updatedFile = response.data!.updatedFile;
      expect(updatedFile.id, 'generic-source-id');
      expect(updatedFile.fileName, 'original-ledger.xlsx');
      expect(updatedFile.uploadedAt, uploadedAt);
      expect(updatedFile.rows.single.sourceLedgerFileId, 'generic-source-id');
      expect(updatedFile.rows.single.sourceFileName, 'original-ledger.xlsx');
      expect(updatedFile.rows.single.sourceLedgerUploadedAt, uploadedAt);
    });
  });
}

Uint8List _buildWorkbook(Map<String, List<List<Object?>>> sheets) {
  final workbook = xlsio.Workbook();
  try {
    var isFirstSheet = true;
    for (final entry in sheets.entries) {
      final sheet = isFirstSheet
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(entry.key);
      sheet.name = entry.key;
      isFirstSheet = false;

      final rows = entry.value;
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
          final value = row[columnIndex];
          if (value == null) continue;

          final cell = sheet.getRangeByIndex(rowIndex + 1, columnIndex + 1);
          if (value is num) {
            cell.setNumber(value.toDouble());
          } else {
            cell.setText(value.toString());
          }
        }
      }
    }

    return Uint8List.fromList(workbook.saveAsStream());
  } finally {
    workbook.dispose();
  }
}

List<List<Object?>> _decorativePrelude(int rowCount) {
  return List<List<Object?>>.generate(rowCount, (index) {
    if (index % 7 == 0) {
      return const [null, null, null];
    }
    if (index % 5 == 0) {
      return ['Address block line ${index + 1}', null, null];
    }
    if (index % 3 == 0) {
      return ['Report metadata ${index + 1}', null, null];
    }
    return ['Decorative title row ${index + 1}', null, null];
  });
}

Future<ColumnMappingResult?> _unexpectedColumnMapping({
  required List<int> bytes,
  required String fileName,
  required ExcelImportType fileType,
  required ExcelValidationResult validation,
  ImportSessionCache? sessionCache,
  String? preferredSheetName,
  int? preferredHeaderRowIndex,
  bool? preferredHeadersTrusted,
  Map<String, String>? preferredColumnMapping,
}) async {
  fail('Column mapping should not open for this test.');
}
