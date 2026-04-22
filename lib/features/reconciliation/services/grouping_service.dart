import 'package:flutter/foundation.dart';

import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';

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
      final sellerPan = row.normalizedPan;
      final sellerName = applyNameMapping(row.partyName, nameMapping);
      final normalizedSellerName = sellerName.isNotEmpty
          ? normalizeName(sellerName)
          : row.normalizedName;

      final rawMonth = row.month;
      final financialYear = financialYearFromMonthKey(rawMonth);
      final month = row.normalizedMonth;
      final debugPurchaseRow = _shouldDebugPurchaseRow(row.partyName);
      final parsedDate = tryParseDate(row.date) ?? monthKeyToDate(month);

      if (month.isEmpty || financialYear.isEmpty) {
        if (debugPurchaseRow) {
          debugPrint(
            'DEBUG PURCHASE GROUP => seller=${row.partyName}, '
            'rawDate=${row.date}, '
            'parsedDate=${parsedDate?.toIso8601String().split('T').first ?? ''}, '
            'monthKey=$month, '
            'amountUsed=${row.basicAmount}, '
            'skipped=true, '
            'reason=missing month or financial year',
          );
        }
        continue;
      }
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) {
        if (debugPurchaseRow) {
          debugPrint(
            'DEBUG PURCHASE GROUP => seller=${row.partyName}, '
            'rawDate=${row.date}, '
            'parsedDate=${parsedDate?.toIso8601String().split('T').first ?? ''}, '
            'monthKey=$month, '
            'amountUsed=${row.basicAmount}, '
            'skipped=true, '
            'reason=missing seller identity',
          );
        }
        continue;
      }

      final sellerKey = resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) {
        if (debugPurchaseRow) {
          debugPrint(
            'DEBUG PURCHASE GROUP => seller=${row.partyName}, '
            'rawDate=${row.date}, '
            'parsedDate=${parsedDate?.toIso8601String().split('T').first ?? ''}, '
            'monthKey=$month, '
            'amountUsed=${row.basicAmount}, '
            'skipped=true, '
            'reason=empty seller key',
          );
        }
        continue;
      }

      final resolvedPan = extractPanFromSellerKey(sellerKey);
      final effectiveSellerPan =
      resolvedPan.isNotEmpty ? resolvedPan : sellerPan;

      final fyMonthKey = '$financialYear|$month';

      if (debugPurchaseRow) {
        debugPrint(
          'DEBUG PURCHASE GROUP => seller=${row.partyName}, '
          'rawDate=${row.date}, '
          'parsedDate=${parsedDate?.toIso8601String().split('T').first ?? ''}, '
          'monthKey=$month, '
          'amountUsed=${row.basicAmount}, '
          'skipped=false, '
          'sellerKey=$sellerKey, '
          'fyMonthKey=$fyMonthKey',
        );
      }

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
          sellerName.isNotEmpty ? sellerName : existing.sellerName,
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
      final sellerPan = row.normalizedPan;
      final sellerName = applyNameMapping(row.deducteeName, nameMapping);
      final normalizedSellerName = sellerName.isNotEmpty
          ? normalizeName(sellerName)
          : row.normalizedName;

      final rawMonth = row.month;
      final financialYear = financialYearFromMonthKey(rawMonth);
      final month = row.normalizedMonth;

      if (month.isEmpty || financialYear.isEmpty) continue;
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) continue;

      final sellerKey = resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final effectiveSection = row.normalizedSection.isNotEmpty
          ? row.normalizedSection
          : row.section;
      final fyMonthSectionKey = '$financialYear|$month|$effectiveSection';

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;

      final existing = monthMap[fyMonthSectionKey];
      if (existing == null) {
        monthMap[fyMonthSectionKey] = TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: sellerPan,
          deductedAmount: row.deductedAmount,
          actualTds: row.tds,
          section: effectiveSection,
        );
      } else {
        monthMap[fyMonthSectionKey] = TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName:
          sellerName.isNotEmpty ? sellerName : existing.sellerName,
          sellerPan:
          existing.sellerPan.isNotEmpty ? existing.sellerPan : sellerPan,
          deductedAmount: existing.deductedAmount + row.deductedAmount,
          actualTds: existing.actualTds + row.tds,
          section: existing.section,
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

const bool _enableVerboseGroupingLogs = false;

bool _shouldDebugPurchaseRow(String sellerName) {
  if (!_enableVerboseGroupingLogs) {
    return false;
  }
  return normalizeName(sellerName.trim()) == normalizeName('Ganesh Cattle Feed');
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

  final normalizedKey = normalizeName(trimmed);
  final mapped = mapping[normalizedKey]?.trim();

  if (mapped != null && mapped.isNotEmpty) {
    return mapped;
  }

  return trimmed;
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
  final extractedYear = _extractYear(value);

  if (normalized.contains('apr') && extractedYear != null) {
    return 'Apr-$extractedYear';
  }
  if (normalized.contains('may') && extractedYear != null) {
    return 'May-$extractedYear';
  }
  if (normalized.contains('jun') && extractedYear != null) {
    return 'Jun-$extractedYear';
  }
  if (normalized.contains('jul') && extractedYear != null) {
    return 'Jul-$extractedYear';
  }
  if (normalized.contains('aug') && extractedYear != null) {
    return 'Aug-$extractedYear';
  }
  if (normalized.contains('sep') && extractedYear != null) {
    return 'Sep-$extractedYear';
  }
  if (normalized.contains('oct') && extractedYear != null) {
    return 'Oct-$extractedYear';
  }
  if (normalized.contains('nov') && extractedYear != null) {
    return 'Nov-$extractedYear';
  }
  if (normalized.contains('dec') && extractedYear != null) {
    return 'Dec-$extractedYear';
  }
  if (normalized.contains('jan') && extractedYear != null) {
    return 'Jan-$extractedYear';
  }
  if (normalized.contains('feb') && extractedYear != null) {
    return 'Feb-$extractedYear';
  }
  if (normalized.contains('mar') && extractedYear != null) {
    return 'Mar-$extractedYear';
  }

  final parsed = _tryParseDate(value);
  if (parsed != null) {
    return _monthLabelFromDate(parsed);
  }

  return '';
}

int? _extractYear(String raw) {
  final match = RegExp(r'(20\d{2})').firstMatch(raw);
  if (match != null) {
    return int.parse(match.group(1)!);
  }

  final parsed = _tryParseDate(raw);
  if (parsed != null) {
    return parsed.year;
  }

  return null;
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
