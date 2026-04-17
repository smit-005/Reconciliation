import 'mapping_service.dart';
import 'grouping_service.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import '../models/reconciliation_row.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/normalize_utils.dart';
import '../core/utils/parse_utils.dart';
import 'timing_service.dart';
import 'section_rule_service.dart';

class _SellerIdentity {
  final String originalName;
  final String mappedName;
  final String normalizedName;
  final String sellerPan;

  _SellerIdentity({
    required this.originalName,
    required this.mappedName,
    required this.normalizedName,
    required this.sellerPan,
  });
}

class _DisjointSet {
  final Map<String, String> _parent = {};

  void add(String value) {
    _parent.putIfAbsent(value, () => value);
  }

  String find(String value) {
    add(value);
    if (_parent[value] == value) return value;
    _parent[value] = find(_parent[value]!);
    return _parent[value]!;
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA == rootB) return;
    _parent[rootB] = rootA;
  }

  Set<String> values() => _parent.keys.toSet();
}

class CalculationService {
  static const double threshold = 5000000.0;
  static const double tolerance = 1.0;

  static int compareMonthLabels(String a, String b) {
    return compareMonthKeys(a, b);
  }

  static DateTime? monthLabelToDate(String value) {
    return monthKeyToDate(value);
  }

  static Future<List<ReconciliationRow>> reconcile({
    required String buyerName,
    required String buyerPan,
    required List<PurchaseRow> purchaseRows,
    required List<Tds26QRow> tdsRows,
    Map<String, String>? nameMapping,
    bool includeAllRows = false,
  }) async {
    final normalizedBuyerPan = normalizePan(buyerPan);
    final normalizedMapping = normalizeNameMapping(nameMapping ?? {});

    final mappings = await MappingService.getAllMappings(normalizedBuyerPan);

    final savedAliasToPan = <String, String>{
      for (final m in mappings)
        normalizeName(m.aliasName): normalizePan(m.mappedPan),
    };

    final sellerKeyResolver = _buildSellerKeyResolver(
      purchaseRows: purchaseRows,
      tdsRows: tdsRows,
      nameMapping: normalizedMapping,
      savedAliasToPan: savedAliasToPan,
    );

    final purchaseGroups = GroupingService.groupPurchaseRows(
      purchaseRows,
      normalizedMapping,
      sellerKeyResolver,
    );

    final tdsGroups = GroupingService.groupTdsRows(
      tdsRows,
      normalizedMapping,
      sellerKeyResolver,
    );

    final relevantSellerKeys = includeAllRows
        ? <String>{...purchaseGroups.keys, ...tdsGroups.keys}
        : GroupingService.getRelevantSellerKeys(
      purchaseGroups: purchaseGroups,
      tdsGroups: tdsGroups,
      threshold: threshold,
    );

    final results = <ReconciliationRow>[];

    for (final sellerKey in relevantSellerKeys) {
      final purchaseByFyMonth = purchaseGroups[sellerKey] ?? {};
      final tdsByFyMonth = tdsGroups[sellerKey] ?? {};

      final allFyMonthKeys = <String>{
        ...purchaseByFyMonth.keys,
        ...tdsByFyMonth.keys,
      }.toList()
        ..sort(compareFinancialYearMonthKeys);

      final Map<String, double> sectionWiseCumulative = {};
      String currentFy = '';
      final sellerRows = <ReconciliationRow>[];

      for (final fyMonthKey in allFyMonthKeys) {
        final purchase = purchaseByFyMonth[fyMonthKey];
        final tds = tdsByFyMonth[fyMonthKey];

        final financialYear = purchase?.financialYear ?? tds?.financialYear ?? '';
        final month = purchase?.month ?? tds?.month ?? '';

        final purchasePresent = purchase != null;
        final tdsPresent = tds != null;

        final basicAmount = round2(purchase?.basicAmount ?? 0.0);

        if (financialYear != currentFy) {
          currentFy = financialYear;
          sectionWiseCumulative.clear();
        }

        final rawResolvedSection = _resolveSectionFromRaw(tds?.section);

        // Purchase rows without 26Q section should still use 194Q fallback
        // so cumulative threshold logic works correctly for purchase register data.

        
        String effectiveSection = rawResolvedSection;
if ((effectiveSection.isEmpty || effectiveSection == 'UNKNOWN') && purchasePresent) {
  effectiveSection = '194Q';
}

        final hasValidSection = _isUsableSection(effectiveSection);

        SectionRuleResult ruleResult;

        if (purchasePresent && hasValidSection) {
          final normalizedSection = effectiveSection.trim().toUpperCase();

          final previousSectionCumulative =
              sectionWiseCumulative[normalizedSection] ?? 0.0;

          final currentSectionCumulative =
          round2(previousSectionCumulative + basicAmount);

          sectionWiseCumulative[normalizedSection] = currentSectionCumulative;

          ruleResult = SectionRuleService.applyRule(
            section: effectiveSection,
            cumulativePurchase: currentSectionCumulative,
            previousCumulative: previousSectionCumulative,
            currentAmount: basicAmount,
            sectionCumulative: currentSectionCumulative,
            previousSectionCumulative: previousSectionCumulative,
          );
        } else {
          ruleResult = SectionRuleResult(
            applicableAmount: 0.0,
            expectedTds: 0.0,
            rate: 0.0,
          );
        }

        final applicableAmount = round2(ruleResult.applicableAmount);
        final expectedTds = round2(ruleResult.expectedTds);
        final tdsRateUsed = ruleResult.rate;

        final deductedAmount = round2(tds?.deductedAmount ?? 0.0);
        final actualTds = round2(tds?.actualTds ?? 0.0);

        final amountDifference = round2(applicableAmount - deductedAmount);
        final tdsDifference = round2(expectedTds - actualTds);

        final sellerPan = _chooseSellerPan(
          purchasePan: purchase?.sellerPan ?? '',
          tdsPan: tds?.sellerPan ?? '',
          fallbackKey: sellerKey,
        );

        final sellerName = _chooseSellerName(
          purchaseName: purchase?.sellerName ?? '',
          tdsName: tds?.sellerName ?? '',
        );

        final status = _buildBaseStatus(
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          tdsDifference: tdsDifference,
          hasValidSection: hasValidSection,
          applicableAmount: applicableAmount,
          actualTds: actualTds,
        );

        final remarks = _buildRemarks(
          sellerPan: sellerPan,
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          amountDifference: amountDifference,
          status: status,
          hasValidSection: hasValidSection,
        );

        sellerRows.add(
          ReconciliationRow(
            buyerName: buyerName,
            buyerPan: normalizedBuyerPan,
            financialYear: financialYear,
            month: month,
            sellerName: sellerName,
            sellerPan: sellerPan,
            section: effectiveSection.isNotEmpty ? effectiveSection : 'No Section',
            basicAmount: basicAmount,
            applicableAmount: applicableAmount,
            tds26QAmount: deductedAmount,
            expectedTds: expectedTds,
            actualTds: actualTds,
            tdsRateUsed: tdsRateUsed,
            amountDifference: amountDifference,
            tdsDifference: tdsDifference,
            status: status,
            remarks: remarks,
            purchasePresent: purchasePresent,
            tdsPresent: tdsPresent,
            openingTimingBalance: 0.0,
            monthTdsDifference: round2(actualTds - expectedTds),
            closingTimingBalance: 0.0,
          ),
        );
      }
      results.addAll(TimingService.applyTimingLogic(sellerRows));
    }

    results.sort((a, b) {
      final sellerNameCompare =
      a.sellerName.toUpperCase().compareTo(b.sellerName.toUpperCase());
      if (sellerNameCompare != 0) return sellerNameCompare;

      final panCompare =
      a.sellerPan.toUpperCase().compareTo(b.sellerPan.toUpperCase());
      if (panCompare != 0) return panCompare;

      final fyCompare = a.financialYear.compareTo(b.financialYear);
      if (fyCompare != 0) return fyCompare;

      return compareMonthKeys(a.month, b.month);
    });

    return results;
  }

  static Map<String, String> _buildSellerKeyResolver({
    required List<PurchaseRow> purchaseRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
    required Map<String, String> savedAliasToPan,
  }) {
    final identities = <_SellerIdentity>[];

    for (final row in purchaseRows) {
      final mappedName = applyNameMapping(row.partyName, nameMapping);
      identities.add(
        _SellerIdentity(
          originalName: row.partyName,
          mappedName: mappedName,
          normalizedName: normalizeName(
            mappedName.isNotEmpty ? mappedName : row.partyName,
          ),
          sellerPan: normalizePan(row.panNumber),
        ),
      );
    }

    for (final row in tdsRows) {
      final mappedName = applyNameMapping(row.deducteeName, nameMapping);
      identities.add(
        _SellerIdentity(
          originalName: row.deducteeName,
          mappedName: mappedName,
          normalizedName: normalizeName(
            mappedName.isNotEmpty ? mappedName : row.deducteeName,
          ),
          sellerPan: normalizePan(row.panNumber),
        ),
      );
    }

    final dsu = _DisjointSet();

    for (final entry in nameMapping.entries) {
      final rawPurchase = entry.key.trim().toUpperCase();
      final rawTds = entry.value.trim().toUpperCase();

      final normPurchase = normalizeName(entry.key);
      final normTds = normalizeName(entry.value);

      final nodes = [
        'NAME:$rawPurchase',
        'NAME:$rawTds',
        'NAME:$normPurchase',
        'NAME:$normTds',
      ];

      for (final n in nodes) {
        if (n.replaceAll('NAME:', '').isEmpty) continue;
        dsu.add(n);
      }

      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          dsu.union(nodes[i], nodes[j]);
        }
      }
    }

    for (final entry in savedAliasToPan.entries) {
      final normAlias = normalizeName(entry.key);
      final mappedPan = normalizePan(entry.value);

      final nameNode = 'NAME:$normAlias';
      final panNode = 'PAN:$mappedPan';

      if (normAlias.isNotEmpty) {
        dsu.add(nameNode);
      }

      if (mappedPan.isNotEmpty) {
        dsu.add(panNode);
      }

      if (normAlias.isNotEmpty && mappedPan.isNotEmpty) {
        dsu.union(nameNode, panNode);
      }
    }

    for (final identity in identities) {
      final pan = identity.sellerPan;
      final normName = identity.normalizedName;

      String? panNode;
      String? nameNode;

      if (pan.isNotEmpty) {
        panNode = 'PAN:$pan';
        dsu.add(panNode);
      }

      if (normName.isNotEmpty) {
        nameNode = 'NAME:$normName';
        dsu.add(nameNode);
      }

      if (panNode != null && nameNode != null) {
        dsu.union(panNode, nameNode);
      }
    }

    final groups = <String, Set<String>>{};
    for (final node in dsu.values()) {
      final root = dsu.find(node);
      groups.putIfAbsent(root, () => <String>{}).add(node);
    }

    final rootToCanonicalKey = <String, String>{};

    for (final entry in groups.entries) {
      final nodes = entry.value;

      final panNodes = nodes.where((e) => e.startsWith('PAN:')).toList()..sort();
      final nameNodes = nodes.where((e) => e.startsWith('NAME:')).toList()..sort();

      if (panNodes.isNotEmpty) {
        rootToCanonicalKey[entry.key] = panNodes.first.substring(4);
      } else if (nameNodes.isNotEmpty) {
        rootToCanonicalKey[entry.key] = nameNodes.first.substring(5);
      }
    }

    final resolver = <String, String>{};

    for (final node in dsu.values()) {
      final root = dsu.find(node);
      final canonical = rootToCanonicalKey[root];
      if (canonical == null || canonical.isEmpty) continue;

      if (node.startsWith('PAN:')) {
        resolver[node.substring(4)] = canonical;
      } else if (node.startsWith('NAME:')) {
        resolver[node.substring(5)] = canonical;
      }
    }

    return resolver;
  }

  static String _resolveSectionFromRaw(String? rawSection) {
    final source = (rawSection ?? '').trim();
    if (source.isEmpty) return '';

    final normalized = normalizeSection(source);
    if (_isUsableSection(normalized)) {
      return normalized;
    }

    final upper = source.toUpperCase().replaceAll(' ', '');

    if (upper.contains('194IA')) return '194IA';
    if (upper.contains('194IB')) return '194IB';
    if (upper.contains('194Q')) return '194Q';
    if (upper.contains('194C')) return '194C';
    if (upper.contains('194J')) return '194J';
    if (upper.contains('194I')) return '194I';
    if (upper.contains('194A')) return '194A';
    if (upper.contains('194H')) return '194H';
    if (upper.contains('194D')) return '194D';
    if (upper.contains('194N')) return '194N';
    if (upper.contains('194M')) return '194M';
    if (upper.contains('206AB')) return '206AB';
    if (upper.contains('206C')) return '206C';

    return '';
  }

  static bool _isUsableSection(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.isEmpty) return false;
    if (upper == 'NO SECTION') return false;
    if (upper == 'UNKNOWN') return false;
    return true;
  }

  static String _buildBaseStatus({
    required bool purchaseMissing,
    required bool tdsMissing,
    required double tdsDifference,
    required bool hasValidSection,
    required double applicableAmount,
    required double actualTds,
  }) {
    if (purchaseMissing && !tdsMissing) {
      return '26Q Only';
    }

    if (!purchaseMissing && tdsMissing) {
      if (applicableAmount > 0) {
        return 'Applicable but no 26Q';
      }
      return 'Purchase Only';
    }

    if (!hasValidSection) {
      return 'Section Missing';
    }

    if (tdsDifference.abs() <= tolerance) {
      return 'Matched';
    }

    if (applicableAmount == 0 && actualTds > 0) {
      return 'Unnecessary Deduction';
    }

    if (tdsDifference > 0) {
      return 'Short Deduction';
    }

    return 'Excess Deduction';
  }

  static String _buildRemarks({
    required String sellerPan,
    required bool purchaseMissing,
    required bool tdsMissing,
    required double amountDifference,
    required String status,
    required bool hasValidSection,
  }) {
    final remarks = <String>[];

    if (sellerPan.isEmpty) {
      remarks.add('PAN missing → high TDS risk');
    }

    if (purchaseMissing) {
      remarks.add('Entry present in 26Q but not in purchase');
    }

    if (tdsMissing) {
      if (amountDifference > 0) {
        remarks.add('TDS not deducted despite applicable purchase');
      } else {
        remarks.add('Not found in 26Q');
      }
    }

    if (!tdsMissing && !hasValidSection) {
      remarks.add('Section not defined in 26Q');
    }

    if (!purchaseMissing && !tdsMissing) {
      if (amountDifference.abs() > tolerance) {
        remarks.add('Purchase vs 26Q amount mismatch');
      }

      if (status == 'Short Deduction') {
        remarks.add('TDS deducted less than expected');
      }

      if (status == 'Excess Deduction') {
        remarks.add('TDS deducted more than expected');
      }
    }

    return remarks.join(', ');
  }

  static String _chooseSellerName({
    required String purchaseName,
    required String tdsName,
  }) {
    if (tdsName.trim().isNotEmpty) return tdsName.trim();
    if (purchaseName.trim().isNotEmpty) return purchaseName.trim();
    return '';
  }

  static String _chooseSellerPan({
    required String purchasePan,
    required String tdsPan,
    required String fallbackKey,
  }) {
    if (tdsPan.trim().isNotEmpty) return tdsPan.trim();
    if (purchasePan.trim().isNotEmpty) return purchasePan.trim();
    if (looksLikePan(fallbackKey)) return fallbackKey.trim();
    return '';
  }
}
