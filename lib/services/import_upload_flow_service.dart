import '../models/manual_mapping_result.dart';
import '../models/ledger_upload_file.dart';
import '../models/normalized_ledger_row.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import 'excel_service.dart';
import 'import_mapping_service.dart';

typedef ImportManualMappingOpener =
    Future<ManualMappingResult?> Function({
      required List<int> bytes,
      required String fileName,
      required ExcelImportType fileType,
      required ExcelValidationResult validation,
      String? preferredSheetName,
    });

class ImportWorkflowResponse<T> {
  final T? data;
  final String? errorMessage;

  const ImportWorkflowResponse._({
    this.data,
    this.errorMessage,
  });

  const ImportWorkflowResponse.success(T data)
    : this._(data: data, errorMessage: null);

  const ImportWorkflowResponse.failure(String errorMessage)
    : this._(data: null, errorMessage: errorMessage);

  const ImportWorkflowResponse.cancelled()
    : this._(data: null, errorMessage: null);

  bool get isSuccess => data != null;
  bool get isFailure => errorMessage != null;
  bool get isCancelled => data == null && errorMessage == null;
}

class PurchaseImportPreparation {
  final List<PurchaseRow> parsedRows;
  final String mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;
  final String sampleSignature;
  final ManualMappingResult? manualMappingResult;

  const PurchaseImportPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.sampleSignature,
    required this.manualMappingResult,
  });
}

class GenericLedgerImportPreparation {
  final List<NormalizedLedgerRow> parsedRows;
  final String mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;
  final ManualMappingResult? manualMappingResult;

  const GenericLedgerImportPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.manualMappingResult,
  });
}

class Tds26QImportPreparation {
  final List<Tds26QRow> parsedRows;
  final ManualMappingResult? manualMappingResult;

  const Tds26QImportPreparation({
    required this.parsedRows,
    required this.manualMappingResult,
  });
}

class SectionFileRemapPreparation {
  final LedgerUploadFile updatedFile;
  final List<PurchaseRow>? parsedPurchaseRows;
  final String? sampleSignature;

  const SectionFileRemapPreparation({
    required this.updatedFile,
    required this.parsedPurchaseRows,
    required this.sampleSignature,
  });
}

class ImportUploadFlowService {
  static bool shouldAutoOpenManualMapping({
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

  static Future<ImportWorkflowResponse<PurchaseImportPreparation>>
  preparePurchaseImport({
    required String buyerId,
    required List<int> bytes,
    required String fileName,
    required ImportManualMappingOpener openManualMapping,
    Map<String, String> initialMappedColumns = const {},
    bool forceManualMapping = false,
  }) async {
    final inspection = ExcelService.inspectExcelFile(
      bytes,
      forcedType: ExcelImportType.purchase,
    );

    if (inspection == null) {
      return const ImportWorkflowResponse.failure(
        'Could not inspect 194Q source file',
      );
    }

    final signature = ExcelService.buildSampleSignature(
      inspection.sheetName,
      inspection.rawHeaderRow,
    );

    final matchedProfile = await ExcelService.findMatchingProfile(
      buyerId: buyerId,
      fileType: ImportMappingService.purchaseFileType,
      sheetName: inspection.sheetName,
      sampleSignature: signature,
    );

    if (matchedProfile != null) {
      final parsedRows = ExcelService.parsePurchaseRowsWithProfile(
        bytes,
        sheetName: inspection.sheetName,
        headerRowIndex: matchedProfile.headerRowIndex,
        headersTrusted: matchedProfile.headersTrusted,
        columnMapping: matchedProfile.columnMapping,
      );

      return ImportWorkflowResponse.success(
        PurchaseImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: 'Saved profile',
          wasManuallyMapped: false,
          sheetName: inspection.sheetName,
          headerRowIndex: matchedProfile.headerRowIndex,
          headersTrusted: matchedProfile.headersTrusted,
          columnMapping: Map<String, String>.from(matchedProfile.columnMapping),
          sampleSignature: signature,
          manualMappingResult: null,
        ),
      );
    }

    final validation = ExcelService.validatePurchaseFile(bytes);
    final shouldOpenManualMapping =
        forceManualMapping ||
        shouldAutoOpenManualMapping(
          validation: validation,
          fileType: ExcelImportType.purchase,
        );

    if (shouldOpenManualMapping) {
      final manualResult = await openManualMapping(
        bytes: bytes,
        fileName: fileName,
        fileType: ExcelImportType.purchase,
        validation: ExcelValidationResult.valid(
          detectedSheet: validation.detectedSheet ?? inspection.sheetName,
          headerRowIndex: validation.headerRowIndex ?? inspection.headerRowIndex,
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
        return const ImportWorkflowResponse.cancelled();
      }

      final parsedRows = ExcelService.parsePurchaseRowsWithProfile(
        bytes,
        sheetName: manualResult.sheetName,
        headerRowIndex: manualResult.headerRowIndex,
        headersTrusted: manualResult.headersTrusted,
        columnMapping: manualResult.columnMapping,
      );

      return ImportWorkflowResponse.success(
        PurchaseImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: 'Manual mapping',
          wasManuallyMapped: true,
          sheetName: manualResult.sheetName,
          headerRowIndex: manualResult.headerRowIndex,
          headersTrusted: manualResult.headersTrusted,
          columnMapping: Map<String, String>.from(manualResult.columnMapping),
          sampleSignature: signature,
          manualMappingResult: manualResult,
        ),
      );
    }

    if (!validation.isValid) {
      return ImportWorkflowResponse.failure(validation.message);
    }

    final parsedRows = ExcelService.parsePurchaseRows(bytes);

    return ImportWorkflowResponse.success(
      PurchaseImportPreparation(
        parsedRows: parsedRows,
        mappingStatus: 'Auto detected',
        wasManuallyMapped: false,
        sheetName: inspection.sheetName,
        headerRowIndex: validation.headerRowIndex,
        headersTrusted: null,
        columnMapping: Map<String, String>.from(initialMappedColumns),
        sampleSignature: signature,
        manualMappingResult: null,
      ),
    );
  }

  static Future<ImportWorkflowResponse<GenericLedgerImportPreparation>>
  prepareGenericLedgerImport({
    required String sectionCode,
    required List<int> bytes,
    required String fileName,
    required ImportManualMappingOpener openManualMapping,
    Map<String, String> initialMappedColumns = const {},
    bool forceManualMapping = false,
  }) async {
    final validation = ExcelService.validateGenericLedgerFile(bytes);
    final shouldOpenManualMapping =
        forceManualMapping ||
        shouldAutoOpenManualMapping(
          validation: validation,
          fileType: ExcelImportType.genericLedger,
        );

    if (shouldOpenManualMapping) {
      final manualResult = await openManualMapping(
        bytes: bytes,
        fileName: fileName,
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
        return const ImportWorkflowResponse.cancelled();
      }

      final parsedRows = ExcelService.parseGenericLedgerRowsWithProfile(
        bytes,
        sheetName: manualResult.sheetName,
        headerRowIndex: manualResult.headerRowIndex,
        headersTrusted: manualResult.headersTrusted,
        columnMapping: manualResult.columnMapping,
        defaultSection: sectionCode,
        sourceFileName: fileName,
      );

      return ImportWorkflowResponse.success(
        GenericLedgerImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: 'Manual mapping',
          wasManuallyMapped: true,
          sheetName: manualResult.sheetName,
          headerRowIndex: manualResult.headerRowIndex,
          headersTrusted: manualResult.headersTrusted,
          columnMapping: Map<String, String>.from(manualResult.columnMapping),
          manualMappingResult: manualResult,
        ),
      );
    }

    if (!validation.isValid) {
      return ImportWorkflowResponse.failure(validation.message);
    }

    final parsedRows = ExcelService.parseGenericLedgerRows(
      bytes,
      defaultSection: sectionCode,
      sourceFileName: fileName,
    );

    return ImportWorkflowResponse.success(
      GenericLedgerImportPreparation(
        parsedRows: parsedRows,
        mappingStatus: 'Auto detected',
        wasManuallyMapped: false,
        sheetName: validation.detectedSheet,
        headerRowIndex: validation.headerRowIndex,
        headersTrusted: null,
        columnMapping: Map<String, String>.from(initialMappedColumns),
        manualMappingResult: null,
      ),
    );
  }

  static ExcelValidationResult validateTds26QImport(List<int> bytes) {
    return ExcelService.validateTds26QFile(bytes);
  }

  static Future<ImportWorkflowResponse<Tds26QImportPreparation>>
  prepareTds26QImport({
    required List<int> bytes,
    required String fileName,
    required ExcelValidationResult validation,
    required ImportManualMappingOpener openManualMapping,
    String? preferredSheetName,
  }) async {
    if (shouldAutoOpenManualMapping(
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

      final manualResult = await openManualMapping(
        bytes: bytes,
        fileName: fileName,
        fileType: ExcelImportType.tds26q,
        validation: selectedValidation,
        preferredSheetName: preferredSheetName,
      );

      if (manualResult == null) {
        return const ImportWorkflowResponse.cancelled();
      }

      final parsedRows = ExcelService.parseTds26QRowsWithProfile(
        bytes,
        sheetName: manualResult.sheetName,
        headerRowIndex: manualResult.headerRowIndex,
        headersTrusted: manualResult.headersTrusted,
        columnMapping: manualResult.columnMapping,
      );

      return ImportWorkflowResponse.success(
        Tds26QImportPreparation(
          parsedRows: parsedRows,
          manualMappingResult: manualResult,
        ),
      );
    }

    if (!validation.isValid) {
      return ImportWorkflowResponse.failure(validation.message);
    }

    final parsedRows = ExcelService.parseTds26QRows(bytes);

    return ImportWorkflowResponse.success(
      Tds26QImportPreparation(
        parsedRows: parsedRows,
        manualMappingResult: null,
      ),
    );
  }

  static Future<ImportWorkflowResponse<SectionFileRemapPreparation>>
  prepareSectionFileRemap({
    required LedgerUploadFile file,
    required ManualMappingResult manualMappingResult,
  }) async {
    if (file.sectionCode == '194Q') {
      final inspection = ExcelService.inspectExcelFile(
        file.bytes,
        forcedType: ExcelImportType.purchase,
        preferredSheetName: manualMappingResult.sheetName,
      );

      final parsedRows = ExcelService.parsePurchaseRowsWithProfile(
        file.bytes,
        sheetName: manualMappingResult.sheetName,
        headerRowIndex: manualMappingResult.headerRowIndex,
        headersTrusted: manualMappingResult.headersTrusted,
        columnMapping: manualMappingResult.columnMapping,
      );
      final normalizedRows = parsedRows
          .map(
            (row) => NormalizedLedgerRow.fromPurchaseRow(
              row,
              sourceFileName: file.fileName,
            ),
          )
          .toList();

      return ImportWorkflowResponse.success(
        SectionFileRemapPreparation(
          updatedFile: LedgerUploadFile(
            id: file.id,
            sectionCode: file.sectionCode,
            fileName: file.fileName,
            bytes: file.bytes,
            rowCount: parsedRows.length,
            uploadedAt: DateTime.now(),
            parserType: file.parserType,
            rows: normalizedRows,
            mappingStatus: 'Manual mapping',
            wasManuallyMapped: true,
            sheetName: manualMappingResult.sheetName,
            headerRowIndex: manualMappingResult.headerRowIndex,
            headersTrusted: manualMappingResult.headersTrusted,
            columnMapping: Map<String, String>.from(
              manualMappingResult.columnMapping,
            ),
          ),
          parsedPurchaseRows: parsedRows,
          sampleSignature: inspection == null
              ? null
              : ExcelService.buildSampleSignature(
                  inspection.sheetName,
                  inspection.rawHeaderRow,
                ),
        ),
      );
    }

    final parsedRows = ExcelService.parseGenericLedgerRowsWithProfile(
      file.bytes,
      sheetName: manualMappingResult.sheetName,
      headerRowIndex: manualMappingResult.headerRowIndex,
      headersTrusted: manualMappingResult.headersTrusted,
      columnMapping: manualMappingResult.columnMapping,
      defaultSection: file.sectionCode,
      sourceFileName: file.fileName,
    );

    return ImportWorkflowResponse.success(
      SectionFileRemapPreparation(
        updatedFile: LedgerUploadFile(
          id: file.id,
          sectionCode: file.sectionCode,
          fileName: file.fileName,
          bytes: file.bytes,
          rowCount: parsedRows.length,
          uploadedAt: DateTime.now(),
          parserType: file.parserType,
          rows: parsedRows,
          mappingStatus: 'Manual mapping',
          wasManuallyMapped: true,
          sheetName: manualMappingResult.sheetName,
          headerRowIndex: manualMappingResult.headerRowIndex,
          headersTrusted: manualMappingResult.headersTrusted,
          columnMapping: Map<String, String>.from(
            manualMappingResult.columnMapping,
          ),
        ),
        parsedPurchaseRows: null,
        sampleSignature: null,
      ),
    );
  }
}
