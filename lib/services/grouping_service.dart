import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import '../core/utils/normalize_utils.dart';
import '../core/utils/date_utils.dart';

class PurchaseGroup {
  final String financialYear;
  final String month;
  final String sellerName;
  final String sellerPan;
  final double basicAmount;
  final double billAmount;

  PurchaseGroup({
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.basicAmount,
    required this.billAmount,
  });
}

class TdsGroup {
  final String financialYear;
  final String month;
  final String sellerName;
  final String sellerPan;
  final double deductedAmount;
  final double actualTds;
  final String section;

  TdsGroup({
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.deductedAmount,
    required this.actualTds,
    required this.section,
  });
}

class GroupingService {
  static Map<String, Map<String, PurchaseGroup>> groupPurchaseRows(
      List<PurchaseRow> rows,
      Map<String, String> nameMapping,
      Map<String, String> sellerKeyResolver,
      ) {
    final grouped = <String, Map<String, PurchaseGroup>>{};

    for (final row in rows) {
      final sellerPan = normalizePan(row.panNumber);
      final sellerName = applyNameMapping(row.partyName, nameMapping);
      final normalizedSellerName =
      normalizeName(sellerName.isNotEmpty ? sellerName : row.partyName);

      final rawMonth = row.month;
      final financialYear = financialYearFromMonthKey(rawMonth);
      final month = normalizeMonthKey(rawMonth);

      if (month.isEmpty || financialYear.isEmpty) continue;
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) continue;

      final sellerKey = resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final resolvedPan = extractPanFromSellerKey(sellerKey);
      final effectiveSellerPan =
      resolvedPan.isNotEmpty ? resolvedPan : sellerPan;

      final fyMonthKey = '$financialYear|$month';

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;

      final existing = monthMap[fyMonthKey];
      if (existing == null) {
        monthMap[fyMonthKey] = PurchaseGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: effectiveSellerPan,
          basicAmount: row.basicAmount,
          billAmount: row.billAmount,
        );
      } else {
        monthMap[fyMonthKey] = PurchaseGroup(
          financialYear: financialYear,
          month: month,
          sellerName:
          existing.sellerName.isNotEmpty ? existing.sellerName : sellerName,
          sellerPan: existing.sellerPan.isNotEmpty
              ? existing.sellerPan
              : effectiveSellerPan,
          basicAmount: existing.basicAmount + row.basicAmount,
          billAmount: existing.billAmount + row.billAmount,
        );
      }
    }

    return grouped;
  }

  static Map<String, Map<String, TdsGroup>> groupTdsRows(
      List<Tds26QRow> rows,
      Map<String, String> nameMapping,
      Map<String, String> sellerKeyResolver,
      ) {
    final grouped = <String, Map<String, TdsGroup>>{};

    for (final row in rows) {
      final sellerPan = normalizePan(row.panNumber);
      final sellerName = applyNameMapping(row.deducteeName, nameMapping);
      final normalizedSellerName =
      normalizeName(sellerName.isNotEmpty ? sellerName : row.deducteeName);

      final rawMonth = row.month;
      final financialYear = financialYearFromMonthKey(rawMonth);
      final month = normalizeMonthKey(rawMonth);

      if (month.isEmpty || financialYear.isEmpty) continue;
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) continue;

      final sellerKey = resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final fyMonthKey = '$financialYear|$month';

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;

      final existing = monthMap[fyMonthKey];
      if (existing == null) {
        monthMap[fyMonthKey] = TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: sellerPan,
          deductedAmount: row.deductedAmount,
          actualTds: row.tds,
          section: row.section,
        );
      } else {
        monthMap[fyMonthKey] = TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName:
          existing.sellerName.isNotEmpty ? existing.sellerName : sellerName,
          sellerPan:
          existing.sellerPan.isNotEmpty ? existing.sellerPan : sellerPan,
          deductedAmount: existing.deductedAmount + row.deductedAmount,
          actualTds: existing.actualTds + row.tds,
          section: existing.section.isNotEmpty ? existing.section : row.section,
        );
      }
    }

    return grouped;
  }

  static Set<String> getRelevantSellerKeys({
    required Map<String, Map<String, PurchaseGroup>> purchaseGroups,
    required Map<String, Map<String, TdsGroup>> tdsGroups,
    required double threshold,
  }) {
    final relevant = <String>{};

    for (final sellerKey in tdsGroups.keys) {
      relevant.add(sellerKey);
    }

    for (final entry in purchaseGroups.entries) {
      final sellerKey = entry.key;
      final monthMap = entry.value;

      final fyTotals = <String, double>{};
      for (final group in monthMap.values) {
        fyTotals[group.financialYear] =
            (fyTotals[group.financialYear] ?? 0.0) + group.basicAmount;
      }

      final crossedThreshold = fyTotals.values.any((total) => total > threshold);
      if (crossedThreshold) {
        relevant.add(sellerKey);
      }
    }

    return relevant;
  }
}

String resolveSellerKey({
  required String sellerPan,
  required String normalizedSellerName,
  required Map<String, String> resolver,
}) {
  if (sellerPan.isNotEmpty) {
    return resolver[sellerPan] ?? sellerPan;
  }
  if (normalizedSellerName.isNotEmpty) {
    return resolver[normalizedSellerName] ?? normalizedSellerName;
  }
  return '';
}

String extractPanFromSellerKey(String sellerKey) {
  final trimmed = sellerKey.trim().toUpperCase();
  return looksLikePan(trimmed) ? trimmed : '';
}

String applyNameMapping(String name, Map<String, String> mapping) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';

  final normalized = normalizeName(trimmed);
  return mapping[normalized] ?? trimmed;
}

Map<String, String> normalizeNameMapping(Map<String, String> mapping) {
  final result = <String, String>{};

  for (final entry in mapping.entries) {
    final key = normalizeName(entry.key);
    final value = entry.value.trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      result[key] = value;
    }
  }

  return result;
}

String normalizeMonthKey(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  final normalized = value.toLowerCase();

  if (normalized.contains('apr')) return 'Apr-${_extractYear(value)}';
  if (normalized.contains('may')) return 'May-${_extractYear(value)}';
  if (normalized.contains('jun')) return 'Jun-${_extractYear(value)}';
  if (normalized.contains('jul')) return 'Jul-${_extractYear(value)}';
  if (normalized.contains('aug')) return 'Aug-${_extractYear(value)}';
  if (normalized.contains('sep')) return 'Sep-${_extractYear(value)}';
  if (normalized.contains('oct')) return 'Oct-${_extractYear(value)}';
  if (normalized.contains('nov')) return 'Nov-${_extractYear(value)}';
  if (normalized.contains('dec')) return 'Dec-${_extractYear(value)}';
  if (normalized.contains('jan')) return 'Jan-${_extractYear(value)}';
  if (normalized.contains('feb')) return 'Feb-${_extractYear(value)}';
  if (normalized.contains('mar')) return 'Mar-${_extractYear(value)}';

  final parsed = _tryParseDate(value);
  if (parsed != null) {
    return _monthLabelFromDate(parsed);
  }

  return value;
}

int _extractYear(String raw) {
  final match = RegExp(r'(20\d{2})').firstMatch(raw);
  if (match != null) {
    return int.parse(match.group(1)!);
  }

  final parsed = _tryParseDate(raw);
  if (parsed != null) {
    return parsed.year;
  }

  return DateTime.now().year;
}

DateTime? _tryParseDate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$');
  final slashMatch = slash.firstMatch(trimmed);
  if (slashMatch != null) {
    final day = int.tryParse(slashMatch.group(1)!);
    final month = int.tryParse(slashMatch.group(2)!);
    int? year = int.tryParse(slashMatch.group(3)!);

    if (day != null && month != null && year != null) {
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    }
  }

  final dash = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{2,4})$');
  final dashMatch = dash.firstMatch(trimmed);
  if (dashMatch != null) {
    final day = int.tryParse(dashMatch.group(1)!);
    final month = int.tryParse(dashMatch.group(2)!);
    int? year = int.tryParse(dashMatch.group(3)!);

    if (day != null && month != null && year != null) {
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    }
  }

  try {
    return DateTime.parse(trimmed);
  } catch (_) {
    return null;
  }
}

String _monthLabelFromDate(DateTime date) {
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

  return '${months[date.month - 1]}-${date.year}';
}