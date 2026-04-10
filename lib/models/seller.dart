class Seller {
  final int? id;
  final String name;
  final String? pan;

  Seller({
    this.id,
    required this.name,
    this.pan,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pan': pan,
    };
  }

  factory Seller.fromMap(Map<String, dynamic> map) {
    return Seller(
      id: map['id'] as int?,
      name: map['name'] as String,
      pan: map['pan'] as String?,
    );
  }
}