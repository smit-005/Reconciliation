import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/excel_preview_data.dart';
import '../models/import_format_profile.dart';
import '../models/ledger_upload_file.dart';
import '../models/manual_mapping_result.dart';
import '../models/normalized_ledger_row.dart';
import '../models/normalized_transaction_row.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import '../services/excel_service.dart';
import '../services/import_mapping_service.dart';
import '../services/import_profile_service.dart';
import 'manual_mapping_screen.dart';
import 'reconciliation_screen.dart';

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

  Future<ManualMappingResult?> showManualMappingScreen({
    required ExcelPreviewData previewData,
  }) async {
    if (!mounted) return null;
    return Navigator.push<ManualMappingResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualMappingScreen(previewData: previewData),
      ),
    );
  }

  Future<ManualMappingResult?> _openImportManualMapping({
    required List<int> bytes,
    required String fileName,
    required ExcelImportType fileType,
    required ExcelValidationResult validation,
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
    );

    if (previewData == null) {
      _showUploadSnackBar('Could not build mapping preview for this file');
      return null;
    }

    return showManualMappingScreen(previewData: previewData);
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

  Future<void> _saveProfileFromManualResult({
    required ManualMappingResult result,
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

  bool _shouldAutoOpenManualMapping({
    required ExcelValidationResult validation,
    required ExcelImportType fileType,
  }) {
    if (!validation.isValid &&
        validation.message.toLowerCase().contains('missing required')) {
      return true;
    }

    if (validation.requiresManualMapping) {
      return true;
    }

    if (fileType == ExcelImportType.tds26q &&
        validation.confidenceScore < 0.75) {
      return true;
    }

    if (fileType == ExcelImportType.genericLedger &&
        validation.confidenceScore < 0.75) {
      return true;
    }

    return false;
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
    bool forceManualMapping = false,
  }) async {
    final inspection = ExcelService.inspectExcelFile(
      bytes,
      forcedType: ExcelImportType.purchase,
    );

    if (inspection == null) {
      _showUploadSnackBar('Could not inspect 194Q source file');
      return null;
    }

    final signature = ExcelService.buildSampleSignature(
      inspection.sheetName,
      inspection.rawHeaderRow,
    );

    final matchedProfile = await ExcelService.findMatchingProfile(
      buyerId: widget.selectedBuyerId,
      fileType: ImportMappingService.purchaseFileType,
      sheetName: inspection.sheetName,
      sampleSignature: signature,
    );

    late final List<PurchaseRow> parsedRows;
    String mappingStatus = 'Auto detected';
    bool wasManuallyMapped = false;
    String? mappedSheetName = inspection.sheetName;
    int? mappedHeaderRowIndex = null;
    bool? mappedHeadersTrusted = null;
    Map<String, String> mappedColumns = Map<String, String>.from(initialMappedColumns);

    if (matchedProfile != null) {
      parsedRows = ExcelService.parsePurchaseRowsWithProfile(
        bytes,
        sheetName: inspection.sheetName,
        headerRowIndex: matchedProfile.headerRowIndex,
        headersTrusted: matchedProfile.headersTrusted,
        columnMapping: matchedProfile.columnMapping,
      );
      mappingStatus = 'Saved profile';
      mappedHeaderRowIndex = matchedProfile.headerRowIndex;
      mappedHeadersTrusted = matchedProfile.headersTrusted;
      mappedColumns = Map<String, String>.from(matchedProfile.columnMapping);
    } else {
      final validation = ExcelService.validatePurchaseFile(bytes);
      final shouldOpenManualMapping = forceManualMapping ||
          _shouldAutoOpenManualMapping(
            validation: validation,
            fileType: ExcelImportType.purchase,
          );

      if (shouldOpenManualMapping) {
        final manualResult = await _openImportManualMapping(
          bytes: bytes,
          fileName: pickedFile.name,
          fileType: ExcelImportType.purchase,
          validation: ExcelValidationResult.valid(
            detectedSheet: validation.detectedSheet ?? inspection.sheetName,
            headerRowIndex:
                validation.headerRowIndex ?? inspection.headerRowIndex,
            detectedType: ExcelImportType.purchase,
            mappedColumns: initialMappedColumns.isNotEmpty
                ? initialMappedColumns
                : validation.mappedColumns,
            warnings: validation.warnings,
            confidenceScore: validation.confidenceScore,
            requiresManualMapping: true,
          ),
        );
        if (manualResult == null) {
          return null;
        }

        await _saveProfileFromManualResult(
          result: manualResult,
          sampleSignature: signature,
        );
        parsedRows = ExcelService.parsePurchaseRowsWithProfile(
          bytes,
          sheetName: manualResult.sheetName,
          headerRowIndex: manualResult.headerRowIndex,
          headersTrusted: manualResult.headersTrusted,
          columnMapping: manualResult.columnMapping,
        );
        mappingStatus = 'Manual mapping';
        wasManuallyMapped = true;
        mappedSheetName = manualResult.sheetName;
        mappedHeaderRowIndex = manualResult.headerRowIndex;
        mappedHeadersTrusted = manualResult.headersTrusted;
        mappedColumns = Map<String, String>.from(manualResult.columnMapping);
      } else {
        if (!validation.isValid) {
          _showUploadSnackBar(validation.message);
          return null;
        }
        parsedRows = ExcelService.parsePurchaseRows(bytes);
        mappingStatus = 'Auto detected';
        mappedHeaderRowIndex = validation.headerRowIndex;
      }
    }

    final fileId =
        existingFileId ?? '194Q_${DateTime.now().microsecondsSinceEpoch}_${pickedFile.name}';
    final normalizedRows = parsedRows
        .map(
          (row) => NormalizedLedgerRow.fromPurchaseRow(
            row,
            sourceFileName: pickedFile.name,
          ),
        )
        .toList();

    purchaseRowsByFileId[fileId] = parsedRows;

    return LedgerUploadFile(
      id: fileId,
      sectionCode: '194Q',
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: parsedRows.length,
      uploadedAt: DateTime.now(),
      parserType: 'purchase',
      rows: normalizedRows,
      mappingStatus: mappingStatus,
      wasManuallyMapped: wasManuallyMapped,
      sheetName: mappedSheetName,
      headerRowIndex: mappedHeaderRowIndex,
      headersTrusted: mappedHeadersTrusted,
      columnMapping: mappedColumns,
    );
  }

  Future<LedgerUploadFile?> _buildGenericLedgerUploadFile({
    required String sectionCode,
    required PlatformFile pickedFile,
    required List<int> bytes,
    String? existingFileId,
    Map<String, String> initialMappedColumns = const {},
    bool forceManualMapping = false,
  }) async {
    final validation = ExcelService.validateGenericLedgerFile(bytes);
    late final List<NormalizedLedgerRow> parsedRows;
    String mappingStatus = 'Auto detected';
    bool wasManuallyMapped = false;
    String? mappedSheetName;
    int? mappedHeaderRowIndex;
    bool? mappedHeadersTrusted;
    Map<String, String> mappedColumns = Map<String, String>.from(initialMappedColumns);

    if (forceManualMapping ||
        _shouldAutoOpenManualMapping(
          validation: validation,
          fileType: ExcelImportType.genericLedger,
        )) {
      final manualResult = await _openImportManualMapping(
        bytes: bytes,
        fileName: pickedFile.name,
        fileType: ExcelImportType.genericLedger,
        validation: ExcelValidationResult.valid(
          detectedSheet: validation.detectedSheet ?? '',
          headerRowIndex: validation.headerRowIndex ?? 0,
          detectedType: ExcelImportType.genericLedger,
          mappedColumns: initialMappedColumns.isNotEmpty
              ? initialMappedColumns
              : validation.mappedColumns,
          warnings: validation.warnings,
          confidenceScore: validation.confidenceScore,
          requiresManualMapping: true,
        ),
      );
      if (manualResult == null) {
        return null;
      }

      parsedRows = ExcelService.parseGenericLedgerRowsWithProfile(
        bytes,
        sheetName: manualResult.sheetName,
        headerRowIndex: manualResult.headerRowIndex,
        headersTrusted: manualResult.headersTrusted,
        columnMapping: manualResult.columnMapping,
        defaultSection: sectionCode,
        sourceFileName: pickedFile.name,
      );
      mappingStatus = 'Manual mapping';
      wasManuallyMapped = true;
      mappedSheetName = manualResult.sheetName;
      mappedHeaderRowIndex = manualResult.headerRowIndex;
      mappedHeadersTrusted = manualResult.headersTrusted;
      mappedColumns = Map<String, String>.from(manualResult.columnMapping);
    } else {
      if (!validation.isValid) {
        _showUploadSnackBar(validation.message);
        return null;
      }

      parsedRows = ExcelService.parseGenericLedgerRows(
        bytes,
        defaultSection: sectionCode,
        sourceFileName: pickedFile.name,
      );
      mappingStatus = 'Auto detected';
      mappedSheetName = validation.detectedSheet;
      mappedHeaderRowIndex = validation.headerRowIndex;
    }

    return LedgerUploadFile(
      id: existingFileId ??
          '${sectionCode}_${DateTime.now().microsecondsSinceEpoch}_${pickedFile.name}',
      sectionCode: sectionCode,
      fileName: pickedFile.name,
      bytes: bytes,
      rowCount: parsedRows.length,
      uploadedAt: DateTime.now(),
      parserType: 'genericLedger',
      rows: parsedRows,
      mappingStatus: mappingStatus,
      wasManuallyMapped: wasManuallyMapped,
      sheetName: mappedSheetName,
      headerRowIndex: mappedHeaderRowIndex,
      headersTrusted: mappedHeadersTrusted,
      columnMapping: mappedColumns,
    );
  }

  Future<void> _remapSectionFile(String sectionCode, LedgerUploadFile file) async {
    _setSectionLoading(sectionCode, true);
    try {
      final pickedFile = PlatformFile(
        name: file.fileName,
        size: file.bytes.length,
        bytes: Uint8List.fromList(file.bytes),
      );

      final updatedFile = sectionCode == '194Q'
          ? await _buildPurchaseUploadFile(
              pickedFile: pickedFile,
              bytes: file.bytes,
              existingFileId: file.id,
              initialMappedColumns: file.columnMapping,
              forceManualMapping: true,
            )
          : await _buildGenericLedgerUploadFile(
              sectionCode: sectionCode,
              pickedFile: pickedFile,
              bytes: file.bytes,
              existingFileId: file.id,
              initialMappedColumns: file.columnMapping,
              forceManualMapping: true,
            );

      if (updatedFile == null) {
        _setSectionLoading(sectionCode, false);
        return;
      }

      setState(() {
        sectionFiles[sectionCode] = sectionFiles[sectionCode]!
            .map((item) => item.id == file.id ? updatedFile : item)
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

      final validation = ExcelService.validateTds26QFile(bytes);
      String? preferredSheetName;

      if (validation.requiresUserSelection) {
        setState(() => isLoadingTds = false);
        preferredSheetName = await _show26QSheetSelectionDialog(
          validation.candidateSheets.isNotEmpty
              ? validation.candidateSheets
              : ExcelService.list26QSelectableSheets(bytes),
        );
        if (preferredSheetName == null || preferredSheetName.trim().isEmpty) {
          return;
        }
      }

      late final List<Tds26QRow> parsedRows;

      if (_shouldAutoOpenManualMapping(
        validation: validation,
        fileType: ExcelImportType.tds26q,
      )) {
        final selectedValidation = preferredSheetName == null
            ? validation
            : ExcelValidationResult.valid(
                detectedSheet: preferredSheetName,
                headerRowIndex: 0,
                detectedType: ExcelImportType.tds26q,
                mappedColumns: validation.mappedColumns,
                warnings: validation.warnings,
                confidenceScore: validation.confidenceScore,
                requiresManualMapping: true,
              );
        setState(() => isLoadingTds = false);
        final manualResult = await _openImportManualMapping(
          bytes: bytes,
          fileName: pickedFile.name,
          fileType: ExcelImportType.tds26q,
          validation: selectedValidation,
          preferredSheetName: preferredSheetName,
        );
        if (manualResult == null) {
          return;
        }

        setState(() => isLoadingTds = true);
        parsedRows = ExcelService.parseTds26QRowsWithProfile(
          bytes,
          sheetName: manualResult.sheetName,
          headerRowIndex: manualResult.headerRowIndex,
          headersTrusted: manualResult.headersTrusted,
          columnMapping: manualResult.columnMapping,
        );
      } else {
        if (!validation.isValid) {
          setState(() => isLoadingTds = false);
          _showUploadSnackBar(validation.message);
          return;
        }
        parsedRows = ExcelService.parseTds26QRows(bytes);
      }

      setState(() {
        tdsFileName = pickedFile.name;
        tdsFileBytes = bytes;
        tdsRows = parsedRows;
        normalizedTdsRows = parsedRows
            .map(NormalizedTransactionRow.fromTds26QRow)
            .toList();
        isLoadingTds = false;
      });

      _showUploadSnackBar('26Q uploaded: ${parsedRows.length} rows');
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
      } else {
        selectedSections.add(sectionCode);
      }
    });
  }

  int get _totalSectionFiles =>
      sectionFiles.values.fold<int>(0, (sum, files) => sum + files.length);

  int get _totalLedgerRows => sectionFiles.values.fold<int>(
        0,
        (sum, files) =>
            sum + files.fold<int>(0, (inner, file) => inner + file.rowCount),
      );

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
      case 'Manual mapping':
        return const Color(0xFFB45309);
      case 'Saved profile':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF166534);
    }
  }

  Color _mappingStatusBackground(LedgerUploadFile file) {
    switch (file.mappingStatus) {
      case 'Manual mapping':
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
              color: Colors.black.withOpacity(0.18),
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

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Multi-Section Upload Workspace',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload one mandatory 26Q file, then add as many section-wise source files as needed. '
            '194Q continues to use the purchase parser; the other sections now flow through a generic ledger intake.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.78),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTdsCard() {
    final uploaded = tdsRows.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(
        borderColor: const Color(0xFF1D4ED8).withOpacity(0.35),
        backgroundColor: const Color(0xFF0B1220),
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tdsFileName ?? 'No 26Q file uploaded yet',
            style: TextStyle(
              color: tdsFileName == null
                  ? const Color(0xFF94A3B8)
                  : Colors.white,
              fontSize: 14,
            ),
          ),
          if (uploaded) ...[
            const SizedBox(height: 8),
            Text(
              '${tdsRows.length} rows parsed',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: isLoadingTds ? null : uploadTds26QFile,
            icon: const Icon(Icons.upload_file),
            label: Text(isLoadingTds ? 'Uploading...' : 'Upload 26Q'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
              final accent = _sectionAccent(section);
              return FilterChip(
                selected: selected,
                label: Text(section),
                onSelected: (_) => _toggleSection(section),
                selectedColor: accent.withOpacity(0.14),
                checkmarkColor: accent,
                backgroundColor: const Color(0xFF111827),
                labelStyle: TextStyle(
                  color: selected ? accent : const Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: selected ? accent : const Color(0xFF334155),
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
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _buildSummaryTile('Buyer', widget.selectedBuyerName),
          _buildSummaryTile('Buyer PAN', widget.selectedBuyerPan),
          _buildSummaryTile('26Q Rows', tdsRows.length.toString()),
          _buildSummaryTile('Section Files', _totalSectionFiles.toString()),
          _buildSummaryTile('Source Rows', _totalLedgerRows.toString()),
          _buildSummaryTile('194Q Rows', purchaseRows.length.toString()),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String sectionCode) {
    final accent = _sectionAccent(sectionCode);
    final files = sectionFiles[sectionCode]!;
    final isLoading = sectionLoading[sectionCode] ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(
        borderColor: accent.withOpacity(0.28),
        backgroundColor: const Color(0xFF0B1220),
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
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
                  color: accent.withOpacity(0.12),
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
              Text(
                _parserLabel(sectionCode),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
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
          const SizedBox(height: 12),
          Text(
            files.isEmpty
                ? 'No files added to this section yet.'
                : '${files.length} file(s) in $sectionCode',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          if (files.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Text(
                sectionCode == '194Q'
                    ? 'Use this bucket for purchase-parser source files.'
                    : 'Use this bucket for generic ledger source files mapped to $sectionCode.',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                ),
              ),
            )
          else
            ...files.map(
              (file) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          const SizedBox(height: 8),
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
                    const SizedBox(width: 8),
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
            ),
        ],
      ),
    );
  }

  Widget _buildReconciliationCard() {
    final ready = tdsRows.isNotEmpty && _buildSourceRowsBySection().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Reconciliation Preview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open reconciliation using the uploaded 26Q file plus all available source rows grouped section-wise. '
            'The reconciliation screen will combine the results and also keep section-level visibility.',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: ready ? openReconciliationScreen : null,
              child: const Text('Open Reconciliation'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSections = selectedSections.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Upload Workspace'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildTdsCard(),
                  const SizedBox(height: 16),
                  _buildSectionSelector(),
                  const SizedBox(height: 16),
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  if (visibleSections.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: _panelDecoration(),
                      child: const Text(
                        'Select one or more section buckets to start building the source-file workspace.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  else
                    ...visibleSections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildSectionCard(section),
                      ),
                    ),
                  _buildReconciliationCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
