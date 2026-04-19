import 'package:flutter/foundation.dart';

import 'mapping_service.dart';
import 'grouping_service.dart';
import '../models/normalized_transaction_row.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import '../models/reconciliation_row.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/normalize_utils.dart';
import '../../../core/utils/parse_utils.dart';
import 'timing_service.dart';
import 'section_rule_service.dart';
import 'reconciliation_engine.dart';

part 'reconciliation_service_debug_helpers.dart';

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

class _NormalizedSourceGroup {
  final String financialYear;
  final String month;
  final String sellerName;
  final String sellerPan;
  final double basicAmount;
  final double sourceAmount;

  _NormalizedSourceGroup({
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.basicAmount,
    required this.sourceAmount,
  });
}

class _SellerNameChoice {
  final String name;
  final int priority;

  const _SellerNameChoice({
    required this.name,
    required this.priority,
  });
}

class ReconciliationSummary {
  final String section;
  final int totalRows;
  final int matchedRows;
  final int mismatchRows;
  final int purchaseOnlyRows;
  final int only26QRows;
  final int applicableButNo26QRows;
  final double sourceAmount;
  final double applicableAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double amountDifference;
  final double tdsDifference;

  const ReconciliationSummary({
    required this.section,
    required this.totalRows,
    required this.matchedRows,
    required this.mismatchRows,
    required this.purchaseOnlyRows,
    required this.only26QRows,
    required this.applicableButNo26QRows,
    required this.sourceAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.amountDifference,
    required this.tdsDifference,
  });
}

class SectionReconciliationResult {
  final List<ReconciliationRow> rows;
  final ReconciliationSummary combinedSummary;
  final Map<String, ReconciliationSummary> sectionSummaries;
  final Map<String, List<ReconciliationRow>> rowsBySection;

  const SectionReconciliationResult({
    required this.rows,
    required this.combinedSummary,
    required this.sectionSummaries,
    required this.rowsBySection,
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
  static const double amountTolerance = 1.0;
  static const double tdsTolerance = 1.0;
  static const double minorTdsTolerance = 5.0;
  static const List<String> supportedSections = [
    '194Q',
    '194C',
    '194H',
    '194J',
    '194IB',
  ];

  static int compareMonthLabels(String a, String b) {
    return compareMonthKeys(a, b);
  }

  static DateTime? monthLabelToDate(String value) {
    return monthKeyToDate(value);
  }

  static Future<SectionReconciliationResult> reconcileSectionWise({
    required String buyerName,
    required String buyerPan,
    required List<NormalizedTransactionRow> sourceRows,
    required List<Tds26QRow> tdsRows,
    Map<String, String>? nameMapping,
    bool includeAllRows = false,
    List<String>? sections,
  }) async {
    final normalizedBuyerPan = normalizePan(buyerPan);
    final normalizedMapping = normalizeNameMapping(nameMapping ?? {});
    final activeSections = (sections ?? supportedSections)
        .map(_normalizeSupportedSection)
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final mappings = await MappingService.getAllMappings(normalizedBuyerPan);
    final savedAliasToPan = <String, String>{
      for (final m in mappings)
        normalizeName(m.aliasName): normalizePan(m.mappedPan),
    };

    final sourceRowsBySection = <String, List<NormalizedTransactionRow>>{};
    for (final row in sourceRows) {
      final section = _sourceSection(row);
      if (section.isEmpty) continue;
      sourceRowsBySection.putIfAbsent(section, () => <NormalizedTransactionRow>[]);
      sourceRowsBySection[section]!.add(row);
    }

    final supportedTdsRowsBySection = <String, List<Tds26QRow>>{};
    final unsupportedTdsRowsBySection = <String, List<Tds26QRow>>{};
    for (final row in tdsRows) {
      final supportedSection = _normalizeSupportedSection(row.section);
      if (supportedSection.isNotEmpty) {
        supportedTdsRowsBySection.putIfAbsent(
          supportedSection,
          () => <Tds26QRow>[],
        );
        supportedTdsRowsBySection[supportedSection]!.add(row);
        continue;
      }

      final unknownSection = _unknownSectionLabel(row.section);
      unsupportedTdsRowsBySection.putIfAbsent(
        unknownSection,
        () => <Tds26QRow>[],
      );
      unsupportedTdsRowsBySection[unknownSection]!.add(row);
    }

    debugPrint(
      'SECTION RECON SOURCE ROWS => ${_debugSectionCounts(sourceRowsBySection)}',
    );
    debugPrint(
      'SECTION RECON 26Q ROWS => '
      '${_debugSectionCounts(supportedTdsRowsBySection, extra: unsupportedTdsRowsBySection)}',
    );

    final sellerKeyResolver = _buildSellerKeyResolverFromNormalized(
      sourceRows: sourceRows,
      tdsRows: tdsRows,
      nameMapping: normalizedMapping,
      savedAliasToPan: savedAliasToPan,
    );
    final resolvedSellerNameLookup = _buildResolvedSellerNameLookup(
      identities: _collectNormalizedSellerIdentities(
        sourceRows: sourceRows,
        tdsRows: tdsRows,
        nameMapping: normalizedMapping,
      ),
      sellerKeyResolver: sellerKeyResolver,
    );

    final rowsBySection = <String, List<ReconciliationRow>>{};
    final allCombinedRows = <ReconciliationRow>[];

    for (final section in activeSections) {
      final sectionSourceRows = sourceRowsBySection[section] ?? const <NormalizedTransactionRow>[];
      final sectionTdsRows = supportedTdsRowsBySection[section] ?? const <Tds26QRow>[];

      if (sectionSourceRows.isEmpty && sectionTdsRows.isEmpty) {
        continue;
      }

      final sectionRows = _reconcileNormalizedSection(
        buyerName: buyerName,
        buyerPan: normalizedBuyerPan,
        section: section,
        sourceRows: sectionSourceRows,
        tdsRows: sectionTdsRows,
        nameMapping: normalizedMapping,
        sellerKeyResolver: sellerKeyResolver,
        includeAllRows: includeAllRows,
      );

      rowsBySection[section] = sectionRows;
      allCombinedRows.addAll(sectionRows);
    }

    for (final entry in unsupportedTdsRowsBySection.entries) {
      if (entry.value.isEmpty) continue;

      final sectionRows = _reconcileNormalizedSection(
        buyerName: buyerName,
        buyerPan: normalizedBuyerPan,
        section: entry.key,
        sourceRows: const <NormalizedTransactionRow>[],
        tdsRows: entry.value,
        nameMapping: normalizedMapping,
        sellerKeyResolver: sellerKeyResolver,
        includeAllRows: true,
      );

      if (sectionRows.isEmpty) continue;

      rowsBySection[entry.key] = sectionRows;
      allCombinedRows.addAll(sectionRows);
    }

    final mergedRows = _applyResolvedSellerNames(
      _mergeRowsWithUniquePanHints(allCombinedRows),
      sellerKeyResolver: sellerKeyResolver,
      resolvedSellerNameLookup: resolvedSellerNameLookup,
    );
    final mergedRowsBySection = <String, List<ReconciliationRow>>{};

    for (final section in rowsBySection.keys) {
      final scopedRows = mergedRows
          .where((row) => row.section.trim() == section)
          .toList();
      if (scopedRows.isNotEmpty) {
        mergedRowsBySection[section] = scopedRows;
        continue;
      }

      final unknownRows = mergedRows
          .where(
            (row) =>
                section == 'UNKNOWN' &&
                (row.section.trim().isEmpty ||
                    row.section.trim().toUpperCase() == 'NO SECTION'),
          )
          .toList();
      if (unknownRows.isNotEmpty) {
        mergedRowsBySection[section] = unknownRows;
      }
    }

    final sectionSummaries = <String, ReconciliationSummary>{
      for (final section in activeSections)
        if ((mergedRowsBySection[section] ?? const <ReconciliationRow>[]).isNotEmpty)
        section: _buildSummary(
          section: section,
          rows: mergedRowsBySection[section] ?? const [],
        ),
    };

    debugPrint(
      'SECTION RECON FINAL SUMMARIES => ${_debugSummaryMap(sectionSummaries)}',
    );

    return SectionReconciliationResult(
      rows: mergedRows,
      combinedSummary: _sumSectionSummaries(sectionSummaries),
      sectionSummaries: sectionSummaries,
      rowsBySection: mergedRowsBySection,
    );
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
    final resolvedSellerNameLookup = _buildResolvedSellerNameLookup(
      identities: _collectSellerIdentities(
        purchaseRows: purchaseRows,
        tdsRows: tdsRows,
        nameMapping: normalizedMapping,
      ),
      sellerKeyResolver: sellerKeyResolver,
    );
    final gstDerivedPanHints = <String, bool>{};

    for (final row in purchaseRows) {
      final sellerPan = normalizePan(row.panNumber);
      final sellerName = applyNameMapping(row.partyName, normalizedMapping);
      final normalizedSellerName =
          normalizeName(sellerName.isNotEmpty ? sellerName : row.partyName);

      final rawMonth = row.month;
      final financialYear = financialYearFromMonthKey(rawMonth);
      final month = normalizeMonthKey(rawMonth);

      if (month.isEmpty || financialYear.isEmpty) continue;

      final sellerKey = resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final panDerivedFromGstin = row.panNumber.trim().isEmpty &&
          row.gstNo.trim().isNotEmpty &&
          sellerPan.isNotEmpty;

      if (panDerivedFromGstin) {
        gstDerivedPanHints['$sellerKey|$financialYear|$month'] = true;
      }
    }

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
      double fyPurchaseCumulative = 0.0;
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
          fyPurchaseCumulative = 0.0;
        }

        // Purchase rows without 26Q section should still use 194Q fallback
        // so cumulative threshold logic works correctly for purchase register data.
        final effectiveSection = _resolveEffectiveSection(tds?.section);

        final hasValidSection = _isUsableSection(effectiveSection);

        SectionRuleResult ruleResult;

        if (purchasePresent && hasValidSection) {
          final normalizedSection = effectiveSection.trim().toUpperCase();
          final previousOverallCumulative = fyPurchaseCumulative;
          final currentOverallCumulative =
              round2(previousOverallCumulative + basicAmount);
          fyPurchaseCumulative = currentOverallCumulative;

          final previousSectionCumulative =
              sectionWiseCumulative[normalizedSection] ?? 0.0;

          final currentSectionCumulative =
              round2(previousSectionCumulative + basicAmount);

          sectionWiseCumulative[normalizedSection] = currentSectionCumulative;

          ruleResult = SectionRuleService.applyRule(
            section: effectiveSection,
            cumulativePurchase: normalizedSection == '194Q'
                ? currentOverallCumulative
                : currentSectionCumulative,
            previousCumulative: normalizedSection == '194Q'
                ? previousOverallCumulative
                : previousSectionCumulative,
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

        final computedAmounts = ReconciliationEngine.buildComputedAmounts(
          rawApplicableAmount: ruleResult.applicableAmount,
          rawExpectedTds: ruleResult.expectedTds,
          rawDeductedAmount: tds?.deductedAmount ?? 0.0,
          rawActualTds: tds?.actualTds ?? 0.0,
        );
        final applicableAmount = computedAmounts.applicableAmount;
        final expectedTds = computedAmounts.expectedTds;
        final tdsRateUsed = ruleResult.rate;
        final normalizedEffectiveSection = effectiveSection.trim().toUpperCase();
        final calculationRemark = purchasePresent &&
                hasValidSection &&
                ruleResult.rate == 0 &&
                (normalizedEffectiveSection == '194C' ||
                    normalizedEffectiveSection == '194J' ||
                    normalizedEffectiveSection == '194I')
            ? 'Expected TDS not calculated due to missing subtype/context'
            : '';

        final actualTds = computedAmounts.actualTds;
        final amountDifference = computedAmounts.amountDifference;
        final tdsDifference = computedAmounts.tdsDifference;

        final sellerPan = _chooseSellerPan(
          purchasePan: purchase?.sellerPan ?? '',
          tdsPan: tds?.sellerPan ?? '',
          fallbackKey: sellerKey,
        );
        final isLowConfidenceMatch = sellerPan.trim().isEmpty;
        final panDerivedFromGstin =
            (purchase?.sellerPan ?? '').trim().isEmpty &&
            sellerPan.trim().isNotEmpty &&
            (gstDerivedPanHints['$sellerKey|$financialYear|$month'] ?? false);

        final sellerName = _chooseSellerName(
          purchaseName: purchase?.sellerName ?? '',
          tdsName: tds?.sellerName ?? '',
        );

        final statusAndRemarks = _buildStatusAndRemarks(
          sellerPan: sellerPan,
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          basicAmount: basicAmount,
          applicableAmount: applicableAmount,
          amountDifference: amountDifference,
          expectedTds: expectedTds,
          actualTds: actualTds,
          tdsDifference: tdsDifference,
          hasValidSection: hasValidSection,
          isLowConfidenceMatch: isLowConfidenceMatch,
          panDerivedFromGstin: panDerivedFromGstin,
        );

        sellerRows.add(
          ReconciliationEngine.buildRow(
            buyerName: buyerName,
            buyerPan: normalizedBuyerPan,
            financialYear: financialYear,
            month: month,
            sellerName: sellerName,
            sellerPan: sellerPan,
            section: effectiveSection.isNotEmpty ? effectiveSection : 'No Section',
            basicAmount: basicAmount,
            computedAmounts: computedAmounts,
            tdsRateUsed: tdsRateUsed,
            status: statusAndRemarks.status,
            remarks: statusAndRemarks.remarks,
            calculationRemark: calculationRemark,
            purchasePresent: purchasePresent,
            tdsPresent: tdsPresent,
          ),
        );
      }
      final timedRows = TimingService.applyTimingLogic(sellerRows)
          .map((row) => _applyBelowThresholdClassification(row))
          .toList();
      results.addAll(timedRows);
    }

    return _applyResolvedSellerNames(
      _mergeRowsWithUniquePanHints(results),
      sellerKeyResolver: sellerKeyResolver,
      resolvedSellerNameLookup: resolvedSellerNameLookup,
    );
  }

  static List<_SellerIdentity> _collectSellerIdentities({
    required List<PurchaseRow> purchaseRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
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

    return identities;
  }

  static List<_SellerIdentity> _collectNormalizedSellerIdentities({
    required List<NormalizedTransactionRow> sourceRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
  }) {
    final identities = <_SellerIdentity>[];

    for (final row in sourceRows) {
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

    return identities;
  }

  static Map<String, String> _buildResolvedSellerNameLookup({
    required List<_SellerIdentity> identities,
    required Map<String, String> sellerKeyResolver,
  }) {
    final choices = <String, _SellerNameChoice>{};

    void consider({
      required String sellerKey,
      required String candidateName,
      required int priority,
    }) {
      final trimmedName = candidateName.trim();
      if (sellerKey.isEmpty || trimmedName.isEmpty) return;

      final existing = choices[sellerKey];
      if (existing == null ||
          priority > existing.priority ||
          (priority == existing.priority &&
              trimmedName.length < existing.name.length)) {
        choices[sellerKey] = _SellerNameChoice(
          name: trimmedName,
          priority: priority,
        );
      }
    }

    for (final identity in identities) {
      final sellerKey = resolveSellerKey(
        sellerPan: identity.sellerPan,
        normalizedSellerName: identity.normalizedName,
        resolver: sellerKeyResolver,
      );
      if (sellerKey.isEmpty) continue;

      final originalName = identity.originalName.trim();
      final mappedName = identity.mappedName.trim();
      final resolvedName = mappedName.isNotEmpty ? mappedName : originalName;
      final isExplicitMapping = mappedName.isNotEmpty &&
          normalizeName(mappedName) != normalizeName(originalName);

      consider(
        sellerKey: sellerKey,
        candidateName: resolvedName,
        priority: isExplicitMapping ? 3 : 1,
      );
    }

    return {
      for (final entry in choices.entries) entry.key: entry.value.name,
    };
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

      if (pan.isNotEmpty) {
        dsu.add('PAN:$pan');
      }

      if (normName.isNotEmpty) {
        dsu.add('NAME:$normName');
      }

      // Keep seller-card identity PAN-first. When the same row has both
      // a PAN and a normalized seller name, they must resolve to one
      // canonical seller key; otherwise purchase can group by name while
      // 26Q groups by PAN and the UI shows two separate seller tables.
      if (pan.isNotEmpty && normName.isNotEmpty) {
        dsu.union('PAN:$pan', 'NAME:$normName');
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

  static Map<String, String> _buildSellerKeyResolverFromNormalized({
    required List<NormalizedTransactionRow> sourceRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
    required Map<String, String> savedAliasToPan,
  }) {
    final identities = <_SellerIdentity>[];

    for (final row in sourceRows) {
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

      if (pan.isNotEmpty) {
        dsu.add('PAN:$pan');
      }

      if (normName.isNotEmpty) {
        dsu.add('NAME:$normName');
      }

      if (pan.isNotEmpty && normName.isNotEmpty) {
        dsu.union('PAN:$pan', 'NAME:$normName');
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

  static String _resolveEffectiveSection(String? rawSection) {
    return (rawSection ?? '').trim();
  }

  static String _normalizeSupportedSection(String value) {
    final section = value.trim();
    return supportedSections.contains(section) ? section : '';
  }

  static String _sourceSection(NormalizedTransactionRow row) {
    return row.section.trim();
  }

  static bool _isUsableSection(String value) {
    final upper = value.trim().toUpperCase();
    if (upper.isEmpty) return false;
    if (upper == 'NO SECTION') return false;
    if (upper == 'UNKNOWN') return false;
    return true;
  }

  static Map<String, Map<String, _NormalizedSourceGroup>> _groupNormalizedSourceRows(
    List<NormalizedTransactionRow> rows,
    Map<String, String> nameMapping,
    Map<String, String> sellerKeyResolver,
  ) {
    final grouped = <String, Map<String, _NormalizedSourceGroup>>{};

    for (final row in rows) {
      final sellerPan = normalizePan(row.panNumber);
      final sellerName = applyNameMapping(row.partyName, nameMapping);
      final normalizedSellerName =
          normalizeName(sellerName.isNotEmpty ? sellerName : row.partyName);
      final rawMonth = row.month;
      final financialYear =
          row.financialYear.trim().isNotEmpty ? row.financialYear.trim() : financialYearFromMonthKey(rawMonth);
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
      final effectiveSellerPan = resolvedPan.isNotEmpty ? resolvedPan : sellerPan;
      final fyMonthKey = '$financialYear|$month';
      final baseAmount = round2(
        row.taxableAmount > 0 ? row.taxableAmount : row.amount,
      );
      final sourceAmount = round2(row.amount);

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;
      final existing = monthMap[fyMonthKey];

      if (existing == null) {
        monthMap[fyMonthKey] = _NormalizedSourceGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: effectiveSellerPan,
          basicAmount: baseAmount,
          sourceAmount: sourceAmount,
        );
      } else {
        monthMap[fyMonthKey] = _NormalizedSourceGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName.isNotEmpty ? sellerName : existing.sellerName,
          sellerPan: existing.sellerPan.isNotEmpty
              ? existing.sellerPan
              : effectiveSellerPan,
          basicAmount: round2(existing.basicAmount + baseAmount),
          sourceAmount: round2(existing.sourceAmount + sourceAmount),
        );
      }
    }

    return grouped;
  }

  static List<ReconciliationRow> _reconcileNormalizedSection({
    required String buyerName,
    required String buyerPan,
    required String section,
    required List<NormalizedTransactionRow> sourceRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
    required Map<String, String> sellerKeyResolver,
    required bool includeAllRows,
  }) {
    final purchaseGroups = _groupNormalizedSourceRows(
      sourceRows,
      nameMapping,
      sellerKeyResolver,
    );
    final tdsGroups = GroupingService.groupTdsRows(
      tdsRows,
      nameMapping,
      sellerKeyResolver,
    );

    final relevantSellerKeys = includeAllRows
        ? <String>{...purchaseGroups.keys, ...tdsGroups.keys}
        : GroupingService.getRelevantSellerKeys(
            purchaseGroups: {
              for (final entry in purchaseGroups.entries)
                entry.key: {
                  for (final monthEntry in entry.value.entries)
                    monthEntry.key: PurchaseGroup(
                      financialYear: monthEntry.value.financialYear,
                      month: monthEntry.value.month,
                      sellerName: monthEntry.value.sellerName,
                      sellerPan: monthEntry.value.sellerPan,
                      basicAmount: monthEntry.value.basicAmount,
                      billAmount: monthEntry.value.sourceAmount,
                    ),
                },
            },
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

      double fyPurchaseCumulative = 0.0;
      double sectionCumulative = 0.0;
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
          fyPurchaseCumulative = 0.0;
          sectionCumulative = 0.0;
        }

        final previousOverallCumulative = fyPurchaseCumulative;
        final previousSectionCumulative = sectionCumulative;
        fyPurchaseCumulative = round2(previousOverallCumulative + basicAmount);
        sectionCumulative = round2(previousSectionCumulative + basicAmount);

        final effectiveSection = _resolveEffectiveSection(section);
        final hasValidSection = _isUsableSection(effectiveSection);
        final ruleResult = purchasePresent && hasValidSection
            ? SectionRuleService.applyRule(
                section: effectiveSection,
                cumulativePurchase: effectiveSection == '194Q'
                    ? fyPurchaseCumulative
                    : sectionCumulative,
                previousCumulative: effectiveSection == '194Q'
                    ? previousOverallCumulative
                    : previousSectionCumulative,
                currentAmount: basicAmount,
                sectionCumulative: sectionCumulative,
                previousSectionCumulative: previousSectionCumulative,
              )
            : SectionRuleResult(
                applicableAmount: 0.0,
                expectedTds: 0.0,
                rate: 0.0,
              );

        final computedAmounts = ReconciliationEngine.buildComputedAmounts(
          rawApplicableAmount: ruleResult.applicableAmount,
          rawExpectedTds: ruleResult.expectedTds,
          rawDeductedAmount: tds?.deductedAmount ?? 0.0,
          rawActualTds: tds?.actualTds ?? 0.0,
        );
        final applicableAmount = computedAmounts.applicableAmount;
        final expectedTds = computedAmounts.expectedTds;
        final actualTds = computedAmounts.actualTds;
        final amountDifference = computedAmounts.amountDifference;
        final tdsDifference = computedAmounts.tdsDifference;
        final sellerPan = _chooseSellerPan(
          purchasePan: purchase?.sellerPan ?? '',
          tdsPan: tds?.sellerPan ?? '',
          fallbackKey: sellerKey,
        );
        final sellerName = _chooseSellerName(
          purchaseName: purchase?.sellerName ?? '',
          tdsName: tds?.sellerName ?? '',
        );

        final statusAndRemarks = _buildStatusAndRemarks(
          sellerPan: sellerPan,
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          basicAmount: basicAmount,
          applicableAmount: applicableAmount,
          amountDifference: amountDifference,
          expectedTds: expectedTds,
          actualTds: actualTds,
          tdsDifference: tdsDifference,
          hasValidSection: hasValidSection,
        );

        sellerRows.add(
          ReconciliationEngine.buildRow(
            buyerName: buyerName,
            buyerPan: buyerPan,
            financialYear: financialYear,
            month: month,
            sellerName: sellerName,
            sellerPan: sellerPan,
            section: effectiveSection.isNotEmpty ? effectiveSection : 'No Section',
            basicAmount: basicAmount,
            computedAmounts: computedAmounts,
            tdsRateUsed: ruleResult.rate,
            status: statusAndRemarks.status,
            remarks: statusAndRemarks.remarks,
            purchasePresent: purchasePresent,
            tdsPresent: tdsPresent,
          ),
        );
      }

      results.addAll(
        TimingService.applyTimingLogic(sellerRows)
            .map((row) => _applyBelowThresholdClassification(row))
            .toList(),
      );
    }

    return results;
  }

static ReconciliationStatusRemarks _buildStatusAndRemarks({
  required String sellerPan,
  required bool purchaseMissing,
  required bool tdsMissing,
  required double basicAmount,
  required double applicableAmount,
  required double amountDifference,
  required double expectedTds,
  required double actualTds,
  required double tdsDifference,
  required bool hasValidSection,
  bool isLowConfidenceMatch = false,
  bool panDerivedFromGstin = false,
}) {
  return ReconciliationEngine.buildStatusAndRemarks(
    sellerPan: sellerPan,
    purchaseMissing: purchaseMissing,
    tdsMissing: tdsMissing,
    basicAmount: basicAmount,
    applicableAmount: applicableAmount,
    amountDifference: amountDifference,
    expectedTds: expectedTds,
    actualTds: actualTds,
    tdsDifference: tdsDifference,
    hasValidSection: hasValidSection,
    amountTolerance: amountTolerance,
    tdsTolerance: tdsTolerance,
    minorTdsTolerance: minorTdsTolerance,
    isLowConfidenceMatch: isLowConfidenceMatch,
    panDerivedFromGstin: panDerivedFromGstin,
  );
}

  static String _chooseSellerName({
    required String purchaseName,
    required String tdsName,
  }) {
    return ReconciliationEngine.chooseSellerName(
      purchaseName: purchaseName,
      tdsName: tdsName,
    );
  }

  static String _chooseSellerPan({
    required String purchasePan,
    required String tdsPan,
    required String fallbackKey,
  }) {
    return ReconciliationEngine.chooseSellerPan(
      purchasePan: purchasePan,
      tdsPan: tdsPan,
      fallbackKey: fallbackKey,
    );
  }

  static List<ReconciliationRow> _applyResolvedSellerNames(
    List<ReconciliationRow> rows, {
    required Map<String, String> sellerKeyResolver,
    required Map<String, String> resolvedSellerNameLookup,
  }) {
    return rows.map((row) {
      final sellerKey = resolveSellerKey(
        sellerPan: normalizePan(row.sellerPan),
        normalizedSellerName: normalizeName(row.sellerName),
        resolver: sellerKeyResolver,
      );
      final resolvedSellerName = resolvedSellerNameLookup[sellerKey]?.trim() ?? '';

      if (resolvedSellerName.isEmpty ||
          resolvedSellerName == row.sellerName.trim()) {
        return row;
      }

      return row.copyWith(sellerName: resolvedSellerName);
    }).toList();
  }

  static ReconciliationRow _applyBelowThresholdClassification(
    ReconciliationRow row,
  ) {
    return ReconciliationEngine.applyBelowThresholdClassification(
      row,
      amountTolerance: amountTolerance,
      tdsTolerance: tdsTolerance,
    );
  }

  static List<ReconciliationRow> _mergeRowsWithUniquePanHints(
    List<ReconciliationRow> rows,
  ) {
    final normalizedNameToPans = <String, Set<String>>{};
    for (final row in rows) {
      final normalizedName = normalizeName(row.sellerName);
      final normalizedPan = normalizePan(row.sellerPan);
      if (normalizedName.isEmpty || normalizedPan.isEmpty) continue;
      normalizedNameToPans.putIfAbsent(normalizedName, () => <String>{});
      normalizedNameToPans[normalizedName]!.add(normalizedPan);
    }

    final mergedRows = rows.map((row) {
      final normalizedName = normalizeName(row.sellerName);
      final normalizedPan = normalizePan(row.sellerPan);

      if (normalizedName.isEmpty || normalizedPan.isNotEmpty) {
        return row;
      }

      final candidatePans = normalizedNameToPans[normalizedName] ?? const <String>{};
      if (candidatePans.length != 1) {
        return row;
      }

      return row.copyWith(sellerPan: candidatePans.first);
    }).toList();

    mergedRows.sort((a, b) {
      final sectionCompare = _normalizeSupportedSection(a.section)
          .compareTo(_normalizeSupportedSection(b.section));
      if (sectionCompare != 0) return sectionCompare;

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

    return mergedRows;
  }

  static ReconciliationSummary _buildSummary({
    required String section,
    required List<ReconciliationRow> rows,
  }) {
    final mismatchRows = rows
        .where((row) => row.status.trim().toUpperCase() != 'MATCHED')
        .length;
    final applicableButNo26QRows = rows
        .where(
          (row) =>
              row.applicableAmount > 0 &&
              row.tds26QAmount == 0 &&
              row.actualTds == 0,
        )
        .length;

    return ReconciliationSummary(
      section: section,
      totalRows: rows.length,
      matchedRows: rows.where((row) => row.status == 'Matched').length,
      mismatchRows: mismatchRows,
      purchaseOnlyRows: rows.where((row) => row.status == 'Purchase Only').length,
      only26QRows: rows.where((row) => row.status == 'Only in 26Q').length,
      applicableButNo26QRows: applicableButNo26QRows,
      sourceAmount: rows.fold(0.0, (sum, row) => sum + row.basicAmount),
      applicableAmount: rows.fold(0.0, (sum, row) => sum + row.applicableAmount),
      tds26QAmount: rows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
      expectedTds: rows.fold(0.0, (sum, row) => sum + row.expectedTds),
      actualTds: rows.fold(0.0, (sum, row) => sum + row.actualTds),
      amountDifference: rows.fold(0.0, (sum, row) => sum + row.amountDifference),
      tdsDifference: rows.fold(0.0, (sum, row) => sum + row.tdsDifference),
    );
  }

  static ReconciliationSummary _sumSectionSummaries(
    Map<String, ReconciliationSummary> summaries,
  ) {
    return ReconciliationSummary(
      section: 'ALL',
      totalRows: summaries.values.fold(0, (sum, item) => sum + item.totalRows),
      matchedRows:
          summaries.values.fold(0, (sum, item) => sum + item.matchedRows),
      mismatchRows:
          summaries.values.fold(0, (sum, item) => sum + item.mismatchRows),
      purchaseOnlyRows:
          summaries.values.fold(0, (sum, item) => sum + item.purchaseOnlyRows),
      only26QRows:
          summaries.values.fold(0, (sum, item) => sum + item.only26QRows),
      applicableButNo26QRows: summaries.values.fold(
        0,
        (sum, item) => sum + item.applicableButNo26QRows,
      ),
      sourceAmount:
          summaries.values.fold(0.0, (sum, item) => sum + item.sourceAmount),
      applicableAmount: summaries.values.fold(
        0.0,
        (sum, item) => sum + item.applicableAmount,
      ),
      tds26QAmount:
          summaries.values.fold(0.0, (sum, item) => sum + item.tds26QAmount),
      expectedTds:
          summaries.values.fold(0.0, (sum, item) => sum + item.expectedTds),
      actualTds:
          summaries.values.fold(0.0, (sum, item) => sum + item.actualTds),
      amountDifference: summaries.values.fold(
        0.0,
        (sum, item) => sum + item.amountDifference,
      ),
      tdsDifference:
          summaries.values.fold(0.0, (sum, item) => sum + item.tdsDifference),
    );
  }

  static String _unknownSectionLabel(String? value) {
    final resolved = _resolveSectionFromRaw(value);
    if (resolved.isNotEmpty && !supportedSections.contains(resolved)) {
      return resolved;
    }

    final normalized = normalizeSection(value ?? '');
    if (normalized.isNotEmpty && !supportedSections.contains(normalized)) {
      return normalized;
    }

    return 'UNKNOWN';
  }

}
