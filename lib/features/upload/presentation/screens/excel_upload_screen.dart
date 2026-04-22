import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/reconciliation_screen.dart';
import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';
import 'package:reconciliation_app/features/upload/models/import_format_profile.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/column_mapping_screen.dart';
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

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  static const List<String> _availableSections = [
    '194Q',
    '194C',
    '194H',
    '194J',
    '194IB',
  ];

  bool isLoadingTds = false;
  String? tdsFileName;
  List<int>? tdsFileBytes;
  String _activeSectionCode = '194Q';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<PlatformFile?> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    return result.files.single;
  }

  void _setSectionLoading(String sectionCode, bool isLoading) {
    setState(() {
      sectionLoading[sectionCode] = isLoading;
    });
  }

  void _rebuildPurchaseState() {
    final allPurchaseRows = purchaseRowsByFileId.values.expand((rows) => rows).toList();
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
      sectionFiles[sectionCode] =
          sectionFiles[sectionCode]!.where((item) => item.id != file.id).toList();
      if (sectionCode == '194Q') {
        purchaseRowsByFileId.remove(file.id);
        _rebuildPurchaseState();
      } else {
        ledgerRowsBySection[sectionCode] =
            sectionFiles[sectionCode]!.expand((item) => item.rows).toList();
      }
    });
  }

  Future<LedgerUploadFile?> _buildPurchaseUploadFile({
    required PlatformFile pickedFile,
    required List<int> bytes,
    String? existingFileId,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
  }) async {
    final response = await ImportUploadFlowService.preparePurchaseImport(
      buyerId: widget.selectedBuyerId,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
    );

    if (response.isFailure) {
      _showUploadSnackBar(response.errorMessage!);
      return null;
    }

    final result = response.data;
    if (result == null) {
      return null;
    }

    if (result.columnMappingResult != null) {
      await _saveProfileFromColumnMappingResult(
        result: result.columnMappingResult!,
        sampleSignature: result.sampleSignature,
      );
    }

    final fileId =
        existingFileId ?? '194Q_${DateTime.now().microsecondsSinceEpoch}_${pickedFile.name}';
    final normalizedRows = result.parsedRows
        .map(
          (row) => NormalizedLedgerRow.fromPurchaseRow(
            row,
            sourceFileName: pickedFile.name,
          ),
        )
        .toList();

    purchaseRowsByFileId[fileId] = result.parsedRows;

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
    final response = await ImportUploadFlowService.prepareGenericLedgerImport(
      sectionCode: sectionCode,
      bytes: bytes,
      fileName: pickedFile.name,
      openColumnMapping: _openImportColumnMapping,
      initialMappedColumns: initialMappedColumns,
      forceColumnMapping: forceColumnMapping,
    );

    if (response.isFailure) {
      _showUploadSnackBar(response.errorMessage!);
      return null;
    }

    final result = response.data;
    if (result == null) {
      return null;
    }

    return LedgerUploadFile(
      id: existingFileId ??
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

  Future<void> _remapSectionFile(String sectionCode, LedgerUploadFile file) async {
    _setSectionLoading(sectionCode, true);
    try {
      final columnMappingResult = await _openStoredFileColumnMapping(file: file);
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
        _showUploadSnackBar('Remap failed for ${file.fileName}: ${response.errorMessage!}');
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
        if (sectionCode == '194Q') {
          _rebuildPurchaseState();
        } else {
          ledgerRowsBySection[sectionCode] =
              sectionFiles[sectionCode]!.expand((item) => item.rows).toList();
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
        sectionFiles['194Q'] = [
          ...sectionFiles['194Q']!,
          uploadFile,
        ];
        _rebuildPurchaseState();
        sectionLoading['194Q'] = false;
      });

      _showUploadSnackBar(
        '194Q source uploaded: ${uploadFile.rowCount} rows from ${pickedFile.name}',
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
        sectionFiles[sectionCode] = [
          ...sectionFiles[sectionCode]!,
          uploadFile,
        ];
        ledgerRowsBySection[sectionCode] =
            sectionFiles[sectionCode]!.expand((item) => item.rows).toList();
        sectionLoading[sectionCode] = false;
      });

      _showUploadSnackBar(
        '$sectionCode source uploaded: ${uploadFile.rowCount} rows from ${pickedFile.name}',
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
              : await ExcelService.list26QSelectableSheetsInBackground(
                  bytes,
                ),
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
        return;
      }

      if (shouldOpenColumnMapping) {
        setState(() => isLoadingTds = true);
      }

      setState(() {
        tdsFileName = pickedFile.name;
        tdsFileBytes = bytes;
        tdsRows = result.parsedRows;
        normalizedTdsRows = result.parsedRows
            .map(NormalizedTransactionRow.fromTds26QRow)
            .toList();
        isLoadingTds = false;
      });

      _showUploadSnackBar('26Q uploaded: ${result.parsedRows.length} rows');
    } catch (e) {
      setState(() => isLoadingTds = false);
      _showUploadSnackBar('26Q upload error: $e');
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
        ),
      ),
    );
  }

  Map<String, List<NormalizedTransactionRow>> _buildSourceRowsBySection() {
    final groupedRows = <String, List<NormalizedTransactionRow>>{};

    for (final section in selectedSections) {
      final ledgerRows = ledgerRowsBySection[section] ?? const <NormalizedLedgerRow>[];
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

  bool get _has26QReady => tdsRows.isNotEmpty;

  bool get canOpenReconciliation => _has26QReady && _buildSourceRowsBySection().isNotEmpty;

  bool get _hasWorkspaceContent => _has26QReady || _totalSectionFiles > 0;

  String get _workspaceStatusLabel {
    if (canOpenReconciliation) return 'Ready';
    if (_hasWorkspaceContent) return 'In Progress';
    return 'Setup Required';
  }

  String get _workspaceStatusDetail {
    if (canOpenReconciliation) {
      return '26Q and source files are ready. Continue to reconciliation.';
    }
    if (!_has26QReady) {
      return 'Upload the mandatory 26Q master file to unlock the workflow.';
    }
    return 'Add at least one source file in a selected section to continue.';
  }

  int _sectionFileCount(String sectionCode) => sectionFiles[sectionCode]?.length ?? 0;

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
      case '194J':
        return 'Generic ledger workspace for professional fee ledgers.';
      case '194IB':
        return 'Generic ledger workspace for rent deduction ledgers.';
      default:
        return 'Generic ledger workspace for the selected section.';
    }
  }

  void _reviewWorkspaceStatus() {
    if (!_hasWorkspaceContent) {
      _showUploadSnackBar(
        'Add a 26Q file or source files to start building the workspace.',
      );
      return;
    }

    _showUploadSnackBar(
      'Workspace status: $_workspaceStatusLabel. $_workspaceStatusDetail',
    );
  }

  Color _sectionAccent(String sectionCode) {
    switch (sectionCode) {
      case '194Q':
        return const Color(0xFF2563EB);
      case '194C':
        return const Color(0xFF0F766E);
      case '194H':
        return const Color(0xFF9333EA);
      case '194J':
        return const Color(0xFFEA580C);
      case '194IB':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF475569);
    }
  }

  String _parserLabel(String sectionCode) {
    return sectionCode == '194Q' ? 'Purchase Parser' : 'Generic Ledger Parser';
  }

  Color _mappingStatusColor(LedgerUploadFile file) {
    switch (file.mappingStatus) {
      case 'Column mapping':
        return const Color(0xFFB45309);
      case 'Saved profile':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF166534);
    }
  }

  Color _mappingStatusBackground(LedgerUploadFile file) {
    switch (file.mappingStatus) {
      case 'Column mapping':
        return const Color(0xFFFEF3C7);
      case 'Saved profile':
        return const Color(0xFFDBEAFE);
      default:
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
      boxShadow: shadows ??
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                onPressed: canOpenReconciliation ? openReconciliationScreen : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: const Color(0xFF1E293B),
                  disabledForegroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
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
    final uploaded = tdsRows.isNotEmpty;

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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: uploaded
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  uploaded ? 'Uploaded' : 'Pending',
                  style: TextStyle(
                    color: uploaded
                        ? const Color(0xFF166534)
                        : const Color(0xFF9A3412),
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
                        uploaded
                            ? (tdsFileName ?? '26Q uploaded')
                            : 'No 26Q file uploaded yet',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        uploaded
                            ? '${tdsRows.length} parsed rows ready for reconciliation'
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
                  icon: Icon(uploaded ? Icons.refresh_rounded : Icons.upload_rounded),
                  label: Text(isLoadingTds ? 'Uploading...' : uploaded ? 'Replace 26Q' : 'Upload 26Q'),
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
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            section,
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: selected ? accent : const Color(0xFF475569),
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
          _buildSummaryTile('Active Buckets', selectedSections.length.toString()),
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

  Widget _buildSectionPanel() {
    final visibleSections = selectedSections.toList()..sort();
    if (visibleSections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _panelDecoration(),
        child: const Text(
          'Select one or more section buckets to start building the source-file workspace.',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            height: 1.5,
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  sectionCode,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
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
                onPressed: isLoading
                    ? null
                    : () => sectionCode == '194Q'
                        ? _upload194QFile()
                        : _uploadGenericSectionFile(sectionCode),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: Text(isLoading ? 'Uploading...' : 'Add File'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                sectionCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                ? 'No files added to this bucket yet.'
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
                      sectionCode == '194Q'
                          ? 'Use this bucket for purchase-parser source files. Add one or more files to stage buyer-side transactions.'
                          : 'Use this bucket for generic ledger source files mapped to $sectionCode. Add files to complete this workspace.',
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
                                        color: _mappingStatusBackground(file),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        file.mappingStatus,
                                        style: TextStyle(
                                          color: _mappingStatusColor(file),
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
                                        borderRadius: BorderRadius.circular(999),
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
                                    : () => _remapSectionFile(sectionCode, file),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF334155)),
                                ),
                                icon: const Icon(Icons.tune, size: 16),
                                label: const Text('Remap'),
                              ),
                              const SizedBox(height: 8),
                              IconButton(
                                onPressed: () => _removeSectionFile(sectionCode, file),
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
          border: const Border(
            top: BorderSide(color: Color(0xFF1E293B)),
          ),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _hasWorkspaceContent ? _reviewWorkspaceStatus : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF64748B),
                side: BorderSide(
                  color: _hasWorkspaceContent
                      ? const Color(0xFF334155)
                      : const Color(0xFF1E293B),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Check Workspace'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: canOpenReconciliation ? openReconciliationScreen : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFF1E293B),
                disabledForegroundColor: const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                canOpenReconciliation
                    ? 'Open Reconciliation'
                    : 'Open Reconciliation',
                style: const TextStyle(fontWeight: FontWeight.w700),
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
                  _buildSectionPanel(),
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
