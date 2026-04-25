import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_ledger_row.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';

class LedgerUploadFile {
  final String id;
  final String sectionCode;
  final String fileName;
  final List<int> bytes;
  final int rowCount;
  final DateTime uploadedAt;
  final String parserType;
  final List<NormalizedLedgerRow> rows;
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;

  const LedgerUploadFile({
    required this.id,
    required this.sectionCode,
    required this.fileName,
    required this.bytes,
    required this.rowCount,
    required this.uploadedAt,
    required this.parserType,
    required this.rows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.columnMapping,
    this.sheetName,
    this.headerRowIndex,
    this.headersTrusted,
  });

  LedgerUploadFile copyWith({
    String? id,
    String? sectionCode,
    String? fileName,
    List<int>? bytes,
    int? rowCount,
    DateTime? uploadedAt,
    String? parserType,
    List<NormalizedLedgerRow>? rows,
    UploadMappingStatus? mappingStatus,
    bool? wasManuallyMapped,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    Map<String, String>? columnMapping,
  }) {
    return LedgerUploadFile(
      id: id ?? this.id,
      sectionCode: sectionCode ?? this.sectionCode,
      fileName: fileName ?? this.fileName,
      bytes: bytes ?? this.bytes,
      rowCount: rowCount ?? this.rowCount,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      parserType: parserType ?? this.parserType,
      rows: rows ?? this.rows,
      mappingStatus: mappingStatus ?? this.mappingStatus,
      wasManuallyMapped: wasManuallyMapped ?? this.wasManuallyMapped,
      sheetName: sheetName ?? this.sheetName,
      headerRowIndex: headerRowIndex ?? this.headerRowIndex,
      headersTrusted: headersTrusted ?? this.headersTrusted,
      columnMapping: columnMapping ?? this.columnMapping,
    );
  }
}
