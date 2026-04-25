import 'package:reconciliation_app/features/upload/models/batch_mapping_review_item.dart';
import 'package:reconciliation_app/features/upload/models/ledger_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/tds_26q_upload_file.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';

class BatchMappingReviewService {
  static List<BatchMappingReviewItem> buildItems({
    required Tds26QUploadFile? tdsFile,
    required Iterable<LedgerUploadFile> sectionFiles,
  }) {
    final items = <BatchMappingReviewItem>[];

    if (tdsFile != null) {
      items.add(
        _buildItem(
          itemKey: 'tds26q',
          type: BatchMappingReviewItemType.tds26q,
          fileName: tdsFile.fileName,
          fileType: ImportMappingService.tds26qFileType,
          sectionCode: '26Q',
          mappingStatus: tdsFile.mappingStatus,
          columnMapping: tdsFile.columnMapping,
          wasManuallyMapped: tdsFile.wasManuallyMapped,
        ),
      );
    }

    final sortedFiles = sectionFiles.toList()
      ..sort((left, right) {
        final bySection = left.sectionCode.compareTo(right.sectionCode);
        if (bySection != 0) return bySection;
        return left.fileName.compareTo(right.fileName);
      });

    for (final file in sortedFiles) {
      items.add(
        _buildItem(
          itemKey: 'section:${file.id}',
          type: BatchMappingReviewItemType.sectionFile,
          fileName: file.fileName,
          fileType: file.sectionCode == '194Q'
              ? ImportMappingService.purchaseFileType
              : ImportMappingService.genericLedgerFileType,
          sectionCode: file.sectionCode,
          mappingStatus: file.mappingStatus,
          columnMapping: file.columnMapping,
          wasManuallyMapped: file.wasManuallyMapped,
        ),
      );
    }

    return items;
  }

  static BatchMappingReviewItem _buildItem({
    required String itemKey,
    required BatchMappingReviewItemType type,
    required String fileName,
    required String fileType,
    required String sectionCode,
    required UploadMappingStatus mappingStatus,
    required Map<String, String> columnMapping,
    required bool wasManuallyMapped,
  }) {
    final requiredFields = _requiredFieldLabels(fileType);
    final normalizedMapping = _normalizeCanonicalMapping(
      fileType: fileType,
      mapping: columnMapping,
    );
    final mappedRequiredCount = requiredFields.keys
        .where((key) => _isRequiredFieldMapped(fileType, key, normalizedMapping))
        .length;
    final issues = _buildIssues(
      fileType: fileType,
      mappingStatus: mappingStatus,
      mapping: normalizedMapping,
      requiredFields: requiredFields,
    );

    return BatchMappingReviewItem(
      itemKey: itemKey,
      type: type,
      fileName: fileName,
      fileType: fileType,
      sectionCode: sectionCode,
      mappingStatus: mappingStatus,
      requiredFieldsCount: requiredFields.length,
      mappedRequiredFieldsCount: mappedRequiredCount,
      issuesCount: issues.length,
      issues: issues,
      wasManuallyMapped: wasManuallyMapped,
    );
  }

  static Map<String, String> _requiredFieldLabels(String fileType) {
    if (fileType == ImportMappingService.tds26qFileType) {
      return const {
        'date_month': 'Date / Month',
        'party_name': 'Party Name',
        'pan_number': 'PAN Number',
        'amount_paid': 'Amount Paid',
        'tds_amount': 'TDS Amount',
        'section': 'Section',
      };
    }

    if (fileType == ImportMappingService.genericLedgerFileType) {
      return const {
        'date': 'Date',
        'party_name': 'Party Name',
        'amount': 'Amount',
      };
    }

    return const {
      'date_or_eom': 'Bill Date or EOM',
      'party_name': 'Party Name',
      'bill_no': 'Bill No',
      'amount_column': 'Bill Amount or Basic Amount',
    };
  }

  static Map<String, String> _normalizeCanonicalMapping({
    required String fileType,
    required Map<String, String> mapping,
  }) {
    final normalized = Map<String, String>.from(mapping);
    final panColumn = normalized.remove('pan_no');
    if (panColumn != null && panColumn.trim().isNotEmpty) {
      normalized['pan_number'] = panColumn;
    }
    final tdsColumn = normalized.remove('tds');
    if (tdsColumn != null && tdsColumn.trim().isNotEmpty) {
      normalized['tds_amount'] = tdsColumn;
    }
    final deductedAmountColumn = normalized.remove('deducted_amount');
    if (deductedAmountColumn != null && deductedAmountColumn.trim().isNotEmpty) {
      normalized[fileType == ImportMappingService.genericLedgerFileType
          ? 'amount'
          : 'amount_paid'] = deductedAmountColumn;
    }
    final productColumn = normalized.remove('productname');
    if (productColumn != null &&
        productColumn.trim().isNotEmpty &&
        fileType == ImportMappingService.genericLedgerFileType) {
      normalized['description'] = productColumn;
    }
    return normalized;
  }

  static List<String> _buildIssues({
    required String fileType,
    required UploadMappingStatus mappingStatus,
    required Map<String, String> mapping,
    required Map<String, String> requiredFields,
  }) {
    final issues = <String>[];

    for (final entry in requiredFields.entries) {
      if (_isRequiredFieldMapped(fileType, entry.key, mapping)) continue;
      issues.add('${entry.value} is missing');
    }

    if (mappingStatus == UploadMappingStatus.needsReview) {
      issues.add('Auto-mapping still needs manual review');
    } else if (mappingStatus == UploadMappingStatus.notMapped) {
      issues.add('Mapping has not been confirmed yet');
    }

    return issues;
  }

  static bool _isRequiredFieldMapped(
    String fileType,
    String fieldKey,
    Map<String, String> mapping,
  ) {
    switch (fieldKey) {
      case 'date_or_eom':
        return mapping.containsKey('date') || mapping.containsKey('eom');
      case 'amount_column':
        return mapping.containsKey('bill_amount') ||
            mapping.containsKey('basic_amount');
      default:
        return mapping.containsKey(fieldKey);
    }
  }
}
