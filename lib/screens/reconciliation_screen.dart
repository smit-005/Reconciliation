import 'package:flutter/material.dart';

import '../../core/utils/normalize_utils.dart';

import '../models/normalized_transaction_row.dart';
import '../models/tds_26q_row.dart';
import '../models/reconciliation_row.dart';
import '../models/seller_mapping.dart';

import '../services/reconciliation_service.dart';
import '../services/excel_export_service.dart';
import '../services/auto_mapping_service.dart';
import '../services/mapping_service.dart';

import '../core/utils/reconciliation_helpers.dart';

import '../widgets/reconciliation/reconciliation_filters.dart';
import '../widgets/reconciliation/reconciliation_summary_panel.dart';
import '../widgets/reconciliation/reconciliation_table_section.dart';

import 'manual_mapping_screen.dart';

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
  bool showSummaryPanel = false;
  bool _isRecalculating = false;

  final List<String> statusOptions = const [
    'All Status',
    'Mismatch Only',
    'Matched',
    'Timing Difference',
    'Short Deduction',
    'Excess Deduction',
    'Purchase Only',
    '26Q Only',
    'Applicable but no 26Q',
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
        sourceRows: List<NormalizedTransactionRow>.from(sourceRows),
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

      final normalizedPrevSection = normalizeSection(prevSection);

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

      setState(() {
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
    final normalizedSelectedSection = normalizeSection(selectedSection);
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

    setState(() {
      sectionOptions = nextSectionOptions;
      selectedSection = nextSelectedSection;
      activeSectionTab =
          nextSelectedSection == 'All Sections' ? 'All' : nextSelectedSection;
      filteredRows = nextFilteredRows;
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
    return section == 'All' ? 'All Sections' : normalizeSection(section);
  }

  List<ReconciliationRow> _rowsForScopedSection(String section) {
    return _filterRows(
      rows: allRows,
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
    final scopedRows = _filterRows(
      rows: rows,
      selectedSellerValue: selectedSellerValue,
      selectedFinancialYearValue: selectedFinancialYearValue,
      selectedSectionValue: 'All Sections',
      selectedStatusValue: selectedStatusValue,
    );

    final sections = scopedRows
        .map((e) => normalizeSection(e.section))
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
    var result = List<ReconciliationRow>.from(rows);

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

    if (selectedSectionValue != 'All Sections') {
      result = result
          .where((row) => normalizeSection(row.section) == selectedSectionValue)
          .toList();
    }

    if (selectedStatusValue != 'All Status') {
      if (selectedStatusValue == 'Mismatch Only') {
        result = result
            .where(
              (row) =>
          row.status == 'Short Deduction' ||
              row.status == 'Excess Deduction' ||
              row.status == 'Purchase Only' ||
              row.status == '26Q Only',
        )
            .toList();
      } else if (selectedStatusValue == 'Applicable but no 26Q') {
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
            .where((row) => row.status.trim() == selectedStatusValue.trim())
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

  double _sum(double Function(ReconciliationRow row) selector) {
    return filteredRows.fold(0.0, (sum, row) => sum + selector(row));
  }

  int _countByStatus(String status) {
    return filteredRows.where((e) => e.status == status).length;
  }

  int _applicableButNo26QCount() {
    return filteredRows
        .where(
          (row) =>
      row.applicableAmount > 0 &&
          row.tds26QAmount == 0 &&
          row.actualTds == 0,
    )
        .length;
  }

  double _applicableButNo26QAmount() {
    return filteredRows
        .where(
          (row) =>
      row.applicableAmount > 0 &&
          row.tds26QAmount == 0 &&
          row.actualTds == 0,
    )
        .fold(0.0, (sum, row) => sum + row.applicableAmount);
  }

  double _applicableButNo26QTds() {
    return filteredRows
        .where(
          (row) =>
      row.applicableAmount > 0 &&
          row.tds26QAmount == 0 &&
          row.actualTds == 0,
    )
        .fold(0.0, (sum, row) => sum + row.expectedTds);
  }

  double _shortDeductionAmount() {
    return filteredRows
        .where((row) => row.status == 'Short Deduction')
        .fold(0.0, (sum, row) => sum + row.tdsDifference.abs());
  }

  double _excessDeductionAmount() {
    return filteredRows
        .where((row) => row.status == 'Excess Deduction')
        .fold(0.0, (sum, row) => sum + row.tdsDifference.abs());
  }

  double _timingDifferenceAmount() {
    return filteredRows
        .where((row) => row.status == 'Timing Difference')
        .fold(0.0, (sum, row) => sum + row.monthTdsDifference.abs());
  }

  double _netMismatchAmount() {
    return filteredRows
        .where(
          (row) =>
      row.status == 'Short Deduction' ||
          row.status == 'Excess Deduction' ||
          row.status == 'Purchase Only' ||
          row.status == '26Q Only',
    )
        .fold(0.0, (sum, row) => sum + row.tdsDifference.abs());
  }

  int _totalSellers() {
    final keys = filteredRows.map(buildSellerDisplayKey).toSet();
    return keys.length;
  }

  int _mismatchRowsCount() {
    return filteredRows
        .where(
          (row) =>
      row.status == 'Short Deduction' ||
          row.status == 'Excess Deduction' ||
          row.status == 'Purchase Only' ||
          row.status == '26Q Only',
    )
        .length;
  }

  double _matchedPercentage() {
    if (filteredRows.isEmpty) return 0.0;
    final matched = filteredRows.where((e) => e.status == 'Matched').length;
    return (matched / filteredRows.length) * 100;
  }

  double _mismatchPercentage() {
    if (filteredRows.isEmpty) return 0.0;
    return (_mismatchRowsCount() / filteredRows.length) * 100;
  }

  ReconciliationSummary? _activeSummary() {
    final scopedRows = filteredRows;
    if (scopedRows.isEmpty &&
        activeSectionTab == 'All' &&
        combinedSummary != null &&
        selectedSeller == 'All Sellers' &&
        selectedFinancialYear == 'All FY' &&
        selectedStatus == 'All Status') {
      return combinedSummary;
    }

    return ReconciliationSummary(
      section: activeSectionTab == 'All' ? 'ALL' : activeSectionTab,
      totalRows: scopedRows.length,
      matchedRows: scopedRows.where((row) => row.status == 'Matched').length,
      mismatchRows: scopedRows
          .where((row) => row.status.trim().toUpperCase() != 'MATCHED')
          .length,
      purchaseOnlyRows:
          scopedRows.where((row) => row.status == 'Purchase Only').length,
      only26QRows: scopedRows.where((row) => row.status == '26Q Only').length,
      applicableButNo26QRows: scopedRows
          .where(
            (row) =>
                row.applicableAmount > 0 &&
                row.tds26QAmount == 0 &&
                row.actualTds == 0,
          )
          .length,
      sourceAmount: scopedRows.fold(0.0, (sum, row) => sum + row.basicAmount),
      applicableAmount:
          scopedRows.fold(0.0, (sum, row) => sum + row.applicableAmount),
      tds26QAmount:
          scopedRows.fold(0.0, (sum, row) => sum + row.tds26QAmount),
      expectedTds: scopedRows.fold(0.0, (sum, row) => sum + row.expectedTds),
      actualTds: scopedRows.fold(0.0, (sum, row) => sum + row.actualTds),
      amountDifference:
          scopedRows.fold(0.0, (sum, row) => sum + row.amountDifference),
      tdsDifference:
          scopedRows.fold(0.0, (sum, row) => sum + row.tdsDifference),
    );
  }

  int _mismatchCountForSection(String section) {
    final scopedRows = _rowsForScopedSection(section);
    return scopedRows
        .where((row) => row.status.trim().toUpperCase() != 'MATCHED')
        .length;
  }

  Map<String, int> _activeMismatchReasonCounts() {
    var no26QEntry = 0;
    var amountMismatch = 0;
    var tdsMismatch = 0;
    var timingDifference = 0;
    var panOrNameMismatch = 0;

    for (final row in filteredRows) {
      final status = row.status.trim().toUpperCase();
      final remarks = row.remarks.trim().toUpperCase();
      final calculationRemark = row.calculationRemark.trim().toUpperCase();
      final combinedText = '$remarks $calculationRemark';

      if (status == 'APPLICABLE BUT NO 26Q' ||
          combinedText.contains('NO 26Q ENTRY')) {
        no26QEntry++;
      }

      if (status == 'AMOUNT MISMATCH' ||
          combinedText.contains('AMOUNT MISMATCH')) {
        amountMismatch++;
      }

      if (status == 'SHORT DEDUCTION' ||
          status == 'EXCESS DEDUCTION' ||
          combinedText.contains('RATE MISMATCH') ||
          combinedText.contains('ROUNDING DIFFERENCE')) {
        tdsMismatch++;
      }

      if (status == 'TIMING DIFFERENCE') {
        timingDifference++;
      }

      if (combinedText.contains('LOW CONFIDENCE MATCH') ||
          combinedText.contains('PAN MISSING') ||
          combinedText.contains('PAN DERIVED FROM GSTIN')) {
        panOrNameMismatch++;
      }
    }

    return {
      'No 26Q entry': no26QEntry,
      'Amount mismatch': amountMismatch,
      'TDS mismatch': tdsMismatch,
      'Timing difference': timingDifference,
      'PAN/name mismatch': panOrNameMismatch,
    };
  }

  List<String> _unsupportedSectionsInActiveScope() {
    final unsupported = filteredRows
        .map((row) => normalizeSection(row.section))
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

    Widget summaryPill(String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget reasonChip(String label, int count, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      );
    }

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
          Text(
            '${activeSectionTab == 'All' ? 'Combined' : activeSectionTab} Summary',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$activeSectionCode  •  $sourceFileCount source file(s)  •  '
            '$sourceRowCount source row(s)',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
                'These rows remain visible for review, while the combined supported-section summary stays limited to '
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
              reasonChip(
                'No 26Q entry',
                mismatchReasonCounts['No 26Q entry'] ?? 0,
                const Color(0xFFB45309),
              ),
              reasonChip(
                'Amount mismatch',
                mismatchReasonCounts['Amount mismatch'] ?? 0,
                const Color(0xFFDC2626),
              ),
              reasonChip(
                'TDS mismatch',
                mismatchReasonCounts['TDS mismatch'] ?? 0,
                const Color(0xFF7C3AED),
              ),
              reasonChip(
                'Timing difference',
                mismatchReasonCounts['Timing difference'] ?? 0,
                const Color(0xFF0F766E),
              ),
              reasonChip(
                'PAN/name mismatch',
                mismatchReasonCounts['PAN/name mismatch'] ?? 0,
                const Color(0xFF1D4ED8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              summaryPill('Total Rows', summary.totalRows.toString()),
              summaryPill('Mismatch Rows', summary.mismatchRows.toString()),
              summaryPill('Source Amount', _fmt(summary.sourceAmount)),
              summaryPill('26Q Amount', _fmt(summary.tds26QAmount)),
              summaryPill('Expected TDS', _fmt(summary.expectedTds)),
              summaryPill('Actual TDS', _fmt(summary.actualTds)),
            ],
          ),
        ],
      ),
    );
  }

  int _totalSections() {
    return filteredRows.map((e) => normalizeSection(e.section)).toSet().length;
  }

  Map<String, int> _sectionCounts() {
    final map = <String, int>{};

    for (final row in filteredRows) {
      final sec = normalizeSection(row.section);
      map[sec] = (map[sec] ?? 0) + 1;
    }

    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {for (final e in entries) e.key: e.value};
  }

  String _topMismatchSection() {
    final map = <String, int>{};

    for (final row in filteredRows) {
      if (row.status == 'Matched') continue;

      final sec = normalizeSection(row.section);
      map[sec] = (map[sec] ?? 0) + 1;
    }

    if (map.isEmpty) return '-';

    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  double _purchaseOnlyAmount() {
    return filteredRows
        .where((row) => row.status == 'Purchase Only')
        .fold(0.0, (sum, row) => sum + row.basicAmount);
  }

  double _only26QAmount() {
    return filteredRows
        .where((row) => row.status == '26Q Only')
        .fold(0.0, (sum, row) => sum + row.tds26QAmount);
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

  Future<void> _openManualMappingScreen() async {
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
        builder: (_) => SellerManualMappingScreen(
            purchaseParties: purchaseNames,
            tdsParties: tdsNames,
            initialMapping: latestManualMappings,
          blockedAliases: blockedAutoMappingAliases,
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

    final cleanedResult = <String, String>{};
    final existingMappings = await MappingService.getAllMappings(
      widget.buyerPan.trim().toUpperCase(),
    );

    for (final entry in returnedMappings.entries) {
      final aliasName = entry.key.trim();
      final mappedName = entry.value.trim();

      if (aliasName.isEmpty || mappedName.isEmpty) continue;

      final normalizedAliasKey = normalizeName(aliasName.trim());
      if (normalizedAliasKey.isEmpty) continue;

      String mappedPan = '';

      for (final row in widget.tdsRows) {
        if (row.deducteeName.trim().toUpperCase() ==
            mappedName.toUpperCase()) {
          if (row.panNumber.trim().isNotEmpty) {
            mappedPan = row.panNumber.trim().toUpperCase();
            break;
          }
        }
      }

      if (mappedPan.isEmpty) {
        for (final row in widget.tdsRows) {
          final tdsName =
          AutoMappingService.normalizePartyName(row.deducteeName);
          final selectedName =
          AutoMappingService.normalizePartyName(mappedName);

          if (tdsName == selectedName && row.panNumber.trim().isNotEmpty) {
            mappedPan = row.panNumber.trim().toUpperCase();
            break;
          }
        }
      }

      final purchasePans = sourceRows
          .where((row) => normalizeName(row.partyName.trim()) == normalizedAliasKey)
          .map((row) => normalizePan(row.panNumber))
          .where((pan) => pan.isNotEmpty)
          .toSet();

      if (purchasePans.isNotEmpty &&
          mappedPan.isNotEmpty &&
          !purchasePans.contains(mappedPan)) {
        _showSnackBar(
          'Manual mapping blocked: PAN mismatch between purchase party '
          '"$aliasName" and 26Q party "$mappedName".',
        );
        continue;
      }

      if (purchasePans.isEmpty || mappedPan.isEmpty) {
        _showSnackBar(
          'Caution: PAN missing on one side for "$aliasName" -> "$mappedName". '
          'Mapping allowed, but please verify manually.',
        );
      }

      cleanedResult[normalizedAliasKey] = mappedName;

      if (mappedPan.isNotEmpty) {
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
    }

    for (final existing in existingMappings) {
      final normalizedAliasKey = normalizeName(existing.aliasName.trim());
      if (normalizedAliasKey.isEmpty) continue;

      if (!cleanedResult.containsKey(normalizedAliasKey)) {
        await MappingService.deleteMapping(
          buyerPan: widget.buyerPan.trim().toUpperCase(),
          aliasName: normalizedAliasKey,
        );
      }
    }

    if (!mounted) return;

    setState(() {
      manualNameMapping = cleanedResult;
      blockedAutoMappingAliases.addAll(clearedAliases);
      blockedAutoMappingAliases.removeAll(cleanedResult.keys);
    });

    await _recalculateAll();

    if (!mounted) return;
    _showSnackBar('Manual mappings saved successfully');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Matched':
        return Colors.green.shade50;
      case 'Timing Difference':
        return Colors.teal.shade50;
      case 'Short Deduction':
        return Colors.orange.shade50;
      case 'Excess Deduction':
        return Colors.red.shade50;
      case 'Purchase Only':
        return Colors.blue.shade50;
      case '26Q Only':
        return Colors.purple.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case 'Matched':
        return Colors.green.shade800;
      case 'Timing Difference':
        return Colors.teal.shade800;
      case 'Short Deduction':
        return Colors.orange.shade800;
      case 'Excess Deduction':
        return Colors.red.shade800;
      case 'Purchase Only':
        return Colors.blue.shade800;
      case '26Q Only':
        return Colors.purple.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  String _fmt(double value) => value.toStringAsFixed(2);

  Widget _buildTopInfoNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: const Text(
        'Relevant sellers only: this report includes only sellers who are present in 26Q or whose total purchase crosses ₹50,00,000 in the financial year. Sellers below threshold and not present in 26Q are excluded to avoid false mismatches.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSectionExportRows = _rowsForAllSectionsExport();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Reconciliation'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Text(
                        showSummaryPanel ? 'Summary On' : 'Summary Off',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: showSummaryPanel,
                        onChanged: (value) {
                          setState(() {
                            showSummaryPanel = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Text(
                        showAllRows ? 'Raw Mode On' : 'Raw Mode Off',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: showAllRows,
                        onChanged: (value) async {
                          setState(() {
                            showAllRows = value;
                          });
                          await _recalculateAll();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isRecalculating ? null : _recalculateAll,
                  icon: _isRecalculating
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _isRecalculating ? 'Recalculating...' : 'Recalculate',
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _openManualMappingScreen,
                  icon: const Icon(Icons.link),
                  label: const Text('Manual Mapping'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      filteredRows.isEmpty ? null : _exportCurrentSectionExcel,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Current Section'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      allSectionExportRows.isEmpty ? null : _exportAllSectionsExcel,
                  icon: const Icon(Icons.download_for_offline),
                  label: const Text('Export All Sections'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: filteredRows.isEmpty ? null : _exportPivotExcel,
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Export Pivot'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTopInfoNote(),
            const SizedBox(height: 12),
            _buildSectionTabs(),
            const SizedBox(height: 12),
            _buildSectionSummaryStrip(),
            const SizedBox(height: 12),
            ReconciliationFilters(
              selectedSeller: selectedSeller,
              selectedFinancialYear: selectedFinancialYear,
              selectedSection: selectedSection,
              selectedStatus: selectedStatus,
              sellerOptions: sellerOptions,
              financialYearOptions: financialYearOptions,
              sectionOptions: sectionOptions,
              statusOptions: statusOptions,
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
            ),
            if (showSummaryPanel) ...[
              const SizedBox(height: 16),
              ReconciliationSummaryPanel(
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
                basicAmount: _sum((e) => e.basicAmount),
                applicableAmount: _sum((e) => e.applicableAmount),
                tds26QAmount: _sum((e) => e.tds26QAmount),
                expectedTds: _sum((e) => e.expectedTds),
                actualTds: _sum((e) => e.actualTds),
                tdsDifference: _sum((e) => e.tdsDifference),
                amountDifference: _sum((e) => e.amountDifference),
                matchedCount: _countByStatus('Matched'),
                timingDifferenceCount: _countByStatus('Timing Difference'),
                shortDeductionCount: _countByStatus('Short Deduction'),
                excessDeductionCount: _countByStatus('Excess Deduction'),
                purchaseOnlyCount: _countByStatus('Purchase Only'),
                only26QCount: _countByStatus('26Q Only'),
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
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ReconciliationTableSection(
                filteredRows: filteredRows,
                isRecalculating: _isRecalculating,
                formatAmount: _fmt,
                statusColor: _statusColor,
                statusTextColor: _statusTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
