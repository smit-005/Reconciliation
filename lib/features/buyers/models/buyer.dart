class Buyer {
  final String id;
  final String name;
  final String pan;
  final String gstNumber;

  Buyer({
    required this.id,
    required this.name,
    required this.pan,
    this.gstNumber = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id.trim(),
      'name': name.trim(),
      'pan': pan.trim().toUpperCase(),
      'gst_number': gstNumber.trim().toUpperCase(),
    };
  }

  factory Buyer.fromMap(Map<String, dynamic> map) {
    return Buyer(
      id: (map['id'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      pan: (map['pan'] ?? '').toString().trim().toUpperCase(),
      gstNumber: (map['gst_number'] ?? '').toString().trim().toUpperCase(),
    );
  }
}
