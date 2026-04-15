String? readAny(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return null;
}

double parseDouble(dynamic value) {
  if (value == null) return 0.0;

  final text = value.toString().trim();
  if (text.isEmpty) return 0.0;

  final cleaned = text.replaceAll(',', '').replaceAll('₹', '');
  return double.tryParse(cleaned) ?? 0.0;
}

double round2(double value) {
  return double.parse(value.toStringAsFixed(2));
}