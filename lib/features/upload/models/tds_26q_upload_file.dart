import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';

class Tds26QUploadFile {
  final String fileName;
  final List<int> bytes;
  final int rowCount;
  final DateTime uploadedAt;
  final List<Tds26QRow> rows;
  final UploadMappingStatus mappingStatus;
  final bool wasManuallyMapped;
  final String? sheetName;
  final int? headerRowIndex;
  final bool? headersTrusted;
  final Map<String, String> columnMapping;

  const Tds26QUploadFile({
    required this.fileName,
    required this.bytes,
    required this.rowCount,
    required this.uploadedAt,
    required this.rows,
    required this.mappingStatus,
    required this.wasManuallyMapped,
    required this.columnMapping,
    this.sheetName,
    this.headerRowIndex,
    this.headersTrusted,
  });

  Tds26QUploadFile copyWith({
    String? fileName,
    List<int>? bytes,
    int? rowCount,
    DateTime? uploadedAt,
    List<Tds26QRow>? rows,
    UploadMappingStatus? mappingStatus,
    bool? wasManuallyMapped,
    String? sheetName,
    int? headerRowIndex,
    bool? headersTrusted,
    Map<String, String>? columnMapping,
  }) {
    return Tds26QUploadFile(
      fileName: fileName ?? this.fileName,
      bytes: bytes ?? this.bytes,
      rowCount: rowCount ?? this.rowCount,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      rows: rows ?? this.rows,
      mappingStatus: mappingStatus ?? this.mappingStatus,
      wasManuallyMapped: wasManuallyMapped ?? this.wasManuallyMapped,
      columnMapping: columnMapping ?? this.columnMapping,
      sheetName: sheetName ?? this.sheetName,
      headerRowIndex: headerRowIndex ?? this.headerRowIndex,
      headersTrusted: headersTrusted ?? this.headersTrusted,
    );
  }
}
