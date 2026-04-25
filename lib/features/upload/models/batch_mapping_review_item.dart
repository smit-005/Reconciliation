import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';

enum BatchMappingReviewItemType { tds26q, sectionFile }

class BatchMappingReviewItem {
  final String itemKey;
  final BatchMappingReviewItemType type;
  final String fileName;
  final String fileType;
  final String sectionCode;
  final UploadMappingStatus mappingStatus;
  final int requiredFieldsCount;
  final int mappedRequiredFieldsCount;
  final int issuesCount;
  final List<String> issues;
  final bool wasManuallyMapped;

  const BatchMappingReviewItem({
    required this.itemKey,
    required this.type,
    required this.fileName,
    required this.fileType,
    required this.sectionCode,
    required this.mappingStatus,
    required this.requiredFieldsCount,
    required this.mappedRequiredFieldsCount,
    required this.issuesCount,
    required this.issues,
    required this.wasManuallyMapped,
  });

  bool get isConfirmed => mappingStatus.isConfirmed;

  bool get hasBlockingIssues => issuesCount > 0;

  bool get canConfirmSafely =>
      !isConfirmed &&
      mappingStatus == UploadMappingStatus.autoMapped &&
      mappedRequiredFieldsCount == requiredFieldsCount &&
      issuesCount == 0;

  String get primaryActionLabel {
    if (isConfirmed) return 'View';
    if (canConfirmSafely) return 'Confirm';
    return 'Review';
  }
}
