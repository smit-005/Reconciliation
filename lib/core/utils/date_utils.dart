String normalizeMonth(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  final parsed = tryParseDate(value);
  if (parsed == null) return value;

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[parsed.month - 1]}-${parsed.year}';
}

DateTime? tryParseDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final direct = DateTime.tryParse(text);
  if (direct != null) return DateTime(direct.year, direct.month, direct.day);

  final numeric = double.tryParse(text);
  if (numeric != null) {
    final excelEpoch = DateTime(1899, 12, 30);
    final date = excelEpoch.add(Duration(days: numeric.floor()));
    return DateTime(date.year, date.month, date.day);
  }

  final cleaned = text.replaceAll('/', '-').replaceAll('.', '-');
  final parts = cleaned.split('-');

  if (parts.length == 3) {
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);

    if (a != null && b != null && c != null) {
      if (a > 1900) {
        return DateTime(a, b, c);
      } else if (c > 1900) {
        return DateTime(c, b, a);
      }
    }
  }

  return null;
}

int compareMonthKeys(String a, String b) {
  final da = monthKeyToDate(a);
  final db = monthKeyToDate(b);

  if (da == null && db == null) return a.compareTo(b);
  if (da == null) return -1;
  if (db == null) return 1;

  return da.compareTo(db);
}

DateTime? monthKeyToDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final parts = text.split('-');
  if (parts.length != 2) return tryParseDate(text);

  const monthMap = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  final month = monthMap[parts[0]];
  final year = int.tryParse(parts[1]);

  if (month == null || year == null) return null;
  return DateTime(year, month, 1);
}

String financialYearFromMonthKey(String monthKey) {
  final date = monthKeyToDate(monthKey);
  if (date == null) return '';

  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endYear = startYear + 1;

  return '$startYear-${endYear.toString().substring(2)}';
}

int compareFinancialYearMonthKeys(String a, String b) {
  final aParts = a.split('|');
  final bParts = b.split('|');

  final aFy = aParts.isNotEmpty ? aParts[0] : '';
  final bFy = bParts.isNotEmpty ? bParts[0] : '';

  final fyCompare = aFy.compareTo(bFy);
  if (fyCompare != 0) return fyCompare;

  final aMonth = aParts.length > 1 ? aParts[1] : '';
  final bMonth = bParts.length > 1 ? bParts[1] : '';

  return compareMonthKeys(aMonth, bMonth);
}