class ExcelPreviewHeaderCandidate {
  final int headerRowIndex;
  final bool headersTrusted;
  final double confidenceScore;
  final List<String> unmappedRawHeaders;
  final List<String> columnKeys;
  final Map<String, String> columnLabels;
  final Map<String, String> suggestedMappings;
  final List<Map<String, dynamic>> rawSampleRows;
  final List<Map<String, String>> sampleRows;
  final int detectionScore;
  final List<String> matchedFields;

  const ExcelPreviewHeaderCandidate({
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.confidenceScore,
    required this.unmappedRawHeaders,
    required this.columnKeys,
    required this.columnLabels,
    required this.suggestedMappings,
    required this.rawSampleRows,
    required this.sampleRows,
    this.detectionScore = 0,
    this.matchedFields = const [],
  });
}

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
  final List<Map<String, dynamic>> rawSampleRows;
  final List<Map<String, String>> sampleRows;
  final List<ExcelPreviewHeaderCandidate> headerRowCandidates;

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
    required this.rawSampleRows,
    required this.sampleRows,
    this.headerRowCandidates = const [],
  });

  bool get hasManualHeaderRowOptions => headerRowCandidates.length > 1;

  ExcelPreviewData copyWithHeaderCandidate(
    ExcelPreviewHeaderCandidate candidate,
  ) {
    return ExcelPreviewData(
      fileType: fileType,
      fileName: fileName,
      sheetName: sheetName,
      headerRowIndex: candidate.headerRowIndex,
      headersTrusted: candidate.headersTrusted,
      confidenceScore: candidate.confidenceScore,
      warnings: warnings,
      unmappedRawHeaders: candidate.unmappedRawHeaders,
      columnKeys: candidate.columnKeys,
      columnLabels: candidate.columnLabels,
      suggestedMappings: candidate.suggestedMappings,
      rawSampleRows: candidate.rawSampleRows,
      sampleRows: candidate.sampleRows,
      headerRowCandidates: headerRowCandidates,
    );
  }
}
