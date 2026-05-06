String currentIndianFinancialYearLabel({DateTime? now}) {
  final date = now ?? DateTime.now();
  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endYear = startYear + 1;

  return '$startYear-${endYear.toString().substring(2)}';
}

String? normalizeFinancialYearLabel(String value) {
  final trimmed = value.trim().toUpperCase().replaceFirst(
    RegExp(r'^FY[_\s-]*'),
    '',
  );
  final match = RegExp(r'^(\d{4})[-/](\d{2}|\d{4})$').firstMatch(trimmed);
  if (match == null) {
    return null;
  }

  final startYear = match.group(1)!;
  final rawEndYear = match.group(2)!;
  final endYear = rawEndYear.length == 4 ? rawEndYear.substring(2) : rawEndYear;

  return '$startYear-$endYear';
}

String formatFinancialYearDisplayLabel(String fyLabel) {
  final normalized = normalizeFinancialYearLabel(fyLabel) ?? fyLabel.trim();
  return normalized.isEmpty ? '' : 'FY $normalized';
}
