import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/utils/app_logger.dart';
import 'package:reconciliation_app/core/widgets/app_info_chip.dart';
import 'package:reconciliation_app/core/widgets/app_page_scaffold.dart';
import 'package:reconciliation_app/core/widgets/app_rect_snackbar.dart';
import 'package:reconciliation_app/core/widgets/app_section_selector.dart';
import 'package:path/path.dart' as p;

import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/reconciliation_screen.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_preflight_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';
import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';
import 'package:reconciliation_app/features/upload/models/import_format_profile.dart';
import 'package:reconciliation_app/features/upload/models/batch_mapping_review_item.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/tds_26q_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/batch_mapping_review_screen.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/column_mapping_screen.dart';
import 'package:reconciliation_app/features/upload/presentation/widgets/upload_file_action_card.dart';
import 'package:reconciliation_app/features/upload/services/batch_mapping_review_service.dart';
import 'package:reconciliation_app/features/upload/services/excel_service.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';
import 'package:reconciliation_app/features/upload/services/import_profile_service.dart';
import 'package:reconciliation_app/features/upload/services/import_upload_flow_service.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_export_path_service.dart';

String formatSellerMappingFinancialYearLabel(
  dynamic financialYear, {
  String? fallbackFinancialYear,
}) {
  String? value;

  if (financialYear is List<Tds26QRow>) {
    value = financialYear.isNotEmpty ? financialYear.first.financialYear : null;
  } else if (financialYear is String?) {
    value = financialYear;
  }

  final normalized =
      _normalizeSellerMappingFinancialYearValue(value) ??
      _normalizeSellerMappingFinancialYearValue(fallbackFinancialYear);

  return normalized == null ? 'FY Unknown' : 'FY $normalized';
}

String? _normalizeSellerMappingFinancialYearValue(String? value) {
  var normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }

  normalized = normalized.replaceFirst(
    RegExp(r'^fy\s*', caseSensitive: false),
    '',
  );
  normalized = normalized.replaceAll(RegExp(r'\s+'), '');

  final compactMatch = RegExp(r'^(\d{4})(\d{2})$').firstMatch(normalized);
  if (compactMatch != null) {
    return '${compactMatch.group(1)}-${compactMatch.group(2)}';
  }

  final dashedMatch = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(normalized);
  if (dashedMatch != null) {
    return '${dashedMatch.group(1)}-${dashedMatch.group(2)}';
  }

  final fullYearMatch = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(normalized);
  if (fullYearMatch != null) {
    final startYear = fullYearMatch.group(1)!;
    final endYear = fullYearMatch.group(2)!;
    return '$startYear-${endYear.substring(2)}';
  }

  return null;
}

class ExcelUploadScreen extends StatefulWidget {
  final String selectedBuyerId;
  final String selectedBuyerName;
  final String selectedBuyerPan;
  final String? selectedFinancialYearId;
  final String? selectedFinancialYearLabel;

  const ExcelUploadScreen({
    super.key,
    required this.selectedBuyerId,
    required this.selectedBuyerName,
    required this.selectedBuyerPan,
    this.selectedFinancialYearId,
    this.selectedFinancialYearLabel,
  });

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  static const List<String> _allowedUploadExtensions = [
    'xlsx',
    'xls',
    'xlsm',
    'csv',
  ];
  static const List<String> _availableSections =
      TdsSectionCatalog.supportedSectionCodes;

  bool isLoadingTds = false;
  Tds26QUploadFile? tdsUploadFile;
  String _activeSectionCode = '194Q';

  // Seller mapping state
  bool _isSellerMappingConfirmed = false;
  bool _isLoadingSellerMapping = false;
  SellerMappingPreflightResult? _cachedPreflightResult;
  bool _isSellerPreflightDirty = true;
  Map<String, String> _sellerSelectedMappings = <String, String>{};
  Set<String> _sellerClearedRowKeys = <String>{};
  final WorkspaceExportPathService _workspaceExportPathService =
      WorkspaceExportPathService();

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

  @override
  void didUpdateWidget(covariant ExcelUploadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasBuyerOrFinancialYearChanged(oldWidget)) return;
    _resetStateForBuyerFinancialYearChange();
  }

  bool _hasBuyerOrFinancialYearChanged(ExcelUploadScreen oldWidget) {
    return _hasBuyerChanged(oldWidget) || _hasFinancialYearChanged(oldWidget);
  }

  bool _hasBuyerChanged(ExcelUploadScreen oldWidget) {
    final oldBuyerId = oldWidget.selectedBuyerId.trim();
    final newBuyerId = widget.selectedBuyerId.trim();
    if (oldBuyerId != newBuyerId) return true;

    final oldBuyerPan = normalizePan(oldWidget.selectedBuyerPan);
    final newBuyerPan = normalizePan(widget.selectedBuyerPan);
    if (oldBuyerPan != newBuyerPan) return true;

    if (oldBuyerId.isEmpty && oldBuyerPan.isEmpty) {
      return oldWidget.selectedBuyerName.trim() !=
          widget.selectedBuyerName.trim();
    }

    return false;
  }

  bool _hasFinancialYearChanged(ExcelUploadScreen oldWidget) {
    final oldFinancialYearId = oldWidget.selectedFinancialYearId?.trim() ?? '';
    final newFinancialYearId = widget.selectedFinancialYearId?.trim() ?? '';
    if (oldFinancialYearId != newFinancialYearId) return true;

    if (oldFinancialYearId.isEmpty) {
      return (oldWidget.selectedFinancialYearLabel?.trim() ?? '') !=
          (widget.selectedFinancialYearLabel?.trim() ?? '');
    }

    return false;
  }

  void _resetStateForBuyerFinancialYearChange() {
    isLoadingTds = false;
    tdsUploadFile = null;
    _activeSectionCode = '194Q';

    _isSellerMappingConfirmed = false;
    _isLoadingSellerMapping = false;
    _cachedPreflightResult = null;
    _isSellerPreflightDirty = true;
    _sellerSelectedMappings = <String, String>{};
    _sellerClearedRowKeys = <String>{};

    selectedSections
      ..clear()
      ..add('194Q');
    for (final section in _availableSections) {
      sectionLoading[section] = false;
      sectionFiles[section] = <LedgerUploadFile>[];
      ledgerRowsBySection[section] = <NormalizedLedgerRow>[];
    }
    purchaseRowsByFileId.clear();

    purchaseRows = <PurchaseRow>[];
    tdsRows = <Tds26QRow>[];
    normalizedPurchaseRows = <NormalizedTransactionRow>[];
    normalizedTdsRows = <NormalizedTransactionRow>[];
    detectedGstNo = null;
  }

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
    int? preferredHeaderRowIndex,
    bool? preferredHeadersTrusted,
    Map<String, String>? preferredColumnMapping,
  }) async {
    final profileSheetName = preferredSheetName ?? validation.detectedSheet;
    final previewData =
        preferredHeaderRowIndex != null &&
            preferredHeadersTrusted != null &&
            preferredColumnMapping != null &&
            profileSheetName != null &&
            profileSheetName.trim().isNotEmpty
        ? ExcelService.buildPreviewDataWithProfile(
            bytes,
            fileType: fileType,
            fileName: fileName,
            sheetName: profileSheetName,
            headerRowIndex: preferredHeaderRowIndex,
            headersTrusted: preferredHeadersTrusted,
            columnMapping: preferredColumnMapping,
            warnings: validation.warnings,
            confidenceScore: validation.confidenceScore,
            sessionCache: sessionCache,
          )
        : ExcelService.buildPreviewData(
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
      if (!mounted) return null;
      _showUploadSnackBar(
        'Could not find valid headers or data in the selected sheet.',
      );
      return null;
    }

    if (!mounted) return null;
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
      if (!mounted) return null;
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    if (!mounted) return null;
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
      if (!mounted) return null;
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    if (!mounted) return null;
    return showColumnMappingScreen(previewData: previewData);
  }

  Future<String?> _showSheetSelectionDialog({
    required List<String> sheets,
    required String title,
  }) async {
    if (!mounted || sheets.isEmpty) return null;

    var selectedSheet = sheets.first;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: RadioGroup<String>(
                      groupValue: selectedSheet,
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedSheet = value;
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: sheets
                            .map(
                              (sheet) => RadioListTile<String>(
                                value: sheet,
                                title: Text(sheet),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
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

  Future<({String sheetName, bool hadMultipleSheets})?> _selectWorkbookSheet({
    required List<int> bytes,
    required String title,
  }) async {
    final sheetNames = await ExcelService.listWorkbookSheetNamesInBackground(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    if (!mounted) return null;

    if (sheetNames.isEmpty) {
      _showUploadSnackBar('No sheets found in the selected Excel workbook.');
      return null;
    }

    if (sheetNames.length == 1) {
      return (sheetName: sheetNames.first, hadMultipleSheets: false);
    }

    final selectedSheet = await _showSheetSelectionDialog(
      sheets: sheetNames,
      title: title,
    );
    if (!mounted) return null;

    if (selectedSheet == null || selectedSheet.trim().isEmpty) {
      return null;
    }

    return (sheetName: selectedSheet, hadMultipleSheets: true);
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
    AppRectSnackBar.show(context, message);
  }

  void _invalidateSellerPreflightCache({bool clearDraftState = false}) {
    _cachedPreflightResult = null;
    _isSellerPreflightDirty = true;
    if (clearDraftState) {
      _sellerSelectedMappings = <String, String>{};
      _sellerClearedRowKeys = <String>{};
    }
  }

  void _markSellerPreflightDirty() {
    _invalidateSellerPreflightCache(clearDraftState: true);
    _isSellerMappingConfirmed = false;
  }

  Future<PlatformFile?> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedUploadExtensions,
      withData: true,
    );
    if (!mounted) return null;

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=file_selected file=${file.name} sizeBytes=${file.size}',
    );
    final normalizedExtension = p.extension(file.name).toLowerCase();
    if (normalizedExtension == '.csv') {
      _showUploadSnackBar(
        'CSV file selected: ${file.name}. CSV selection is visible now, but the current import parser expects workbook sheets. Please export as .xlsx, .xls, or .xlsm and retry.',
      );
    }

    return file;
  }

  Future<void> _snapshotSourceFile({
    required PlatformFile pickedFile,
    required List<int> bytes,
    required SourceFileSnapshotType type,
  }) async {
    try {
      final snapshotPath = await _workspaceExportPathService
          .copySourceFileSnapshot(
            buyerId: widget.selectedBuyerId,
            financialYearId: widget.selectedFinancialYearId,
            originalFileName: pickedFile.name,
            bytes: bytes,
            type: type,
          );
      if (snapshotPath == null) {
        AppLogger.debug(
          'SOURCE SNAPSHOT => skipped workspace unavailable file=${pickedFile.name}',
        );
        return;
      }
      AppLogger.debug('SOURCE SNAPSHOT => copied $snapshotPath');
    } catch (e) {
      AppLogger.warning(
        'SOURCE SNAPSHOT => failed file=${pickedFile.name} error=$e',
      );
    }
  }

  void _setSectionLoading(String sectionCode, bool isLoading) {
    if (!mounted) return;
    final setStateWatch = Stopwatch()..start();
    setState(() {
      sectionLoading[sectionCode] = isLoading;
    });
    setStateWatch.stop();
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=set_section_loading_setState ms=${setStateWatch.elapsedMilliseconds} section=$sectionCode loading=$isLoading',
    );
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
      _markSellerPreflightDirty();
      sectionFiles[sectionCode] = sectionFiles[sectionCode]!
          .where((item) => item.id != file.id)
          .toList();
      if (sectionCode == '194Q') {
        purchaseRowsByFileId.remove(file.id);
        _rebuildPurchaseState();
      } else {
        ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
            .expand((item) => item.rows)
            .toList();
      }
    });
  }

  Future<LedgerUploadFile?> _buildPurchaseUploadFile({
    required PlatformFile pickedFile,
    required List<int> bytes,
    String? existingFileId,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
    String? preferredSheetName,
  }) async {
    final parseWatch = Stopwatch()..start();
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=purchase_file_size file=${pickedFile.name} sizeBytes=${bytes.length}',
    );
    final response = await ImportUploadFlowService.preparePurchaseImport(
      buyerId: widget.selectedBuyerId,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
      preferredSheetName: preferredSheetName,
    );
    if (!mounted) return null;

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
      if (!mounted) return null;
    }

    final uploadedAt = DateTime.now();
    final fileId =
        existingFileId ??
        '194Q_${uploadedAt.microsecondsSinceEpoch}_${pickedFile.name}';
    final normalizedRows = result.parsedRows
        .map(
          (row) => NormalizedLedgerRow.fromPurchaseRow(
            row,
            sourceFileName: pickedFile.name,
            sourceLedgerFileId: fileId,
            sourceLedgerUploadedAt: uploadedAt,
          ),
        )
        .toList();

    purchaseRowsByFileId[fileId] = result.parsedRows;
    parseWatch.stop();
    AppLogger.debug(
      'UPLOAD PERF => purchase parse ${parseWatch.elapsedMilliseconds} ms | '
      'file=${pickedFile.name} rows=${result.parsedRows.length} mappingStatus=${result.mappingStatus}',
    );

    return LedgerUploadFile(
      id: fileId,
      sectionCode: '194Q',
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: result.parsedRows.length,
      uploadedAt: uploadedAt,
      parserType: 'purchase',
      rows: normalizedRows,
      mappingStatus: result.mappingStatus,
      wasManuallyMapped: result.wasManuallyMapped,
      wasAutoConfirmed: result.wasAutoConfirmed,
      usedSavedProfile: result.usedSavedProfile,
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
    String? preferredSheetName,
  }) async {
    final parseWatch = Stopwatch()..start();
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=generic_file_size section=$sectionCode file=${pickedFile.name} sizeBytes=${bytes.length}',
    );
    final response = await ImportUploadFlowService.prepareGenericLedgerImport(
      buyerId: widget.selectedBuyerId,
      sectionCode: sectionCode,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
      preferredSheetName: preferredSheetName,
    );
    if (!mounted) return null;

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
    AppLogger.debug(
      'UPLOAD PERF => source parse ${parseWatch.elapsedMilliseconds} ms | '
      'section=$sectionCode file=${pickedFile.name} rows=${result.parsedRows.length} '
      'mappingStatus=${result.mappingStatus}',
    );

    final uploadedAt = DateTime.now();
    final fileId =
        existingFileId ??
        '${sectionCode}_${uploadedAt.microsecondsSinceEpoch}_${pickedFile.name}';
    final rowsWithSource = result.parsedRows
        .map(
          (row) => row.copyWith(
            sourceFileName: pickedFile.name,
            sourceLedgerFileId: fileId,
            sourceLedgerUploadedAt: uploadedAt,
          ),
        )
        .toList();

    return LedgerUploadFile(
      id: fileId,
      sectionCode: sectionCode,
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: result.parsedRows.length,
      uploadedAt: uploadedAt,
      parserType: 'genericLedger',
      rows: rowsWithSource,
      mappingStatus: result.mappingStatus,
      wasManuallyMapped: result.wasManuallyMapped,
      wasAutoConfirmed: result.wasAutoConfirmed,
      usedSavedProfile: result.usedSavedProfile,
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
      if (!mounted) return;
      if (columnMappingResult == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      final response = await ImportUploadFlowService.prepareSectionFileRemap(
        file: file,
        columnMappingResult: columnMappingResult,
      );
      if (!mounted) return;
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
          if (!mounted) return;
        }
        if (result.parsedPurchaseRows != null) {
          purchaseRowsByFileId[file.id] = result.parsedPurchaseRows!;
        }
      }

      final resolvedUpdatedFile = result.updatedFile;

      setState(() {
        _markSellerPreflightDirty();
        sectionFiles[sectionCode] = sectionFiles[sectionCode]!
            .map<LedgerUploadFile>(
              (item) => item.id == file.id ? resolvedUpdatedFile : item,
            )
            .toList();
        if (sectionCode == '194Q') {
          _rebuildPurchaseState();
        } else {
          ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
              .expand((item) => item.rows)
              .toList();
        }
        sectionLoading[sectionCode] = false;
      });

      _showUploadSnackBar('${file.fileName} remapped successfully');
    } catch (e) {
      _setSectionLoading(sectionCode, false);
      _showUploadSnackBar('Remap failed for ${file.fileName}: $e');
    }
  }

  Future<void> _upload194QFile() async {
    _setSectionLoading('194Q', true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final pickedFile = await _pickExcelFile();
      if (!mounted) return;
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

      final sheetSelection = await _selectWorkbookSheet(
        bytes: bytes,
        title: 'Select 194Q Purchase Sheet',
      );
      if (!mounted) return;
      if (sheetSelection == null) {
        _setSectionLoading('194Q', false);
        return;
      }

      final uploadFile = await _buildPurchaseUploadFile(
        pickedFile: pickedFile,
        bytes: bytes,
        preferredSheetName: sheetSelection.sheetName,
        forceColumnMapping: sheetSelection.hadMultipleSheets,
      );
      if (!mounted) return;
      if (uploadFile == null) {
        _setSectionLoading('194Q', false);
        return;
      }

      final setStateWatch = Stopwatch()..start();
      setState(() {
        _markSellerPreflightDirty();
        sectionFiles['194Q'] = [...sectionFiles['194Q']!, uploadFile];
        _rebuildPurchaseState();
        sectionLoading['194Q'] = false;
      });
      setStateWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=purchase_upload_setState ms=${setStateWatch.elapsedMilliseconds} rows=${uploadFile.rowCount}',
      );

      unawaited(
        _snapshotSourceFile(
          pickedFile: pickedFile,
          bytes: bytes,
          type: SourceFileSnapshotType.ledger,
        ),
      );
      _showUploadSnackBar('${pickedFile.name} uploaded');
    } catch (e) {
      _setSectionLoading('194Q', false);
      _showUploadSnackBar('194Q upload error: $e');
    }
  }

  Future<void> _uploadGenericSectionFile(String sectionCode) async {
    _setSectionLoading(sectionCode, true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final pickedFile = await _pickExcelFile();
      if (!mounted) return;
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

      final sheetSelection = await _selectWorkbookSheet(
        bytes: bytes,
        title: 'Select $sectionCode Ledger Sheet',
      );
      if (!mounted) return;
      if (sheetSelection == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      final uploadFile = await _buildGenericLedgerUploadFile(
        sectionCode: sectionCode,
        pickedFile: pickedFile,
        bytes: bytes,
        preferredSheetName: sheetSelection.sheetName,
        forceColumnMapping: sheetSelection.hadMultipleSheets,
      );
      if (!mounted) return;
      if (uploadFile == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      final setStateWatch = Stopwatch()..start();
      setState(() {
        _markSellerPreflightDirty();
        sectionFiles[sectionCode] = [...sectionFiles[sectionCode]!, uploadFile];
        ledgerRowsBySection[sectionCode] = sectionFiles[sectionCode]!
            .expand((item) => item.rows)
            .toList();
        sectionLoading[sectionCode] = false;
      });
      setStateWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=generic_upload_setState ms=${setStateWatch.elapsedMilliseconds} section=$sectionCode rows=${uploadFile.rowCount}',
      );

      unawaited(
        _snapshotSourceFile(
          pickedFile: pickedFile,
          bytes: bytes,
          type: SourceFileSnapshotType.ledger,
        ),
      );
      _showUploadSnackBar('${pickedFile.name} uploaded');
    } catch (e) {
      _setSectionLoading(sectionCode, false);
      _showUploadSnackBar('$sectionCode upload error: $e');
    }
  }

  Future<void> uploadTds26QFile() async {
    final initialSetStateWatch = Stopwatch()..start();
    setState(() {
      isLoadingTds = true;
    });
    initialSetStateWatch.stop();
    AppLogger.debug(
      'UPLOAD FREEZE PERF => step=tds_loading_setState ms=${initialSetStateWatch.elapsedMilliseconds} loading=true',
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final uploadWatch = Stopwatch()..start();
      final pickWatch = Stopwatch()..start();
      final pickedFile = await _pickExcelFile();
      if (!mounted) return;
      pickWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=tds_pick_file ms=${pickWatch.elapsedMilliseconds} selected=${pickedFile != null}',
      );
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
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=tds_file_size file=${pickedFile.name} sizeBytes=${bytes.length}',
      );

      final sheetSelection = await _selectWorkbookSheet(
        bytes: bytes,
        title: 'Select 26Q Sheet',
      );
      if (!mounted) return;
      if (sheetSelection == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      final validationWatch = Stopwatch()..start();
      final validation = await ImportUploadFlowService.validateTds26QImport(
        bytes,
        preferredSheetName: sheetSelection.sheetName,
      );
      if (!mounted) return;
      validationWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=tds_validation_total ms=${validationWatch.elapsedMilliseconds} valid=${validation.isValid} requiresSelection=${validation.requiresUserSelection}',
      );

      final shouldOpenColumnMapping =
          sheetSelection.hadMultipleSheets ||
          _shouldAutoOpenColumnMapping(
            validation: validation,
            fileType: ExcelImportType.tds26q,
          );
      if (shouldOpenColumnMapping) {
        setState(() => isLoadingTds = false);
      }

      final prepareWatch = Stopwatch()..start();
      final response = await ImportUploadFlowService.prepareTds26QImport(
        bytes: bytes,
        fileName: pickedFile.name,
        validation: validation,
        openColumnMapping: _openImportColumnMapping,
        preferredSheetName: sheetSelection.sheetName,
        forceColumnMapping: sheetSelection.hadMultipleSheets,
      );
      if (!mounted) return;
      prepareWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=tds_prepare_import_total ms=${prepareWatch.elapsedMilliseconds} success=${response.isSuccess}',
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

      final setStateWatch = Stopwatch()..start();
      setState(() {
        _markSellerPreflightDirty();
        tdsUploadFile = Tds26QUploadFile(
          fileName: pickedFile.name,
          bytes: bytes,
          rowCount: result.parsedRows.length,
          uploadedAt: DateTime.now(),
          rows: result.parsedRows,
          mappingStatus: result.mappingStatus,
          wasManuallyMapped: result.wasManuallyMapped,
          wasAutoConfirmed: result.wasAutoConfirmed,
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
      setStateWatch.stop();
      AppLogger.debug(
        'UPLOAD FREEZE PERF => step=tds_upload_setState ms=${setStateWatch.elapsedMilliseconds} rows=${result.parsedRows.length}',
      );
      uploadWatch.stop();
      AppLogger.debug(
        'UPLOAD PERF => 26Q upload total ${uploadWatch.elapsedMilliseconds} ms | '
        'file=${pickedFile.name} rows=${result.parsedRows.length} '
        'sheet=${validation.detectedSheet ?? 'manual'}',
      );
      AppLogger.debug('UPLOAD COUNT => 26Q rows=${result.parsedRows.length}');

      unawaited(
        _snapshotSourceFile(
          pickedFile: pickedFile,
          bytes: bytes,
          type: SourceFileSnapshotType.tds26q,
        ),
      );
      _showUploadSnackBar('${pickedFile.name} uploaded');
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      if (columnMappingResult == null) {
        setState(() => isLoadingTds = false);
        return;
      }

      final response = await ImportUploadFlowService.prepareTds26QRemap(
        bytes: file.bytes,
        columnMappingResult: columnMappingResult,
      );
      if (!mounted) return;
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
        _markSellerPreflightDirty();
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

      _showUploadSnackBar('26Q mapping confirmed');
    } catch (e) {
      if (!mounted) return;
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
        'Please review and confirm seller mappings before opening reconciliation.',
      );
      return;
    }

    final totalSourceRows = sourceRowsBySection.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );
    AppLogger.debug(
      'UPLOAD COUNT => open reconciliation sourceRows=$totalSourceRows '
      'tdsRows=${tdsRows.length} sections=${sourceRowsBySection.keys.join(',')}',
    );

    if (!mounted) return;
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
          selectedBuyerId: widget.selectedBuyerId,
          buyerName: widget.selectedBuyerName,
          buyerPan: widget.selectedBuyerPan,
          selectedFinancialYearId: widget.selectedFinancialYearId,
          selectedFinancialYearLabel: widget.selectedFinancialYearLabel,
          gstNo: detectedGstNo ?? '',
          sellerMappingConfirmed: _isSellerMappingConfirmed,
        ),
      ),
    );
  }

  Future<void> openSellerMappingScreen() async {
    if (tdsRows.isEmpty) {
      _showUploadSnackBar('Please upload and map the 26Q file first');
      return;
    }

    final sourceRowsBySection = _buildSourceRowsBySection();
    if (sourceRowsBySection.isEmpty) {
      _showUploadSnackBar(
        'Upload at least one source file in any selected section first.',
      );
      return;
    }

    setState(() => _isLoadingSellerMapping = true);

    try {
      final preflightWatch = Stopwatch()..start();
      final SellerMappingPreflightResult preflightResult;
      if (!_isSellerPreflightDirty && _cachedPreflightResult != null) {
        preflightResult = _cachedPreflightResult!;
        AppLogger.debug('UPLOAD POSTMAP PERF => preflight_cache_hit');
      } else {
        preflightResult = await SellerMappingPreflightService.analyze(
          buyerName: widget.selectedBuyerName,
          buyerPan: widget.selectedBuyerPan,
          tdsRows: tdsRows,
          sourceRowsBySection: sourceRowsBySection,
        );
        _cachedPreflightResult = preflightResult;
        _isSellerPreflightDirty = false;
        AppLogger.debug(
          'UPLOAD POSTMAP PERF => preflight_analyze ms=${preflightWatch.elapsedMilliseconds}',
        );
      }

      if (!mounted) return;

      final fyLabel =
          _selectedFinancialYearDisplayLabel() ??
          _buildSellerMappingFinancialYearLabel();

      final totalSourceRows = sourceRowsBySection.values.fold<int>(
        0,
        (sum, rows) => sum + rows.length,
      );

      final result = await Navigator.push<SellerMappingScreenResult>(
        context,
        MaterialPageRoute(
          builder: (_) => SellerMappingScreen(
            mode: SellerMappingScreenMode.preflight,
            buyerName: widget.selectedBuyerName,
            buyerPan: widget.selectedBuyerPan,
            financialYearLabel: fyLabel,
            selectedSectionLabel: _activeSectionCode,
            initialViewMode: ReconciliationViewMode.summary,
            purchaseRows: preflightResult.reviewRows,
            tdsParties: preflightResult.tdsParties,
            existingMappings: preflightResult.existingMappings,
            blockedAliases: preflightResult.blockedAliases,
            tdsPartyPans: preflightResult.tdsPartyPans,
            rawSourceRowCount: totalSourceRows,
            buyerGstNo: detectedGstNo ?? '',
            initialSelectedMappings: _sellerSelectedMappings,
            initialClearedRowKeys: _sellerClearedRowKeys,
          ),
        ),
      );
      if (!mounted) return;

      // Phase 2 perf: if SellerMappingScreen already proves review is safe,
      // skip the expensive full seller preflight refresh.
      if (result != null &&
          result.dangerousRemaining == 0 &&
          result.unreviewedExceptionCount == 0) {
        AppLogger.debug(
          'UPLOAD POSTMAP PERF => refresh_preflight_skipped dangerousRemaining=0',
        );

        await _persistSellerMappingResult(result);
        if (!mounted) return;
        _storeSellerMappingDraft(result);

        setState(() {
          _isSellerMappingConfirmed = true;
          _isLoadingSellerMapping = false;
        });
        _invalidateSellerPreflightCache();

        _showUploadSnackBar('Seller mapping saved');
        return;
      }
      if (result == null) {
        setState(() => _isLoadingSellerMapping = false);
        _showUploadSnackBar('Seller mapping review cancelled');
        return;
      }

      await _persistSellerMappingResult(result);
      if (!mounted) return;
      _storeSellerMappingDraft(result);
      _invalidateSellerPreflightCache();

      final canOpen =
          result.dangerousRemaining == 0 &&
          result.unreviewedExceptionCount == 0;
      setState(() {
        _isSellerMappingConfirmed = canOpen;
        _isLoadingSellerMapping = false;
      });

      _showUploadSnackBar(
        canOpen
            ? 'Seller mappings reviewed successfully'
            : 'Seller mapping review saved, but blocking items still remain',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSellerMapping = false);
        _showUploadSnackBar('Failed to open seller mapping: $e');
      }
    }
  }

  String _buildSellerMappingFinancialYearLabel() {
    final primaryFinancialYear = tdsRows.isNotEmpty
        ? tdsRows.first.financialYear
        : null;
    final fallbackFinancialYear = _firstAvailableFinancialYear();
    return _formatFinancialYearLabel(
      primaryFinancialYear,
      fallbackFinancialYear: fallbackFinancialYear,
    );
  }

  String? _firstAvailableFinancialYear() {
    for (final row in tdsRows) {
      final value = row.financialYear.trim();
      if (_normalizeFinancialYearValue(value) != null) {
        return value;
      }
    }

    if (tdsUploadFile != null) {
      for (final row in tdsUploadFile!.rows) {
        final value = row.financialYear.trim();
        if (_normalizeFinancialYearValue(value) != null) {
          return value;
        }
      }
    }

    return null;
  }

  String _formatFinancialYearLabel(
    String? financialYear, {
    String? fallbackFinancialYear,
  }) {
    return formatSellerMappingFinancialYearLabel(
      financialYear,
      fallbackFinancialYear: fallbackFinancialYear,
    );
  }

  String? _normalizeFinancialYearValue(String? value) {
    return _normalizeSellerMappingFinancialYearValue(value);
  }

  String? _selectedFinancialYearValue() {
    final label = widget.selectedFinancialYearLabel?.trim();
    if (label == null || label.isEmpty) {
      return null;
    }

    return _normalizeFinancialYearValue(label) ?? label;
  }

  String? _selectedFinancialYearDisplayLabel() {
    final value = _selectedFinancialYearValue();
    if (value == null || value.isEmpty) {
      return null;
    }

    final stripped = value.replaceFirst(
      RegExp(r'^fy\s*', caseSensitive: false),
      '',
    );
    return 'FY $stripped';
  }

  Future<void> _persistSellerMappingResult(
    SellerMappingScreenResult result,
  ) async {
    final totalWatch = Stopwatch()..start();
    final deleteWatch = Stopwatch()..start();
    await SellerMappingService.deleteMappings(
      result.deleted
          .map(
            (item) => <String, String>{
              'buyerPan': widget.selectedBuyerPan,
              'aliasName': item['aliasName'] ?? '',
              'sectionCode': item['sectionCode'] ?? 'ALL',
            },
          )
          .toList(growable: false),
    );
    deleteWatch.stop();
    AppLogger.debug(
      'SELLER DB PERF => step=delete_mappings ms=${deleteWatch.elapsedMilliseconds} count=${result.deleted.length}',
    );

    final upsertWatch = Stopwatch()..start();
    await SellerMappingService.saveMappings(
      result.upserts
          .map(
            (item) => SellerMapping(
              buyerName: widget.selectedBuyerName,
              buyerPan: widget.selectedBuyerPan,
              aliasName: item['aliasName'] ?? '',
              sectionCode: item['sectionCode'] ?? 'ALL',
              mappedPan: item['mappedPan'] ?? '',
              mappedName: item['mappedName'] ?? '',
            ),
          )
          .toList(growable: false),
    );
    upsertWatch.stop();
    totalWatch.stop();
    AppLogger.debug(
      'SELLER DB PERF => step=upsert_mappings ms=${upsertWatch.elapsedMilliseconds} count=${result.upserts.length}',
    );
    AppLogger.debug(
      'SELLER DB PERF => step=total_db_save ms=${totalWatch.elapsedMilliseconds} deletes=${result.deleted.length} upserts=${result.upserts.length}',
    );
  }

  void _storeSellerMappingDraft(SellerMappingScreenResult result) {
    _sellerSelectedMappings = Map<String, String>.from(result.selectedMappings);
    _sellerClearedRowKeys = Set<String>.from(result.clearedRowKeys);
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

  Iterable<LedgerUploadFile> get _allUploadedSectionFiles =>
      sectionFiles.values.expand((files) => files);

  List<String> get _pendingMappingReviewLabels {
    final pending = <String>[];

    final tdsFile = tdsUploadFile;
    if (tdsFile != null && !tdsFile.mappingStatus.isConfirmed) {
      pending.add('26Q (${tdsFile.fileName})');
    }

    for (final file in _allUploadedSectionFiles) {
      if (!file.mappingStatus.isConfirmed) {
        pending.add('${file.sectionCode} (${file.fileName})');
      }
    }

    return pending;
  }

  bool get _allRequiredMappingsConfirmed => _pendingMappingReviewLabels.isEmpty;

  bool get canOpenReconciliation =>
      _has26QReady &&
      _buildSourceRowsBySection().isNotEmpty &&
      _allRequiredMappingsConfirmed &&
      _isSellerMappingConfirmed;

  bool get _hasWorkspaceContent => _has26QReady || _totalSectionFiles > 0;

  Future<List<BatchMappingReviewItem>> _loadBatchMappingReviewItems() async {
    return BatchMappingReviewService.buildItems(
      tdsFile: tdsUploadFile,
      sectionFiles: _allUploadedSectionFiles,
    );
  }

  LedgerUploadFile? _findSectionFileByBatchItem(BatchMappingReviewItem item) {
    if (item.type != BatchMappingReviewItemType.sectionFile) {
      return null;
    }
    if (!item.itemKey.startsWith('section:')) {
      return null;
    }

    final fileId = item.itemKey.substring('section:'.length);
    for (final file in _allUploadedSectionFiles) {
      if (file.id == fileId) {
        return file;
      }
    }
    return null;
  }

  String _mappingSnapshot(Map<String, String> mapping) {
    final entries = mapping.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries.map((entry) => '${entry.key}=${entry.value}').join('|');
  }

  String? _batchItemSnapshot(BatchMappingReviewItem item) {
    switch (item.type) {
      case BatchMappingReviewItemType.tds26q:
        final file = tdsUploadFile;
        if (file == null) return null;
        return [
          'tds26q',
          file.mappingStatus.name,
          file.wasManuallyMapped.toString(),
          file.sheetName ?? '',
          file.headerRowIndex?.toString() ?? '',
          _mappingSnapshot(file.columnMapping),
        ].join('||');
      case BatchMappingReviewItemType.sectionFile:
        final file = _findSectionFileByBatchItem(item);
        if (file == null) return null;
        return [
          file.id,
          file.mappingStatus.name,
          file.wasManuallyMapped.toString(),
          file.sheetName ?? '',
          file.headerRowIndex?.toString() ?? '',
          _mappingSnapshot(file.columnMapping),
        ].join('||');
    }
  }

  Future<bool> _reviewBatchMappingItem(BatchMappingReviewItem item) async {
    final beforeSnapshot = _batchItemSnapshot(item);

    switch (item.type) {
      case BatchMappingReviewItemType.tds26q:
        await _reviewTds26QMapping();
        if (!mounted) return false;
        break;
      case BatchMappingReviewItemType.sectionFile:
        final file = _findSectionFileByBatchItem(item);
        if (file == null) {
          return false;
        }
        await _remapSectionFile(file.sectionCode, file);
        if (!mounted) return false;
    }

    return beforeSnapshot != _batchItemSnapshot(item);
  }

  Future<bool> _confirmBatchMappingItem(BatchMappingReviewItem item) async {
    if (!mounted) return false;
    if (item.mappingStatus.isConfirmed) {
      return false;
    }

    switch (item.type) {
      case BatchMappingReviewItemType.tds26q:
        final file = tdsUploadFile;
        if (file == null) {
          return false;
        }
        setState(() {
          tdsUploadFile = file.copyWith(
            mappingStatus: UploadMappingStatus.confirmed,
          );
        });
        return true;
      case BatchMappingReviewItemType.sectionFile:
        final file = _findSectionFileByBatchItem(item);
        if (file == null) {
          return false;
        }
        setState(() {
          sectionFiles[file.sectionCode] = sectionFiles[file.sectionCode]!
              .map<LedgerUploadFile>(
                (current) => current.id == file.id
                    ? current.copyWith(
                        mappingStatus: UploadMappingStatus.confirmed,
                      )
                    : current,
              )
              .toList();
        });
        return true;
    }
  }

  Future<int> _confirmAllSafeBatchMappings() async {
    final items = await _loadBatchMappingReviewItems();
    if (!mounted) return 0;
    var confirmedCount = 0;

    for (final item in items) {
      if (!item.canConfirmSafely) {
        continue;
      }
      final confirmed = await _confirmBatchMappingItem(item);
      if (!mounted) return confirmedCount;
      if (confirmed) {
        confirmedCount += 1;
      }
    }

    return confirmedCount;
  }

  String get _workspaceStatusLabel {
    if (canOpenReconciliation) return 'Ready';
    if (_hasWorkspaceContent) return 'In Progress';
    return 'Setup Required';
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

  Future<void> _reviewWorkspaceStatus() async {
    if (!_hasWorkspaceContent) {
      _showUploadSnackBar(
        'Add a 26Q file or source files to start building the workspace.',
      );
      return;
    }

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchMappingReviewScreen(
          loadItems: _loadBatchMappingReviewItems,
          onReviewItem: _reviewBatchMappingItem,
          onConfirmItem: _confirmBatchMappingItem,
          onConfirmAllSafe: _confirmAllSafeBatchMappings,
        ),
      ),
    );
  }

  Color _sectionAccent(String sectionCode) {
    switch (sectionCode) {
      case '194Q':
        return AppColorScheme.primary;
      case '194C':
        return AppColorScheme.secondary;
      case '194H':
        return const Color(0xFF6750A4);
      case '194I_A':
        return AppColorScheme.warning;
      case '194I_B':
        return AppColorScheme.danger;
      case '194J_A':
        return const Color(0xFF0E7490);
      case '194J_B':
        return const Color(0xFF5B4B8A);
      default:
        return AppColorScheme.textSecondary;
    }
  }

  String _parserLabel(String sectionCode) {
    return TdsSectionCatalog.uploadModeFor(sectionCode) ==
            TdsSectionUploadMode.purchase
        ? 'Purchase Parser'
        : 'Generic Ledger Parser';
  }

  Color _mappingStatusColor(UploadMappingStatus status) {
    switch (status) {
      case UploadMappingStatus.notMapped:
        return AppColorScheme.warning;
      case UploadMappingStatus.autoMapped:
        return AppColorScheme.info;
      case UploadMappingStatus.needsReview:
        return AppColorScheme.warning;
      case UploadMappingStatus.confirmed:
        return AppColorScheme.success;
    }
  }

  Color _mappingStatusBackground(UploadMappingStatus status) {
    switch (status) {
      case UploadMappingStatus.notMapped:
        return AppColorScheme.warningSoft;
      case UploadMappingStatus.autoMapped:
        return AppColorScheme.infoSoft;
      case UploadMappingStatus.needsReview:
        return AppColorScheme.warningSoft;
      case UploadMappingStatus.confirmed:
        return AppColorScheme.successSoft;
    }
  }

  String _uploadStatusLabel(
    UploadMappingStatus status, {
    required bool wasAutoConfirmed,
    required bool usedSavedProfile,
  }) {
    if (status == UploadMappingStatus.confirmed && wasAutoConfirmed) {
      return usedSavedProfile
          ? 'Auto-confirmed (saved format)'
          : 'Auto-confirmed';
    }

    return status.label;
  }

  BoxDecoration _panelDecoration({
    Color borderColor = AppColorScheme.border,
    Color backgroundColor = Colors.white,
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
              color: Colors.black.withValues(alpha: 0.055),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF0F172A),
              fixedSize: const Size(40, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Upload',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              _showUploadSnackBar(
                'Upload 26Q first, add source files by section, review mappings, then open reconciliation.',
              );
            },
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Upload help',
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              fixedSize: const Size(40, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuyerContextCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.selectedBuyerName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppInfoChip(
                label: 'PAN',
                value: 'PAN ${widget.selectedBuyerPan}',
                icon: Icons.badge_outlined,
                compact: true,
                showLabel: false,
                backgroundColor: const Color(0xFFF8FAFC),
                borderColor: const Color(0xFFCBD5E1),
                iconColor: const Color(0xFF475569),
                valueColor: const Color(0xFF475569),
                fontSize: 12,
              ),
              if (_selectedFinancialYearValue() != null)
                AppInfoChip(
                  label: 'FY',
                  value: 'FY ${_selectedFinancialYearValue()}',
                  icon: Icons.calendar_month_outlined,
                  compact: true,
                  showLabel: false,
                  backgroundColor: const Color(0xFFF8FAFC),
                  borderColor: const Color(0xFFCBD5E1),
                  iconColor: const Color(0xFF475569),
                  valueColor: const Color(0xFF475569),
                  fontSize: 12,
                ),
              AppInfoChip(
                label: 'Status',
                value: _workspaceStatusLabel,
                icon: canOpenReconciliation
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_bottom_rounded,
                compact: true,
                showLabel: false,
                iconColor: canOpenReconciliation
                    ? const Color(0xFF047857)
                    : const Color(0xFF475569),
                valueColor: canOpenReconciliation
                    ? const Color(0xFF047857)
                    : const Color(0xFF475569),
                backgroundColor: canOpenReconciliation
                    ? const Color(0xFFD1FAE5)
                    : const Color(0xFFF8FAFC),
                borderColor: canOpenReconciliation
                    ? const Color(0xFF10B981)
                    : const Color(0xFFCBD5E1),
                fontSize: 12,
              ),
              AppInfoChip(
                label: 'Source files',
                value: '$_totalSectionFiles source file(s)',
                icon: Icons.folder_copy_rounded,
                compact: true,
                showLabel: false,
                backgroundColor: const Color(0xFFF8FAFC),
                borderColor: const Color(0xFFCBD5E1),
                iconColor: const Color(0xFF475569),
                valueColor: const Color(0xFF475569),
                fontSize: 12,
              ),
              AppInfoChip(
                label: 'Source rows',
                value: '$_totalLedgerRows source rows',
                icon: Icons.table_rows_rounded,
                compact: true,
                showLabel: false,
                backgroundColor: const Color(0xFFF8FAFC),
                borderColor: const Color(0xFFCBD5E1),
                iconColor: const Color(0xFF475569),
                valueColor: const Color(0xFF475569),
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSectionSelector(),
        ],
      ),
    );
  }

  Widget _buildTdsCard() {
    final file = tdsUploadFile;
    final uploaded = file != null;
    final mappingStatus = file?.mappingStatus ?? UploadMappingStatus.notMapped;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: _panelDecoration(
        borderColor: AppColorScheme.primary.withValues(alpha: 0.26),
        backgroundColor: Colors.white,
        shadows: [
          BoxShadow(
            color: AppColorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColorScheme.infoSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  color: AppColorScheme.info,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '26Q Master File',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                  uploaded
                      ? _uploadStatusLabel(
                          mappingStatus,
                          wasAutoConfirmed: file.wasAutoConfirmed,
                          usedSavedProfile: false,
                        )
                      : 'Pending',
                  style: TextStyle(
                    color: _mappingStatusColor(mappingStatus),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This file is mandatory and powers the reconciliation baseline.',
            style: const TextStyle(
              color: AppColorScheme.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (uploaded)
            UploadFileActionCard(
              fileName: file.fileName,
              rowCount: tdsRows.length,
              status: mappingStatus,
              statusLabel: _uploadStatusLabel(
                mappingStatus,
                wasAutoConfirmed: file.wasAutoConfirmed,
                usedSavedProfile: false,
              ),
              is26Q: true,
              isBusy: isLoadingTds,
              onReview: _reviewTds26QMapping,
              onReplace: uploadTds26QFile,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColorScheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColorScheme.infoSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.upload_file_rounded,
                          color: AppColorScheme.info,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No 26Q file uploaded yet',
                              style: TextStyle(
                                color: AppColorScheme.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Upload the statutory 26Q workbook to unlock reconciliation.',
                              style: TextStyle(
                                color: AppColorScheme.textMuted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('upload_26q_button'),
                      onPressed: isLoadingTds ? null : uploadTds26QFile,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: isLoadingTds
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_rounded),
                      label: Text(isLoadingTds ? 'Uploading...' : 'Upload 26Q'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionSelector() {
    return AppSectionSelector(
      items: _availableSections.map((section) {
        final selected = selectedSections.contains(section);
        final active = _activeSectionCode == section && selected;
        final fileCount = _sectionFileCount(section);
        final rowCount = _sectionRowCount(section);
        final metricText = fileCount == 0
            ? '0 files'
            : '$fileCount file${fileCount == 1 ? '' : 's'}';

        return AppSectionSelectorItem(
          value: section,
          label: compactSectionDisplayLabel(section),
          subtitle: rowCount == 0 ? 'Section rows' : '$rowCount rows',
          metricLabel: metricText,
          isSelected: active,
          isMuted: !selected,
          onTap: selected
              ? () => _setActiveSection(section)
              : () => _toggleSection(section),
          onLongPress: selected ? () => _toggleSection(section) : null,
        );
      }).toList(),
    );
  }

  Widget _buildSectionPanel() {
    final visibleSections = selectedSections.toList()..sort();
    if (visibleSections.isEmpty) {
      return SizedBox(
        width: 380,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: _panelDecoration(
            borderColor: const Color(0xFFE2E8F0),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Text(
            'Select one or more section buckets to start building the source-file workspace.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.5),
          ),
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
    final sectionLabel = sectionDisplayLabel(sectionCode);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(
        borderColor: accent.withValues(alpha: 0.24),
        backgroundColor: Colors.white,
        shadows: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sectionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('add_source_file_button'),
                onPressed: isLoading
                    ? null
                    : () => sectionCode == '194Q'
                          ? _upload194QFile()
                          : _uploadGenericSectionFile(sectionCode),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(isLoading ? 'Uploading...' : 'Add File'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _parserLabel(sectionCode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _sectionDescription(sectionCode),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (files.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: isLoading ? 0.30 : 1,
                          child: Icon(
                            Icons.folder_open_rounded,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        if (isLoading)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sectionCode == '194Q'
                          ? 'Add purchase-register source files for this buyer.'
                          : 'Add ledger source files mapped to $sectionLabel.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: files.map((file) {
                return UploadFileActionCard(
                  fileName: file.fileName,
                  rowCount: file.rowCount,
                  status: file.mappingStatus,
                  statusLabel: _uploadStatusLabel(
                    file.mappingStatus,
                    wasAutoConfirmed: file.wasAutoConfirmed,
                    usedSavedProfile: file.usedSavedProfile,
                  ),
                  isBusy: isLoading,
                  onReview: () => _remapSectionFile(sectionCode, file),
                  onReplace: () async {
                    _removeSectionFile(sectionCode, file);
                    if (sectionCode == '194Q') {
                      await _upload194QFile();
                    } else {
                      await _uploadGenericSectionFile(sectionCode);
                    }
                  },
                  onDelete: () => _removeSectionFile(sectionCode, file),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadWorkspaceLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 900;

        if (useVerticalLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTdsCard(),
              const SizedBox(height: 16),
              _buildSectionPanel(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 390, child: _buildTdsCard()),
            const SizedBox(width: 20),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _buildSectionPanel(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: AppColorScheme.surface,
          border: const Border(top: BorderSide(color: AppColorScheme.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('review_mapping_button'),
              onPressed: _hasWorkspaceContent ? _reviewWorkspaceStatus : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColorScheme.textPrimary,
                disabledForegroundColor: AppColorScheme.textMuted,
                side: BorderSide(
                  color: _hasWorkspaceContent
                      ? AppColorScheme.border
                      : AppColorScheme.divider,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined),
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
                      ? AppColorScheme.success
                      : AppColorScheme.textPrimary,
                  disabledForegroundColor: AppColorScheme.textMuted,
                  side: BorderSide(
                    color: _isSellerMappingConfirmed
                        ? AppColorScheme.success.withValues(alpha: 0.38)
                        : AppColorScheme.border,
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
                            : 'Review Seller Mappings'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('open_reconciliation_button'),
              onPressed: canOpenReconciliation
                  ? openReconciliationScreen
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColorScheme.primary,
                disabledBackgroundColor: AppColorScheme.surfaceMuted,
                disabledForegroundColor: AppColorScheme.textMuted,
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
    return AppPageScaffold(
      bottomNavigationBar: _buildBottomActionBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            _buildBuyerContextCard(),
            const SizedBox(height: 18),
            _buildUploadWorkspaceLayout(),
          ],
        ),
      ),
    );
  }
}
