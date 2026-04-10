class Mapping {
  final int? id;
  final int buyerId;
  final int sellerId;
  final String aliasName;

  Mapping({
    this.id,
    required this.buyerId,
    required this.sellerId,
    required this.aliasName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'alias_name': aliasName,
    };
  }

  factory Mapping.fromMap(Map<String, dynamic> map) {
    return Mapping(
      id: map['id'],
      buyerId: map['buyer_id'],
      sellerId: map['seller_id'],
      aliasName: map['alias_name'],
    );
  }
}