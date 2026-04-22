class Buyer {
  final String id;
  final String name;
  final String pan;

  Buyer({
    required this.id,
    required this.name,
    required this.pan,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pan': pan,
    };
  }

  factory Buyer.fromMap(Map<String, dynamic> map) {
    return Buyer(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      pan: (map['pan'] ?? '').toString(),
    );
  }
}