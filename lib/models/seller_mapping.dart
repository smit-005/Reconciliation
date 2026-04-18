import '../core/utils/normalize_utils.dart';

class SellerMapping {
  final int? id;
  final String buyerName;
  final String buyerPan;
  final String aliasName;
  final String mappedPan;
  final String mappedName;

  SellerMapping({
    this.id,
    required this.buyerName,
    required this.buyerPan,
    required this.aliasName,
    required this.mappedPan,
    required this.mappedName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_name': buyerName,
      'buyer_pan': buyerPan.trim().toUpperCase(),
      'alias_name': normalizeName(aliasName.trim()),
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
      mappedPan: (map['mapped_pan'] ?? '').toString(),
      mappedName: (map['mapped_name'] ?? '').toString(),
    );
  }
}
