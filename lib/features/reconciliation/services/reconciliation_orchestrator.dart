import 'package:flutter/foundation.dart';

import 'package:reconciliation_app/core/utils/date_utils.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/parse_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/purchase_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_debug_info.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_summary.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/resolved_seller_identity.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/skipped_row_summary.dart';

import 'reconciliation_engine.dart';
import 'section_rule_service.dart';
import 'seller_identity_resolver.dart';
import 'seller_mapping_service.dart';
import 'timing_service.dart';

part 'reconciliation_service_debug_helpers.dart';

class SectionReconciliationResult {
  final List<ReconciliationRow> rows;
  final ReconciliationSummary combinedSummary;
  final Map<String, ReconciliationSummary> sectionSummaries;
  final Map<String, List<ReconciliationRow>> rowsBySection;
  final SkippedRowSummary skippedRowSummary;

  const SectionReconciliationResult({
    required this.rows,
    required this.combinedSummary,
    required this.sectionSummaries,
    required this.rowsBySection,
    this.skippedRowSummary = SkippedRowSummary.empty,
  });
}

class SellerLevelStatusSnapshot {
  final String status;
  final int rowCount;
  final double totalBasic;
  final double totalApplicable;
  final double total26Q;
  final double totalExpected;
  final double totalActual;
  final double totalAmountDifference;
  final double totalTdsDifference;

  const SellerLevelStatusSnapshot({
    required this.status,
    required this.rowCount,
    required this.totalBasic,
    required this.totalApplicable,
    required this.total26Q,
    required this.totalExpected,
    required this.totalActual,
    required this.totalAmountDifference,
    required this.totalTdsDifference,
  });
}

class _PurchaseComputation {
  final _ResolvedSourceRow source;
  final double basicAmount;
  final double applicableAmount;
  final double expectedTds;
  final double tdsRateUsed;
  final double cumulativeBefore;
  final double cumulativeAfter;
  final bool thresholdCrossed;
  final bool manualReviewRequired;
  final String manualReviewReason;
  final String applicableAmountReason;
  final String expectedTdsReason;

  const _PurchaseComputation({
    required this.source,
    required this.basicAmount,
    required this.applicableAmount,
    required this.expectedTds,
    required this.tdsRateUsed,
    required this.cumulativeBefore,
    required this.cumulativeAfter,
    required this.thresholdCrossed,
    required this.manualReviewRequired,
    required this.manualReviewReason,
    required this.applicableAmountReason,
    required this.expectedTdsReason,
  });
}

class _ResolvedSourceRow {
  final String sourceType;
  final String buyerPan;
  final String originalSellerName;
  final String mappedSellerName;
  final String normalizedSellerName;
  final String originalPan;
  final String financialYear;
  final String month;
  final DateTime chronologyDate;
  final String section;
  final double amount;
  final double tdsAmount;
  final ResolvedSellerIdentity identity;

  const _ResolvedSourceRow({
    required this.sourceType,
    required this.buyerPan,
    required this.originalSellerName,
    required this.mappedSellerName,
    required this.normalizedSellerName,
    required this.originalPan,
    required this.financialYear,
    required this.month,
    required this.chronologyDate,
    required this.section,
    required this.amount,
    required this.tdsAmount,
    required this.identity,
  });
}

class _MonthlyPurchaseBucket {
  final ResolvedSellerIdentity identity;
  final String financialYear;
  final String month;
  final String section;
  double basicAmount = 0.0;
  double applicableAmount = 0.0;
  double expectedTds = 0.0;
  double tdsRateUsed = 0.0;
  double cumulativeBefore = 0.0;
  double cumulativeAfter = 0.0;
  bool thresholdCrossed = false;
  bool manualReviewRequired = false;
  String manualReviewReason = '';
  final Set<String> originalSellerNames = <String>{};
  final Set<String> normalizedSellerNames = <String>{};
  final Set<String> originalPans = <String>{};
  final Set<String> applicableReasons = <String>{};
  final Set<String> expectedReasons = <String>{};
  final Set<String> identityFlags = <String>{};

  _MonthlyPurchaseBucket({
    required this.identity,
    required this.financialYear,
    required this.month,
    required this.section,
  });
}

class _MonthlyTdsBucket {
  final ResolvedSellerIdentity identity;
  final String financialYear;
  final String month;
  final String section;
  double deductedAmount = 0.0;
  double actualTds = 0.0;
  final Set<String> originalSellerNames = <String>{};
  final Set<String> normalizedSellerNames = <String>{};
  final Set<String> originalPans = <String>{};

  _MonthlyTdsBucket({
    required this.identity,
    required this.financialYear,
    required this.month,
    required this.section,
  });
}

class _MonthlyBucketKey {
  final String resolvedSellerId;
  final String financialYear;
  final String section;
  final String month;

  const _MonthlyBucketKey({
    required this.resolvedSellerId,
    required this.financialYear,
    required this.section,
    required this.month,
  });

  @override
  bool operator ==(Object other) {
    return other is _MonthlyBucketKey &&
        other.resolvedSellerId == resolvedSellerId &&
        other.financialYear == financialYear &&
        other.section == section &&
        other.month == month;
  }

  @override
  int get hashCode => Object.hash(
    resolvedSellerId,
    financialYear,
    section,
    month,
  );
}

class _SkippedRowAccumulator {
  static const int _maxSamples = 5;

  final Map<String, int> _reasonCounts = <String, int>{};
  final List<SkippedRowSample> _samples = <SkippedRowSample>[];
  int _total = 0;

  void add({
    required String sourceType,
    required String reason,
    required String sellerName,
    required String month,
  }) {
    _total += 1;
    _reasonCounts[reason] = (_reasonCounts[reason] ?? 0) + 1;

    if (_samples.length < _maxSamples) {
      _samples.add(
        SkippedRowSample(
          sourceType: sourceType,
          reason: reason,
          sellerName: sellerName.trim(),
          month: month.trim(),
        ),
      );
    }
  }

  SkippedRowSummary build() {
    final sortedCounts = _reasonCounts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return a.key.compareTo(b.key);
      });

    return SkippedRowSummary(
      total: _total,
      reasonCounts: {
        for (final entry in sortedCounts) entry.key: entry.value,
      },
      samples: List<SkippedRowSample>.unmodifiable(_samples),
    );
  }
}

class CalculationService {
  static const double threshold = 5000000.0;
  static const double amountTolerance = 1.0;
  static const double tdsTolerance = 1.0;
  static const double minorTdsTolerance = 5.0;
  static const String sellerStatusMatched = ReconciliationStatus.matched;
  static const String sellerStatusMismatch = 'Mismatch';
  static const String sellerStatusNo26Q = 'No 26Q';
  static const String sellerStatusOnly26Q = 'Only 26Q';
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
    final normalizedMapping = _normalizeNameMapping(nameMapping ?? {});
    final skippedRows = _SkippedRowAccumulator();
    final activeSections = (sections ?? supportedSections)
        .map(_normalizeSupportedSection)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final savedMappings = await SellerMappingService.getAllMappings(normalizedBuyerPan);
    final savedAliasToPan = <String, String>{
      for (final mapping in savedMappings)
        if (normalizeSellerMappingSectionCode(mapping.sectionCode) == 'ALL')
        normalizeName(mapping.aliasName): normalizePan(mapping.mappedPan),
    };

    final observations = <SellerIdentityObservation>[
      ...sourceRows.map(
        (row) => SellerIdentityObservation(
          originalName: row.partyName,
          mappedName: _applyNameMapping(row.partyName, normalizedMapping),
          normalizedName: _normalizeSellerName(row.partyName, normalizedMapping),
          originalPan: row.panNumber,
          normalizedPan: normalizePan(row.panNumber),
        ),
      ),
      ...tdsRows.map(
        (row) => SellerIdentityObservation(
          originalName: row.deducteeName,
          mappedName: _applyNameMapping(row.deducteeName, normalizedMapping),
          normalizedName: _normalizeSellerName(row.deducteeName, normalizedMapping),
          originalPan: row.panNumber,
          normalizedPan: normalizePan(row.panNumber),
        ),
      ),
    ];

    final resolver = SellerIdentityResolver.build(
      observations: observations,
      savedMappings: savedMappings,
      savedAliasToPan: savedAliasToPan,
    );

    final resolvedPurchases = sourceRows
        .map(
          (row) => _resolvePurchaseRow(
            buyerPan: normalizedBuyerPan,
            row: row,
            nameMapping: normalizedMapping,
            resolver: resolver,
            skippedRows: skippedRows,
          ),
        )
        .whereType<_ResolvedSourceRow>()
        .toList();

    final resolvedTdsRows = tdsRows
        .map(
          (row) => _resolveTdsRow(
            buyerPan: normalizedBuyerPan,
            row: row,
            nameMapping: normalizedMapping,
            resolver: resolver,
            skippedRows: skippedRows,
          ),
        )
        .whereType<_ResolvedSourceRow>()
        .toList();

    debugPrint(
      'SECTION RECON SOURCE ROWS => '
      '${_debugSectionCounts(_debugResolvedSectionCounts(resolvedPurchases))}',
    );
    debugPrint(
      'SECTION RECON 26Q ROWS => '
      '${_debugSectionCounts(_debugResolvedSectionCounts(resolvedTdsRows))}',
    );

    final purchaseBuckets = _aggregatePurchaseBuckets(resolvedPurchases);
    final tdsBuckets = _aggregateTdsBuckets(resolvedTdsRows);
    final allKeys = <_MonthlyBucketKey>{
      ...purchaseBuckets.keys,
      ...tdsBuckets.keys,
    }.toList()
      ..sort(_compareMonthlyBucketKeys);

    final rows = <ReconciliationRow>[];
    for (final key in allKeys) {
      final purchase = purchaseBuckets[key];
      final tds = tdsBuckets[key];

      if (!includeAllRows &&
          purchase == null &&
          tds == null) {
        continue;
      }

      final row = _buildReconciliationRow(
        buyerName: buyerName,
        buyerPan: normalizedBuyerPan,
        key: key,
        purchase: purchase,
        tds: tds,
      );

      rows.add(row);
    }

    final timedRows = _applyTimingBySeller(rows);
    final rowsBySection = _groupRowsBySection(timedRows);
    final sectionSummaries = <String, ReconciliationSummary>{};
    for (final entry in rowsBySection.entries) {
      final section = entry.key;
      if (activeSections.isNotEmpty &&
          !activeSections.contains(section) &&
          supportedSections.contains(section)) {
        continue;
      }
      sectionSummaries[section] = _buildSummary(
        section: section,
        rows: entry.value,
      );
    }

    debugPrint(
      'SECTION RECON FINAL SUMMARIES => ${_debugSummaryMap(sectionSummaries)}',
    );

    return SectionReconciliationResult(
      rows: timedRows,
      combinedSummary: _buildSummary(section: 'ALL', rows: timedRows),
      sectionSummaries: sectionSummaries,
      rowsBySection: rowsBySection,
      skippedRowSummary: skippedRows.build(),
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
    final normalizedRows = purchaseRows
        .map(NormalizedTransactionRow.fromPurchaseRow)
        .toList();
    final result = await reconcileSectionWise(
      buyerName: buyerName,
      buyerPan: buyerPan,
      sourceRows: normalizedRows,
      tdsRows: tdsRows,
      nameMapping: nameMapping,
      includeAllRows: includeAllRows,
      sections: supportedSections,
    );
    return result.rows;
  }

  static SellerLevelStatusSnapshot buildSellerLevelStatus(
    List<ReconciliationRow> rows,
  ) {
    final totalBasic = round2(
      rows.fold(0.0, (sum, row) => sum + row.basicAmount),
    );
    final totalApplicable = round2(
      rows.fold(0.0, (sum, row) => sum + row.applicableAmount),
    );
    final total26Q = round2(
      rows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
    );
    final totalExpected = round2(
      rows.fold(0.0, (sum, row) => sum + row.expectedTds),
    );
    final totalActual = round2(
      rows.fold(0.0, (sum, row) => sum + row.actualTds),
    );
    final totalAmountDifference = round2(
      rows.fold(0.0, (sum, row) => sum + row.amountDifference),
    );
    final totalTdsDifference = round2(
      rows.fold(0.0, (sum, row) => sum + row.tdsDifference),
    );

    final hasMeaningfulPurchaseSide =
        totalApplicable.abs() > amountTolerance ||
        totalExpected.abs() > minorTdsTolerance;
    final hasMeaningful26QSide =
        total26Q.abs() > amountTolerance ||
        totalActual.abs() > minorTdsTolerance;

    final status = () {
      if (hasMeaningful26QSide && !hasMeaningfulPurchaseSide) {
        return sellerStatusOnly26Q;
      }
      if (hasMeaningfulPurchaseSide && !hasMeaningful26QSide) {
        return sellerStatusNo26Q;
      }
      if (isSellerLevelMatched(
        amountDifference: totalAmountDifference,
        tdsDifference: totalTdsDifference,
      )) {
        return sellerStatusMatched;
      }
      return sellerStatusMismatch;
    }();

    return SellerLevelStatusSnapshot(
      status: status,
      rowCount: rows.length,
      totalBasic: totalBasic,
      totalApplicable: totalApplicable,
      total26Q: total26Q,
      totalExpected: totalExpected,
      totalActual: totalActual,
      totalAmountDifference: totalAmountDifference,
      totalTdsDifference: totalTdsDifference,
    );
  }

  static bool isSellerLevelMatched({
    required double amountDifference,
    required double tdsDifference,
  }) {
    return amountDifference.abs() <= amountTolerance &&
        tdsDifference.abs() <= minorTdsTolerance;
  }

  static _ResolvedSourceRow? _resolvePurchaseRow({
    required String buyerPan,
    required NormalizedTransactionRow row,
    required Map<String, String> nameMapping,
    required SellerIdentityResolver resolver,
    required _SkippedRowAccumulator skippedRows,
  }) {
    final mappedName = _applyNameMapping(row.partyName, nameMapping);
    final normalizedName = _normalizeSellerName(row.partyName, nameMapping);
    final month = row.normalizedMonth.trim().isNotEmpty
        ? row.normalizedMonth.trim()
        : normalizeMonth(row.month);
    final financialYear = row.financialYear.trim().isNotEmpty
        ? row.financialYear.trim()
        : financialYearFromMonthKey(month);
    final section = _normalizeSourceSection(row.section, row.normalizedSection);
    final amount = round2(row.taxableAmount > 0 ? row.taxableAmount : row.amount);

    if (month.isEmpty || financialYear.isEmpty) {
      skippedRows.add(
        sourceType: row.sourceType,
        reason: 'Missing month',
        sellerName: row.partyName,
        month: row.month,
      );
      return null;
    }

    if (amount == 0.0) {
      skippedRows.add(
        sourceType: row.sourceType,
        reason: 'Missing required numeric data',
        sellerName: row.partyName,
        month: row.month,
      );
      return null;
    }

    final identity = resolver.resolve(
      buyerPan: buyerPan,
      originalName: row.partyName,
      mappedName: mappedName,
      originalPan: row.panNumber,
      sectionCode: section,
    );

    return _ResolvedSourceRow(
      sourceType: row.sourceType,
      buyerPan: buyerPan,
      originalSellerName: row.partyName,
      mappedSellerName: mappedName,
      normalizedSellerName: normalizedName,
      originalPan: row.panNumber,
      financialYear: financialYear,
      month: month,
      chronologyDate: _resolveChronologyDate(row.transactionDateRaw, month),
      section: section,
      amount: amount,
      tdsAmount: 0.0,
      identity: identity,
    );
  }

  static _ResolvedSourceRow? _resolveTdsRow({
    required String buyerPan,
    required Tds26QRow row,
    required Map<String, String> nameMapping,
    required SellerIdentityResolver resolver,
    required _SkippedRowAccumulator skippedRows,
  }) {
    final mappedName = _applyNameMapping(row.deducteeName, nameMapping);
    final normalizedName = _normalizeSellerName(row.deducteeName, nameMapping);
    final month = row.normalizedMonth.trim().isNotEmpty
        ? row.normalizedMonth.trim()
        : normalizeMonth(row.month);
    final financialYear = row.financialYear.trim().isNotEmpty
        ? row.financialYear.trim()
        : financialYearFromMonthKey(month);
    final section = _normalizeTdsSection(row.section);

    if (month.isEmpty || financialYear.isEmpty) {
      skippedRows.add(
        sourceType: 'tds26q',
        reason: 'Missing month',
        sellerName: row.deducteeName,
        month: row.month,
      );
      return null;
    }

    final identity = resolver.resolve(
      buyerPan: buyerPan,
      originalName: row.deducteeName,
      mappedName: mappedName,
      originalPan: row.panNumber,
      sectionCode: section,
    );

    return _ResolvedSourceRow(
      sourceType: 'tds26q',
      buyerPan: buyerPan,
      originalSellerName: row.deducteeName,
      mappedSellerName: mappedName,
      normalizedSellerName: normalizedName,
      originalPan: row.panNumber,
      financialYear: financialYear,
      month: month,
      chronologyDate: _resolveChronologyDate(row.month, month),
      section: section,
      amount: round2(row.deductedAmount),
      tdsAmount: round2(row.tds),
      identity: identity,
    );
  }

  static Map<_MonthlyBucketKey, _MonthlyPurchaseBucket> _aggregatePurchaseBuckets(
    List<_ResolvedSourceRow> rows,
  ) {
    final groupedBySellerFy = <String, List<_ResolvedSourceRow>>{};
    for (final row in rows) {
      final key =
          '${row.buyerPan}|${row.identity.resolvedSellerId}|${row.financialYear}';
      groupedBySellerFy.putIfAbsent(key, () => <_ResolvedSourceRow>[]).add(row);
    }

    final buckets = <_MonthlyBucketKey, _MonthlyPurchaseBucket>{};
    for (final entries in groupedBySellerFy.values) {
      entries.sort(_compareResolvedSourceRows);
      double cumulative194Q = 0.0;
      final sectionTotals = <String, double>{};

      for (final entry in entries) {
        final normalizedSection = _normalizeSupportedSection(entry.section);
        final sectionKey = normalizedSection.isNotEmpty ? normalizedSection : entry.section;
        final previousOverall = cumulative194Q;
        final previousSection = sectionTotals[sectionKey] ?? 0.0;
        final nextOverall = normalizedSection == '194Q'
            ? round2(previousOverall + entry.amount)
            : previousOverall;
        final nextSection = round2(previousSection + entry.amount);

        final rule = normalizedSection.isNotEmpty
            ? SectionRuleService.applyRule(
                section: normalizedSection,
                cumulativePurchase:
                    normalizedSection == '194Q' ? nextOverall : nextSection,
                previousCumulative:
                    normalizedSection == '194Q' ? previousOverall : previousSection,
                currentAmount: entry.amount,
                sectionCumulative: nextSection,
                previousSectionCumulative: previousSection,
                sellerPan: entry.identity.resolvedPan.isNotEmpty
                    ? entry.identity.resolvedPan
                    : entry.originalPan,
              )
            : SectionRuleResult(
                applicableAmount: 0.0,
                expectedTds: 0.0,
                rate: 0.0,
              );

        if (normalizedSection == '194Q') {
          cumulative194Q = nextOverall;
        }
        sectionTotals[sectionKey] = nextSection;

        final computation = _PurchaseComputation(
          source: entry,
          basicAmount: entry.amount,
          applicableAmount: round2(rule.applicableAmount),
          expectedTds: round2(rule.expectedTds),
          tdsRateUsed: rule.rate,
          cumulativeBefore: normalizedSection == '194Q' ? previousOverall : previousSection,
          cumulativeAfter: normalizedSection == '194Q' ? nextOverall : nextSection,
          thresholdCrossed: normalizedSection == '194Q'
              ? previousOverall < threshold && nextOverall > threshold
              : previousSection < nextSection && rule.applicableAmount > 0,
          manualReviewRequired: rule.manualReviewRequired,
          manualReviewReason: rule.reviewReason,
          applicableAmountReason: _buildApplicableReason(
            section: entry.section,
            amount: entry.amount,
            previousCumulative:
                normalizedSection == '194Q' ? previousOverall : previousSection,
            currentCumulative:
                normalizedSection == '194Q' ? nextOverall : nextSection,
            applicableAmount: round2(rule.applicableAmount),
          ),
          expectedTdsReason: _buildExpectedTdsReason(
            section: entry.section,
            expectedTds: round2(rule.expectedTds),
            rate: rule.rate,
            applicableAmount: round2(rule.applicableAmount),
            manualReviewRequired: rule.manualReviewRequired,
            manualReviewReason: rule.reviewReason,
          ),
        );

        final bucketKey = _MonthlyBucketKey(
          resolvedSellerId: entry.identity.resolvedSellerId,
          financialYear: entry.financialYear,
          section: entry.section,
          month: entry.month,
        );
        final bucket = buckets.putIfAbsent(
          bucketKey,
          () => _MonthlyPurchaseBucket(
            identity: entry.identity,
            financialYear: entry.financialYear,
            month: entry.month,
            section: entry.section,
          ),
        );
        _mergePurchaseBucket(bucket, computation);
      }
    }

    return buckets;
  }

  static Map<_MonthlyBucketKey, _MonthlyTdsBucket> _aggregateTdsBuckets(
    List<_ResolvedSourceRow> rows,
  ) {
    final buckets = <_MonthlyBucketKey, _MonthlyTdsBucket>{};
    for (final entry in rows) {
      final key = _MonthlyBucketKey(
        resolvedSellerId: entry.identity.resolvedSellerId,
        financialYear: entry.financialYear,
        section: entry.section,
        month: entry.month,
      );
      final bucket = buckets.putIfAbsent(
        key,
        () => _MonthlyTdsBucket(
          identity: entry.identity,
          financialYear: entry.financialYear,
          month: entry.month,
          section: entry.section,
        ),
      );
      bucket.deductedAmount = round2(bucket.deductedAmount + entry.amount);
      bucket.actualTds = round2(bucket.actualTds + entry.tdsAmount);
      bucket.originalSellerNames.add(entry.originalSellerName.trim());
      bucket.normalizedSellerNames.add(entry.normalizedSellerName);
      final normalizedPan = normalizePan(entry.originalPan);
      if (normalizedPan.isNotEmpty) {
        bucket.originalPans.add(normalizedPan);
      }
    }
    return buckets;
  }

  static ReconciliationRow _buildReconciliationRow({
    required String buyerName,
    required String buyerPan,
    required _MonthlyBucketKey key,
    required _MonthlyPurchaseBucket? purchase,
    required _MonthlyTdsBucket? tds,
  }) {
    final identity = purchase?.identity ?? tds!.identity;
    final rawActualTds = tds == null ? 0.0 : tds.actualTds;
    final rawDeductedAmount = tds == null ? 0.0 : tds.deductedAmount;

    final computedAmounts = ReconciliationEngine.buildComputedAmounts(
      rawApplicableAmount: purchase?.applicableAmount ?? 0.0,
      rawExpectedTds: purchase?.expectedTds ?? 0.0,
      rawDeductedAmount: rawDeductedAmount,
      rawActualTds: rawActualTds,
    );

    final statusAndRemarks = ReconciliationEngine.buildStatusAndRemarks(
      section: key.section,
      sellerPan: identity.resolvedPan,
      purchaseMissing: purchase == null,
      tdsMissing: tds == null,
      basicAmount: purchase?.basicAmount ?? 0.0,
      applicableAmount: computedAmounts.applicableAmount,
      amountDifference: computedAmounts.amountDifference,
      expectedTds: computedAmounts.expectedTds,
      actualTds: computedAmounts.actualTds,
      tdsDifference: computedAmounts.tdsDifference,
      hasValidSection: _isUsableSection(key.section),
      amountTolerance: amountTolerance,
      tdsTolerance: tdsTolerance,
      minorTdsTolerance: minorTdsTolerance,
      manualReviewRequired: purchase?.manualReviewRequired ?? false,
      manualReviewReason: purchase?.manualReviewReason ?? '',
      isLowConfidenceMatch: identity.identityConfidence < 0.75,
    );

    final remarks = <String>[
      statusAndRemarks.remarks.trim(),
      if (identity.identityNotes.trim().isNotEmpty) identity.identityNotes.trim(),
    ].where((value) => value.isNotEmpty).join(', ');

    final finalStatusReason = _buildFinalStatusReason(
      status: statusAndRemarks.status,
      purchase: purchase,
      tds: tds,
      amountDifference: computedAmounts.amountDifference,
      tdsDifference: computedAmounts.tdsDifference,
    );

    return ReconciliationEngine.applyBelowThresholdClassification(
      ReconciliationRow(
        buyerName: buyerName,
        buyerPan: buyerPan,
        financialYear: key.financialYear,
        month: key.month,
        sellerName: identity.resolvedSellerName,
        sellerPan: identity.resolvedPan,
        section: key.section,
        resolvedSellerId: identity.resolvedSellerId,
        resolvedSellerName: identity.resolvedSellerName,
        resolvedPan: identity.resolvedPan,
        identitySource: identity.identitySource,
        identityConfidence: identity.identityConfidence,
        identityNotes: identity.identityNotes,
        basicAmount: round2(purchase?.basicAmount ?? 0.0),
        applicableAmount: computedAmounts.applicableAmount,
        tds26QAmount: computedAmounts.deductedAmount,
        expectedTds: computedAmounts.expectedTds,
        actualTds: computedAmounts.actualTds,
        tdsRateUsed: purchase?.tdsRateUsed ?? 0.0,
        amountDifference: computedAmounts.amountDifference,
        tdsDifference: computedAmounts.tdsDifference,
        status: statusAndRemarks.status,
        remarks: remarks,
        calculationRemark: <String>[
          purchase == null
              ? ''
              : purchase.expectedReasons.where((value) => value.isNotEmpty).join(', '),
        ].where((value) => value.isNotEmpty).join(', '),
        purchasePresent: purchase != null,
        tdsPresent: tds != null,
        openingTimingBalance: 0.0,
        monthTdsDifference: computedAmounts.monthTdsDifference,
        closingTimingBalance: 0.0,
        debugInfo: ReconciliationDebugInfo(
          originalSellerNames: _sortedValues(
            <String>{
              ...?purchase?.originalSellerNames,
              ...?tds?.originalSellerNames,
            },
          ),
          normalizedSellerNames: _sortedValues(
            <String>{
              ...?purchase?.normalizedSellerNames,
              ...?tds?.normalizedSellerNames,
            },
          ),
          originalPans: _sortedValues(
            <String>{
              ...?purchase?.originalPans,
              ...?tds?.originalPans,
            },
          ),
          resolvedSellerId: identity.resolvedSellerId,
          resolvedIdentitySource: identity.identitySource,
          section: key.section,
          financialYear: key.financialYear,
          cumulativePurchaseBeforeRow: purchase?.cumulativeBefore ?? 0.0,
          cumulativePurchaseAfterRow: purchase?.cumulativeAfter ?? 0.0,
          thresholdCrossed: purchase?.thresholdCrossed ?? false,
          applicableAmountReason: purchase == null
              ? 'No purchase row for this seller/FY/section/month bucket.'
              : purchase.applicableReasons.where((value) => value.isNotEmpty).join(', '),
          expectedTdsReason: purchase == null
              ? 'Expected TDS is zero because there is no purchase row in this bucket.'
              : purchase.expectedReasons.where((value) => value.isNotEmpty).join(', '),
          finalStatusReason: finalStatusReason,
          mappingAttempted: identity.mappingAttempted,
          mappingSectionUsed: identity.mappingSectionUsed,
          mappingHit: identity.mappingHit,
          identityFlags: _sortedValues(identity.identityFlags.toSet()
            ..addAll(purchase?.identityFlags ?? const <String>{})),
          identityNotes: identity.identityNotes,
        ),
      ),
      amountTolerance: amountTolerance,
      tdsTolerance: tdsTolerance,
      manualReviewRequired: purchase?.manualReviewRequired ?? false,
    );
  }

  static void _mergePurchaseBucket(
    _MonthlyPurchaseBucket bucket,
    _PurchaseComputation computation,
  ) {
    bucket.basicAmount = round2(bucket.basicAmount + computation.basicAmount);
    bucket.applicableAmount =
        round2(bucket.applicableAmount + computation.applicableAmount);
    bucket.expectedTds = round2(bucket.expectedTds + computation.expectedTds);
    bucket.tdsRateUsed = computation.tdsRateUsed > 0
        ? computation.tdsRateUsed
        : bucket.tdsRateUsed;
    bucket.cumulativeBefore = bucket.basicAmount == computation.basicAmount
        ? computation.cumulativeBefore
        : bucket.cumulativeBefore;
    bucket.cumulativeAfter = computation.cumulativeAfter;
    bucket.thresholdCrossed = bucket.thresholdCrossed || computation.thresholdCrossed;
    bucket.manualReviewRequired =
        bucket.manualReviewRequired || computation.manualReviewRequired;
    if (bucket.manualReviewReason.trim().isEmpty &&
        computation.manualReviewReason.trim().isNotEmpty) {
      bucket.manualReviewReason = computation.manualReviewReason.trim();
    }
    bucket.originalSellerNames.add(computation.source.originalSellerName.trim());
    bucket.normalizedSellerNames.add(computation.source.normalizedSellerName);
    final originalPan = normalizePan(computation.source.originalPan);
    if (originalPan.isNotEmpty) {
      bucket.originalPans.add(originalPan);
    }
    if (computation.applicableAmountReason.trim().isNotEmpty) {
      bucket.applicableReasons.add(computation.applicableAmountReason.trim());
    }
    if (computation.expectedTdsReason.trim().isNotEmpty) {
      bucket.expectedReasons.add(computation.expectedTdsReason.trim());
    }
    bucket.identityFlags.addAll(computation.source.identity.identityFlags);
  }

  static List<ReconciliationRow> _applyTimingBySeller(List<ReconciliationRow> rows) {
    final grouped = <String, List<ReconciliationRow>>{};
    for (final row in rows) {
      final key = '${normalizePan(row.buyerPan)}|${row.resolvedSellerId}';
      grouped.putIfAbsent(key, () => <ReconciliationRow>[]).add(row);
    }

    final output = <ReconciliationRow>[];
    final sellerKeys = grouped.keys.toList()..sort();
    for (final sellerKey in sellerKeys) {
      final timed = TimingService.applyTimingLogic(grouped[sellerKey]!)
          .map(
            (row) => row.copyWith(
              debugInfo: row.debugInfo.copyWith(
                finalStatusReason: row.debugInfo.finalStatusReason,
              ),
            ),
          )
          .toList();
      output.addAll(timed);
    }

    output.sort((a, b) {
      final sellerCompare = a.resolvedSellerName
          .toUpperCase()
          .compareTo(b.resolvedSellerName.toUpperCase());
      if (sellerCompare != 0) return sellerCompare;
      final fyCompare = a.financialYear.compareTo(b.financialYear);
      if (fyCompare != 0) return fyCompare;
      final sectionCompare = sortKeyForSection(a.section).compareTo(
        sortKeyForSection(b.section),
      );
      if (sectionCompare != 0) return sectionCompare;
      return compareMonthKeys(a.month, b.month);
    });
    return output;
  }

  static Map<String, List<ReconciliationRow>> _groupRowsBySection(
    List<ReconciliationRow> rows,
  ) {
    final grouped = <String, List<ReconciliationRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.section, () => <ReconciliationRow>[]).add(row);
    }

    for (final value in grouped.values) {
      value.sort((a, b) {
        final sellerCompare = a.resolvedSellerName
            .toUpperCase()
            .compareTo(b.resolvedSellerName.toUpperCase());
        if (sellerCompare != 0) return sellerCompare;
        final fyCompare = a.financialYear.compareTo(b.financialYear);
        if (fyCompare != 0) return fyCompare;
        return compareMonthKeys(a.month, b.month);
      });
    }

    return grouped;
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
      matchedRows:
          rows.where((row) => row.status == ReconciliationStatus.matched).length,
      mismatchRows: mismatchRows,
      purchaseOnlyRows: rows
          .where((row) => row.status == ReconciliationStatus.purchaseOnly)
          .length,
      only26QRows: rows
          .where((row) => row.status == ReconciliationStatus.onlyIn26Q)
          .length,
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

  static String _applyNameMapping(String name, Map<String, String> mapping) {
    final normalized = normalizeName(name);
    return mapping[normalized]?.trim().isNotEmpty == true
        ? mapping[normalized]!.trim()
        : name.trim();
  }

  static String _normalizeSellerName(String name, Map<String, String> mapping) {
    return normalizeName(_applyNameMapping(name, mapping));
  }

  static Map<String, String> _normalizeNameMapping(Map<String, String> mapping) {
    final normalized = <String, String>{};
    for (final entry in mapping.entries) {
      final key = normalizeName(entry.key);
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        normalized[key] = value;
      }
    }
    return normalized;
  }

  static String _normalizeSourceSection(String section, String normalizedSection) {
    final normalized = _normalizeSupportedSection(normalizedSection);
    if (normalized.isNotEmpty) return normalized;
    final rawNormalized = _normalizeSupportedSection(section);
    if (rawNormalized.isNotEmpty) return rawNormalized;
    return normalizedSection.trim().isNotEmpty
        ? normalizedSection.trim()
        : (section.trim().isNotEmpty ? section.trim() : 'No Section');
  }

  static String _normalizeTdsSection(String section) {
    final normalized = _normalizeSupportedSection(section);
    if (normalized.isNotEmpty) return normalized;
    final raw = normalizeSection(section);
    if (raw.isNotEmpty) return raw;
    return section.trim().isEmpty ? 'UNKNOWN' : section.trim();
  }

  static String _normalizeSupportedSection(String value) {
    final normalized = normalizeSection(value);
    return supportedSections.contains(normalized) ? normalized : '';
  }

  static bool _isUsableSection(String value) {
    final upper = value.trim().toUpperCase();
    return upper.isNotEmpty && upper != 'NO SECTION' && upper != 'UNKNOWN';
  }

  static DateTime _resolveChronologyDate(String rawValue, String month) {
    return tryParseDate(rawValue) ?? monthKeyToDate(month) ?? DateTime(1970, 1, 1);
  }

  static int _compareResolvedSourceRows(_ResolvedSourceRow a, _ResolvedSourceRow b) {
    final dateCompare = a.chronologyDate.compareTo(b.chronologyDate);
    if (dateCompare != 0) return dateCompare;
    final monthCompare = compareMonthKeys(a.month, b.month);
    if (monthCompare != 0) return monthCompare;
    final sectionCompare = a.section.compareTo(b.section);
    if (sectionCompare != 0) return sectionCompare;
    return a.originalSellerName.toUpperCase().compareTo(
      b.originalSellerName.toUpperCase(),
    );
  }

  static int _compareMonthlyBucketKeys(_MonthlyBucketKey a, _MonthlyBucketKey b) {
    final sellerCompare = a.resolvedSellerId.compareTo(b.resolvedSellerId);
    if (sellerCompare != 0) return sellerCompare;
    final fyCompare = a.financialYear.compareTo(b.financialYear);
    if (fyCompare != 0) return fyCompare;
    final sectionCompare = sortKeyForSection(a.section).compareTo(
      sortKeyForSection(b.section),
    );
    if (sectionCompare != 0) return sectionCompare;
    return compareMonthKeys(a.month, b.month);
  }

  static Map<String, List<dynamic>> _debugResolvedSectionCounts(
    List<_ResolvedSourceRow> rows,
  ) {
    final map = <String, List<dynamic>>{};
    for (final row in rows) {
      map.putIfAbsent(row.section, () => <dynamic>[]).add(row);
    }
    return map;
  }

  static String _buildApplicableReason({
    required String section,
    required double amount,
    required double previousCumulative,
    required double currentCumulative,
    required double applicableAmount,
  }) {
    final normalizedSection = _normalizeSupportedSection(section);
    if (normalizedSection.isEmpty) {
      return 'Section unresolved; applicability was kept at zero for safety until the section is confirmed.';
    }

    if (normalizedSection == '194Q') {
      if (applicableAmount <= 0) {
        return '194Q threshold not crossed yet; cumulative remained at ${round2(currentCumulative)}.';
      }
      if (previousCumulative < threshold && currentCumulative > threshold) {
        return '194Q threshold crossed in this month; only the excess ${round2(applicableAmount)} is applicable.';
      }
      return '194Q threshold was already crossed before this row; full amount ${round2(amount)} is applicable.';
    }

    if (normalizedSection == '194C') {
      if (applicableAmount <= 0) {
        return '194C threshold not crossed; single payment stayed within 30000 and cumulative remained at ${round2(currentCumulative)}.';
      }
      if (amount > 30000.0) {
        return 'Applicable under 194C because single payment ${round2(amount)} exceeds 30000.';
      }
      return 'Applicable under 194C because cumulative section amount ${round2(currentCumulative)} exceeds 100000.';
    }

    if (applicableAmount <= 0) {
      return 'Section threshold/rule not met for $normalizedSection.';
    }

    return 'Applicable under $normalizedSection based on cumulative section amount ${round2(currentCumulative)}.';
  }

  static String _buildExpectedTdsReason({
    required String section,
    required double expectedTds,
    required double rate,
    required double applicableAmount,
    required bool manualReviewRequired,
    required String manualReviewReason,
  }) {
    final normalizedSection = _normalizeSupportedSection(section);
    if (normalizedSection.isEmpty) {
      return 'Expected TDS was kept at zero for safety because the section is unresolved.';
    }

    if (manualReviewRequired) {
      return 'Expected TDS could not be confirmed for $normalizedSection because ${manualReviewReason.trim().isEmpty ? 'rate inference was unresolved.' : manualReviewReason.trim()}';
    }

    if (expectedTds == 0 && rate == 0) {
      if (normalizedSection == '194C' ||
          normalizedSection == '194J' ||
          normalizedSection == '194I') {
        if (normalizedSection == '194C' && applicableAmount <= 0) {
          return 'Expected TDS is zero because the 194C threshold is not crossed.';
        }
        return 'Expected TDS kept at zero because subtype/rate context is not modeled yet for $normalizedSection.';
      }
      return 'Expected TDS is zero because the row is not yet applicable.';
    }

    return 'Expected TDS calculated at rate ${rate.toStringAsFixed(4)} for $normalizedSection.';
  }

  static String _buildFinalStatusReason({
    required String status,
    required _MonthlyPurchaseBucket? purchase,
    required _MonthlyTdsBucket? tds,
    required double amountDifference,
    required double tdsDifference,
  }) {
    switch (status) {
      case ReconciliationStatus.onlyIn26Q:
        return '26Q entry exists without a matching purchase bucket for the same resolved seller, FY, section, and month.';
      case ReconciliationStatus.applicableButNo26Q:
        return 'Purchase bucket is applicable but there is no matching 26Q bucket.';
      case ReconciliationStatus.belowThreshold:
        return 'Purchase bucket stayed below the applicable threshold and no 26Q bucket exists.';
      case ReconciliationStatus.reviewRequired:
        return 'Purchase bucket is applicable, but the expected TDS rate could not be confirmed automatically and needs manual review.';
      case ReconciliationStatus.amountMismatch:
        return 'Applicable purchase amount and deducted 26Q amount differ by ${round2(amountDifference)}.';
      case ReconciliationStatus.shortDeduction:
        return 'Actual TDS is lower than expected by ${round2(tdsDifference)}.';
      case ReconciliationStatus.excessDeduction:
        return 'Actual TDS is higher than expected by ${round2(tdsDifference.abs())}.';
      case ReconciliationStatus.noDeductionRequired:
        return 'Bucket is not applicable for TDS after rule evaluation.';
      case ReconciliationStatus.sectionMissing:
        return 'Section was unavailable, blank, or unsupported for this bucket, so section-based applicability and expected TDS were kept conservative for review.';
      default:
        return 'Status derived from resolved seller + FY + section + month reconciliation bucket.';
    }
  }

  static List<String> _sortedValues(Set<String> values) {
    final list = values.where((value) => value.trim().isNotEmpty).toList()..sort();
    return list;
  }
}

String sortKeyForSection(String value) {
  const preferredOrder = ['194Q', '194C', '194J', '194I', '194H', '194IB'];
  final normalized = value.trim();
  final index = preferredOrder.indexOf(normalized);
  if (index == -1) {
    return 'Z:$normalized';
  }
  return 'A:${index.toString().padLeft(2, '0')}:$normalized';
}
