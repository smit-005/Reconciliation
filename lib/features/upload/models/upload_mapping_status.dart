enum UploadMappingStatus { notMapped, autoMapped, needsReview, confirmed }

extension UploadMappingStatusX on UploadMappingStatus {
  String get label {
    switch (this) {
      case UploadMappingStatus.notMapped:
        return 'Not mapped';
      case UploadMappingStatus.autoMapped:
        return 'Auto-mapped';
      case UploadMappingStatus.needsReview:
        return 'Needs review';
      case UploadMappingStatus.confirmed:
        return 'Confirmed';
    }
  }

  bool get isConfirmed => this == UploadMappingStatus.confirmed;

  bool get requiresReview =>
      this == UploadMappingStatus.notMapped ||
      this == UploadMappingStatus.autoMapped ||
      this == UploadMappingStatus.needsReview;
}
