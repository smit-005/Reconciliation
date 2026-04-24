import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';

import 'excel_service.dart';
import 'import_mapping_service.dart';

typedef ImportColumnMappingOpener =
    Future<ColumnMappingResult?> Function({
      required List<int> bytes,
      required String fileName,
      required ExcelImportType fileType,
      required ExcelValidationResult validation,
      ImportSessionCache? sessionCache,
      String? preferredSheetName,
    });

class ImportWorkflowResponse<T> {
  final T? data;
  final String? errorMessage;

  const ImportWorkflowResponse._({this.data, this.errorMessage});

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
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;
  final String sampleSignature;
  final ColumnMappingResult? columnMappingResult;

  const PurchaseImportPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.sampleSignature,
    required this.columnMappingResult,
  });
}

class GenericLedgerImportPreparation {
  final List<NormalizedLedgerRow> parsedRows;
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;
  final ColumnMappingResult? columnMappingResult;

  const GenericLedgerImportPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.columnMappingResult,
  });
}

class Tds26QImportPreparation {
  final List<Tds26QRow> parsedRows;
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;
  final ColumnMappingResult? columnMappingResult;

  const Tds26QImportPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.columnMappingResult,
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

class Tds26QRemapPreparation {
  final List<Tds26QRow> parsedRows;
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String sheetName;
  final int headerRowIndex;
  final bool headersTrusted;
  final Map<String, String> columnMapping;

  const Tds26QRemapPreparation({
    required this.parsedRows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
  });
}

class ImportUploadFlowService {
  static const List<String> supportedUploadExtensions = [
    'xlsx',
    'xls',
    'xlsm',
    'csv',
  ];
  static const String supportedUploadFilterLabel =
      'Excel Files (*.xlsx;*.xls;*.xlsm;*.csv)';

  static bool shouldAutoOpenColumnMapping({
    required ExcelValidationResult validation,
    required ExcelImportType fileType,
  }) {
    if (validation.decision == ExcelImportDecision.manualReview) {
      return true;
    }

    if (validation.decision == ExcelImportDecision.invalidMapping) {
      return false;
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
    required ImportColumnMappingOpener openColumnMapping,
    ImportSessionCache? sessionCache,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
  }) async {
    final preflightError = _preflightUploadFormat(fileName);
    if (preflightError != null) {
      return ImportWorkflowResponse.failure(preflightError);
    }

    try {
      final purchasePreparation = await _preparePurchaseUploadInBackground(
        bytes: bytes,
      );

      if (purchasePreparation == null) {
        return ImportWorkflowResponse.failure(
          _readFailureMessage(
            fileName: fileName,
            defaultMessage: 'Could not inspect 194Q source file',
          ),
        );
      }

      final inspection = purchasePreparation.inspection;

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
        final parsedRows = await _parsePurchaseRowsWithProfileInBackground(
          bytes: bytes,
          sheetName: inspection.sheetName,
          headerRowIndex: matchedProfile.headerRowIndex,
          headersTrusted: matchedProfile.headersTrusted,
          columnMapping: matchedProfile.columnMapping,
        );

        return ImportWorkflowResponse.success(
          PurchaseImportPreparation(
            parsedRows: parsedRows,
            mappingStatus: UploadMappingStatus.autoMapped,
            wasManuallyMapped: false,
            sheetName: inspection.sheetName,
            headerRowIndex: matchedProfile.headerRowIndex,
            headersTrusted: matchedProfile.headersTrusted,
            columnMapping: Map<String, String>.from(
              matchedProfile.columnMapping,
            ),
            sampleSignature: signature,
            columnMappingResult: null,
          ),
        );
      }

      final validation = purchasePreparation.validation;
      final shouldOpenColumnMapping =
          forceColumnMapping ||
          shouldAutoOpenColumnMapping(
            validation: validation,
            fileType: ExcelImportType.purchase,
          );

      if (shouldOpenColumnMapping) {
        final columnMappingResult = await openColumnMapping(
          bytes: bytes,
          fileName: fileName,
          fileType: ExcelImportType.purchase,
          validation: ExcelValidationResult.manualReview(
            detectedSheet: validation.detectedSheet ?? inspection.sheetName,
            headerRowIndex:
                validation.headerRowIndex ?? inspection.headerRowIndex,
            detectedType: ExcelImportType.purchase,
            mappedColumns: initialMappedColumns.isNotEmpty
                ? initialMappedColumns
                : validation.mappedColumns,
            warnings: validation.warnings,
            confidenceScore: validation.confidenceScore,
            message: validation.message,
            unmappedRawHeaders: validation.unmappedRawHeaders,
          ),
          sessionCache: sessionCache,
        );

        if (columnMappingResult == null) {
          return const ImportWorkflowResponse.cancelled();
        }

        final parsedRows = await _parsePurchaseRowsWithProfileInBackground(
          bytes: bytes,
          sheetName: columnMappingResult.sheetName,
          headerRowIndex: columnMappingResult.headerRowIndex,
          headersTrusted: columnMappingResult.headersTrusted,
          columnMapping: columnMappingResult.columnMapping,
        );

        return ImportWorkflowResponse.success(
          PurchaseImportPreparation(
            parsedRows: parsedRows,
            mappingStatus: UploadMappingStatus.confirmed,
            wasManuallyMapped: true,
            sheetName: columnMappingResult.sheetName,
            headerRowIndex: columnMappingResult.headerRowIndex,
            headersTrusted: columnMappingResult.headersTrusted,
            columnMapping: Map<String, String>.from(
              columnMappingResult.columnMapping,
            ),
            sampleSignature: signature,
            columnMappingResult: columnMappingResult,
          ),
        );
      }

      if (!validation.isValid) {
        return ImportWorkflowResponse.failure(validation.message);
      }

      final parsedRows =
          purchasePreparation.parsedRows ?? const <PurchaseRow>[];

      return ImportWorkflowResponse.success(
        PurchaseImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: _initialMappingStatusForValidation(validation),
          wasManuallyMapped: false,
          sheetName: inspection.sheetName,
          headerRowIndex: validation.headerRowIndex,
          headersTrusted: null,
          columnMapping: Map<String, String>.from(initialMappedColumns),
          sampleSignature: signature,
          columnMappingResult: null,
        ),
      );
    } catch (_) {
      return ImportWorkflowResponse.failure(
        _readFailureMessage(
          fileName: fileName,
          defaultMessage: 'Could not inspect 194Q source file',
        ),
      );
    }
  }

  static Future<ImportWorkflowResponse<GenericLedgerImportPreparation>>
  prepareGenericLedgerImport({
    required String sectionCode,
    required List<int> bytes,
    required String fileName,
    required ImportColumnMappingOpener openColumnMapping,
    ImportSessionCache? sessionCache,
    Map<String, String> initialMappedColumns = const {},
    bool forceColumnMapping = false,
  }) async {
    final preflightError = _preflightUploadFormat(fileName);
    if (preflightError != null) {
      return ImportWorkflowResponse.failure(preflightError);
    }

    try {
      final validation =
          await ExcelService.validateGenericLedgerFileInBackground(
            sessionCache?.bytes ?? Uint8List.fromList(bytes),
          );
      final shouldOpenColumnMapping =
          forceColumnMapping ||
          shouldAutoOpenColumnMapping(
            validation: validation,
            fileType: ExcelImportType.genericLedger,
          );

      if (shouldOpenColumnMapping) {
        final columnMappingResult = await openColumnMapping(
          bytes: bytes,
          fileName: fileName,
          fileType: ExcelImportType.genericLedger,
          validation: ExcelValidationResult.manualReview(
            detectedSheet: validation.detectedSheet ?? '',
            headerRowIndex: validation.headerRowIndex ?? 0,
            detectedType: ExcelImportType.genericLedger,
            mappedColumns: initialMappedColumns.isNotEmpty
                ? initialMappedColumns
                : validation.mappedColumns,
            warnings: validation.warnings,
            confidenceScore: validation.confidenceScore,
            message: validation.message,
            unmappedRawHeaders: validation.unmappedRawHeaders,
          ),
          sessionCache: sessionCache,
        );

        if (columnMappingResult == null) {
          return const ImportWorkflowResponse.cancelled();
        }

        final parsedRows =
            await ExcelService.parseGenericLedgerRowsWithProfileInBackground(
              sessionCache?.bytes ?? Uint8List.fromList(bytes),
              sheetName: columnMappingResult.sheetName,
              headerRowIndex: columnMappingResult.headerRowIndex,
              headersTrusted: columnMappingResult.headersTrusted,
              columnMapping: columnMappingResult.columnMapping,
              defaultSection: sectionCode,
              sourceFileName: fileName,
            );

        return ImportWorkflowResponse.success(
          GenericLedgerImportPreparation(
            parsedRows: parsedRows,
            mappingStatus: UploadMappingStatus.confirmed,
            wasManuallyMapped: true,
            sheetName: columnMappingResult.sheetName,
            headerRowIndex: columnMappingResult.headerRowIndex,
            headersTrusted: columnMappingResult.headersTrusted,
            columnMapping: Map<String, String>.from(
              columnMappingResult.columnMapping,
            ),
            columnMappingResult: columnMappingResult,
          ),
        );
      }

      if (!validation.isValid) {
        return ImportWorkflowResponse.failure(validation.message);
      }

      final parsedRows = await ExcelService.parseGenericLedgerRowsInBackground(
        sessionCache?.bytes ?? Uint8List.fromList(bytes),
        defaultSection: sectionCode,
        sourceFileName: fileName,
      );

      return ImportWorkflowResponse.success(
        GenericLedgerImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: _initialMappingStatusForValidation(validation),
          wasManuallyMapped: false,
          sheetName: validation.detectedSheet,
          headerRowIndex: validation.headerRowIndex,
          headersTrusted: null,
          columnMapping: Map<String, String>.from(initialMappedColumns),
          columnMappingResult: null,
        ),
      );
    } catch (_) {
      return ImportWorkflowResponse.failure(
        _readFailureMessage(
          fileName: fileName,
          defaultMessage: 'Could not read ledger workbook',
        ),
      );
    }
  }

  static Future<ExcelValidationResult> validateTds26QImport(Uint8List bytes) {
    return ExcelService.validateTds26QFileInBackground(bytes);
  }

  static Future<ImportWorkflowResponse<Tds26QImportPreparation>>
  prepareTds26QImport({
    required List<int> bytes,
    required String fileName,
    required ExcelValidationResult validation,
    required ImportColumnMappingOpener openColumnMapping,
    ImportSessionCache? sessionCache,
    String? preferredSheetName,
  }) async {
    final preflightError = _preflightUploadFormat(fileName);
    if (preflightError != null) {
      return ImportWorkflowResponse.failure(preflightError);
    }

    try {
      final effectiveValidation = preferredSheetName == null
          ? validation
          : await ExcelService.validateTds26QFileInBackground(
              sessionCache?.bytes ?? Uint8List.fromList(bytes),
              preferredSheetName: preferredSheetName,
            );

      if (shouldAutoOpenColumnMapping(
        validation: effectiveValidation,
        fileType: ExcelImportType.tds26q,
      )) {
        final selectedValidation = preferredSheetName == null
            ? effectiveValidation
            : ExcelValidationResult.manualReview(
                detectedSheet: preferredSheetName,
                headerRowIndex: effectiveValidation.headerRowIndex ?? 0,
                detectedType: ExcelImportType.tds26q,
                mappedColumns: effectiveValidation.mappedColumns,
                warnings: effectiveValidation.warnings,
                confidenceScore: effectiveValidation.confidenceScore,
                message: effectiveValidation.message,
                unmappedRawHeaders: effectiveValidation.unmappedRawHeaders,
              );

        final columnMappingResult = await openColumnMapping(
          bytes: bytes,
          fileName: fileName,
          fileType: ExcelImportType.tds26q,
          validation: selectedValidation,
          sessionCache: sessionCache,
          preferredSheetName: preferredSheetName,
        );

        if (columnMappingResult == null) {
          return const ImportWorkflowResponse.cancelled();
        }

        final parsedRows = await _parseTdsRowsWithProfileInBackground(
          bytes: bytes,
          sheetName: columnMappingResult.sheetName,
          headerRowIndex: columnMappingResult.headerRowIndex,
          headersTrusted: columnMappingResult.headersTrusted,
          columnMapping: columnMappingResult.columnMapping,
        );

        return ImportWorkflowResponse.success(
          Tds26QImportPreparation(
            parsedRows: parsedRows,
            mappingStatus: UploadMappingStatus.confirmed,
            wasManuallyMapped: true,
            sheetName: columnMappingResult.sheetName,
            headerRowIndex: columnMappingResult.headerRowIndex,
            headersTrusted: columnMappingResult.headersTrusted,
            columnMapping: Map<String, String>.from(
              columnMappingResult.columnMapping,
            ),
            columnMappingResult: columnMappingResult,
          ),
        );
      }

      if (!effectiveValidation.isValid) {
        return ImportWorkflowResponse.failure(effectiveValidation.message);
      }

      final parsedRows = await ExcelService.parseTds26QRowsInBackground(
        sessionCache?.bytes ?? Uint8List.fromList(bytes),
        sheetName: preferredSheetName ?? effectiveValidation.detectedSheet,
      );

      return ImportWorkflowResponse.success(
        Tds26QImportPreparation(
          parsedRows: parsedRows,
          mappingStatus: _initialMappingStatusForValidation(
            effectiveValidation,
          ),
          wasManuallyMapped: false,
          sheetName: preferredSheetName ?? effectiveValidation.detectedSheet,
          headerRowIndex: effectiveValidation.headerRowIndex,
          headersTrusted: null,
          columnMapping: Map<String, String>.from(
            effectiveValidation.mappedColumns,
          ),
          columnMappingResult: null,
        ),
      );
    } catch (_) {
      return ImportWorkflowResponse.failure(
        _readFailureMessage(
          fileName: fileName,
          defaultMessage: 'Could not read 26Q workbook',
        ),
      );
    }
  }

  static Future<ImportWorkflowResponse<SectionFileRemapPreparation>>
  prepareSectionFileRemap({
    required LedgerUploadFile file,
    required ColumnMappingResult columnMappingResult,
  }) async {
    if (file.sectionCode == '194Q') {
      final inspection = await _inspectPurchaseFileInBackground(
        bytes: file.bytes,
        preferredSheetName: columnMappingResult.sheetName,
      );

      final parsedRows = await _parsePurchaseRowsWithProfileInBackground(
        bytes: file.bytes,
        sheetName: columnMappingResult.sheetName,
        headerRowIndex: columnMappingResult.headerRowIndex,
        headersTrusted: columnMappingResult.headersTrusted,
        columnMapping: columnMappingResult.columnMapping,
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
            mappingStatus: UploadMappingStatus.confirmed,
            wasManuallyMapped: true,
            sheetName: columnMappingResult.sheetName,
            headerRowIndex: columnMappingResult.headerRowIndex,
            headersTrusted: columnMappingResult.headersTrusted,
            columnMapping: Map<String, String>.from(
              columnMappingResult.columnMapping,
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

    final parsedRows =
        await ExcelService.parseGenericLedgerRowsWithProfileInBackground(
          Uint8List.fromList(file.bytes),
          sheetName: columnMappingResult.sheetName,
          headerRowIndex: columnMappingResult.headerRowIndex,
          headersTrusted: columnMappingResult.headersTrusted,
          columnMapping: columnMappingResult.columnMapping,
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
          mappingStatus: UploadMappingStatus.confirmed,
          wasManuallyMapped: true,
          sheetName: columnMappingResult.sheetName,
          headerRowIndex: columnMappingResult.headerRowIndex,
          headersTrusted: columnMappingResult.headersTrusted,
          columnMapping: Map<String, String>.from(
            columnMappingResult.columnMapping,
          ),
        ),
        parsedPurchaseRows: null,
        sampleSignature: null,
      ),
    );
  }

  static Future<ImportWorkflowResponse<Tds26QRemapPreparation>>
  prepareTds26QRemap({
    required List<int> bytes,
    required ColumnMappingResult columnMappingResult,
  }) async {
    try {
      final parsedRows = await _parseTdsRowsWithProfileInBackground(
        bytes: bytes,
        sheetName: columnMappingResult.sheetName,
        headerRowIndex: columnMappingResult.headerRowIndex,
        headersTrusted: columnMappingResult.headersTrusted,
        columnMapping: columnMappingResult.columnMapping,
      );

      return ImportWorkflowResponse.success(
        Tds26QRemapPreparation(
          parsedRows: parsedRows,
          mappingStatus: UploadMappingStatus.confirmed,
          wasManuallyMapped: true,
          sheetName: columnMappingResult.sheetName,
          headerRowIndex: columnMappingResult.headerRowIndex,
          headersTrusted: columnMappingResult.headersTrusted,
          columnMapping: Map<String, String>.from(
            columnMappingResult.columnMapping,
          ),
        ),
      );
    } catch (_) {
      return ImportWorkflowResponse.failure('Could not remap 26Q workbook');
    }
  }
}

UploadMappingStatus _initialMappingStatusForValidation(
  ExcelValidationResult validation,
) {
  if (validation.mappedColumns.isEmpty) {
    return UploadMappingStatus.notMapped;
  }

  if (validation.requiresManualMapping ||
      validation.warnings.isNotEmpty ||
      validation.confidenceScore < 0.75) {
    return UploadMappingStatus.needsReview;
  }

  return UploadMappingStatus.autoMapped;
}

String? _preflightUploadFormat(String fileName) {
  final extension = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  if (extension.isEmpty) {
    return 'Could not determine the file format. Please select an ${ImportUploadFlowService.supportedUploadFilterLabel} file.';
  }

  if (!ImportUploadFlowService.supportedUploadExtensions.contains(extension)) {
    return 'Unsupported file format ".$extension". Please select an ${ImportUploadFlowService.supportedUploadFilterLabel} file.';
  }

  if (extension == 'csv') {
    return 'CSV files can now be selected in the picker, but the current import parser expects workbook sheets for detection and column mapping. Please export the file as .xlsx, .xls, or .xlsm and retry.';
  }

  return null;
}

String _readFailureMessage({
  required String fileName,
  required String defaultMessage,
}) {
  final extension = p.extension(fileName).toLowerCase();
  if (extension == '.xls') {
    return 'The selected .xls file could not be read by the current workbook parser. Please re-save or export it as .xlsx or .xlsm and retry.';
  }
  if (extension == '.xlsm') {
    return 'The selected .xlsm file could not be read. If the workbook contains unsupported macros or workbook features, please save a copy as .xlsx and retry.';
  }
  if (extension == '.csv') {
    return 'CSV files are not yet supported by the current workbook-based import flow. Please export the file as .xlsx, .xls, or .xlsm and retry.';
  }
  return defaultMessage;
}

class _PurchaseUploadPreparation {
  final _PurchaseInspectionResult inspection;
  final ExcelValidationResult validation;
  final List<PurchaseRow>? parsedRows;

  const _PurchaseUploadPreparation({
    required this.inspection,
    required this.validation,
    required this.parsedRows,
  });
}

class _PurchaseInspectionResult {
  final String sheetName;
  final int headerRowIndex;
  final List<String> rawHeaderRow;
  final bool headersTrusted;

  const _PurchaseInspectionResult({
    required this.sheetName,
    required this.headerRowIndex,
    required this.rawHeaderRow,
    required this.headersTrusted,
  });
}

Future<_PurchaseInspectionResult?> _inspectPurchaseFileInBackground({
  required List<int> bytes,
  required String preferredSheetName,
}) async {
  final payload = await compute(
    _computePurchaseInspectionPayload,
    <String, dynamic>{'bytes': bytes, 'preferredSheetName': preferredSheetName},
  );
  if (payload == null) {
    return null;
  }
  return _deserializePurchaseInspectionResult(
    Map<String, dynamic>.from(payload as Map),
  );
}

Future<_PurchaseUploadPreparation?> _preparePurchaseUploadInBackground({
  required List<int> bytes,
}) async {
  final payload = await compute(_computePurchaseUploadPayload, bytes);
  if (payload == null) {
    return null;
  }

  final mapPayload = Map<String, dynamic>.from(payload);
  return _deserializePurchaseUploadPreparation(mapPayload);
}

Future<List<PurchaseRow>> _parsePurchaseRowsWithProfileInBackground({
  required List<int> bytes,
  required String sheetName,
  required int headerRowIndex,
  required bool headersTrusted,
  required Map<String, String> columnMapping,
}) async {
  final response =
      await compute(_computePurchaseProfileParsePayload, <String, dynamic>{
        'bytes': bytes,
        'sheetName': sheetName,
        'headerRowIndex': headerRowIndex,
        'headersTrusted': headersTrusted,
        'columnMapping': columnMapping,
      });

  return _deserializePurchaseRows(response);
}

Future<List<Tds26QRow>> _parseTdsRowsWithProfileInBackground({
  required List<int> bytes,
  required String sheetName,
  required int headerRowIndex,
  required bool headersTrusted,
  required Map<String, String> columnMapping,
}) async {
  final response =
      await compute(_computeTdsProfileParsePayload, <String, dynamic>{
        'bytes': bytes,
        'sheetName': sheetName,
        'headerRowIndex': headerRowIndex,
        'headersTrusted': headersTrusted,
        'columnMapping': columnMapping,
      });

  return _deserializeTdsRows(response);
}

Map<String, dynamic>? _computePurchaseUploadPayload(List<int> bytes) {
  final preparation = ExcelService.preparePurchaseUploadData(bytes);
  if (preparation == null) {
    return null;
  }

  return {
    'inspection': _serializePurchaseInspectionResult((
      sheetName: preparation.sheetName,
      headerRowIndex: preparation.headerRowIndex,
      rawHeaderRow: preparation.rawHeaderRow,
      headersTrusted: preparation.headersTrusted,
    )),
    'validation': _serializeExcelValidationResult(preparation.validation),
    'parsedRows': preparation.parsedRows == null
        ? null
        : _serializePurchaseRows(preparation.parsedRows!),
  };
}

Map<String, dynamic>? _computePurchaseInspectionPayload(
  Map<String, dynamic> payload,
) {
  final inspection = ExcelService.inspectExcelFile(
    List<int>.from(payload['bytes'] as List),
    forcedType: ExcelImportType.purchase,
    preferredSheetName: payload['preferredSheetName'] as String?,
  );
  if (inspection == null) {
    return null;
  }

  return _serializePurchaseInspectionResult((
    sheetName: inspection.sheetName,
    headerRowIndex: inspection.headerRowIndex,
    rawHeaderRow: inspection.rawHeaderRow,
    headersTrusted: inspection.headersTrusted,
  ));
}

Map<String, dynamic> _serializePurchaseInspectionResult(
  ({
    String sheetName,
    int headerRowIndex,
    List<dynamic> rawHeaderRow,
    bool headersTrusted,
  })
  inspection,
) {
  return {
    'sheetName': inspection.sheetName,
    'headerRowIndex': inspection.headerRowIndex,
    'rawHeaderRow': inspection.rawHeaderRow
        .map((cell) => cell?.toString() ?? '')
        .toList(),
    'headersTrusted': inspection.headersTrusted,
  };
}

_PurchaseInspectionResult _deserializePurchaseInspectionResult(
  Map<String, dynamic> payload,
) {
  return _PurchaseInspectionResult(
    sheetName: payload['sheetName'] as String? ?? '',
    headerRowIndex: payload['headerRowIndex'] as int? ?? 0,
    rawHeaderRow: List<String>.from(
      payload['rawHeaderRow'] as List? ?? const [],
    ),
    headersTrusted: payload['headersTrusted'] as bool? ?? false,
  );
}

_PurchaseUploadPreparation _deserializePurchaseUploadPreparation(
  Map<String, dynamic> payload,
) {
  return _PurchaseUploadPreparation(
    inspection: _deserializePurchaseInspectionResult(
      Map<String, dynamic>.from(payload['inspection'] as Map),
    ),
    validation: _deserializeExcelValidationResult(
      Map<String, dynamic>.from(payload['validation'] as Map),
    ),
    parsedRows: payload['parsedRows'] == null
        ? null
        : _deserializePurchaseRows(payload['parsedRows'] as List),
  );
}

List<Map<String, dynamic>> _computePurchaseProfileParsePayload(
  Map<String, dynamic> payload,
) {
  final bytes = List<int>.from(payload['bytes'] as List);
  final sheetName = payload['sheetName'] as String;
  final headerRowIndex = payload['headerRowIndex'] as int;
  final headersTrusted = payload['headersTrusted'] as bool;
  final columnMapping = Map<String, String>.from(
    payload['columnMapping'] as Map,
  );

  return _serializePurchaseRows(
    ExcelService.parsePurchaseRowsWithProfile(
      bytes,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
    ),
  );
}

List<Map<String, dynamic>> _computeTdsProfileParsePayload(
  Map<String, dynamic> payload,
) {
  final bytes = List<int>.from(payload['bytes'] as List);
  final sheetName = payload['sheetName'] as String;
  final headerRowIndex = payload['headerRowIndex'] as int;
  final headersTrusted = payload['headersTrusted'] as bool;
  final columnMapping = Map<String, String>.from(
    payload['columnMapping'] as Map,
  );

  return _serializeTdsRows(
    ExcelService.parseTds26QRowsWithProfile(
      bytes,
      sheetName: sheetName,
      headerRowIndex: headerRowIndex,
      headersTrusted: headersTrusted,
      columnMapping: columnMapping,
    ),
  );
}

Map<String, dynamic> _serializeExcelValidationResult(
  ExcelValidationResult validation,
) {
  return {
    'isValid': validation.isValid,
    'message': validation.message,
    'detectedSheet': validation.detectedSheet,
    'headerRowIndex': validation.headerRowIndex,
    'detectedType': validation.detectedType?.name,
    'mappedColumns': validation.mappedColumns,
    'warnings': validation.warnings,
    'confidenceScore': validation.confidenceScore,
    'requiresManualMapping': validation.requiresManualMapping,
    'requiresUserSelection': validation.requiresUserSelection,
    'candidateSheets': validation.candidateSheets,
    'unmappedRawHeaders': validation.unmappedRawHeaders,
    'decision': validation.decision.name,
  };
}

ExcelValidationResult _deserializeExcelValidationResult(
  Map<String, dynamic> payload,
) {
  final detectedTypeName = payload['detectedType'] as String?;
  final decisionName = payload['decision'] as String? ?? 'invalidMapping';

  return ExcelValidationResult(
    isValid: payload['isValid'] as bool? ?? false,
    message: payload['message'] as String? ?? '',
    detectedSheet: payload['detectedSheet'] as String?,
    headerRowIndex: payload['headerRowIndex'] as int?,
    detectedType: detectedTypeName == null
        ? null
        : ExcelImportType.values.firstWhere(
            (value) => value.name == detectedTypeName,
          ),
    mappedColumns: Map<String, String>.from(
      payload['mappedColumns'] as Map? ?? const {},
    ),
    warnings: List<String>.from(payload['warnings'] as List? ?? const []),
    confidenceScore: (payload['confidenceScore'] as num?)?.toDouble() ?? 0.0,
    requiresManualMapping: payload['requiresManualMapping'] as bool? ?? false,
    requiresUserSelection: payload['requiresUserSelection'] as bool? ?? false,
    candidateSheets: List<String>.from(
      payload['candidateSheets'] as List? ?? const [],
    ),
    unmappedRawHeaders: List<String>.from(
      payload['unmappedRawHeaders'] as List? ?? const [],
    ),
    decision: ExcelImportDecision.values.firstWhere(
      (value) => value.name == decisionName,
      orElse: () => ExcelImportDecision.invalidMapping,
    ),
  );
}

List<Map<String, dynamic>> _serializePurchaseRows(List<PurchaseRow> rows) {
  return rows
      .map(
        (row) => <String, dynamic>{
          'date': row.date,
          'month': row.month,
          'billNo': row.billNo,
          'partyName': row.partyName,
          'gstNo': row.gstNo,
          'panNumber': row.panNumber,
          'productName': row.productName,
          'basicAmount': row.basicAmount,
          'billAmount': row.billAmount,
        },
      )
      .toList();
}

List<PurchaseRow> _deserializePurchaseRows(List rows) {
  return rows
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .map(
        (row) => PurchaseRow(
          date: row['date'] as String? ?? '',
          month: row['month'] as String? ?? '',
          billNo: row['billNo'] as String? ?? '',
          partyName: row['partyName'] as String? ?? '',
          gstNo: row['gstNo'] as String? ?? '',
          panNumber: row['panNumber'] as String? ?? '',
          productName: row['productName'] as String? ?? '',
          basicAmount: (row['basicAmount'] as num?)?.toDouble() ?? 0.0,
          billAmount: (row['billAmount'] as num?)?.toDouble() ?? 0.0,
        ),
      )
      .toList();
}

List<Map<String, dynamic>> _serializeTdsRows(List<Tds26QRow> rows) {
  return rows
      .map(
        (row) => <String, dynamic>{
          'month': row.month,
          'financialYear': row.financialYear,
          'deducteeName': row.deducteeName,
          'panNumber': row.panNumber,
          'deductedAmount': row.deductedAmount,
          'tds': row.tds,
          'section': row.section,
        },
      )
      .toList();
}

List<Tds26QRow> _deserializeTdsRows(List rows) {
  return rows
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .map(
        (row) => Tds26QRow(
          month: row['month'] as String? ?? '',
          financialYear: row['financialYear'] as String? ?? '',
          deducteeName: row['deducteeName'] as String? ?? '',
          panNumber: row['panNumber'] as String? ?? '',
          deductedAmount: (row['deductedAmount'] as num?)?.toDouble() ?? 0.0,
          tds: (row['tds'] as num?)?.toDouble() ?? 0.0,
          section: row['section'] as String? ?? '',
        ),
      )
      .toList();
}
