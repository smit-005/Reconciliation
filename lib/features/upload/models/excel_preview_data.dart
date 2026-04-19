class ExcelPreviewData {
  final String fileType;
  final String fileName;
  final String sheetName;
  final int headerRowIndex;
  final bool headersTrusted;
  final double confidenceScore;
  final List<String> warnings;
  final List<String> unmappedRawHeaders;
  final List<String> columnKeys;
  final Map<String, String> columnLabels;
  final Map<String, String> suggestedMappings;
  final List<Map<String, String>> sampleRows;

  const ExcelPreviewData({
    required this.fileType,
    required this.fileName,
    required this.sheetName,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.confidenceScore,
    required this.warnings,
    required this.unmappedRawHeaders,
    required this.columnKeys,
    required this.columnLabels,
    required this.suggestedMappings,
    required this.sampleRows,
  });
}
