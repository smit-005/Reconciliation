import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/reconciliation_screen.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_preflight_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';
import 'package:reconciliation_app/features/upload/models/batch_mapping_review_item.dart';
import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';
import 'package:reconciliation_app/features/upload/models/import_format_profile.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/tds_26q_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/batch_mapping_review_screen.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/column_mapping_screen.dart';
import 'package:reconciliation_app/features/upload/services/batch_mapping_review_service.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';
import 'package:reconciliation_app/features/upload/services/import_profile_service.dart';
import 'package:reconciliation_app/features/upload/services/import_upload_flow_service.dart';

class ExcelUploadScreen extends StatefulWidget {
  final String selectedBuyerId;
  final String selectedBuyerName;
  final String selectedBuyerPan;

  const ExcelUploadScreen({
    super.key,
    required this.selectedBuyerId,
    required this.selectedBuyerName,
    required this.selectedBuyerPan,
  });

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

String formatSellerMappingFinancialYearLabel(List<Tds26QRow> tdsRows) {
  if (tdsRows.isEmpty) return 'FY Unknown';

  final rawFinancialYear = tdsRows.first.financialYear.trim();
  if (rawFinancialYear.isEmpty) return 'FY Unknown';

  final compactDigits = rawFinancialYear.replaceAll(RegExp(r'[^0-9]'), '');
  if (compactDigits.length >= 6) {
    return 'FY ${compactDigits.substring(0, 4)}-${compactDigits.substring(4, 6)}';
  }

  return 'FY $rawFinancialYear';
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  static const List<String> _allowedUploadExtensions = [
    'xlsx',
    'xls',
    'xlsm',
    'csv',
  ];
  static const List<String> _availableSections = [
    '194Q',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
  ];

  bool isLoadingTds = false;
  Tds26QUploadFile? tdsUploadFile;
  String _activeSectionCode = '194Q';

  // Seller mapping state
  bool _isSellerMappingConfirmed = false;
  bool _isLoadingSellerMapping = false;
  SellerMappingPreflightResult? _sellerMappingPreflight;

  final Set<String> selectedSections = {'194Q'};
  final Map<String, bool> sectionLoading = {
    for (final section in _availableSections) section: false,
  };
  final Map<String, List<LedgerUploadFile>> sectionFiles = {
    for (final section in _availableSections) section: <LedgerUploadFile>[],
  };
  final Map<String, List<PurchaseRow>> purchaseRowsByFileId = {};
  final Map<String, List<NormalizedLedgerRow>> ledgerRowsBySection = {
    for (final section in _availableSections) section: <NormalizedLedgerRow>[],
  };

  List<PurchaseRow> purchaseRows = [];
  List<Tds26QRow> tdsRows = [];
  List<NormalizedTransactionRow> normalizedPurchaseRows = [];
  List<NormalizedTransactionRow> normalizedTdsRows = [];
  String? detectedGstNo;

  Future<ColumnMappingResult?> showColumnMappingScreen({
    required ExcelPreviewData previewData,
  }) async {
    if (!mounted) return null;
    return Navigator.push<ColumnMappingResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ColumnMappingScreen(previewData: previewData),
      ),
    );
  }

  Future<ColumnMappingResult?> _openImportColumnMapping({
    required List<int> bytes,
    required String fileName,
    required ExcelImportType fileType,
    required ExcelValidationResult validation,
    ImportSessionCache? sessionCache,
    String? preferredSheetName,
  }) async {
    final previewData = ExcelService.buildPreviewData(
      bytes,
      fileType: fileType,
      fileName: fileName,
      initialMappedColumns: validation.mappedColumns,
      warnings: validation.warnings,
      confidenceScore: validation.confidenceScore,
      preferredSheetName: preferredSheetName,
      sessionCache: sessionCache,
    );

    if (previewData == null) {
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    return showColumnMappingScreen(previewData: previewData);
  }

  Future<ColumnMappingResult?> _openStoredFileColumnMapping({
    required LedgerUploadFile file,
  }) async {
    final fileType = file.sectionCode == '194Q'
        ? ExcelImportType.purchase
        : ExcelImportType.genericLedger;
    final previewData = ExcelService.buildPreviewDataWithProfile(
      file.bytes,
      fileType: fileType,
      fileName: file.fileName,
      sheetName: file.sheetName ?? '',
      headerRowIndex: file.headerRowIndex ?? 0,
      headersTrusted: file.headersTrusted ?? true,
      columnMapping: file.columnMapping,
      sessionCache: ImportSessionCache.fromBytes(file.bytes),
    );

    if (previewData == null) {
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    return showColumnMappingScreen(previewData: previewData);
  }

  Future<ColumnMappingResult?> _openStoredTdsColumnMapping({
    required Tds26QUploadFile file,
  }) async {
    final previewData = ExcelService.buildPreviewDataWithProfile(
      file.bytes,
      fileType: ExcelImportType.tds26q,
      fileName: file.fileName,
      sheetName: file.sheetName ?? '',
      headerRowIndex: file.headerRowIndex ?? 0,
      headersTrusted: file.headersTrusted ?? true,
      columnMapping: file.columnMapping,
      sessionCache: ImportSessionCache.fromBytes(file.bytes),
    );

    if (previewData == null) {
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    return showColumnMappingScreen(previewData: previewData);
  }

  Future<String?> _show26QSheetSelectionDialog(List<String> sheets) async {
    if (!mounted || sheets.isEmpty) return null;

    var selectedSheet = sheets.first;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Select 26Q Sheet'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: sheets
                      .map(
                        (sheet) => RadioListTile<String>(
                          value: sheet,
                          groupValue: selectedSheet,
                          title: Text(sheet),
                          onChanged: (value) {
                            if (value == null) return;
                            setLocalState(() {
                              selectedSheet = value;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedSheet),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfileFromColumnMappingResult({
    required ColumnMappingResult result,
    required String sampleSignature,
  }) async {
    if (!result.saveProfile ||
        result.fileType != ImportMappingService.purchaseFileType) {
      return;
    }

    final profile = ImportFormatProfile(
      buyerId: widget.selectedBuyerId,
      fileType: result.fileType,
      sheetNamePattern: result.sheetName,
      headerRowIndex: result.headerRowIndex,
      headersTrusted: result.headersTrusted,
      columnMapping: result.columnMapping,
      sampleSignature: sampleSignature,
      lastUsedAt: DateTime.now().toIso8601String(),
    );

    await ImportProfileService.saveProfile(profile);
  }

  bool _shouldAutoOpenColumnMapping({
    required ExcelValidationResult validation,
    required ExcelImportType fileType,
  }) {
    return ImportUploadFlowService.shouldAutoOpenColumnMapping(
      validation: validation,
      fileType: fileType,
    );
  }

  void _showUploadSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.fixed, content: Text(message)),
      );
  }

  Future<PlatformFile?> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedUploadExtensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final normalizedExtension = p.extension(file.name).toLowerCase();
    if (normalizedExtension == '.csv') {
      _showUploadSnackBar(
        'CSV file selected: ${file.name}. CSV selection is visible now, but the current import parser expects workbook sheets. Please export as .xlsx, .xls, or .xlsm and retry.',
      );
    }

    return file;
  }

  void _setSectionLoading(String sectionCode, bool isLoading) {
    setState(() {
      sectionLoading[sectionCode] = isLoading;
    });
  }

  void _invalidateSellerMappingConfirmation() {
    if (_isSellerMappingConfirmed) {
      _isSellerMappingConfirmed = false;
    }
    _sellerMappingPreflight = null;
  }

  bool get _canReviewSellerMappings =>
      _has26QReady &&
      _allRequiredMappingsConfirmed &&
      _buildSourceRowsBySection().isNotEmpty;

  int get _pendingSellerMappingReviewCount =>
      _sellerMappingPreflight?.pendingReviewCount ?? 0;

  Future<void> _refreshSellerMappingPreflight() async {
    if (!_canReviewSellerMappings) {
      if (!mounted) return;
      setState(() {
        _sellerMappingPreflight = null;
        _isSellerMappingConfirmed = false;
        _isLoadingSellerMapping = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingSellerMapping = true;
      });
    }

    try {
      final result = await SellerMappingPreflightService.analyze(
        buyerName: widget.selectedBuyerName,
        buyerPan: widget.selectedBuyerPan,
        tdsRows: tdsRows,
        sourceRowsBySection: _buildSourceRowsBySection(),
      );

      if (!mounted) return;

      setState(() {
        _sellerMappingPreflight = result;
        _isSellerMappingConfirmed = result.isSafeForReconciliation;
        _isLoadingSellerMapping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sellerMappingPreflight = null;
        _isSellerMappingConfirmed = false;
        _isLoadingSellerMapping = false;
      });
      _showUploadSnackBar('Failed to prepare seller mapping review: $e');
    }
  }

  void _refreshSellerMappingPreflightIfReady() {
    if (_canReviewSellerMappings) {
      _refreshSellerMappingPreflight();
    }
  }

  @visibleForTesting
  Future<void> refreshSellerMappingPreflightForTest() {
    return _refreshSellerMappingPreflight();
  }

  @visibleForTesting
  bool get isSellerMappingConfirmedForTest => _isSellerMappingConfirmed;

  Future<void> _applySellerMappingChanges(Map<String, dynamic> result) async {
    final upserts = List<Map<String, String>>.from(
      result['upserts'] as List? ?? const <Map<String, String>>[],
    );
    final deleted = List<Map<String, String>>.from(
      result['deleted'] as List? ?? const <Map<String, String>>[],
    );

    for (final entry in deleted) {
      final aliasName = entry['aliasName']?.trim() ?? '';
      final sectionCode = entry['sectionCode']?.trim() ?? 'ALL';
      if (aliasName.isEmpty) continue;
      await SellerMappingService.deleteMapping(
        buyerPan: widget.selectedBuyerPan,
        aliasName: aliasName,
        sectionCode: sectionCode,
      );
    }

    for (final entry in upserts) {
      final aliasName = entry['aliasName']?.trim() ?? '';
      final sectionCode = entry['sectionCode']?.trim() ?? 'ALL';
      final mappedName = entry['mappedName']?.trim() ?? '';
      if (aliasName.isEmpty || mappedName.isEmpty) continue;

      await SellerMappingService.saveMapping(
        SellerMapping(
          buyerName: widget.selectedBuyerName,
          buyerPan: widget.selectedBuyerPan,
          aliasName: aliasName,
          sectionCode: sectionCode,
          mappedPan: entry['mappedPan']?.trim() ?? '',
          mappedName: mappedName,
        ),
      );
    }
  }

  void _rebuildPurchaseState() {
    final allPurchaseRows = purchaseRowsByFileId.values
        .expand((rows) => rows)
        .toList();
    purchaseRows = allPurchaseRows;
    normalizedPurchaseRows = allPurchaseRows
        .map(NormalizedTransactionRow.fromPurchaseRow)
        .toList();
    detectedGstNo = ExcelService.detectGstNoFromPurchase(allPurchaseRows);
    ledgerRowsBySection['194Q'] = sectionFiles['194Q']!
        .expand((file) => file.rows)
        .toList();
  }

  void _removeSectionFile(String sectionCode, LedgerUploadFile file) {
    setState(() {
      sectionFiles[sectionCode] = sectionFiles[sectionCode]!
          .where((item) => item.id != file.id)
          .toList();
      _invalidateSellerMappingConfirmation();
      if (sectionCode == '194Q') {
        purchaseRowsByFileId.remove(file.id);
        _rebuildPurchaseState();
      } else {
        ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
            .expand((item) => item.rows)
            .toList();
      }
    });
    _refreshSellerMappingPreflightIfReady();
  }

  Future<LedgerUploadFile?> _buildPurchaseUploadFile({
    required PlatformFile pickedFile,
    required List<int> bytes,
    String? existingFileId,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
  }) async {
    final parseWatch = Stopwatch()..start();
    final response = await ImportUploadFlowService.preparePurchaseImport(
      buyerId: widget.selectedBuyerId,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
    );

    if (response.isFailure) {
      parseWatch.stop();
      _showUploadSnackBar(response.errorMessage!);
      return null;
    }

    final result = response.data;
    if (result == null) {
      parseWatch.stop();
      return null;
    }

    if (result.columnMappingResult != null) {
      await _saveProfileFromColumnMappingResult(
        result: result.columnMappingResult!,
        sampleSignature: result.sampleSignature,
      );
    }

    final fileId =
        existingFileId ??
        '194Q_${DateTime.now().microsecondsSinceEpoch}_${pickedFile.name}';
    final normalizedRows = result.parsedRows
        .map(
          (row) => NormalizedLedgerRow.fromPurchaseRow(
            row,
            sourceFileName: pickedFile.name,
          ),
        )
        .toList();

    purchaseRowsByFileId[fileId] = result.parsedRows;
    parseWatch.stop();
    debugPrint(
      'UPLOAD PERF => purchase parse ${parseWatch.elapsedMilliseconds} ms | '
      'file=${pickedFile.name} rows=${result.parsedRows.length} mappingStatus=${result.mappingStatus}',
    );

    return LedgerUploadFile(
      id: fileId,
      sectionCode: '194Q',
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: result.parsedRows.length,
      uploadedAt: DateTime.now(),
      parserType: 'purchase',
      rows: normalizedRows,
      mappingStatus: result.mappingStatus,
      wasManuallyMapped: result.wasManuallyMapped,
      sheetName: result.sheetName,
      headerRowIndex: result.headerRowIndex,
      headersTrusted: result.headersTrusted,
      columnMapping: result.columnMapping,
    );
  }

  Future<LedgerUploadFile?> _buildGenericLedgerUploadFile({
    required String sectionCode,
    required PlatformFile pickedFile,
    required List<int> bytes,
    String? existingFileId,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
  }) async {
    final parseWatch = Stopwatch()..start();
    final response = await ImportUploadFlowService.prepareGenericLedgerImport(
      sectionCode: sectionCode,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
    );

    if (response.isFailure) {
      parseWatch.stop();
      _showUploadSnackBar(response.errorMessage!);
      return null;
    }

    final result = response.data;
    if (result == null) {
      parseWatch.stop();
      return null;
    }
    parseWatch.stop();
    debugPrint(
      'UPLOAD PERF => source parse ${parseWatch.elapsedMilliseconds} ms | '
      'section=$sectionCode file=${pickedFile.name} rows=${result.parsedRows.length} '
      'mappingStatus=${result.mappingStatus}',
    );

    return LedgerUploadFile(
      id:
          existingFileId ??
          '${sectionCode}_${DateTime.now().microsecondsSinceEpoch}_${pickedFile.name}',
      sectionCode: sectionCode,
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: result.parsedRows.length,
      uploadedAt: DateTime.now(),
      parserType: 'genericLedger',
      rows: result.parsedRows,
      mappingStatus: result.mappingStatus,
      wasManuallyMapped: result.wasManuallyMapped,
      sheetName: result.sheetName,
      headerRowIndex: result.headerRowIndex,
      headersTrusted: result.headersTrusted,
      columnMapping: result.columnMapping,
    );
  }

  Future<void> _remapSectionFile(
    String sectionCode,
    LedgerUploadFile file,
  ) async {
    _setSectionLoading(sectionCode, true);
    try {
      final columnMappingResult = await _openStoredFileColumnMapping(
        file: file,
      );
      if (columnMappingResult == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      final response = await ImportUploadFlowService.prepareSectionFileRemap(
        file: file,
        columnMappingResult: columnMappingResult,
      );
      if (response.isFailure) {
        _setSectionLoading(sectionCode, false);
        _showUploadSnackBar(
          'Remap failed for ${file.fileName}: ${response.errorMessage!}',
        );
        return;
      }

      final result = response.data;
      if (result == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      if (sectionCode == '194Q') {
        if (result.sampleSignature != null) {
          await _saveProfileFromColumnMappingResult(
            result: columnMappingResult,
            sampleSignature: result.sampleSignature!,
          );
        }
        if (result.parsedPurchaseRows != null) {
          purchaseRowsByFileId[file.id] = result.parsedPurchaseRows!;
        }
      }

      final resolvedUpdatedFile = result.updatedFile;

      setState(() {
        sectionFiles[sectionCode] = sectionFiles[sectionCode]!
            .map<LedgerUploadFile>(
              (item) => item.id == file.id ? resolvedUpdatedFile : item,
            )
            .toList();
        _invalidateSellerMappingConfirmation();
        if (sectionCode == '194Q') {
          _rebuildPurchaseState();
        } else {
          ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
              .expand((item) => item.rows)
              .toList();
        }
        sectionLoading[sectionCode] = false;
      });
      _refreshSellerMappingPreflightIfReady();

      _showUploadSnackBar('${file.fileName} remapped successfully');
    } catch (e) {
      _setSectionLoading(sectionCode, false);
      _showUploadSnackBar('Remap failed for ${file.fileName}: $e');
    }
  }

  Future<void> _upload194QFile() async {
    _setSectionLoading('194Q', true);

    try {
      final pickedFile = await _pickExcelFile();
      if (pickedFile == null) {
        _setSectionLoading('194Q', false);
        return;
      }

      final bytes = pickedFile.bytes;
      if (bytes == null) {
        _setSectionLoading('194Q', false);
        _showUploadSnackBar('Could not read 194Q source file');
        return;
      }
      final uploadFile = await _buildPurchaseUploadFile(
        pickedFile: pickedFile,
        bytes: bytes,
      );
      if (uploadFile == null) {
        _setSectionLoading('194Q', false);
        return;
      }

      setState(() {
        sectionFiles['194Q'] = [...sectionFiles['194Q']!, uploadFile];
        _invalidateSellerMappingConfirmation();
        _rebuildPurchaseState();
        sectionLoading['194Q'] = false;
      });
      _refreshSellerMappingPreflightIfReady();

      _showUploadSnackBar(
        '194Q source uploaded: ${uploadFile.rowCount} rows from ${pickedFile.name}. Open Review All Mappings to confirm it.',
      );
    } catch (e) {
      _setSectionLoading('194Q', false);
      _showUploadSnackBar('194Q upload error: $e');
    }
  }

  Future<void> _uploadGenericSectionFile(String sectionCode) async {
    _setSectionLoading(sectionCode, true);

    try {
      final pickedFile = await _pickExcelFile();
      if (pickedFile == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      final bytes = pickedFile.bytes;
      if (bytes == null) {
        _setSectionLoading(sectionCode, false);
        _showUploadSnackBar('Could not read $sectionCode source file');
        return;
      }
      final uploadFile = await _buildGenericLedgerUploadFile(
        sectionCode: sectionCode,
        pickedFile: pickedFile,
        bytes: bytes,
      );
      if (uploadFile == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      setState(() {
        sectionFiles[sectionCode] = [...sectionFiles[sectionCode]!, uploadFile];
        _invalidateSellerMappingConfirmation();
        ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
            .expand((item) => item.rows)
            .toList();
        sectionLoading[sectionCode] = false;
      });
      _refreshSellerMappingPreflightIfReady();

      _showUploadSnackBar(
        '$sectionCode source uploaded: ${uploadFile.rowCount} rows from ${pickedFile.name}. Open Review All Mappings to confirm it.',
      );
    } catch (e) {
      _setSectionLoading(sectionCode, false);
      _showUploadSnackBar('$sectionCode upload error: $e');
    }
  }

  Future<void> uploadTds26QFile() async {
    setState(() {
      isLoadingTds = true;
    });

    try {
      final uploadWatch = Stopwatch()..start();
      final pickedFile = await _pickExcelFile();
      if (pickedFile == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      final bytes = pickedFile.bytes;
      if (bytes == null) {
        setState(() => isLoadingTds = false);
        _showUploadSnackBar('Could not read 26Q file');
        return;
      }

      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
      );
      String? preferredSheetName;

      if (validation.requiresUserSelection) {
        setState(() => isLoadingTds = false);
        preferredSheetName = await _show26QSheetSelectionDialog(
          validation.candidateSheets.isNotEmpty
              ? validation.candidateSheets
              : await ExcelService.list26QSelectableSheetsInBackground(bytes),
        );
        if (preferredSheetName == null || preferredSheetName.trim().isEmpty) {
          return;
        }
      }

      final shouldOpenColumnMapping = _shouldAutoOpenColumnMapping(
        validation: validation,
        fileType: ExcelImportType.tds26q,
      );
      if (shouldOpenColumnMapping) {
        setState(() => isLoadingTds = false);
      }

      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: pickedFile.name,
        validation: validation,
        openColumnMapping: _openImportColumnMapping,
        preferredSheetName: preferredSheetName,
      );

      if (response.isFailure) {
        setState(() => isLoadingTds = false);
        _showUploadSnackBar(response.errorMessage!);
        return;
      }

      final result = response.data;
      if (result == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      if (shouldOpenColumnMapping) {
        setState(() => isLoadingTds = true);
      }

      setState(() {
        _invalidateSellerMappingConfirmation();
        tdsUploadFile = Tds26QUploadFile(
          fileName: pickedFile.name,
          bytes: bytes,
          rowCount: result.parsedRows.length,
          uploadedAt: DateTime.now(),
          rows: result.parsedRows,
          mappingStatus: result.mappingStatus,
          wasManuallyMapped: result.wasManuallyMapped,
          sheetName: result.sheetName,
          headerRowIndex: result.headerRowIndex,
          headersTrusted: result.headersTrusted,
          columnMapping: result.columnMapping,
        );
        tdsRows = result.parsedRows;
        normalizedTdsRows = result.parsedRows
            .map(NormalizedTransactionRow.fromTds26QRow)
            .toList();
        isLoadingTds = false;
      });
      _refreshSellerMappingPreflightIfReady();
      uploadWatch.stop();
      debugPrint(
        'UPLOAD PERF => 26Q parse ${uploadWatch.elapsedMilliseconds} ms | '
        'file=${pickedFile.name} rows=${result.parsedRows.length} '
        'sheet=${validation.detectedSheet ?? 'manual'}',
      );
      debugPrint('UPLOAD COUNT => 26Q rows=${result.parsedRows.length}');

      _showUploadSnackBar(
        '26Q uploaded: ${result.parsedRows.length} rows. Continue uploading files, then open Review All Mappings.',
      );
    } catch (e) {
      setState(() => isLoadingTds = false);
      _showUploadSnackBar('26Q upload error: $e');
    }
  }

  Future<void> _reviewTds26QMapping() async {
    final file = tdsUploadFile;
    if (file == null) return;

    setState(() {
      isLoadingTds = true;
    });

    try {
      final columnMappingResult = await _openStoredTdsColumnMapping(file: file);
      if (columnMappingResult == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      final response = await ImportUploadFlowService.prepareTds26QRemap(
        bytes: file.bytes,
        columnMappingResult: columnMappingResult,
      );
      if (response.isFailure) {
        setState(() => isLoadingTds = false);
        _showUploadSnackBar(response.errorMessage ?? '26Q remap failed');
        return;
      }

      final result = response.data;
      if (result == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      setState(() {
        _invalidateSellerMappingConfirmation();
        tdsUploadFile = Tds26QUploadFile(
          fileName: file.fileName,
          bytes: file.bytes,
          rowCount: result.parsedRows.length,
          uploadedAt: DateTime.now(),
          rows: result.parsedRows,
          mappingStatus: result.mappingStatus,
          wasManuallyMapped: result.wasManuallyMapped,
          sheetName: result.sheetName,
          headerRowIndex: result.headerRowIndex,
          headersTrusted: result.headersTrusted,
          columnMapping: result.columnMapping,
        );
        tdsRows = result.parsedRows;
        normalizedTdsRows = result.parsedRows
            .map(NormalizedTransactionRow.fromTds26QRow)
            .toList();
        isLoadingTds = false;
      });
      _refreshSellerMappingPreflightIfReady();

      _showUploadSnackBar('26Q mapping confirmed');
    } catch (e) {
      setState(() => isLoadingTds = false);
      _showUploadSnackBar('26Q remap failed: $e');
    }
  }

  void openReconciliationScreen() {
    if (tdsRows.isEmpty) {
      _showUploadSnackBar('Please upload the mandatory 26Q file first');
      return;
    }

    final sourceRowsBySection = _buildSourceRowsBySection();
    if (sourceRowsBySection.isEmpty) {
      _showUploadSnackBar(
        'Upload at least one source file in any selected section to continue.',
      );
      return;
    }

    if (!_allRequiredMappingsConfirmed) {
      _showUploadSnackBar(
        'Confirm mapping for: ${_pendingMappingReviewLabels.join(', ')}',
      );
      return;
    }

    if (!_isSellerMappingConfirmed) {
      _showUploadSnackBar(
        _pendingSellerMappingReviewCount > 0
            ? 'Resolve $_pendingSellerMappingReviewCount dangerous 26Q seller review ${_pendingSellerMappingReviewCount == 1 ? 'issue' : 'issues'} before opening reconciliation.'
            : 'Please wait for seller mapping review to complete.',
      );
      return;
    }

    final totalSourceRows = sourceRowsBySection.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    debugPrint(
      'UPLOAD COUNT => open reconciliation sourceRows=$totalSourceRows '
      'tdsRows=${tdsRows.length} sections=${sourceRowsBySection.keys.join(',')}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReconciliationScreen(
          sourceRowsBySection: sourceRowsBySection,
          sourceFileCountBySection: {
            for (final entry in sectionFiles.entries)
              if (entry.value.isNotEmpty) entry.key: entry.value.length,
          },
          tdsRows: tdsRows,
          buyerName: widget.selectedBuyerName,
          buyerPan: widget.selectedBuyerPan,
          gstNo: detectedGstNo ?? '',
          sellerMappingConfirmed: _isSellerMappingConfirmed,
        ),
      ),
    );
  }

  Future<void> openSellerMappingScreen() async {
    if (!_canReviewSellerMappings) {
      _showUploadSnackBar(
        'Complete file uploads and column mapping before reviewing seller mappings.',
      );
      return;
    }

    setState(() => _isLoadingSellerMapping = true);

    try {
      final preparationResult =
          _sellerMappingPreflight ??
          await SellerMappingPreflightService.analyze(
            buyerName: widget.selectedBuyerName,
            buyerPan: widget.selectedBuyerPan,
            tdsRows: tdsRows,
            sourceRowsBySection: _buildSourceRowsBySection(),
          );

      if (!mounted) return;

      final fyLabel = _sellerMappingFinancialYearLabel();

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => SellerMappingScreen(
            mode: SellerMappingScreenMode.preflight,
            buyerName: widget.selectedBuyerName,
            buyerPan: widget.selectedBuyerPan,
            financialYearLabel: fyLabel,
            selectedSectionLabel: 'All',
            initialViewMode: ReconciliationViewMode.summary,
            purchaseRows: preparationResult.reviewRows,
            tdsParties: preparationResult.tdsParties,
            existingMappings: preparationResult.existingMappings,
            blockedAliases: preparationResult.blockedAliases,
            tdsPartyPans: preparationResult.tdsPartyPans,
          ),
        ),
      );

      if (result == null) {
        setState(() => _isLoadingSellerMapping = false);
        _showUploadSnackBar('Seller mapping review cancelled');
        return;
      }

      await _applySellerMappingChanges(result);
      if (result['dangerousRemaining'] == 0) {
        setState(() {
          _isSellerMappingConfirmed = true;
        });
      }

      final upsertsCount = (result['upserts'] as List?)?.length ?? 0;
      final deletedCount = (result['deleted'] as List?)?.length ?? 0;
      debugPrint(
        'SAVE_REVIEW => upserts=$upsertsCount deleted=$deletedCount dangerousRemaining=${result['dangerousRemaining']}',
      );

      await _refreshSellerMappingPreflight();

      debugPrint(
        'SAVE_REVIEW => pendingReviewCount=${_sellerMappingPreflight?.pendingReviewCount}',
      );

      if (!mounted) return;

      _showUploadSnackBar(
        _isSellerMappingConfirmed
            ? 'Seller mapping review completed. No dangerous unresolved identities remain.'
            : 'Seller mapping review saved. $_pendingSellerMappingReviewCount dangerous 26Q seller ${_pendingSellerMappingReviewCount == 1 ? 'item remains' : 'items remain'}.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSellerMapping = false);
        _showUploadSnackBar('Failed to open seller mapping: $e');
      }
    }
  }

  String _sellerMappingFinancialYearLabel() {
    return formatSellerMappingFinancialYearLabel(tdsRows);
  }

  Map<String, List<NormalizedTransactionRow>> _buildSourceRowsBySection() {
    final groupedRows = <String, List<NormalizedTransactionRow>>{};

    for (final section in selectedSections) {
      final ledgerRows =
          ledgerRowsBySection[section] ?? const <NormalizedLedgerRow>[];
      if (ledgerRows.isEmpty) continue;

      groupedRows[section] = ledgerRows
          .map(NormalizedTransactionRow.fromNormalizedLedgerRow)
          .toList();
    }

    if (groupedRows.isNotEmpty) {
      return groupedRows;
    }

    if (purchaseRows.isNotEmpty) {
      groupedRows['194Q'] = purchaseRows
          .map(NormalizedTransactionRow.fromPurchaseRow)
          .toList();
    }

    return groupedRows;
  }

  void _toggleSection(String sectionCode) {
    if (selectedSections.contains(sectionCode) &&
        sectionFiles[sectionCode]!.isNotEmpty) {
      _showUploadSnackBar(
        'Remove uploaded files from $sectionCode before hiding this section.',
      );
      return;
    }

    setState(() {
      if (selectedSections.contains(sectionCode)) {
        selectedSections.remove(sectionCode);
        if (_activeSectionCode == sectionCode) {
          _activeSectionCode = selectedSections.isEmpty
              ? sectionCode
              : (selectedSections.toList()..sort()).first;
        }
      } else {
        selectedSections.add(sectionCode);
        _activeSectionCode = sectionCode;
      }
    });
  }

  void _setActiveSection(String sectionCode) {
    if (!selectedSections.contains(sectionCode)) return;
    setState(() {
      _activeSectionCode = sectionCode;
    });
  }

  int get _totalSectionFiles =>
      sectionFiles.values.fold<int>(0, (sum, files) => sum + files.length);

  int get _totalLedgerRows => sectionFiles.values.fold<int>(
    0,
    (sum, files) =>
        sum + files.fold<int>(0, (inner, file) => inner + file.rowCount),
  );

  bool get _has26QReady => tdsUploadFile != null && tdsRows.isNotEmpty;

  bool get _is26QMappingConfirmed =>
      _has26QReady &&
      tdsUploadFile!.mappingStatus == UploadMappingStatus.confirmed;

  bool get _canUploadSectionFiles => _is26QMappingConfirmed;

  Iterable<LedgerUploadFile> get _allUploadedSectionFiles =>
      sectionFiles.values.expand((files) => files);

  List<BatchMappingReviewItem> get _batchMappingReviewItems =>
      BatchMappingReviewService.buildItems(
        tdsFile: tdsUploadFile,
        sectionFiles: _allUploadedSectionFiles,
      );

  List<String> get _pendingMappingReviewLabels {
    return _batchMappingReviewItems
        .where((item) => !item.isConfirmed)
        .map((item) => '${item.sectionCode} (${item.fileName})')
        .toList();
  }

  bool get _allRequiredMappingsConfirmed => _pendingMappingReviewLabels.isEmpty;

  bool get canOpenReconciliation =>
      _has26QReady &&
      _buildSourceRowsBySection().isNotEmpty &&
      _allRequiredMappingsConfirmed &&
      _isSellerMappingConfirmed;

  bool get _hasWorkspaceContent => _has26QReady || _totalSectionFiles > 0;

  String get _workspaceStatusLabel {
    if (canOpenReconciliation) return 'Ready';
    if (_hasWorkspaceContent) return 'In Progress';
    return 'Setup Required';
  }

  String get _workspaceStatusDetail {
    if (canOpenReconciliation) {
      return '26Q and source files are confirmed. Continue to reconciliation.';
    }
    if (!_has26QReady) {
      return 'Upload the mandatory 26Q master file to unlock the workflow.';
    }
    if (!_allRequiredMappingsConfirmed) {
      return 'Review and confirm column mapping for every uploaded file before reconciliation.';
    }
    if (_canReviewSellerMappings && !_isSellerMappingConfirmed) {
      return _pendingSellerMappingReviewCount > 0
          ? 'Review seller mappings. $_pendingSellerMappingReviewCount dangerous 26Q seller ${_pendingSellerMappingReviewCount == 1 ? 'still needs' : 'still need'} action.'
          : 'Preparing seller mapping preflight review.';
    }
    return 'Add at least one source file in a selected section to continue.';
  }

  int _sectionFileCount(String sectionCode) =>
      sectionFiles[sectionCode]?.length ?? 0;

  int _sectionRowCount(String sectionCode) {
    if (sectionCode == '194Q') return purchaseRows.length;
    return ledgerRowsBySection[sectionCode]?.length ?? 0;
  }

  String _sectionDescription(String sectionCode) {
    switch (sectionCode) {
      case '194Q':
        return 'Purchase parser workspace for buyer-side source files.';
      case '194C':
        return 'Generic ledger workspace for contractor payment ledgers.';
      case '194H':
        return 'Generic ledger workspace for commission or brokerage ledgers.';
      case '194I_A':
        return 'Generic ledger workspace for machinery, plant, or equipment rent ledgers.';
      case '194I_B':
        return 'Generic ledger workspace for land, building, or furniture rent ledgers.';
      case '194J_A':
        return 'Generic ledger workspace for technical services ledgers.';
      case '194J_B':
        return 'Generic ledger workspace for professional services ledgers.';
      default:
        return 'Generic ledger workspace for the selected section.';
    }
  }

  int get _safeBatchMappingCount =>
      _batchMappingReviewItems.where((item) => item.canConfirmSafely).length;

  int get _reviewRequiredBatchMappingCount =>
      _batchMappingReviewItems.where((item) => !item.isConfirmed).length;

  Future<void> _openBatchMappingReviewScreen() async {
    if (_batchMappingReviewItems.isEmpty) {
      _showUploadSnackBar(
        'Upload a 26Q file or source files before opening mapping review.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BatchMappingReviewScreen(
          loadItems: () async => _batchMappingReviewItems,
          onReviewItem: _handleBatchReviewItem,
          onConfirmItem: _confirmSingleSafeMapping,
          onConfirmAllSafe: _confirmAllSafeMappings,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _handleBatchReviewItem(BatchMappingReviewItem item) async {
    if (item.type == BatchMappingReviewItemType.tds26q) {
      final previousStatus = tdsUploadFile?.mappingStatus;
      await _reviewTds26QMapping();
      return previousStatus != tdsUploadFile?.mappingStatus;
    }

    final fileId = item.itemKey.replaceFirst('section:', '');
    final file = _findSectionFileById(fileId);
    if (file == null) return false;

    final previousStatus = file.mappingStatus;
    await _remapSectionFile(file.sectionCode, file);
    final updatedFile = _findSectionFileById(fileId);
    return previousStatus != updatedFile?.mappingStatus;
  }

  Future<bool> _confirmSingleSafeMapping(BatchMappingReviewItem item) async {
    if (!item.canConfirmSafely) return false;

    if (item.type == BatchMappingReviewItemType.tds26q) {
      final file = tdsUploadFile;
      if (file == null) return false;
      setState(() {
        tdsUploadFile = file.copyWith(
          mappingStatus: UploadMappingStatus.confirmed,
        );
      });
      _refreshSellerMappingPreflightIfReady();
      return true;
    }

    final fileId = item.itemKey.replaceFirst('section:', '');
    final target = _findSectionFileById(fileId);
    if (target == null) return false;

    setState(() {
      sectionFiles[target.sectionCode] = sectionFiles[target.sectionCode]!
          .map(
            (file) => file.id == target.id
                ? file.copyWith(mappingStatus: UploadMappingStatus.confirmed)
                : file,
          )
          .toList();
    });
    _refreshSellerMappingPreflightIfReady();
    return true;
  }

  Future<int> _confirmAllSafeMappings() async {
    final safeItems = _batchMappingReviewItems
        .where((item) => item.canConfirmSafely)
        .toList();
    if (safeItems.isEmpty) return 0;

    var confirmedCount = 0;
    for (final item in safeItems) {
      final changed = await _confirmSingleSafeMapping(item);
      if (changed) {
        confirmedCount += 1;
      }
    }
    return confirmedCount;
  }

  LedgerUploadFile? _findSectionFileById(String fileId) {
    for (final file in _allUploadedSectionFiles) {
      if (file.id == fileId) {
        return file;
      }
    }
    return null;
  }

  Color _sectionAccent(String sectionCode) {
    switch (sectionCode) {
      case '194Q':
        return const Color(0xFF2563EB);
      case '194C':
        return const Color(0xFF0F766E);
      case '194H':
        return const Color(0xFF9333EA);
      case '194I_A':
        return const Color(0xFFEA580C);
      case '194I_B':
        return const Color(0xFFDC2626);
      case '194J_A':
        return const Color(0xFF0891B2);
      case '194J_B':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF475569);
    }
  }

  String _parserLabel(String sectionCode) {
    return sectionCode == '194Q' ? 'Purchase Parser' : 'Generic Ledger Parser';
  }

  Color _mappingStatusColor(UploadMappingStatus status) {
    switch (status) {
      case UploadMappingStatus.notMapped:
        return const Color(0xFF9A3412);
      case UploadMappingStatus.autoMapped:
        return const Color(0xFF1D4ED8);
      case UploadMappingStatus.needsReview:
        return const Color(0xFFB45309);
      case UploadMappingStatus.confirmed:
        return const Color(0xFF166534);
    }
  }

  Color _mappingStatusBackground(UploadMappingStatus status) {
    switch (status) {
      case UploadMappingStatus.notMapped:
        return const Color(0xFFFFEDD5);
      case UploadMappingStatus.autoMapped:
        return const Color(0xFFDBEAFE);
      case UploadMappingStatus.needsReview:
        return const Color(0xFFFEF3C7);
      case UploadMappingStatus.confirmed:
        return const Color(0xFFDCFCE7);
    }
  }

  BoxDecoration _panelDecoration({
    Color borderColor = const Color(0xFF1E293B),
    Color backgroundColor = const Color(0xFF0F172A),
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor),
      boxShadow:
          shadows ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
    );
  }

  String _formatTimestamp(DateTime value) {
    final date = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$date/$month/$year $hour:$minute';
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(
        borderColor: const Color(0xFF1E293B),
        backgroundColor: const Color(0xFF07111F),
        shadows: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF111C31),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload Workspace',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Prepare the 26Q master and section-wise source files before opening reconciliation.',
                      style: TextStyle(
                        color: Colors.blueGrey.shade100,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: canOpenReconciliation
                      ? const Color(0xFF052E2B)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: canOpenReconciliation
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF334155),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      canOpenReconciliation
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_bottom_rounded,
                      size: 16,
                      color: canOpenReconciliation
                          ? const Color(0xFF5EEAD4)
                          : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _workspaceStatusLabel,
                      style: TextStyle(
                        color: canOpenReconciliation
                            ? const Color(0xFFCCFBF1)
                            : const Color(0xFFE2E8F0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: canOpenReconciliation
                    ? openReconciliationScreen
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: const Color(0xFF1E293B),
                  disabledForegroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text(
                  'Open Reconciliation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1728),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFF93C5FD),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _workspaceStatusDetail,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTdsCard() {
    final file = tdsUploadFile;
    final uploaded = file != null;
    final mappingStatus = file?.mappingStatus ?? UploadMappingStatus.notMapped;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(
        borderColor: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
        backgroundColor: const Color(0xFF0B1220),
        shadows: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Mandatory',
                  style: TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _mappingStatusBackground(mappingStatus),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  uploaded ? mappingStatus.label : 'Pending',
                  style: TextStyle(
                    color: _mappingStatusColor(mappingStatus),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '26Q Master File',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This file is mandatory and powers the reconciliation baseline.',
            style: TextStyle(
              color: Colors.blueGrey.shade100,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF09101C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: uploaded
                    ? const Color(0xFF1D4ED8).withValues(alpha: 0.45)
                    : const Color(0xFF334155),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: uploaded
                        ? const Color(0xFFDBEAFE).withValues(alpha: 0.12)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    uploaded
                        ? Icons.fact_check_rounded
                        : Icons.upload_file_rounded,
                    color: uploaded
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uploaded ? file.fileName : 'No 26Q file uploaded yet',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        uploaded
                            ? '${tdsRows.length} parsed rows | Mapping ${mappingStatus.label.toLowerCase()}'
                            : 'Upload the statutory 26Q workbook to unlock reconciliation.',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: isLoadingTds ? null : uploadTds26QFile,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        disabledBackgroundColor: const Color(0xFF1E293B),
                        disabledForegroundColor: const Color(0xFF64748B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: Icon(
                        uploaded ? Icons.refresh_rounded : Icons.upload_rounded,
                      ),
                      label: Text(
                        isLoadingTds
                            ? 'Uploading...'
                            : uploaded
                            ? 'Replace 26Q'
                            : 'Upload 26Q',
                      ),
                    ),
                    if (uploaded) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: isLoadingTds ? null : _reviewTds26QMapping,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF334155)),
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Review Mapping'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Section Buckets',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the section buckets you want to upload. Each selected section can hold multiple files.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _availableSections.map((section) {
              final selected = selectedSections.contains(section);
              final active = _activeSectionCode == section && selected;
              final accent = _sectionAccent(section);
              final fileCount = _sectionFileCount(section);
              final rowCount = _sectionRowCount(section);
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: selected
                    ? () => _setActiveSection(section)
                    : () => _toggleSection(section),
                onLongPress: selected ? () => _toggleSection(section) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: 0.18)
                        : selected
                        ? const Color(0xFF111827)
                        : const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active
                          ? accent
                          : selected
                          ? accent.withValues(alpha: 0.55)
                          : const Color(0xFF334155),
                      width: active ? 1.6 : 1,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sectionDisplayLabel(section),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: selected
                                  ? accent
                                  : const Color(0xFF475569),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$fileCount file${fileCount == 1 ? '' : 's'} | $rowCount rows',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildSummaryTile('Buyer', widget.selectedBuyerName),
          _buildSummaryTile('Buyer PAN', widget.selectedBuyerPan),
          _buildSummaryTile('26Q Rows', tdsRows.length.toString()),
          _buildSummaryTile('Section Files', _totalSectionFiles.toString()),
          _buildSummaryTile('Source Rows', _totalLedgerRows.toString()),
          _buildSummaryTile(
            'Active Buckets',
            selectedSections.length.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchMappingReviewCard() {
    final hasFiles = _batchMappingReviewItems.isNotEmpty;
    final reviewPendingCount = _reviewRequiredBatchMappingCount;
    final safeCount = _safeBatchMappingCount;
    final allConfirmed = hasFiles && reviewPendingCount == 0;

    final statusLabel = !hasFiles
        ? 'Locked'
        : allConfirmed
        ? 'Confirmed'
        : safeCount > 0
        ? 'Safe files ready'
        : 'Review required';
    final statusBackground = !hasFiles
        ? const Color(0xFF1E293B)
        : allConfirmed
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEF3C7);
    final statusColor = !hasFiles
        ? const Color(0xFF94A3B8)
        : allConfirmed
        ? const Color(0xFF166534)
        : const Color(0xFFB45309);

    final detailText = !hasFiles
        ? 'Upload the 26Q file and source files first. Batch Mapping Review aggregates current mapping state without reparsing files.'
        : allConfirmed
        ? 'All uploaded files have confirmed mappings. Seller Mapping and Reconciliation can continue when seller review is safe.'
        : safeCount > 0
        ? '$safeCount file${safeCount == 1 ? '' : 's'} can be confirmed in one click. Remaining files still need detailed review.'
        : '$reviewPendingCount file${reviewPendingCount == 1 ? '' : 's'} still need mapping review before Seller Mapping and Reconciliation unlock.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Batch Mapping Review',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  detailText,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildInfoChip(
                      'Uploaded Files',
                      _batchMappingReviewItems.length.toString(),
                    ),
                    _buildInfoChip(
                      'Need Review',
                      reviewPendingCount.toString(),
                      accentColor: allConfirmed
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B),
                    ),
                    _buildInfoChip(
                      'Safe to Confirm',
                      safeCount.toString(),
                      accentColor: safeCount > 0
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: hasFiles ? _openBatchMappingReviewScreen : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
                icon: const Icon(Icons.rule_folder_outlined),
                label: const Text('Review All Mappings'),
              ),
              FilledButton.icon(
                onPressed: safeCount > 0
                    ? () async {
                        final count = await _confirmAllSafeMappings();
                        if (!mounted) return;
                        _showUploadSnackBar(
                          count <= 0
                              ? 'No safe mappings were ready to confirm.'
                              : 'Confirmed $count safe mapping${count == 1 ? '' : 's'}.',
                        );
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: const Color(0xFF1E293B),
                  disabledForegroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Confirm All Safe Mappings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSellerMappingCard() {
    final isLocked = !_canReviewSellerMappings;
    final isSafe = _isSellerMappingConfirmed;
    final pendingCount = _pendingSellerMappingReviewCount;

    final statusLabel = isLocked
        ? 'Locked'
        : _isLoadingSellerMapping
        ? 'Checking'
        : isSafe
        ? 'Safe'
        : pendingCount > 0
        ? 'Needs Review'
        : 'Pending';
    final statusColor = isLocked
        ? const Color(0xFF94A3B8)
        : isSafe
        ? const Color(0xFF166534)
        : const Color(0xFFB45309);
    final statusBackground = isLocked
        ? const Color(0xFF1E293B)
        : isSafe
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEF3C7);

    final detailText = isLocked
        ? 'Complete 26Q and file column mapping before seller identity review starts.'
        : _isLoadingSellerMapping
        ? 'Refreshing seller identity preflight from the current uploaded data.'
        : isSafe
        ? 'No dangerous unresolved seller identity issues were detected.'
        : pendingCount > 0
        ? '$pendingCount seller ${pendingCount == 1 ? 'identity needs' : 'identities need'} review before reconciliation.'
        : 'Open Seller Mapping Review to validate seller identity safety.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Seller Mapping Review',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  detailText,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildInfoChip(
                      'Pending Review',
                      isLocked ? '-' : pendingCount.toString(),
                      accentColor: isSafe
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B),
                    ),
                    _buildInfoChip(
                      'Dangerous Statuses',
                      'conflicting PAN, ambiguous identity, unresolved identity',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: isLocked || _isLoadingSellerMapping
                ? null
                : openSellerMappingScreen,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            icon: const Icon(Icons.person_search_rounded),
            label: Text(isSafe ? 'Review Again' : 'Review Seller Mappings'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, minHeight: 112),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, {Color? accentColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accentColor ?? Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPanel() {
    final visibleSections = selectedSections.toList()..sort();
    if (visibleSections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text(
          'Select one or more section buckets to start building the source-file workspace.',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.5),
        ),
      );
    }

    final sectionCode = selectedSections.contains(_activeSectionCode)
        ? _activeSectionCode
        : visibleSections.first;
    final accent = _sectionAccent(sectionCode);
    final files = sectionFiles[sectionCode]!;
    final isLoading = sectionLoading[sectionCode] ?? false;

    return _buildSectionCard(
      sectionCode: sectionCode,
      files: files,
      isLoading: isLoading,
      accent: accent,
    );
  }

  Widget _buildSectionCard({
    required String sectionCode,
    required List<LedgerUploadFile> files,
    required bool isLoading,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(
        borderColor: accent.withValues(alpha: 0.28),
        backgroundColor: const Color(0xFF0B1220),
        shadows: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sectionDisplayLabel(sectionCode),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _parserLabel(sectionCode),
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _sectionDescription(sectionCode),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: isLoading || !_canUploadSectionFiles
                    ? null
                    : () => sectionCode == '194Q'
                          ? _upload194QFile()
                          : _uploadGenericSectionFile(sectionCode),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: Text(
                  isLoading
                      ? 'Uploading...'
                      : _canUploadSectionFiles
                      ? 'Add File'
                      : 'Confirm 26Q Mapping First',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                sectionDisplayLabel(sectionCode),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  '${files.length} file${files.length == 1 ? '' : 's'} | ${_sectionRowCount(sectionCode)} rows',
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            files.isEmpty
                ? _canUploadSectionFiles
                      ? 'No files added to this bucket yet.'
                      : 'Confirm 26Q mapping before adding source files.'
                : 'Review uploaded files for this section and adjust mapping if required.',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          if (files.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF09101C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.folder_open_rounded, color: accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      !_canUploadSectionFiles
                          ? 'This bucket unlocks after the 26Q mapping is confirmed.'
                          : sectionCode == '194Q'
                          ? 'Use this bucket for purchase-parser source files. Add one or more files to stage buyer-side transactions.'
                          : 'Use this bucket for generic ledger source files mapped to ${sectionDisplayLabel(sectionCode)}. Add files to complete this workspace.',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: files
                  .map(
                    (file) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09101C),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.description_outlined,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.fileName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      '${file.rowCount} rows',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _formatTimestamp(file.uploadedAt),
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _mappingStatusBackground(
                                          file.mappingStatus,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        file.mappingStatus.label,
                                        style: TextStyle(
                                          color: _mappingStatusColor(
                                            file.mappingStatus,
                                          ),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1F2937),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        file.parserType == 'purchase'
                                            ? 'Purchase parser'
                                            : 'Generic ledger parser',
                                        style: const TextStyle(
                                          color: Color(0xFFE2E8F0),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              OutlinedButton.icon(
                                onPressed: isLoading
                                    ? null
                                    : () =>
                                          _remapSectionFile(sectionCode, file),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                icon: const Icon(Icons.tune, size: 16),
                                label: const Text('Review Mapping'),
                              ),
                              const SizedBox(height: 8),
                              IconButton(
                                onPressed: () =>
                                    _removeSectionFile(sectionCode, file),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remove file',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF07111F).withValues(alpha: 0.98),
          border: const Border(top: BorderSide(color: Color(0xFF1E293B))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF334155)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _hasWorkspaceContent
                  ? _openBatchMappingReviewScreen
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF64748B),
                side: BorderSide(
                  color: _hasWorkspaceContent
                      ? const Color(0xFF334155)
                      : const Color(0xFF1E293B),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.rule_folder_outlined),
              label: const Text('Review All Mappings'),
            ),
            const Spacer(),
            if (_has26QReady && _allRequiredMappingsConfirmed)
              OutlinedButton.icon(
                onPressed: _isLoadingSellerMapping
                    ? null
                    : openSellerMappingScreen,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isSellerMappingConfirmed
                      ? Colors.green
                      : Colors.white,
                  disabledForegroundColor: const Color(0xFF64748B),
                  side: BorderSide(
                    color: _isSellerMappingConfirmed
                        ? Colors.green.shade600
                        : const Color(0xFF334155),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  _isSellerMappingConfirmed
                      ? Icons.check_circle_rounded
                      : Icons.person_search_rounded,
                ),
                label: Text(
                  _isLoadingSellerMapping
                      ? 'Loading...'
                      : (_isSellerMappingConfirmed
                            ? 'Seller Mappings Confirmed'
                            : _pendingSellerMappingReviewCount > 0
                            ? 'Review Seller Mappings ($_pendingSellerMappingReviewCount)'
                            : 'Review Seller Mappings'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: canOpenReconciliation
                  ? openReconciliationScreen
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFF1E293B),
                disabledForegroundColor: const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                'Open Reconciliation',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      bottomNavigationBar: _buildBottomActionBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: ListView(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildTdsCard(),
                  const SizedBox(height: 18),
                  _buildSectionSelector(),
                  const SizedBox(height: 18),
                  _buildSummaryCard(),
                  const SizedBox(height: 18),
                  _buildBatchMappingReviewCard(),
                  const SizedBox(height: 18),
                  _buildSectionPanel(),
                  const SizedBox(height: 18),
                  _buildSellerMappingCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
