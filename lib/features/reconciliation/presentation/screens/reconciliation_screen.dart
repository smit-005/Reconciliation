import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/utils/reconciliation_helpers.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/skipped_row_summary.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_summary.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/pan_propagation_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/reconciliation_view_visibility.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_analysis_panel.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_bottom_action_bar.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_filters.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_reason_chip.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_summary_header.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_summary_pill.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_table_section.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/reconciliation_top_toolbar.dart';
import 'package:reconciliation_app/features/upload/services/auto_mapping_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/excel_export_service.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_orchestrator.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

class _FilteredMetrics {
  final ReconciliationSummary summary;
  final Map<String, int> mismatchReasonCounts;
  final Map<String, int> sectionCounts;
  final Map<String, int> sectionMismatchCounts;
  final String topMismatchSection;
  final int totalSellers;
  final int totalSections;
  final int matchedCount;
  final int mismatchRowsCount;
  final int timingDifferenceCount;
  final int shortDeductionCount;
  final int excessDeductionCount;
  final int purchaseOnlyCount;
  final int only26QCount;
  final int applicableButNo26QCount;
  final double matchedPercentage;
  final double mismatchPercentage;
  final double basicAmount;
  final double applicableAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double tdsDifference;
  final double amountDifference;
  final double shortDeductionAmount;
  final double excessDeductionAmount;
  final double timingDifferenceAmount;
  final double purchaseOnlyAmount;
  final double only26QAmount;
  final double netMismatchAmount;
  final double applicableButNo26QAmount;
  final double applicableButNo26QTds;

  const _FilteredMetrics({
    required this.summary,
    required this.mismatchReasonCounts,
    required this.sectionCounts,
    required this.sectionMismatchCounts,
    required this.topMismatchSection,
    required this.totalSellers,
    required this.totalSections,
    required this.matchedCount,
    required this.mismatchRowsCount,
    required this.timingDifferenceCount,
    required this.shortDeductionCount,
    required this.excessDeductionCount,
    required this.purchaseOnlyCount,
    required this.only26QCount,
    required this.applicableButNo26QCount,
    required this.matchedPercentage,
    required this.mismatchPercentage,
    required this.basicAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.tdsDifference,
    required this.amountDifference,
    required this.shortDeductionAmount,
    required this.excessDeductionAmount,
    required this.timingDifferenceAmount,
    required this.purchaseOnlyAmount,
    required this.only26QAmount,
    required this.netMismatchAmount,
    required this.applicableButNo26QAmount,
    required this.applicableButNo26QTds,
  });
}

class _SellerMappingConflict {
  final String aliasKey;
  final String message;

  const _SellerMappingConflict({required this.aliasKey, required this.message});
}

enum _SellerExceptionFilter { skippedRows, missing26Q }

class ReconciliationScreen extends StatefulWidget {
  final Map<String, List<NormalizedTransactionRow>> sourceRowsBySection;
  final Map<String, int> sourceFileCountBySection;
  final List<Tds26QRow> tdsRows;

  final String buyerName;
  final String buyerPan;
  final String gstNo;
  final bool sellerMappingConfirmed;

  const ReconciliationScreen({
    super.key,
    required this.sourceRowsBySection,
    this.sourceFileCountBySection = const {},
    required this.tdsRows,
    this.buyerName = '',
    this.buyerPan = '',
    this.gstNo = '',
    this.sellerMappingConfirmed = false,
  });

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  static const List<String> _sectionTabs = [
    'All',
    '194Q',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
  ];

  List<ReconciliationRow> allRows = [];
  List<ReconciliationRow> filteredRows = [];
  List<ReconciliationRow> tableRows = [];
  Map<String, ReconciliationSummary> sectionSummaries = {};
  ReconciliationSummary? combinedSummary;
  SectionReconciliationResult? _sectionResultCache;
  _FilteredMetrics? _filteredMetrics;

  List<String> sellerOptions = [];
  List<String> financialYearOptions = ['All FY'];
  List<String> sectionOptions = ['All Sections'];

  Map<String, String> manualNameMapping = {};

  String selectedSeller = '';
  String selectedFinancialYear = 'All FY';
  String selectedSection = 'All Sections';
  String selectedStatus = 'All Status';
  String activeSectionTab = 'All';
  ReconciliationViewMode _viewMode = ReconciliationViewMode.summary;
  _SellerExceptionFilter? _activeSellerExceptionFilter;

  bool _isRecalculating = false;
  String _processingMessage = 'Processing reconciliation...';
  final Map<String, List<ReconciliationRow>> _filterRowsCache = {};
  final Map<String, List<String>> _sectionOptionsCache = {};
  String? _autoMappingCacheKey;
  AutoMappingBatchResult? _autoMappingCacheResult;
  String? _tdsPanLookupCacheKey;
  Map<String, String> _exactTdsPanLookup = {};
  Map<String, String> _normalizedTdsPanLookup = {};

  final List<String> statusOptions = const [
    'All Status',
    CalculationService.sellerStatusMatched,
    CalculationService.sellerStatusMismatch,
    CalculationService.sellerStatusNo26Q,
    CalculationService.sellerStatusOnly26Q,
    ReconciliationStatus.reviewRequired,
  ];

  @override
  void initState() {
    super.initState();
    _recalculateAll();
  }

  Future<void> _allowLoadingFrame() async {
    debugPrint('RECON UI => loading state set');
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    debugPrint('RECON UI => first frame painted');
  }

  void _logPerformance(String label, Stopwatch watch, {String details = ''}) {
    final suffix = details.trim().isEmpty ? '' : ' | $details';
    debugPrint('RECON PERF => $label ${watch.elapsedMilliseconds} ms$suffix');
  }

  Future<List<SellerMapping>> _loadManualMappingRecordsFromDb() {
    return SellerMappingService.getAllMappings(
      widget.buyerPan.trim().toUpperCase(),
    );
  }

  Future<Map<String, String>> _loadManualMappingsFromDb() async {
    final mappings = await _loadManualMappingRecordsFromDb();

    final latest = <String, String>{};
    final mappingsByAlias = <String, List<SellerMapping>>{};

    for (final mapping in mappings) {
      final aliasKey = normalizeName(mapping.aliasName.trim());
      if (aliasKey.isEmpty) continue;
      mappingsByAlias.putIfAbsent(aliasKey, () => <SellerMapping>[]);
      mappingsByAlias[aliasKey]!.add(mapping);
    }

    for (final entry in mappingsByAlias.entries) {
      final mappedNames = entry.value
          .map((mapping) => mapping.mappedName.trim())
          .where((name) => name.isNotEmpty)
          .toSet();

      if (mappedNames.length != 1) continue;
      latest[entry.key] = mappedNames.first;
    }

    return latest;
  }

  String _normalizeAlias(String value) => normalizeName(value.trim());

  String _buildCollectionSignature(Iterable<String> values) {
    final items = values.toList()..sort();
    return '${items.length}:${Object.hashAll(items)}';
  }

  String _buildAutoMappingCacheKey({
    required List<String> purchaseNames,
    required List<String> tdsNames,
  }) {
    return '${normalizePan(widget.buyerPan)}|'
        '${_buildCollectionSignature(purchaseNames)}|'
        '${_buildCollectionSignature(tdsNames)}';
  }

  String _buildTdsPanLookupCacheKey() {
    final signatures =
        widget.tdsRows
            .map(
              (row) =>
                  '${row.deducteeName.trim().toUpperCase()}|${normalizePan(row.panNumber)}',
            )
            .toList()
          ..sort();
    return _buildCollectionSignature(signatures);
  }

  void _invalidatePerformanceCaches() {
    _autoMappingCacheKey = null;
    _autoMappingCacheResult = null;
    _tdsPanLookupCacheKey = null;
    _exactTdsPanLookup = {};
    _normalizedTdsPanLookup = {};
  }

  void _ensureTdsPanLookups() {
    final nextCacheKey = _buildTdsPanLookupCacheKey();
    if (_tdsPanLookupCacheKey == nextCacheKey) {
      return;
    }

    final exactPanSets = <String, Set<String>>{};
    final normalizedPanSets = <String, Set<String>>{};

    for (final row in widget.tdsRows) {
      final pan = normalizePan(row.panNumber);
      if (pan.isEmpty) continue;

      final exactName = row.deducteeName.trim().toUpperCase();
      final normalizedName = _normalizeAlias(row.deducteeName);

      if (exactName.isNotEmpty) {
        exactPanSets.putIfAbsent(exactName, () => <String>{}).add(pan);
      }
      if (normalizedName.isNotEmpty) {
        normalizedPanSets
            .putIfAbsent(normalizedName, () => <String>{})
            .add(pan);
      }
    }

    _exactTdsPanLookup = {
      for (final entry in exactPanSets.entries)
        if (entry.value.length == 1) entry.key: entry.value.first,
    };
    _normalizedTdsPanLookup = {
      for (final entry in normalizedPanSets.entries)
        if (entry.value.length == 1) entry.key: entry.value.first,
    };
    _tdsPanLookupCacheKey = nextCacheKey;
  }

  Set<String> _resolveTargetPans(String mappedName) {
    _ensureTdsPanLookups();
    final pans = <String>{};
    final exactName = mappedName.trim().toUpperCase();
    final normalizedMappedName = _normalizeAlias(mappedName);

    final exactPan = _exactTdsPanLookup[exactName];
    if (exactPan != null && exactPan.isNotEmpty) {
      pans.add(exactPan);
    }

    final normalizedPan = _normalizedTdsPanLookup[normalizedMappedName];
    if (normalizedPan != null && normalizedPan.isNotEmpty) {
      pans.add(normalizedPan);
    }

    return pans;
  }

  String _resolveSingleTargetPan(String mappedName) {
    final pans = _resolveTargetPans(mappedName);
    return pans.length == 1 ? pans.first : '';
  }

  Map<String, List<String>> _buildPurchaseSectionsByAlias(
    List<NormalizedTransactionRow> sourceRows,
  ) {
    final sectionsByAlias = <String, Set<String>>{};

    for (final row in sourceRows) {
      final aliasKey = _normalizeAlias(row.partyName);
      final section = normalizeSection(row.section).isNotEmpty
          ? normalizeSection(row.section)
          : normalizeSection(row.normalizedSection);

      if (aliasKey.isEmpty || section.isEmpty) continue;
      sectionsByAlias.putIfAbsent(aliasKey, () => <String>{});
      sectionsByAlias[aliasKey]!.add(section);
    }

    return {
      for (final entry in sectionsByAlias.entries)
        entry.key: (entry.value.toList()..sort()),
    };
  }

  String _resolveSuggestedTdsPartyName(ReconciliationRow row) {
    final resolvedPan = normalizePan(row.resolvedPan);
    final resolvedName = row.resolvedSellerName.trim();

    if (resolvedPan.isNotEmpty) {
      final panMatches =
          widget.tdsRows
              .where((tdsRow) => normalizePan(tdsRow.panNumber) == resolvedPan)
              .map((tdsRow) => tdsRow.deducteeName.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      if (panMatches.length == 1) {
        return panMatches.first;
      }

      final normalizedResolvedName = normalizeName(resolvedName);
      if (normalizedResolvedName.isNotEmpty) {
        for (final match in panMatches) {
          if (normalizeName(match) == normalizedResolvedName) {
            return match;
          }
        }
      }
    }

    final normalizedResolvedName = normalizeName(resolvedName);
    if (normalizedResolvedName.isEmpty) {
      return resolvedName;
    }

    final nameMatches =
        widget.tdsRows
            .map((tdsRow) => tdsRow.deducteeName.trim())
            .where((name) => name.isNotEmpty)
            .where((name) => normalizeName(name) == normalizedResolvedName)
            .toSet()
            .toList()
          ..sort();

    if (nameMatches.isNotEmpty) {
      return nameMatches.first;
    }

    return resolvedName;
  }

  String _resolvedSuggestionSource(ReconciliationRow row) {
    switch (row.debugInfo.mappingHit.trim()) {
      case 'exact':
        return 'saved_exact';
      case 'fallback':
        return 'saved_fallback';
      default:
        return row.resolvedSellerName.trim().isEmpty &&
                normalizePan(row.resolvedPan).isEmpty
            ? 'none'
            : 'backend_inferred';
    }
  }

  String _resolvedSuggestionHelper(ReconciliationRow row, String source) {
    switch (source) {
      case 'saved_exact':
        return 'Exact section mapping is already saved.';
      case 'saved_fallback':
        return 'Using global fallback in reconciliation; save to store as exact section mapping.';
      case 'backend_inferred':
        return 'Resolved in reconciliation only; not yet saved as exact section mapping.';
      default:
        return '';
    }
  }

  int _resolvedSuggestionPriority(String source) {
    switch (source) {
      case 'saved_exact':
        return 4;
      case 'saved_fallback':
        return 3;
      case 'backend_inferred':
        return 2;
      default:
        return 0;
    }
  }

  Map<String, SellerMappingResolvedSuggestion> _buildResolvedSuggestions(
    List<ReconciliationRow> rows,
  ) {
    final suggestions = <String, SellerMappingResolvedSuggestion>{};
    final suggestionScores = <String, int>{};

    for (final row in rows) {
      if (!row.purchasePresent) continue;

      final sectionCode = normalizeSellerMappingSectionCode(row.section);
      final source = _resolvedSuggestionSource(row);
      if (source == 'none') continue;

      final mappedName = _resolveSuggestedTdsPartyName(row).trim();
      final mappedPan = normalizePan(row.resolvedPan);
      if (mappedName.isEmpty && mappedPan.isEmpty) continue;

      final score =
          (_resolvedSuggestionPriority(source) * 1000) +
          (row.identityConfidence * 100).round() +
          (mappedPan.isNotEmpty ? 10 : 0);

      final suggestion = SellerMappingResolvedSuggestion(
        mappedName: mappedName,
        mappedPan: mappedPan,
        source: source,
        helperText: _resolvedSuggestionHelper(row, source),
      );

      final aliases = row.debugInfo.originalSellerNames
          .map((name) => _normalizeAlias(name))
          .where((name) => name.isNotEmpty)
          .toSet();

      for (final alias in aliases) {
        final rowKey = '$alias|$sectionCode';
        if (score < (suggestionScores[rowKey] ?? -1)) continue;
        suggestionScores[rowKey] = score;
        suggestions[rowKey] = suggestion;
      }
    }

    return suggestions;
  }

  Map<String, List<String>> _buildTdsPartyPans() {
    final pansByParty = <String, Set<String>>{};

    for (final row in widget.tdsRows) {
      final partyName = row.deducteeName.trim();
      final pan = normalizePan(row.panNumber);
      if (partyName.isEmpty || pan.isEmpty) continue;
      pansByParty.putIfAbsent(partyName, () => <String>{});
      pansByParty[partyName]!.add(pan);
    }

    return {
      for (final entry in pansByParty.entries)
        entry.key: (entry.value.toList()..sort()),
    };
  }

  List<_SellerMappingConflict> _buildAliasPanConflicts({
    required Map<String, String> mappings,
    required Map<String, List<String>> purchaseSectionsByAlias,
  }) {
    final conflicts = <_SellerMappingConflict>[];

    for (final entry in mappings.entries) {
      final aliasKey = _normalizeAlias(entry.key);
      final targetPans = _resolveTargetPans(entry.value);

      if (aliasKey.isEmpty || targetPans.length <= 1) continue;

      final sections = purchaseSectionsByAlias[aliasKey] ?? const <String>[];
      final sectionSuffix = sections.isEmpty
          ? ''
          : ' Sections: ${sections.join(', ')}.';
      conflicts.add(
        _SellerMappingConflict(
          aliasKey: aliasKey,
          message:
              'This seller maps to different PANs. Section-wise mapping is required.$sectionSuffix',
        ),
      );
    }

    return conflicts;
  }

  List<NormalizedTransactionRow> _applyPropagatedPanToSourceRows({
    required List<NormalizedTransactionRow> sourceRows,
    required Map<String, String> nameMapping,
  }) {
    return sourceRows.map((row) {
      final existingPan = normalizePan(row.panNumber);
      if (existingPan.isNotEmpty) {
        return row;
      }

      final aliasKey = _normalizeAlias(row.partyName);
      final mappedName = nameMapping[aliasKey]?.trim() ?? '';
      if (aliasKey.isEmpty || mappedName.isEmpty) {
        return row;
      }

      final propagatedPan = _resolveSingleTargetPan(mappedName);
      if (propagatedPan.isEmpty) {
        return row;
      }

      return row.copyWith(
        panNumber: propagatedPan,
        normalizedPan: propagatedPan,
      );
    }).toList();
  }

  @override
  void didUpdateWidget(covariant ReconciliationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sourceChanged =
        oldWidget.sourceRowsBySection != widget.sourceRowsBySection;
    final tdsChanged = oldWidget.tdsRows != widget.tdsRows;
    final buyerChanged =
        oldWidget.buyerName != widget.buyerName ||
        oldWidget.buyerPan != widget.buyerPan ||
        oldWidget.gstNo != widget.gstNo;

    if (sourceChanged || tdsChanged || buyerChanged) {
      _invalidatePerformanceCaches();
      _recalculateAll();
    }
  }

  Future<void> _recalculateAll() async {
    if (_isRecalculating) return;

    setState(() {
      _isRecalculating = true;
      _processingMessage = 'Processing reconciliation...';
    });
    await _allowLoadingFrame();

    try {
      debugPrint('RECON PERF => heavy work started');
      final totalWatch = Stopwatch()..start();
      final prevSeller = selectedSeller;
      final prevFY = selectedFinancialYear;
      final prevSection = selectedSection;
      final prevStatus = selectedStatus;
      final mappingsWatch = Stopwatch()..start();
      final latestManualMappings = await _loadManualMappingsFromDb();
      mappingsWatch.stop();
      _logPerformance(
        'manual mapping load',
        mappingsWatch,
        details: 'mappings=${latestManualMappings.length}',
      );

      setState(() {
        _processingMessage = 'Preparing source data...';
      });
      await _allowLoadingFrame();

      final sourceRows = widget.sourceRowsBySection.values
          .expand((rows) => rows)
          .toList();
      debugPrint(
        'RECON INPUT => sourceRows=${sourceRows.length} sourceSections=${widget.sourceRowsBySection.length} '
        'tdsRows=${widget.tdsRows.length} buyer=${widget.buyerPan}',
      );

      final purchaseNames =
          sourceRows
              .map((e) => e.partyName.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final tdsNames =
          widget.tdsRows
              .map((e) => e.deducteeName.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final autoMapWatch = Stopwatch()..start();
      final autoMapCacheKey = _buildAutoMappingCacheKey(
        purchaseNames: purchaseNames,
        tdsNames: tdsNames,
      );
      final autoMapCacheHit =
          _autoMappingCacheKey == autoMapCacheKey &&
          _autoMappingCacheResult != null;
      late final AutoMappingBatchResult autoMappingBatch;
      if (autoMapCacheHit) {
        autoMappingBatch = _autoMappingCacheResult!;
      } else {
        final isolateWatch = Stopwatch()..start();
        debugPrint('AUTO MAP ISOLATE => started');
        autoMappingBatch = await AutoMappingService.autoMapPartiesInBackground(
          purchaseParties: purchaseNames,
          tdsParties: tdsNames,
          threshold: 0.80,
        );
        isolateWatch.stop();
        debugPrint(
          'AUTO MAP ISOLATE => completed ${isolateWatch.elapsedMilliseconds} ms',
        );
      }
      if (!autoMapCacheHit) {
        _autoMappingCacheKey = autoMapCacheKey;
        _autoMappingCacheResult = autoMappingBatch;
      }
      autoMapWatch.stop();
      final mappingResults = autoMappingBatch.results;
      debugPrint(
        'AUTO MAP PERF => cacheHit=$autoMapCacheHit | '
        'normalize ${autoMapCacheHit ? 0 : autoMappingBatch.normalizationMs} ms | '
        'match ${autoMapCacheHit ? 0 : autoMappingBatch.matchingMs} ms | '
        'results=${mappingResults.length}',
      );
      _logPerformance(
        'auto mapping',
        autoMapWatch,
        details:
            'purchaseNames=${purchaseNames.length} tdsNames=${tdsNames.length} results=${mappingResults.length}',
      );

      final nameMapping = <String, String>{};
      final eligibleAutoMappings =
          <({String purchaseParty, String mappedTdsParty})>[];

      for (final m in mappingResults) {
        final purchaseRaw = m.purchaseParty.trim();
        final tdsRaw = m.matchedTdsParty?.trim();

        if (purchaseRaw.isEmpty || tdsRaw == null || tdsRaw.isEmpty) continue;

        final purchaseKey = normalizeName(purchaseRaw.trim());
        if (purchaseKey.isEmpty) continue;

        if (m.isMatched) {
          nameMapping[purchaseKey] = tdsRaw;
          eligibleAutoMappings.add((
            purchaseParty: purchaseRaw,
            mappedTdsParty: tdsRaw,
          ));
          continue;
        }

        if (m.normalizedPurchaseParty == m.normalizedMatchedTdsParty) {
          nameMapping[purchaseKey] = tdsRaw;
          eligibleAutoMappings.add((
            purchaseParty: purchaseRaw,
            mappedTdsParty: tdsRaw,
          ));
        }
      }

      for (final entry in latestManualMappings.entries) {
        final normalizedSource = normalizeName(entry.key.trim());
        final mappedTarget = entry.value.trim();

        if (normalizedSource.isEmpty || mappedTarget.isEmpty) continue;

        nameMapping[normalizedSource] = mappedTarget;
      }

      setState(() {
        _processingMessage = 'Propagating seller PAN mappings...';
      });
      await _allowLoadingFrame();

      final panPropagationWatch = Stopwatch()..start();
      final panMapBuildWatch = Stopwatch()..start();
      _ensureTdsPanLookups();
      final panPropagationMapping = buildPanPropagationMapping(
        manualMappings: latestManualMappings.entries,
        autoMappings: eligibleAutoMappings,
      );
      panMapBuildWatch.stop();
      final panApplyWatch = Stopwatch()..start();
      final propagatedSourceRows = _applyPropagatedPanToSourceRows(
        sourceRows: List<NormalizedTransactionRow>.from(sourceRows),
        nameMapping: panPropagationMapping,
      );
      panApplyWatch.stop();
      panPropagationWatch.stop();
      debugPrint(
        'PAN PROP PERF => mapBuild ${panMapBuildWatch.elapsedMilliseconds} ms | '
        'apply ${panApplyWatch.elapsedMilliseconds} ms',
      );
      _logPerformance(
        'pan propagation',
        panPropagationWatch,
        details:
            'propagationMap=${panPropagationMapping.length} sourceRows=${propagatedSourceRows.length}',
      );

      setState(() {
        _processingMessage = 'Calculating reconciliation results...';
      });
      await _allowLoadingFrame();

      final reconciliationWatch = Stopwatch()..start();
      final sectionResult = await CalculationService.reconcileSectionWise(
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        sourceRows: propagatedSourceRows,
        tdsRows: List<Tds26QRow>.from(widget.tdsRows),
        nameMapping: nameMapping,
        includeAllRows: true,
        sections: widget.sourceRowsBySection.keys.toList(),
      );
      reconciliationWatch.stop();
      _logPerformance(
        'reconciliation calculation',
        reconciliationWatch,
        details:
            'rows=${sectionResult.rows.length} sections=${sectionResult.sectionSummaries.length}',
      );

      setState(() {
        _processingMessage = 'Applying filters and preparing results table...';
      });
      await _allowLoadingFrame();

      final freshRows = sectionResult.rows;
      final visibleRows = _rowsForCurrentSummaryScope(freshRows);

      final sellerOptionsByKey = <String, String>{};
      for (final row in visibleRows) {
        final key = buildSellerDisplayKey(row);
        final label = _sellerFilterLabel(row);
        if (key.isEmpty || label.isEmpty) continue;
        sellerOptionsByKey[key] = label;
      }
      final sellers = sellerOptionsByKey.values.toList()..sort();

      final financialYears =
          visibleRows
              .map((e) => e.financialYear.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      final nextSellerOptions = sellers;
      final nextFinancialYearOptions = ['All FY', ...financialYears];

      final normalizedPrevSection = prevSection.trim();

      final nextSelectedSeller = prevSeller;

      final nextSelectedFinancialYear =
          nextFinancialYearOptions.contains(prevFY) ? prevFY : 'All FY';

      final nextSelectedStatus = statusOptions.contains(prevStatus)
          ? prevStatus
          : 'All Status';

      final nextSectionOptions = _buildSectionOptions(
        rows: freshRows,
        selectedSellerValue: nextSelectedSeller,
        selectedFinancialYearValue: nextSelectedFinancialYear,
        selectedStatusValue: nextSelectedStatus,
      );

      final nextSelectedSection =
          nextSectionOptions.contains(normalizedPrevSection) ||
              _isSupportedSectionTab(normalizedPrevSection)
          ? normalizedPrevSection
          : 'All Sections';

      final filterWatch = Stopwatch()..start();
      final nextFilteredRows = _filterRows(
        rows: freshRows,
        selectedSellerValue: nextSelectedSeller,
        selectedFinancialYearValue: nextSelectedFinancialYear,
        selectedSectionValue: nextSelectedSection,
        selectedStatusValue: nextSelectedStatus,
      );
      final nextTableRows = _filterTableRows(
        rows: freshRows,
        selectedSellerValue: nextSelectedSeller,
        selectedFinancialYearValue: nextSelectedFinancialYear,
        selectedSectionValue: nextSelectedSection,
        selectedStatusValue: nextSelectedStatus,
      );
      filterWatch.stop();
      _logPerformance(
        'filtering',
        filterWatch,
        details:
            'summaryRows=${nextFilteredRows.length} tableRows=${nextTableRows.length} activeTab=${nextSelectedSection == 'All Sections' ? 'All' : nextSelectedSection}',
      );

      if (!mounted) return;

      _filterRowsCache.clear();
      _sectionOptionsCache.clear();
      setState(() {
        _sectionResultCache = sectionResult;
        allRows = freshRows;
        filteredRows = nextFilteredRows;
        tableRows = nextTableRows;
        manualNameMapping = latestManualMappings;
        sectionSummaries = sectionResult.sectionSummaries;
        combinedSummary = sectionResult.combinedSummary;

        sellerOptions = nextSellerOptions;
        financialYearOptions = nextFinancialYearOptions;
        sectionOptions = nextSectionOptions;

        selectedSeller = nextSelectedSeller;
        selectedFinancialYear = nextSelectedFinancialYear;
        selectedSection = nextSelectedSection;
        selectedStatus = nextSelectedStatus;
        activeSectionTab = nextSelectedSection == 'All Sections'
            ? 'All'
            : nextSelectedSection;
        _filteredMetrics = _buildFilteredMetrics(
          rows: nextFilteredRows,
          activeTab: nextSelectedSection == 'All Sections'
              ? 'All'
              : nextSelectedSection,
        );
      });
      totalWatch.stop();
      _logPerformance(
        'reconciliation screen total refresh',
        totalWatch,
        details:
            'allRows=${freshRows.length} summaryRows=${nextFilteredRows.length} tableRows=${nextTableRows.length}',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Recalculation failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRecalculating = false;
        });
      }
    }
  }

  void _applyFilters() {
    final filterWatch = Stopwatch()..start();
    final visibleRows = _rowsForCurrentSummaryScope(allRows);
    final sellerOptionsByKey = <String, String>{};
    for (final row in visibleRows) {
      final key = buildSellerDisplayKey(row);
      final label = _sellerFilterLabel(row);
      if (key.isEmpty || label.isEmpty) continue;
      sellerOptionsByKey[key] = label;
    }

    final nextSellerOptions = sellerOptionsByKey.values.toList()..sort();
    final nextFinancialYearOptions = [
      'All FY',
      ...(visibleRows
          .map((row) => row.financialYear.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort()),
    ];
    final nextSelectedSeller = selectedSeller;
    final nextSelectedFinancialYear =
        nextFinancialYearOptions.contains(selectedFinancialYear)
        ? selectedFinancialYear
        : 'All FY';

    final nextSectionOptions = _buildSectionOptions(
      rows: allRows,
      selectedSellerValue: nextSelectedSeller,
      selectedFinancialYearValue: nextSelectedFinancialYear,
      selectedStatusValue: selectedStatus,
    );
    final normalizedSelectedSection = selectedSection.trim();
    final nextSelectedSection =
        nextSectionOptions.contains(normalizedSelectedSection) ||
            _isSupportedSectionTab(normalizedSelectedSection)
        ? normalizedSelectedSection
        : 'All Sections';

    final nextFilteredRows = _filterRows(
      rows: allRows,
      selectedSellerValue: nextSelectedSeller,
      selectedFinancialYearValue: nextSelectedFinancialYear,
      selectedSectionValue: nextSelectedSection,
      selectedStatusValue: selectedStatus,
    );
    final nextTableRows = _filterTableRows(
      rows: allRows,
      selectedSellerValue: nextSelectedSeller,
      selectedFinancialYearValue: nextSelectedFinancialYear,
      selectedSectionValue: nextSelectedSection,
      selectedStatusValue: selectedStatus,
    );
    final nextActiveTab = nextSelectedSection == 'All Sections'
        ? 'All'
        : nextSelectedSection;

    setState(() {
      sellerOptions = nextSellerOptions;
      financialYearOptions = nextFinancialYearOptions;
      sectionOptions = nextSectionOptions;
      selectedSeller = nextSelectedSeller;
      selectedFinancialYear = nextSelectedFinancialYear;
      selectedSection = nextSelectedSection;
      activeSectionTab = nextActiveTab;
      filteredRows = nextFilteredRows;
      tableRows = nextTableRows;
      _filteredMetrics = _buildFilteredMetrics(
        rows: nextFilteredRows,
        activeTab: nextActiveTab,
      );
    });
    filterWatch.stop();
    _logPerformance(
      'filter apply',
      filterWatch,
      details:
          'summaryRows=${nextFilteredRows.length} tableRows=${nextTableRows.length} sellerFilter=${selectedSeller.isEmpty ? 'ALL' : selectedSeller}',
    );
  }

  void _selectSectionTab(String tab) {
    setState(() {
      activeSectionTab = tab;
      selectedSection = tab == 'All' ? 'All Sections' : tab;
    });
    _applyFilters();
  }

  bool _isSupportedSectionTab(String value) {
    return value != 'All Sections' && _sectionTabs.contains(value);
  }

  List<ReconciliationRow> _baseRowsForSection(String selectedSectionValue) {
    if (selectedSectionValue == 'All Sections') {
      return List<ReconciliationRow>.of(allRows);
    }

    final sectionRows =
        _sectionResultCache?.rowsBySection[selectedSectionValue] ??
        const <ReconciliationRow>[];
    return List<ReconciliationRow>.of(sectionRows);
  }

  List<ReconciliationRow> _rowsForCurrentSummaryScope(
    List<ReconciliationRow> rows,
  ) {
    if (_viewMode == ReconciliationViewMode.audit) {
      return List<ReconciliationRow>.of(rows);
    }

    return rows.where(isReconciliationRowSummaryEligible).toList();
  }

  List<ReconciliationRow> _rowsForVisibleSellers(List<ReconciliationRow> rows) {
    if (_viewMode == ReconciliationViewMode.audit) {
      return List<ReconciliationRow>.of(rows);
    }

    final rowsBySeller = <String, List<ReconciliationRow>>{};
    for (final row in rows) {
      final sellerKey = buildSellerSectionDisplayKey(row);
      rowsBySeller.putIfAbsent(sellerKey, () => <ReconciliationRow>[]).add(row);
    }

    final visibleSellerKeys = rowsBySeller.entries
        .where(
          (entry) =>
              isReconciliationSellerVisibleInViewMode(entry.value, _viewMode),
        )
        .map((entry) => entry.key)
        .toSet();

    return rows
        .where(
          (row) =>
              visibleSellerKeys.contains(buildSellerSectionDisplayKey(row)),
        )
        .toList();
  }

  List<String> _buildSectionOptions({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedStatusValue,
  }) {
    if (identical(rows, allRows)) {
      final cacheKey = _sectionOptionsCacheKey(
        selectedSellerValue: selectedSellerValue,
        selectedFinancialYearValue: selectedFinancialYearValue,
        selectedStatusValue: selectedStatusValue,
      );
      final cachedOptions = _sectionOptionsCache[cacheKey];
      if (cachedOptions != null) {
        return cachedOptions;
      }

      final computedOptions = _computeSectionOptions(
        rows: rows,
        selectedSellerValue: selectedSellerValue,
        selectedFinancialYearValue: selectedFinancialYearValue,
        selectedStatusValue: selectedStatusValue,
      );
      _sectionOptionsCache[cacheKey] = computedOptions;
      return computedOptions;
    }

    return _computeSectionOptions(
      rows: rows,
      selectedSellerValue: selectedSellerValue,
      selectedFinancialYearValue: selectedFinancialYearValue,
      selectedStatusValue: selectedStatusValue,
    );
  }

  String _sectionOptionsCacheKey({
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedStatusValue,
  }) {
    return [
      _viewMode.name,
      selectedSellerValue,
      selectedFinancialYearValue,
      selectedStatusValue,
    ].join('\u0001');
  }

  List<String> _computeSectionOptions({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedStatusValue,
  }) {
    final scopedRows = _filterRows(
      rows: rows,
      selectedSellerValue: selectedSellerValue,
      selectedFinancialYearValue: selectedFinancialYearValue,
      selectedSectionValue: 'All Sections',
      selectedStatusValue: selectedStatusValue,
    );

    final sections = scopedRows
        .map((e) => e.section.trim())
        .where(_isSupportedSectionTab)
        .toSet()
        .toList();

    sortSections(sections);
    return ['All Sections', ...sections];
  }

  List<ReconciliationRow> _filterRows({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
  }) {
    if (identical(rows, allRows)) {
      final cacheKey = _filterRowsCacheKey(
        selectedSellerValue: selectedSellerValue,
        selectedFinancialYearValue: selectedFinancialYearValue,
        selectedSectionValue: selectedSectionValue,
        selectedStatusValue: selectedStatusValue,
      );
      final cachedRows = _filterRowsCache[cacheKey];
      if (cachedRows != null) {
        return cachedRows;
      }

      final computedRows = _computeFilteredRows(
        rows: rows,
        selectedSellerValue: selectedSellerValue,
        selectedFinancialYearValue: selectedFinancialYearValue,
        selectedSectionValue: selectedSectionValue,
        selectedStatusValue: selectedStatusValue,
        preserveVisibleSellerHistory: false,
        sellerExceptionFilter: null,
      );
      _filterRowsCache[cacheKey] = computedRows;
      return computedRows;
    }

    return _computeFilteredRows(
      rows: rows,
      selectedSellerValue: selectedSellerValue,
      selectedFinancialYearValue: selectedFinancialYearValue,
      selectedSectionValue: selectedSectionValue,
      selectedStatusValue: selectedStatusValue,
      preserveVisibleSellerHistory: false,
      sellerExceptionFilter: null,
    );
  }

  List<ReconciliationRow> _filterTableRows({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
  }) {
    return _computeFilteredRows(
      rows: rows,
      selectedSellerValue: selectedSellerValue,
      selectedFinancialYearValue: selectedFinancialYearValue,
      selectedSectionValue: selectedSectionValue,
      selectedStatusValue: selectedStatusValue,
      preserveVisibleSellerHistory: true,
      sellerExceptionFilter: _activeSellerExceptionFilter,
    );
  }

  String _filterRowsCacheKey({
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
  }) {
    return [
      _viewMode.name,
      selectedSellerValue,
      selectedFinancialYearValue,
      selectedSectionValue,
      selectedStatusValue,
    ].join('\u0001');
  }

  bool _matchesSellerQuery(ReconciliationRow row, String query) {
    final normalizedQuery = query.trim().toUpperCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final haystack = <String>{
      _sellerFilterLabel(row),
      row.resolvedSellerName.trim(),
      row.sellerName.trim(),
      normalizePan(row.resolvedPan),
      normalizePan(row.sellerPan),
    }.join(' ').toUpperCase();

    return haystack.contains(normalizedQuery);
  }

  String? _sellerLevelStatusFromFilter(String selectedStatusValue) {
    switch (selectedStatusValue.trim()) {
      case ReconciliationStatus.matched:
        return CalculationService.sellerStatusMatched;
      case CalculationService.sellerStatusMismatch:
      case 'Mismatch Only':
        return CalculationService.sellerStatusMismatch;
      case CalculationService.sellerStatusNo26Q:
      case ReconciliationStatus.applicableButNo26Q:
        return CalculationService.sellerStatusNo26Q;
      case CalculationService.sellerStatusOnly26Q:
      case ReconciliationStatus.onlyIn26Q:
        return CalculationService.sellerStatusOnly26Q;
      default:
        return null;
    }
  }

  bool _isSellerLevelStatusFilter(String selectedStatusValue) {
    return _sellerLevelStatusFromFilter(selectedStatusValue) != null;
  }

  List<ReconciliationRow> _filterRowsBySellerLevelStatus({
    required List<ReconciliationRow> rows,
    required String selectedStatusValue,
  }) {
    final expectedStatus = _sellerLevelStatusFromFilter(selectedStatusValue);
    if (expectedStatus == null) {
      return rows;
    }

    final grouped = <String, List<ReconciliationRow>>{};
    for (final row in rows) {
      final key = buildSellerSectionDisplayKey(row);
      grouped.putIfAbsent(key, () => <ReconciliationRow>[]).add(row);
    }

    final matchingRows = <ReconciliationRow>[];
    final sortedKeys = grouped.keys.toList()..sort();
    for (final key in sortedKeys) {
      final sellerRows = grouped[key]!;
      final snapshot = CalculationService.buildSellerLevelStatus(sellerRows);
      if (snapshot.status == expectedStatus) {
        matchingRows.addAll(sellerRows);
      }
    }

    return matchingRows;
  }

  List<ReconciliationRow> _computeFilteredRows({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
    required bool preserveVisibleSellerHistory,
    required _SellerExceptionFilter? sellerExceptionFilter,
  }) {
    var baseRows = identical(rows, allRows)
        ? _baseRowsForSection(selectedSectionValue)
        : rows;

    if (selectedSellerValue.trim().isNotEmpty) {
      baseRows = baseRows
          .where((row) => _matchesSellerQuery(row, selectedSellerValue))
          .toList();
    }

    if (selectedFinancialYearValue != 'All FY') {
      baseRows = baseRows
          .where(
            (row) =>
                row.financialYear.trim() == selectedFinancialYearValue.trim(),
          )
          .toList();
    }

    if (selectedSectionValue != 'All Sections' && !identical(baseRows, rows)) {
      // Section scoping already narrowed the base list when filtering from the
      // cached reconciliation result.
    } else if (selectedSectionValue != 'All Sections') {
      baseRows = baseRows
          .where((row) => row.section.trim() == selectedSectionValue)
          .toList();
    }

    final sellerHistoryRows = _rowsForVisibleSellers(baseRows);
    var summaryScopedRows = _rowsForCurrentSummaryScope(baseRows);

    if (selectedStatusValue != 'All Status') {
      if (_isSellerLevelStatusFilter(selectedStatusValue)) {
        summaryScopedRows = _filterRowsBySellerLevelStatus(
          rows: summaryScopedRows,
          selectedStatusValue: selectedStatusValue,
        );
      } else {
        summaryScopedRows = summaryScopedRows.where((row) {
          final status = row.status.trim();
          final selected = selectedStatusValue.trim();
          return status == selected;
        }).toList();
      }
    }

    if (sellerExceptionFilter != null) {
      final visibleSellerKeys = _sellerKeysForExceptionFilter(
        rows: summaryScopedRows,
        filter: sellerExceptionFilter,
      );
      summaryScopedRows = summaryScopedRows
          .where(
            (row) =>
                visibleSellerKeys.contains(buildSellerSectionDisplayKey(row)),
          )
          .toList();
    }

    var filteredRows = List<ReconciliationRow>.of(summaryScopedRows);
    if (preserveVisibleSellerHistory) {
      final visibleSellerKeys = summaryScopedRows
          .map(buildSellerSectionDisplayKey)
          .toSet();
      filteredRows = sellerHistoryRows
          .where(
            (row) =>
                visibleSellerKeys.contains(buildSellerSectionDisplayKey(row)),
          )
          .toList();
    }

    filteredRows.sort((a, b) {
      final sellerCompare = _sellerFilterLabel(a)
          .trim()
          .toUpperCase()
          .compareTo(_sellerFilterLabel(b).trim().toUpperCase());
      if (sellerCompare != 0) return sellerCompare;

      final panCompare = normalizePan(
        a.resolvedPan,
      ).compareTo(normalizePan(b.resolvedPan));
      if (panCompare != 0) return panCompare;

      final fyCompare = a.financialYear.trim().compareTo(
        b.financialYear.trim(),
      );
      if (fyCompare != 0) return fyCompare;

      return CalculationService.compareMonthLabels(a.month, b.month);
    });

    return filteredRows;
  }

  _FilteredMetrics _buildFilteredMetrics({
    required List<ReconciliationRow> rows,
    required String activeTab,
  }) {
    final sectionCounts = <String, int>{};
    final sectionMismatchCounts = <String, int>{
      for (final section in _sectionTabs) section: 0,
    };
    final mismatchReasonCounts = <String, int>{
      'No 26Q entry': 0,
      'Amount mismatch': 0,
      'TDS mismatch': 0,
      'Timing difference': 0,
      'PAN/name mismatch': 0,
    };
    final sellerKeys = <String>{};

    var matchedCount = 0;
    var summaryMismatchRows = 0;
    var mismatchRowsCount = 0;
    var timingDifferenceCount = 0;
    var shortDeductionCount = 0;
    var excessDeductionCount = 0;
    var purchaseOnlyCount = 0;
    var only26QCount = 0;
    var applicableButNo26QCount = 0;
    var basicAmount = 0.0;
    var applicableAmount = 0.0;
    var tds26QAmount = 0.0;
    var expectedTds = 0.0;
    var actualTds = 0.0;
    var tdsDifference = 0.0;
    var amountDifference = 0.0;
    var shortDeductionAmount = 0.0;
    var excessDeductionAmount = 0.0;
    var timingDifferenceAmount = 0.0;
    var purchaseOnlyAmount = 0.0;
    var only26QAmount = 0.0;
    var applicableButNo26QAmount = 0.0;
    var applicableButNo26QTds = 0.0;

    for (final row in rows) {
      final section = row.section.trim();
      final status = row.status.trim();
      final upperStatus = status.toUpperCase();
      sellerKeys.add(buildSellerSectionDisplayKey(row));
      sectionCounts[section] = (sectionCounts[section] ?? 0) + 1;

      if (status == ReconciliationStatus.matched) {
        matchedCount++;
      } else {
        summaryMismatchRows++;
      }

      if (sectionMismatchCounts.containsKey(
            section == 'All Sections' ? 'All' : section,
          ) &&
          upperStatus != 'MATCHED') {
        sectionMismatchCounts[section] =
            (sectionMismatchCounts[section] ?? 0) + 1;
      }
      if (upperStatus != 'MATCHED') {
        sectionMismatchCounts['All'] = (sectionMismatchCounts['All'] ?? 0) + 1;
      }

      basicAmount += row.basicAmount;
      applicableAmount += row.applicableAmount;
      tds26QAmount += row.tds26QAmount;
      expectedTds += row.expectedTds;
      actualTds += row.actualTds;
      tdsDifference += row.tdsDifference;
      amountDifference += row.amountDifference;

      if (status == ReconciliationStatus.timingDifference) {
        timingDifferenceCount++;
        timingDifferenceAmount += row.monthTdsDifference.abs();
      }
      if (status == ReconciliationStatus.shortDeduction) {
        shortDeductionCount++;
        mismatchRowsCount++;
        shortDeductionAmount += row.tdsDifference.abs();
      }
      if (status == ReconciliationStatus.excessDeduction) {
        excessDeductionCount++;
        mismatchRowsCount++;
        excessDeductionAmount += row.tdsDifference.abs();
      }
      if (status == ReconciliationStatus.purchaseOnly) {
        purchaseOnlyCount++;
        mismatchRowsCount++;
        purchaseOnlyAmount += row.basicAmount;
      }
      if (status == ReconciliationStatus.onlyIn26Q) {
        only26QCount++;
        mismatchRowsCount++;
        only26QAmount += row.tds26QAmount;
      }
      if (row.applicableAmount > 0 &&
          row.tds26QAmount == 0 &&
          row.actualTds == 0) {
        applicableButNo26QCount++;
        applicableButNo26QAmount += row.applicableAmount;
        applicableButNo26QTds += row.expectedTds;
      }

      if (status == ReconciliationStatus.applicableButNo26Q) {
        mismatchReasonCounts['No 26Q entry'] =
            (mismatchReasonCounts['No 26Q entry'] ?? 0) + 1;
      }
      if (status == ReconciliationStatus.amountMismatch) {
        mismatchReasonCounts['Amount mismatch'] =
            (mismatchReasonCounts['Amount mismatch'] ?? 0) + 1;
      }
      if (status == ReconciliationStatus.shortDeduction ||
          status == ReconciliationStatus.excessDeduction) {
        mismatchReasonCounts['TDS mismatch'] =
            (mismatchReasonCounts['TDS mismatch'] ?? 0) + 1;
      }
      if (status == ReconciliationStatus.timingDifference) {
        mismatchReasonCounts['Timing difference'] =
            (mismatchReasonCounts['Timing difference'] ?? 0) + 1;
      }
      if (row.identityConfidence < 0.75 ||
          normalizePan(row.resolvedPan).isEmpty ||
          row.remarks.contains('PAN from GSTIN')) {
        mismatchReasonCounts['PAN/name mismatch'] =
            (mismatchReasonCounts['PAN/name mismatch'] ?? 0) + 1;
      }
    }

    final topMismatchSection = () {
      final mismatchEntries =
          sectionCounts.keys
              .map(
                (section) =>
                    MapEntry(section, sectionMismatchCounts[section] ?? 0),
              )
              .where((entry) => entry.value > 0)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      return mismatchEntries.isEmpty ? '-' : mismatchEntries.first.key;
    }();

    final summary = ReconciliationSummary(
      section: activeTab == 'All' ? 'ALL' : activeTab,
      totalRows: rows.length,
      matchedRows: matchedCount,
      mismatchRows: summaryMismatchRows,
      purchaseOnlyRows: purchaseOnlyCount,
      only26QRows: only26QCount,
      applicableButNo26QRows: applicableButNo26QCount,
      sourceAmount: basicAmount,
      applicableAmount: applicableAmount,
      tds26QAmount: tds26QAmount,
      expectedTds: expectedTds,
      actualTds: actualTds,
      amountDifference: amountDifference,
      tdsDifference: tdsDifference,
    );

    final mismatchPercentage = rows.isEmpty
        ? 0.0
        : (mismatchRowsCount / rows.length) * 100;

    return _FilteredMetrics(
      summary: summary,
      mismatchReasonCounts: mismatchReasonCounts,
      sectionCounts: {
        for (final entry
            in (sectionCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value))))
          entry.key: entry.value,
      },
      sectionMismatchCounts: sectionMismatchCounts,
      topMismatchSection: topMismatchSection,
      totalSellers: sellerKeys.length,
      totalSections: sectionCounts.length,
      matchedCount: matchedCount,
      mismatchRowsCount: mismatchRowsCount,
      timingDifferenceCount: timingDifferenceCount,
      shortDeductionCount: shortDeductionCount,
      excessDeductionCount: excessDeductionCount,
      purchaseOnlyCount: purchaseOnlyCount,
      only26QCount: only26QCount,
      applicableButNo26QCount: applicableButNo26QCount,
      matchedPercentage: rows.isEmpty
          ? 0.0
          : (matchedCount / rows.length) * 100,
      mismatchPercentage: mismatchPercentage,
      basicAmount: basicAmount,
      applicableAmount: applicableAmount,
      tds26QAmount: tds26QAmount,
      expectedTds: expectedTds,
      actualTds: actualTds,
      tdsDifference: tdsDifference,
      amountDifference: amountDifference,
      shortDeductionAmount: shortDeductionAmount,
      excessDeductionAmount: excessDeductionAmount,
      timingDifferenceAmount: timingDifferenceAmount,
      purchaseOnlyAmount: purchaseOnlyAmount,
      only26QAmount: only26QAmount,
      netMismatchAmount:
          shortDeductionAmount +
          excessDeductionAmount +
          purchaseOnlyAmount +
          only26QAmount,
      applicableButNo26QAmount: applicableButNo26QAmount,
      applicableButNo26QTds: applicableButNo26QTds,
    );
  }

  int _countByStatus(String status) {
    switch (status) {
      case ReconciliationStatus.matched:
        return _filteredMetrics?.matchedCount ?? 0;
      case ReconciliationStatus.timingDifference:
        return _filteredMetrics?.timingDifferenceCount ?? 0;
      case ReconciliationStatus.shortDeduction:
        return _filteredMetrics?.shortDeductionCount ?? 0;
      case ReconciliationStatus.excessDeduction:
        return _filteredMetrics?.excessDeductionCount ?? 0;
      case ReconciliationStatus.purchaseOnly:
        return _filteredMetrics?.purchaseOnlyCount ?? 0;
      case ReconciliationStatus.onlyIn26Q:
        return _filteredMetrics?.only26QCount ?? 0;
      default:
        return filteredRows.where((e) => e.status == status).length;
    }
  }

  int _applicableButNo26QCount() {
    return _filteredMetrics?.applicableButNo26QCount ?? 0;
  }

  double _applicableButNo26QAmount() {
    return _filteredMetrics?.applicableButNo26QAmount ?? 0.0;
  }

  double _applicableButNo26QTds() {
    return _filteredMetrics?.applicableButNo26QTds ?? 0.0;
  }

  double _shortDeductionAmount() {
    return _filteredMetrics?.shortDeductionAmount ?? 0.0;
  }

  double _excessDeductionAmount() {
    return _filteredMetrics?.excessDeductionAmount ?? 0.0;
  }

  double _timingDifferenceAmount() {
    return _filteredMetrics?.timingDifferenceAmount ?? 0.0;
  }

  double _netMismatchAmount() {
    return _filteredMetrics?.netMismatchAmount ?? 0.0;
  }

  int _totalSellers() {
    return _filteredMetrics?.totalSellers ?? 0;
  }

  int _mismatchRowsCount() {
    return _filteredMetrics?.mismatchRowsCount ?? 0;
  }

  double _matchedPercentage() {
    return _filteredMetrics?.matchedPercentage ?? 0.0;
  }

  double _mismatchPercentage() {
    return _filteredMetrics?.mismatchPercentage ?? 0.0;
  }

  ReconciliationSummary? _activeSummary() {
    return _filteredMetrics?.summary;
  }

  int _mismatchCountForSection(String section) {
    return _filteredMetrics?.sectionMismatchCounts[section] ?? 0;
  }

  List<ReconciliationRow> _stableSectionCountScope() {
    if (_viewMode == ReconciliationViewMode.audit) {
      return List<ReconciliationRow>.of(allRows);
    }

    return _rowsForVisibleSellers(allRows);
  }

  int _sellerCountForSection(String section) {
    final stableRows = _stableSectionCountScope();
    final scopedRows = section == 'All'
        ? stableRows
        : stableRows.where((row) => row.section.trim() == section).toList();

    return scopedRows.map(buildSellerSectionDisplayKey).toSet().length;
  }

  Map<String, int> _activeMismatchReasonCounts() {
    return _filteredMetrics?.mismatchReasonCounts ??
        const <String, int>{
          'No 26Q entry': 0,
          'Amount mismatch': 0,
          'TDS mismatch': 0,
          'Timing difference': 0,
          'PAN/name mismatch': 0,
        };
  }

  List<String> _unsupportedSectionsInActiveScope() {
    final unsupported =
        filteredRows
            .map((row) => row.section.trim())
            .where(
              (section) =>
                  section.isNotEmpty &&
                  !CalculationService.supportedSections.contains(section),
            )
            .toSet()
            .toList()
          ..sort();

    return unsupported;
  }

  void _setViewMode(ReconciliationViewMode nextMode) {
    if (_viewMode == nextMode) {
      return;
    }

    setState(() {
      _viewMode = nextMode;
    });
    _applyFilters();
  }

  int _summaryHiddenSellerCount() {
    if (_viewMode != ReconciliationViewMode.summary) {
      return 0;
    }

    final allSellerKeys = allRows.map(buildSellerSectionDisplayKey).toSet();
    final visibleSellerKeys = _rowsForCurrentSummaryScope(
      allRows,
    ).map(buildSellerSectionDisplayKey).toSet();
    return allSellerKeys.length - visibleSellerKeys.length;
  }

  int _summaryHiddenRowCount() {
    if (_viewMode != ReconciliationViewMode.summary) {
      return 0;
    }

    return allRows.length - _rowsForVisibleSellers(allRows).length;
  }

  String? _viewModeHelperText() {
    if (_viewMode != ReconciliationViewMode.summary) {
      return null;
    }

    final hiddenSellers = _summaryHiddenSellerCount();
    final hiddenRows = _summaryHiddenRowCount();
    if (hiddenSellers <= 0 && hiddenRows <= 0) {
      return null;
    }

    if (hiddenSellers > 0 && hiddenRows > 0) {
      return '$hiddenSellers below-threshold sellers and $hiddenRows non-actionable rows are hidden in Summary View.';
    }
    if (hiddenSellers > 0) {
      return '$hiddenSellers below-threshold sellers are hidden in Summary View.';
    }
    return '$hiddenRows non-actionable rows are hidden in Summary View.';
  }

  Widget _buildSectionTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _sectionTabs.map((section) {
          final isActive = activeSectionTab == section;
          final sellerCount = _sellerCountForSection(section);
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => _selectSectionTab(section),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isActive ? null : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF93C5FD)
                        : AppColorScheme.border,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          section == 'All'
                              ? section
                              : sectionDisplayLabel(section),
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : AppColorScheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          section == 'All'
                              ? 'Unique sellers'
                              : 'Section sellers',
                          style: TextStyle(
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.72)
                                : AppColorScheme.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF1E40AF)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$sellerCount sellers',
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF1D4ED8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionSummaryStrip() {
    final summary = _activeSummary();
    if (summary == null) return const SizedBox.shrink();
    final activeSectionCode = activeSectionTab == 'All'
        ? 'All Sections'
        : activeSectionTab;
    final sourceFileCount = activeSectionTab == 'All'
        ? widget.sourceFileCountBySection.values.fold<int>(
            0,
            (sum, count) => sum + count,
          )
        : (widget.sourceFileCountBySection[activeSectionTab] ?? 0);
    final sourceRowCount = activeSectionTab == 'All'
        ? widget.sourceRowsBySection.values.fold<int>(
            0,
            (sum, rows) => sum + rows.length,
          )
        : (widget.sourceRowsBySection[activeSectionTab]?.length ?? 0);
    final mismatchReasonCounts = _activeMismatchReasonCounts();
    final unsupportedSections = _unsupportedSectionsInActiveScope();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReconciliationSummaryHeader(
            title:
                '${activeSectionTab == 'All' ? 'Combined' : sectionDisplayLabel(activeSectionTab)} Summary',
            subtitle:
                '$activeSectionCode  •  $sourceFileCount source file(s)  •  '
                '$sourceRowCount source row(s)',
          ),
          if (activeSectionTab == 'All' && unsupportedSections.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Text(
                'All includes unsupported/unknown 26Q sections: '
                '${unsupportedSections.join(', ')}. '
                'These rows remain visible for review and are included in the combined All-sections summary. '
                'Supported sections remain '
                '${CalculationService.supportedSections.join(', ')}.',
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ReconciliationReasonChip(
                label: 'No 26Q entry',
                count: mismatchReasonCounts['No 26Q entry'] ?? 0,
                color: const Color(0xFFB45309),
              ),
              ReconciliationReasonChip(
                label: 'Amount mismatch',
                count: mismatchReasonCounts['Amount mismatch'] ?? 0,
                color: const Color(0xFFDC2626),
              ),
              ReconciliationReasonChip(
                label: 'TDS mismatch',
                count: mismatchReasonCounts['TDS mismatch'] ?? 0,
                color: const Color(0xFF7C3AED),
              ),
              ReconciliationReasonChip(
                label: 'Timing difference',
                count: mismatchReasonCounts['Timing difference'] ?? 0,
                color: const Color(0xFF0F766E),
              ),
              ReconciliationReasonChip(
                label: 'PAN/name mismatch',
                count: mismatchReasonCounts['PAN/name mismatch'] ?? 0,
                color: const Color(0xFF1D4ED8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ReconciliationSummaryPill(
                label: 'Total Rows',
                value: summary.totalRows.toString(),
              ),
              ReconciliationSummaryPill(
                label: 'Mismatch Rows',
                value: summary.mismatchRows.toString(),
              ),
              ReconciliationSummaryPill(
                label: 'Source Amount',
                value: _fmt(summary.sourceAmount),
              ),
              ReconciliationSummaryPill(
                label: '26Q Amount',
                value: _fmt(summary.tds26QAmount),
              ),
              ReconciliationSummaryPill(
                label: 'Expected TDS',
                value: _fmt(summary.expectedTds),
              ),
              ReconciliationSummaryPill(
                label: 'Actual TDS',
                value: _fmt(summary.actualTds),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _totalSections() {
    return _filteredMetrics?.totalSections ?? 0;
  }

  Map<String, int> _sectionCounts() {
    return _filteredMetrics?.sectionCounts ?? const <String, int>{};
  }

  String _topMismatchSection() {
    return _filteredMetrics?.topMismatchSection ?? '-';
  }

  int _skippedSellerCount(SkippedRowSummary skippedRowSummary) {
    final skippedSellerNames = skippedRowSummary.samples
        .map((sample) => normalizeName(sample.sellerName))
        .where((seller) => seller.isNotEmpty)
        .toSet();

    return filteredRows
        .where((row) {
          final resolvedName = normalizeName(row.resolvedSellerName);
          final sellerName = normalizeName(row.sellerName);
          return skippedSellerNames.contains(resolvedName) ||
              skippedSellerNames.contains(sellerName);
        })
        .map(buildSellerDisplayKey)
        .toSet()
        .length;
  }

  int _applicableButNo26QSellerCount() {
    return _sellerKeysForExceptionFilter(
      rows: filteredRows,
      filter: _SellerExceptionFilter.missing26Q,
    ).length;
  }

  Map<String, int> _sellerOutcomeCounts() {
    final rowsBySeller = <String, List<ReconciliationRow>>{};

    for (final row in filteredRows) {
      final scopedSellerKey = buildSellerSectionDisplayKey(row);
      if (scopedSellerKey.isEmpty) continue;
      rowsBySeller
          .putIfAbsent(scopedSellerKey, () => <ReconciliationRow>[])
          .add(row);
    }

    var matchedSellers = 0;
    var mismatchSellers = 0;
    var only26QSellers = 0;
    var belowThresholdOnlySellers = 0;

    for (final sellerRows in rowsBySeller.values) {
      final isBelowThresholdOnlySeller = sellerRows.every(
        (row) =>
            row.status == ReconciliationStatus.belowThreshold ||
            row.status == ReconciliationStatus.noDeductionRequired,
      );
      if (isBelowThresholdOnlySeller) {
        belowThresholdOnlySellers++;
        continue;
      }

      final snapshot = CalculationService.buildSellerLevelStatus(sellerRows);
      switch (snapshot.status) {
        case CalculationService.sellerStatusMatched:
          matchedSellers++;
          break;
        case CalculationService.sellerStatusOnly26Q:
          only26QSellers++;
          break;
        case CalculationService.sellerStatusMismatch:
        case CalculationService.sellerStatusNo26Q:
          mismatchSellers++;
          break;
      }
    }

    return <String, int>{
      'matched': matchedSellers,
      'mismatch': mismatchSellers,
      'only26q': only26QSellers,
      'belowThresholdOnly': belowThresholdOnlySellers,
    };
  }

  Set<String> _sellerKeysForExceptionFilter({
    required List<ReconciliationRow> rows,
    required _SellerExceptionFilter filter,
  }) {
    switch (filter) {
      case _SellerExceptionFilter.missing26Q:
        return rows
            .where(
              (row) =>
                  row.applicableAmount > 0 &&
                  row.tds26QAmount == 0 &&
                  row.actualTds == 0,
            )
            .map(buildSellerSectionDisplayKey)
            .toSet();
      case _SellerExceptionFilter.skippedRows:
        final skippedSummary =
            _sectionResultCache?.skippedRowSummary ?? SkippedRowSummary.empty;
        final skippedSellerNames = skippedSummary.samples
            .map((sample) => normalizeName(sample.sellerName))
            .where((seller) => seller.isNotEmpty)
            .toSet();

        return rows
            .where((row) {
              final resolvedName = normalizeName(row.resolvedSellerName);
              final sellerName = normalizeName(row.sellerName);
              return skippedSellerNames.contains(resolvedName) ||
                  skippedSellerNames.contains(sellerName);
            })
            .map(buildSellerSectionDisplayKey)
            .toSet();
    }
  }

  String _sellerExceptionFilterLabel(_SellerExceptionFilter filter) {
    switch (filter) {
      case _SellerExceptionFilter.skippedRows:
        return 'Seller exception: Skipped rows';
      case _SellerExceptionFilter.missing26Q:
        return 'Seller exception: Missing 26Q deductions';
    }
  }

  void _toggleSellerExceptionFilter(_SellerExceptionFilter filter) {
    setState(() {
      _activeSellerExceptionFilter = _activeSellerExceptionFilter == filter
          ? null
          : filter;
    });
    _applyFilters();
  }

  double _purchaseOnlyAmount() {
    return _filteredMetrics?.purchaseOnlyAmount ?? 0.0;
  }

  double _only26QAmount() {
    return _filteredMetrics?.only26QAmount ?? 0.0;
  }

  String _sellerFilterDisplayValue() {
    final query = selectedSeller.trim();
    return query.isEmpty ? 'All Visible Sellers' : query;
  }

  String _exportSellerLabel() {
    final query = selectedSeller.trim();
    return query.isEmpty ? 'All Sellers' : query;
  }

  List<ReconciliationRow> _rowsForAllSectionsExport() {
    return _filterRows(
      rows: allRows,
      selectedSellerValue: selectedSeller,
      selectedFinancialYearValue: selectedFinancialYear,
      selectedSectionValue: 'All Sections',
      selectedStatusValue: selectedStatus,
    );
  }

  Future<void> _exportCurrentSectionExcel() async {
    try {
      final filePath = await ExcelExportService.exportReconciliationExcel(
        rows: filteredRows,
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        gstNo: widget.gstNo,
        financialYear: selectedFinancialYear,
        sellerName: _exportSellerLabel(),
      );

      if (!mounted) return;
      _showSnackBar('Exported to: $filePath');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _exportAllSectionsExcel() async {
    final rows = _rowsForAllSectionsExport();
    try {
      final filePath = await ExcelExportService.exportReconciliationExcel(
        rows: rows,
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        gstNo: widget.gstNo,
        financialYear: selectedFinancialYear,
        sellerName: _exportSellerLabel(),
      );

      if (!mounted) return;
      _showSnackBar('Exported to: $filePath');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _exportPivotExcel() async {
    try {
      final filePath = await ExcelExportService.exportPivotSummaryExcel(
        rows: filteredRows,
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        gstNo: widget.gstNo,
        financialYear: selectedFinancialYear,
        sellerName: _exportSellerLabel(),
      );

      if (!mounted) return;
      _showSnackBar('Pivot Exported to: $filePath');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Pivot export failed: $e');
    }
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.fixed, content: Text(message)),
      );
  }

  Color _statusColor(String status) {
    switch (status) {
      case CalculationService.sellerStatusMatched:
      case ReconciliationStatus.matched:
        return Colors.green.shade50;
      case CalculationService.sellerStatusMismatch:
        return Colors.red.shade50;
      case CalculationService.sellerStatusNo26Q:
      case ReconciliationStatus.applicableButNo26Q:
        return Colors.orange.shade50;
      case ReconciliationStatus.sectionMissing:
      case ReconciliationStatus.reviewRequired:
        return const Color(0xFFFFF7ED);
      case CalculationService.sellerStatusOnly26Q:
      case ReconciliationStatus.onlyIn26Q:
        return Colors.purple.shade50;
      case ReconciliationStatus.belowThreshold:
        return Colors.grey.shade100;
      case ReconciliationStatus.timingDifference:
        return Colors.teal.shade50;
      case ReconciliationStatus.shortDeduction:
        return Colors.orange.shade50;
      case ReconciliationStatus.excessDeduction:
        return Colors.red.shade50;
      case ReconciliationStatus.purchaseOnly:
        return Colors.blue.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case CalculationService.sellerStatusMismatch:
        return const Color(0xFFB91C1C);
      case CalculationService.sellerStatusNo26Q:
        return const Color(0xFFB45309);
      case ReconciliationStatus.belowThreshold:
        return const Color(0xFF64748B);
      case ReconciliationStatus.sectionMissing:
      case ReconciliationStatus.reviewRequired:
        return const Color(0xFF9A3412);
      case ReconciliationStatus.applicableButNo26Q:
        return const Color(0xFFB45309);
      case CalculationService.sellerStatusMatched:
      case ReconciliationStatus.matched:
        return const Color(0xFF166534);
      case ReconciliationStatus.amountMismatch:
        return const Color(0xFFB91C1C);
      case 'PAN/name mismatch':
        return const Color(0xFF1D4ED8);
      case CalculationService.sellerStatusOnly26Q:
      case ReconciliationStatus.onlyIn26Q:
        return const Color(0xFF6D28D9);
      case ReconciliationStatus.timingDifference:
        return Colors.teal.shade800;
      case ReconciliationStatus.shortDeduction:
        return Colors.orange.shade800;
      case ReconciliationStatus.excessDeduction:
        return Colors.red.shade800;
      case ReconciliationStatus.purchaseOnly:
        return Colors.blue.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  String _fmt(double value) => value.toStringAsFixed(2);

  String _sellerFilterLabel(ReconciliationRow row) {
    final resolvedName = row.resolvedSellerName.trim();
    final fallbackName = row.sellerName.trim();
    final displayName = resolvedName.isNotEmpty ? resolvedName : fallbackName;
    final resolvedPan = normalizePan(row.resolvedPan);

    if (displayName.isEmpty) {
      return resolvedPan.isEmpty ? '-' : resolvedPan;
    }

    if (resolvedPan.isEmpty) {
      return displayName;
    }

    return '$displayName ($resolvedPan)';
  }

  int _activeSourceFileCount() {
    return activeSectionTab == 'All'
        ? widget.sourceFileCountBySection.values.fold<int>(
            0,
            (sum, count) => sum + count,
          )
        : (widget.sourceFileCountBySection[activeSectionTab] ?? 0);
  }

  int _activeSourceRowCount() {
    return activeSectionTab == 'All'
        ? widget.sourceRowsBySection.values.fold<int>(
            0,
            (sum, rows) => sum + rows.length,
          )
        : (widget.sourceRowsBySection[activeSectionTab]?.length ?? 0);
  }

  Widget _buildFilters() {
    return ReconciliationFilters(
      selectedSeller: selectedSeller,
      selectedFinancialYear: selectedFinancialYear,
      selectedSection: selectedSection,
      selectedStatus: selectedStatus,
      sellerOptions: sellerOptions,
      financialYearOptions: financialYearOptions,
      sectionOptions: sectionOptions,
      statusOptions: statusOptions,
      showSectionFilter: false,
      onSellerChanged: (value) {
        setState(() => selectedSeller = value);
        _applyFilters();
      },
      onFinancialYearChanged: (value) {
        setState(() => selectedFinancialYear = value);
        _applyFilters();
      },
      onSectionChanged: (value) {
        setState(() {
          selectedSection = value;
          activeSectionTab = value == 'All Sections' ? 'All' : value;
        });
        _applyFilters();
      },
      onStatusChanged: (value) {
        setState(() => selectedStatus = value);
        _applyFilters();
      },
    );
  }

  Widget _buildMainContent() {
    final skippedRowSummary =
        _sectionResultCache?.skippedRowSummary ?? SkippedRowSummary.empty;
    final tableContent = ReconciliationTableSection(
      filteredRows: tableRows,
      skippedRowSummary: skippedRowSummary,
      showSkippedRowImpact:
          _activeSellerExceptionFilter == _SellerExceptionFilter.skippedRows,
      isRecalculating: _isRecalculating,
      formatAmount: _fmt,
      statusColor: _statusColor,
      statusTextColor: _statusTextColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplitView = constraints.maxWidth >= 1180;
        final sellerOutcomeCounts = _sellerOutcomeCounts();
        final analysisPane = SizedBox(
          width: useSplitView ? null : double.infinity,
          child: ReconciliationAnalysisPanel(
            activeSectionTab: activeSectionTab,
            sourceFileCount: _activeSourceFileCount(),
            sourceRowCount: _activeSourceRowCount(),
            totalSellers: _totalSellers(),
            totalSections: _totalSections(),
            manualMappingsCount: manualNameMapping.length,
            matchedSellersCount: sellerOutcomeCounts['matched'] ?? 0,
            mismatchSellersCount: sellerOutcomeCounts['mismatch'] ?? 0,
            only26QSellersCount: sellerOutcomeCounts['only26q'] ?? 0,
            belowThresholdOnlySellersCount:
                sellerOutcomeCounts['belowThresholdOnly'] ?? 0,
            mismatchReasonCounts: _activeMismatchReasonCounts(),
            unsupportedSections: _unsupportedSectionsInActiveScope(),
            skippedSellerCount: _skippedSellerCount(skippedRowSummary),
            skippedRowsCount: skippedRowSummary.total,
            applicableButNo26QSellerCount: _applicableButNo26QSellerCount(),
            applicableButNo26QRowCount: _applicableButNo26QCount(),
            isSkippedRowsFilterActive:
                _activeSellerExceptionFilter ==
                _SellerExceptionFilter.skippedRows,
            isMissing26QFilterActive:
                _activeSellerExceptionFilter ==
                _SellerExceptionFilter.missing26Q,
            onSkippedRowsTap: skippedRowSummary.total <= 0
                ? null
                : () => _toggleSellerExceptionFilter(
                    _SellerExceptionFilter.skippedRows,
                  ),
            onMissing26QTap: _applicableButNo26QCount() <= 0
                ? null
                : () => _toggleSellerExceptionFilter(
                    _SellerExceptionFilter.missing26Q,
                  ),
          ),
        );

        final tablePane = tableContent;

        if (!useSplitView) {
          return Column(
            children: [
              Expanded(child: tablePane),
              const SizedBox(height: 16),
              SizedBox(height: 520, child: analysisPane),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 4, child: tablePane),
            const SizedBox(width: 16),
            Expanded(flex: 1, child: analysisPane),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSectionExportRows = _rowsForAllSectionsExport();
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          ReconciliationTopToolbar(
            buyerName: widget.buyerName,
            buyerPan: widget.buyerPan,
            gstNo: widget.gstNo,
            sectionTabs: _buildSectionTabs(),
            filters: _buildFilters(),
            viewMode: _viewMode,
            isRecalculating: _isRecalculating,
            onViewModeChanged: _setViewMode,
            onRecalculate: _isRecalculating ? null : _recalculateAll,
            viewModeHelperText: _viewModeHelperText(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(title: const Text('Reconciliation')),
      bottomNavigationBar: ReconciliationBottomActionBar(
        onExportCurrentSection: filteredRows.isEmpty
            ? null
            : _exportCurrentSectionExcel,
        onExportAllSections: allSectionExportRows.isEmpty
            ? null
            : _exportAllSectionsExcel,
        onExportPivot: filteredRows.isEmpty ? null : _exportPivotExcel,
      ),
      body: Stack(
        children: [
          body,
          if (_isRecalculating)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _processingMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColorScheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Please wait while the reconciliation results are prepared.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColorScheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
