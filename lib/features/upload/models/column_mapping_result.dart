class ColumnMappingResult {
  final String fileType;
  final String sheetName;
  final int headerRowIndex;
  final bool headersTrusted;
  final bool saveProfile;
  final Map<String, String> rawToCanonicalMapping;
  final Map<String, String> columnMapping;

  const ColumnMappingResult({
    required this.fileType,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.saveProfile,
    required this.rawToCanonicalMapping,
    required this.columnMapping,
  });
}
