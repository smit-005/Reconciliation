import 'normalized_ledger_row.dart';

class LedgerUploadFile {
  final String id;
  final String sectionCode;
  final String fileName;
  final List<int> bytes;
  final int rowCount;
  final DateTime uploadedAt;
  final String parserType;
  final List<NormalizedLedgerRow> rows;
  final String mappingStatus;
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
}
