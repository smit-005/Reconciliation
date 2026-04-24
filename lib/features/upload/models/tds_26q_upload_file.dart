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
}
