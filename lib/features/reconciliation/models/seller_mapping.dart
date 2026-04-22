import 'package:reconciliation_app/core/utils/normalize_utils.dart';

class SellerMapping {
  final int? id;
  final String buyerName;
  final String buyerPan;
  final String aliasName;
  final String sectionCode;
  final String mappedPan;
  final String mappedName;

  SellerMapping({
    this.id,
    required this.buyerName,
    required this.buyerPan,
    required this.aliasName,
    this.sectionCode = 'ALL',
    required this.mappedPan,
    required this.mappedName,
  });

  SellerMapping copyWith({
    int? id,
    String? buyerName,
    String? buyerPan,
    String? aliasName,
    String? sectionCode,
    String? mappedPan,
    String? mappedName,
  }) {
    return SellerMapping(
      id: id ?? this.id,
      buyerName: buyerName ?? this.buyerName,
      buyerPan: buyerPan ?? this.buyerPan,
      aliasName: aliasName ?? this.aliasName,
      sectionCode: sectionCode ?? this.sectionCode,
      mappedPan: mappedPan ?? this.mappedPan,
      mappedName: mappedName ?? this.mappedName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_name': buyerName,
      'buyer_pan': buyerPan.trim().toUpperCase(),
      'alias_name': normalizeName(aliasName.trim()),
      'section_code': normalizeSellerMappingSectionCode(sectionCode),
      'mapped_pan': mappedPan.trim().toUpperCase(),
      'mapped_name': mappedName.trim(),
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  factory SellerMapping.fromMap(Map<String, dynamic> map) {
    return SellerMapping(
      id: map['id'] as int?,
      buyerName: (map['buyer_name'] ?? '').toString(),
      buyerPan: (map['buyer_pan'] ?? '').toString(),
      aliasName: (map['alias_name'] ?? '').toString(),
      sectionCode: normalizeSellerMappingSectionCode(
        (map['section_code'] ?? 'ALL').toString(),
      ),
      mappedPan: (map['mapped_pan'] ?? '').toString(),
      mappedName: (map['mapped_name'] ?? '').toString(),
    );
  }
}

String normalizeSellerMappingSectionCode(String value) {
  final trimmed = value.trim().toUpperCase();
  if (trimmed.isEmpty || trimmed == 'ALL') {
    return 'ALL';
  }

  final normalized = normalizeSection(trimmed);
  return normalized.isEmpty ? 'ALL' : normalized;
}
