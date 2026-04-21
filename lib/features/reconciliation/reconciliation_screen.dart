import 'package:flutter/material.dart';

import '../../core/utils/normalize_utils.dart';

import 'models/normalized_transaction_row.dart';
import 'models/tds_26q_row.dart';
import 'models/reconciliation_row.dart';
import 'models/reconciliation_status.dart';
import 'models/seller_mapping.dart';

import 'services/reconciliation_service.dart';
import 'services/excel_export_service.dart';
import '../../services/auto_mapping_service.dart';
import 'services/mapping_service.dart';

import '../../core/utils/reconciliation_helpers.dart';

import 'widgets/reconciliation_filters.dart';
import 'widgets/reconciliation_bottom_action_bar.dart';
import 'widgets/reconciliation_analysis_panel.dart';
import 'widgets/reconciliation_reason_chip.dart';
import 'widgets/reconciliation_summary_header.dart';
import 'widgets/reconciliation_summary_panel.dart';
import 'widgets/reconciliation_summary_pill.dart';
import 'widgets/reconciliation_table_section.dart';
import 'widgets/reconciliation_top_toolbar.dart';

import 'presentation/seller_mapping/seller_mapping_screen.dart';

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

  const _SellerMappingConflict({
    required this.aliasKey,
    required this.message,
  });
}

class ReconciliationScreen extends StatefulWidget {
  final Map<String, List<NormalizedTransactionRow>> sourceRowsBySection;
  final Map<String, int> sourceFileCountBySection;
  final List<Tds26QRow> tdsRows;

  final String buyerName;
  final String buyerPan;
  final String gstNo;

  const ReconciliationScreen({
    super.key,
    required this.sourceRowsBySection,
    this.sourceFileCountBySection = const {},
    required this.tdsRows,
    this.buyerName = '',
    this.buyerPan = '',
    this.gstNo = '',
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
    '194J',
    '194IB',
  ];

  List<ReconciliationRow> allRows = [];
  List<ReconciliationRow> filteredRows = [];
  Map<String, ReconciliationSummary> sectionSummaries = {};
  ReconciliationSummary? combinedSummary;
  SectionReconciliationResult? _sectionResultCache;
  _FilteredMetrics? _filteredMetrics;

  List<String> sellerOptions = ['All Sellers'];
  List<String> financialYearOptions = ['All FY'];
  List<String> sectionOptions = ['All Sections'];

  Map<String, String> manualNameMapping = {};
  final Set<String> blockedAutoMappingAliases = {};

  String selectedSeller = 'All Sellers';
  String selectedFinancialYear = 'All FY';
  String selectedSection = 'All Sections';
  String selectedStatus = 'All Status';
  String activeSectionTab = 'All';

  bool showAllRows = false;
  bool _isRecalculating = false;
  final Map<String, List<ReconciliationRow>> _filterRowsCache = {};
  final Map<String, List<String>> _sectionOptionsCache = {};

  final List<String> statusOptions = const [
    'All Status',
    'Mismatch Only',
    ...ReconciliationStatus.filterOptions,
    'Threshold Crossed Only',
  ];

  @override
  void initState() {
    super.initState();
    _recalculateAll();
  }

  Future<Map<String, String>> _loadManualMappingsFromDb() async {
    final mappings = await MappingService.getAllMappings(
      widget.buyerPan.trim().toUpperCase(),
    );

    final latest = <String, String>{};

    for (final mapping in mappings) {
      final aliasKey = normalizeName(mapping.aliasName.trim());
      final mappedName = mapping.mappedName.trim();

      if (aliasKey.isEmpty || mappedName.isEmpty) continue;
      latest[aliasKey] = mappedName;
    }

    return latest;
  }

  String _normalizeAlias(String value) => normalizeName(value.trim());

  Set<String> _resolveTargetPans(String mappedName) {
    final normalizedMappedName = _normalizeAlias(mappedName);
    final pans = <String>{};

    for (final row in widget.tdsRows) {
      final rowPan = normalizePan(row.panNumber);
      if (rowPan.isEmpty) continue;

      final exactMatch =
          row.deducteeName.trim().toUpperCase() == mappedName.trim().toUpperCase();
      final normalizedMatch =
          _normalizeAlias(row.deducteeName) == normalizedMappedName;

      if (exactMatch || normalizedMatch) {
        pans.add(rowPan);
      }
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
      _recalculateAll();
    }
  }

  Future<void> _recalculateAll() async {
    if (_isRecalculating) return;

    setState(() {
      _isRecalculating = true;
    });

    try {
      final prevSeller = selectedSeller;
      final prevFY = selectedFinancialYear;
      final prevSection = selectedSection;
      final prevStatus = selectedStatus;
      final latestManualMappings = await _loadManualMappingsFromDb();
      final sourceRows = widget.sourceRowsBySection.values
          .expand((rows) => rows)
          .toList();

      final purchaseNames = sourceRows
          .map((e) => e.partyName.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final tdsNames = widget.tdsRows
          .map((e) => e.deducteeName.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final mappingResults = AutoMappingService.autoMapParties(
        purchaseParties: purchaseNames,
        tdsParties: tdsNames,
        threshold: 0.80,
      );

      final nameMapping = <String, String>{};

      for (final m in mappingResults) {
        final purchaseRaw = m.purchaseParty.trim();
        final tdsRaw = m.matchedTdsParty?.trim();

        if (purchaseRaw.isEmpty || tdsRaw == null || tdsRaw.isEmpty) continue;

        final purchaseKey = normalizeName(purchaseRaw.trim());
        if (purchaseKey.isEmpty) continue;
        if (blockedAutoMappingAliases.contains(purchaseKey)) continue;

        if (m.isMatched) {
          nameMapping[purchaseKey] = tdsRaw;
          continue;
        }

        final pNorm = AutoMappingService.normalizePartyName(purchaseRaw);
        final tNorm = AutoMappingService.normalizePartyName(tdsRaw);

        if (pNorm == tNorm) {
          nameMapping[purchaseKey] = tdsRaw;
        }
      }

      for (final entry in latestManualMappings.entries) {
        final normalizedSource = normalizeName(entry.key.trim());
        final mappedTarget = entry.value.trim();

        if (normalizedSource.isEmpty || mappedTarget.isEmpty) continue;

        nameMapping[normalizedSource] = mappedTarget;
      }

      final sectionResult = await CalculationService.reconcileSectionWise(
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        sourceRows: _applyPropagatedPanToSourceRows(
          sourceRows: List<NormalizedTransactionRow>.from(sourceRows),
          nameMapping: nameMapping,
        ),
        tdsRows: List<Tds26QRow>.from(widget.tdsRows),
        nameMapping: nameMapping,
        includeAllRows: showAllRows,
        sections: widget.sourceRowsBySection.keys.toList(),
      );
      final freshRows = sectionResult.rows;

      final sellers = freshRows
          .map((e) => e.sellerName.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final financialYears = freshRows
          .map((e) => e.financialYear.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final nextSellerOptions = ['All Sellers', ...sellers];
      final nextFinancialYearOptions = ['All FY', ...financialYears];

      final normalizedPrevSection = prevSection.trim();

      final nextSelectedSeller =
      nextSellerOptions.contains(prevSeller) ? prevSeller : 'All Sellers';

      final nextSelectedFinancialYear =
      nextFinancialYearOptions.contains(prevFY) ? prevFY : 'All FY';

      final nextSelectedStatus =
      statusOptions.contains(prevStatus) ? prevStatus : 'All Status';

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

      final nextFilteredRows = _filterRows(
        rows: freshRows,
        selectedSellerValue: nextSelectedSeller,
        selectedFinancialYearValue: nextSelectedFinancialYear,
        selectedSectionValue: nextSelectedSection,
        selectedStatusValue: nextSelectedStatus,
      );

      if (!mounted) return;

      _filterRowsCache.clear();
      _sectionOptionsCache.clear();
      setState(() {
        _sectionResultCache = sectionResult;
        allRows = freshRows;
        filteredRows = nextFilteredRows;
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
        activeSectionTab =
            nextSelectedSection == 'All Sections' ? 'All' : nextSelectedSection;
        _filteredMetrics = _buildFilteredMetrics(
          rows: nextFilteredRows,
          activeTab: nextSelectedSection == 'All Sections' ? 'All' : nextSelectedSection,
        );
      });
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
    final nextSectionOptions = _buildSectionOptions(
      rows: allRows,
      selectedSellerValue: selectedSeller,
      selectedFinancialYearValue: selectedFinancialYear,
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
      selectedSellerValue: selectedSeller,
      selectedFinancialYearValue: selectedFinancialYear,
      selectedSectionValue: nextSelectedSection,
      selectedStatusValue: selectedStatus,
    );
    final nextActiveTab =
        nextSelectedSection == 'All Sections' ? 'All' : nextSelectedSection;

    setState(() {
      sectionOptions = nextSectionOptions;
      selectedSection = nextSelectedSection;
      activeSectionTab = nextActiveTab;
      filteredRows = nextFilteredRows;
      _filteredMetrics = _buildFilteredMetrics(
        rows: nextFilteredRows,
        activeTab: nextActiveTab,
      );
    });
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

  String _sectionScopeValue(String section) {
    return section == 'All' ? 'All Sections' : section;
  }

  List<ReconciliationRow> _baseRowsForSection(String selectedSectionValue) {
    if (selectedSectionValue == 'All Sections') {
      return allRows;
    }

    return _sectionResultCache?.rowsBySection[selectedSectionValue] ??
        const <ReconciliationRow>[];
  }

  List<ReconciliationRow> _rowsForScopedSection(String section) {
    return _filterRows(
      rows: _baseRowsForSection(_sectionScopeValue(section)),
      selectedSellerValue: selectedSeller,
      selectedFinancialYearValue: selectedFinancialYear,
      selectedSectionValue: _sectionScopeValue(section),
      selectedStatusValue: selectedStatus,
    );
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
    );
  }

  String _filterRowsCacheKey({
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
  }) {
    return [
      selectedSellerValue,
      selectedFinancialYearValue,
      selectedSectionValue,
      selectedStatusValue,
    ].join('\u0001');
  }

  List<ReconciliationRow> _computeFilteredRows({
    required List<ReconciliationRow> rows,
    required String selectedSellerValue,
    required String selectedFinancialYearValue,
    required String selectedSectionValue,
    required String selectedStatusValue,
  }) {
    var result = identical(rows, allRows)
        ? _baseRowsForSection(selectedSectionValue)
        : rows;

    if (selectedSellerValue != 'All Sellers') {
      result = result
          .where((row) => row.sellerName.trim() == selectedSellerValue.trim())
          .toList();
    }

    if (selectedFinancialYearValue != 'All FY') {
      result = result
          .where(
            (row) =>
        row.financialYear.trim() == selectedFinancialYearValue.trim(),
      )
          .toList();
    }

    if (selectedSectionValue != 'All Sections' && !identical(result, rows)) {
      // Section scoping already narrowed the base list when filtering from the
      // cached reconciliation result.
    } else if (selectedSectionValue != 'All Sections') {
      result = result
          .where((row) => row.section.trim() == selectedSectionValue)
          .toList();
    }

    if (selectedStatusValue != 'All Status') {
      if (selectedStatusValue == 'Mismatch Only') {
        result = result
            .where(
              (row) =>
                  row.status == ReconciliationStatus.shortDeduction ||
                  row.status == ReconciliationStatus.excessDeduction ||
                  row.status == ReconciliationStatus.purchaseOnly ||
                  row.status == ReconciliationStatus.onlyIn26Q,
        )
            .toList();
      } else if (selectedStatusValue ==
          ReconciliationStatus.applicableButNo26Q) {
        result = result
            .where(
              (row) =>
          row.applicableAmount > 0 &&
              row.tds26QAmount == 0 &&
              row.actualTds == 0,
        )
            .toList();
      } else if (selectedStatusValue == 'Threshold Crossed Only') {
        final grouped = <String, double>{};

        for (final row in result) {
          final key =
              '${buildSellerDisplayKey(row)}|${row.financialYear.trim()}';
          grouped[key] = (grouped[key] ?? 0.0) + row.basicAmount;
        }

        result = result.where((row) {
          final key =
              '${buildSellerDisplayKey(row)}|${row.financialYear.trim()}';
          return (grouped[key] ?? 0.0) > 5000000;
        }).toList();
      } else {
        result = result
            .where((row) {
              final status = row.status.trim();
              final selected = selectedStatusValue.trim();
              return status == selected;
            })
            .toList();
      }
    }

    result.sort((a, b) {
      final sellerCompare = a.sellerName
          .trim()
          .toUpperCase()
          .compareTo(b.sellerName.trim().toUpperCase());
      if (sellerCompare != 0) return sellerCompare;

      final panCompare =
      normalizePan(a.sellerPan).compareTo(normalizePan(b.sellerPan));
      if (panCompare != 0) return panCompare;

      final fyCompare =
      a.financialYear.trim().compareTo(b.financialYear.trim());
      if (fyCompare != 0) return fyCompare;

      return CalculationService.compareMonthLabels(a.month, b.month);
    });

    return result;
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
      final remarks = row.remarks.trim().toUpperCase();
      final calculationRemark = row.calculationRemark.trim().toUpperCase();
      final combinedText = '$remarks $calculationRemark';

      sellerKeys.add(buildSellerDisplayKey(row));
      sectionCounts[section] = (sectionCounts[section] ?? 0) + 1;

      if (status == ReconciliationStatus.matched) {
        matchedCount++;
      } else {
        summaryMismatchRows++;
      }

      if (sectionMismatchCounts.containsKey(section == 'All Sections' ? 'All' : section) &&
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

      if (upperStatus == 'APPLICABLE BUT NO 26Q' ||
          combinedText.contains('NO 26Q ENTRY')) {
        mismatchReasonCounts['No 26Q entry'] =
            (mismatchReasonCounts['No 26Q entry'] ?? 0) + 1;
      }
      if (upperStatus == 'AMOUNT MISMATCH' ||
          combinedText.contains('AMOUNT MISMATCH')) {
        mismatchReasonCounts['Amount mismatch'] =
            (mismatchReasonCounts['Amount mismatch'] ?? 0) + 1;
      }
      if (upperStatus == 'SHORT DEDUCTION' ||
          upperStatus == 'EXCESS DEDUCTION' ||
          combinedText.contains('RATE MISMATCH') ||
          combinedText.contains('ROUNDING DIFFERENCE')) {
        mismatchReasonCounts['TDS mismatch'] =
            (mismatchReasonCounts['TDS mismatch'] ?? 0) + 1;
      }
      if (upperStatus == 'TIMING DIFFERENCE') {
        mismatchReasonCounts['Timing difference'] =
            (mismatchReasonCounts['Timing difference'] ?? 0) + 1;
      }
      if (combinedText.contains('LOW CONFIDENCE MATCH') ||
          combinedText.contains('PAN MISSING') ||
          combinedText.contains('PAN DERIVED FROM GSTIN')) {
        mismatchReasonCounts['PAN/name mismatch'] =
            (mismatchReasonCounts['PAN/name mismatch'] ?? 0) + 1;
      }
    }

    final topMismatchSection = () {
      final mismatchEntries = sectionCounts.keys
          .map((section) => MapEntry(section, sectionMismatchCounts[section] ?? 0))
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

    final mismatchPercentage =
        rows.isEmpty ? 0.0 : (mismatchRowsCount / rows.length) * 100;

    return _FilteredMetrics(
      summary: summary,
      mismatchReasonCounts: mismatchReasonCounts,
      sectionCounts: {
        for (final entry in (sectionCounts.entries.toList()
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
      matchedPercentage: rows.isEmpty ? 0.0 : (matchedCount / rows.length) * 100,
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
          shortDeductionAmount + excessDeductionAmount + purchaseOnlyAmount + only26QAmount,
      applicableButNo26QAmount: applicableButNo26QAmount,
      applicableButNo26QTds: applicableButNo26QTds,
    );
  }

  double _sum(double Function(ReconciliationRow row) selector) {
    return filteredRows.fold(0.0, (sum, row) => sum + selector(row));
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
    final unsupported = filteredRows
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

  Widget _buildSectionTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _sectionTabs.map((section) {
          final isActive = activeSectionTab == section;
          final mismatchCount = _mismatchCountForSection(section);
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _selectSectionTab(section),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF60A5FA)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      section,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: mismatchCount > 0
                            ? const Color(0xFF7F1D1D)
                            : const Color(0xFF14532D),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$mismatchCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
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
    final activeSectionCode =
        activeSectionTab == 'All' ? 'All Sections' : activeSectionTab;
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
                '${activeSectionTab == 'All' ? 'Combined' : activeSectionTab} Summary',
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

  double _purchaseOnlyAmount() {
    return _filteredMetrics?.purchaseOnlyAmount ?? 0.0;
  }

  double _only26QAmount() {
    return _filteredMetrics?.only26QAmount ?? 0.0;
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
        sellerName: selectedSeller,
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
        sellerName: selectedSeller,
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
        sellerName: selectedSeller,
      );

      if (!mounted) return;
      _showSnackBar('Pivot Exported to: $filePath');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Pivot export failed: $e');
    }
  }

  Future<void> _openSellerMappingScreen() async {
    final latestManualMappings = await _loadManualMappingsFromDb();
    if (!mounted) return;
    final sourceRows = widget.sourceRowsBySection.values
        .expand((rows) => rows)
        .toList();

    final purchaseNames = sourceRows
        .map((e) => e.partyName.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final tdsNames = widget.tdsRows
        .map((e) => e.deducteeName.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerMappingScreen(
          purchaseParties: purchaseNames,
          tdsParties: tdsNames,
          initialMapping: latestManualMappings,
          blockedAliases: blockedAutoMappingAliases,
          tdsPartyPans: _buildTdsPartyPans(),
          purchaseSections: _buildPurchaseSectionsByAlias(sourceRows),
        ),
      ),
    );

    if (result == null) return;

    final returnedMappings =
        (result['mappings'] as Map?)?.cast<String, String>() ?? {};
    final clearedAliases = ((result['clearedAliases'] as List?) ?? const [])
        .map((e) => normalizeName(e.toString()))
        .where((e) => e.isNotEmpty)
        .toSet();
    final conflictedAliases = ((result['conflictedAliases'] as List?) ?? const [])
        .map((e) => normalizeName(e.toString()))
        .where((e) => e.isNotEmpty)
        .toSet();
    final returnedConflictMessages =
        (result['conflictMessages'] as Map?)?.cast<String, String>() ?? {};
    final purchaseSectionsByAlias = _buildPurchaseSectionsByAlias(sourceRows);
    final revalidatedConflicts = _buildAliasPanConflicts(
      mappings: returnedMappings,
      purchaseSectionsByAlias: purchaseSectionsByAlias,
    );
    conflictedAliases.addAll(revalidatedConflicts.map((e) => e.aliasKey));

    final cleanedResult = <String, String>{};
    final updatedManualMappings = Map<String, String>.from(latestManualMappings);
    final conflictWarnings = <String>[];
    final mismatchWarnings = <String>[];
    final cautionWarnings = <String>[];
    final mismatchedAliases = <String>{};

    conflictWarnings.addAll(returnedConflictMessages.values);

    for (final conflict in revalidatedConflicts) {
      if (!conflictWarnings.contains(conflict.message)) {
        conflictWarnings.add(conflict.message);
      }
    }

    for (final entry in returnedMappings.entries) {
      final aliasName = entry.key.trim();
      final mappedName = entry.value.trim();

      if (aliasName.isEmpty || mappedName.isEmpty) continue;

      final normalizedAliasKey = _normalizeAlias(aliasName);
      if (normalizedAliasKey.isEmpty) continue;
      if (conflictedAliases.contains(normalizedAliasKey)) {
        updatedManualMappings.remove(normalizedAliasKey);
        continue;
      }

      final mappedPan = _resolveSingleTargetPan(mappedName);

      final purchasePans = sourceRows
          .where((row) => _normalizeAlias(row.partyName) == normalizedAliasKey)
          .map((row) => normalizePan(row.panNumber))
          .where((pan) => pan.isNotEmpty)
          .toSet();

      if (purchasePans.isNotEmpty &&
          mappedPan.isNotEmpty &&
          !purchasePans.contains(mappedPan)) {
        mismatchWarnings.add(
          'Seller mapping blocked: PAN mismatch between purchase party '
          '"$aliasName" and 26Q party "$mappedName".',
        );
        mismatchedAliases.add(normalizedAliasKey);
        updatedManualMappings.remove(normalizedAliasKey);
        continue;
      }

      if (purchasePans.isEmpty || mappedPan.isEmpty) {
        cautionWarnings.add(
          'Caution: PAN missing on one side for "$aliasName" -> "$mappedName". '
          'Mapping allowed, but please verify manually.',
        );
      }

      cleanedResult[normalizedAliasKey] = mappedName;
      updatedManualMappings[normalizedAliasKey] = mappedName;

      await MappingService.saveMapping(
        SellerMapping(
          buyerName: widget.buyerName,
          buyerPan: widget.buyerPan.trim().toUpperCase(),
          aliasName: normalizedAliasKey,
          mappedPan: mappedPan,
          mappedName: mappedName,
        ),
      );
    }

    final aliasesToDelete = <String>{
      ...clearedAliases,
      ...conflictedAliases,
      ...mismatchedAliases,
    };

    for (final normalizedAliasKey in aliasesToDelete) {
      updatedManualMappings.remove(normalizedAliasKey);
      await MappingService.deleteMapping(
        buyerPan: widget.buyerPan.trim().toUpperCase(),
        aliasName: normalizedAliasKey,
      );
    }

    if (!mounted) return;

    setState(() {
      manualNameMapping = updatedManualMappings;
      blockedAutoMappingAliases.addAll(aliasesToDelete);
      blockedAutoMappingAliases.removeAll(cleanedResult.keys);
    });

    await _recalculateAll();

    if (!mounted) return;
    if (conflictWarnings.isNotEmpty) {
      _showSnackBar(conflictWarnings.join('\n'));
    } else if (mismatchWarnings.isNotEmpty) {
      _showSnackBar(mismatchWarnings.join('\n'));
    } else if (cautionWarnings.isNotEmpty) {
      _showSnackBar(cautionWarnings.join('\n'));
    } else {
      _showSnackBar('Seller mappings saved successfully');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case ReconciliationStatus.matched:
        return Colors.green.shade50;
      case ReconciliationStatus.timingDifference:
        return Colors.teal.shade50;
      case ReconciliationStatus.shortDeduction:
        return Colors.orange.shade50;
      case ReconciliationStatus.excessDeduction:
        return Colors.red.shade50;
      case ReconciliationStatus.purchaseOnly:
        return Colors.blue.shade50;
      case ReconciliationStatus.onlyIn26Q:
        return Colors.purple.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case ReconciliationStatus.belowThreshold:
        return const Color(0xFF64748B);
      case ReconciliationStatus.matched:
        return const Color(0xFF166534);
      case ReconciliationStatus.amountMismatch:
        return const Color(0xFFB91C1C);
      case ReconciliationStatus.applicableButNo26Q:
        return const Color(0xFFB45309);
      case 'PAN/name mismatch':
        return const Color(0xFF1D4ED8);
      case ReconciliationStatus.onlyIn26Q:
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
        if (value == null) return;
        setState(() => selectedSeller = value);
        _applyFilters();
      },
      onFinancialYearChanged: (value) {
        if (value == null) return;
        setState(() => selectedFinancialYear = value);
        _applyFilters();
      },
      onSectionChanged: (value) {
        if (value == null) return;
        setState(() {
          selectedSection = value;
          activeSectionTab = value == 'All Sections' ? 'All' : value;
        });
        _applyFilters();
      },
      onStatusChanged: (value) {
        if (value == null) return;
        setState(() => selectedStatus = value);
        _applyFilters();
      },
    );
  }

  Widget _buildMainContent() {
    final summary = _activeSummary();
    final detailedSummary = ReconciliationSummaryPanel(
      buyerName: widget.buyerName,
      buyerPan: widget.buyerPan,
      gstNo: widget.gstNo,
      selectedSeller: selectedSeller,
      selectedFinancialYear: selectedFinancialYear,
      selectedSection: selectedSection,
      selectedStatus: selectedStatus,
      filteredRowsCount: filteredRows.length,
      totalSellers: _totalSellers(),
      totalSections: _totalSections(),
      matchedPercentage: _matchedPercentage(),
      mismatchPercentage: _mismatchPercentage(),
      topMismatchSection: _topMismatchSection(),
      basicAmount: _filteredMetrics?.basicAmount ?? 0.0,
      applicableAmount: _filteredMetrics?.applicableAmount ?? 0.0,
      tds26QAmount: _filteredMetrics?.tds26QAmount ?? 0.0,
      expectedTds: _filteredMetrics?.expectedTds ?? 0.0,
      actualTds: _filteredMetrics?.actualTds ?? 0.0,
      tdsDifference: _filteredMetrics?.tdsDifference ?? 0.0,
      amountDifference: _filteredMetrics?.amountDifference ?? 0.0,
      matchedCount: _countByStatus(ReconciliationStatus.matched),
      timingDifferenceCount:
          _countByStatus(ReconciliationStatus.timingDifference),
      shortDeductionCount:
          _countByStatus(ReconciliationStatus.shortDeduction),
      excessDeductionCount:
          _countByStatus(ReconciliationStatus.excessDeduction),
      purchaseOnlyCount: _countByStatus(ReconciliationStatus.purchaseOnly),
      only26QCount: _countByStatus(ReconciliationStatus.onlyIn26Q),
      applicableButNo26QCount: _applicableButNo26QCount(),
      shortDeductionAmount: _shortDeductionAmount(),
      excessDeductionAmount: _excessDeductionAmount(),
      timingDifferenceAmount: _timingDifferenceAmount(),
      purchaseOnlyAmount: _purchaseOnlyAmount(),
      only26QAmount: _only26QAmount(),
      netMismatchAmount: _netMismatchAmount(),
      applicableButNo26QAmount: _applicableButNo26QAmount(),
      applicableButNo26QTds: _applicableButNo26QTds(),
      manualMappingsCount: manualNameMapping.length,
      mismatchRowsCount: _mismatchRowsCount(),
      sectionCounts: _sectionCounts(),
    );
    final tableContent = ReconciliationTableSection(
      filteredRows: filteredRows,
      isRecalculating: _isRecalculating,
      formatAmount: _fmt,
      statusColor: _statusColor,
      statusTextColor: _statusTextColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplitView = constraints.maxWidth >= 1180;
        final analysisPane = SizedBox(
          width: useSplitView ? null : double.infinity,
          child: ReconciliationAnalysisPanel(
            activeSectionTab: activeSectionTab,
            sourceFileCount: _activeSourceFileCount(),
            sourceRowCount: _activeSourceRowCount(),
            totalSellers: _totalSellers(),
            totalSections: _totalSections(),
            manualMappingsCount: manualNameMapping.length,
            topMismatchSection: _topMismatchSection(),
            detailedSummary: detailedSummary,
            mismatchReasonCounts: _activeMismatchReasonCounts(),
            unsupportedSections: _unsupportedSectionsInActiveScope(),
            totalRows: summary?.totalRows ?? 0,
            mismatchRows: summary?.mismatchRows ?? 0,
            sourceAmount: summary?.sourceAmount ?? 0.0,
            tds26QAmount: summary?.tds26QAmount ?? 0.0,
            expectedTds: summary?.expectedTds ?? 0.0,
            actualTds: summary?.actualTds ?? 0.0,
          ),
        );

        if (!useSplitView) {
          return Column(
            children: [
              Expanded(child: tableContent),
              const SizedBox(height: 16),
              SizedBox(
                height: 520,
                child: analysisPane,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: tableContent,
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: analysisPane,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSectionExportRows = _rowsForAllSectionsExport();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Reconciliation'),
      ),
      bottomNavigationBar: ReconciliationBottomActionBar(
        onExportCurrentSection:
            filteredRows.isEmpty ? null : _exportCurrentSectionExcel,
        onExportAllSections:
            allSectionExportRows.isEmpty ? null : _exportAllSectionsExcel,
        onExportPivot: filteredRows.isEmpty ? null : _exportPivotExcel,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ReconciliationTopToolbar(
              buyerName: widget.buyerName,
              buyerPan: widget.buyerPan,
              gstNo: widget.gstNo,
              sectionTabs: _buildSectionTabs(),
              filters: _buildFilters(),
              showAllRows: showAllRows,
              isRecalculating: _isRecalculating,
              onShowAllRowsChanged: (value) async {
                setState(() {
                  showAllRows = value;
                });
                await _recalculateAll();
              },
              onRecalculate: _isRecalculating ? null : _recalculateAll,
              onManualMapping: _openSellerMappingScreen,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }
}


