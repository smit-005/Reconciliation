enum ImportAuditRowType { tds26q, ledgerSource }

enum ImportAuditReason {
  invalidRowSkipped,
  continuationMerged,
  duplicateIgnored,
  suspiciousReviewNote,
  emptyRowIgnored,
}

class ImportAuditRecord {
  final String sourceFileName;
  final String sheetName;
  final int? rowNumber;
  final ImportAuditRowType rowType;
  final String sectionBucket;
  final ImportAuditReason reason;
  final String message;

  const ImportAuditRecord({
    required this.sourceFileName,
    required this.sheetName,
    required this.rowNumber,
    required this.rowType,
    required this.sectionBucket,
    required this.reason,
    required this.message,
  });
}

extension ImportAuditReasonX on ImportAuditReason {
  bool get isSecondary => this == ImportAuditReason.emptyRowIgnored;
}
