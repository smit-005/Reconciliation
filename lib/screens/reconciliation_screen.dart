import 'package:flutter/material.dart';

import '../../core/utils/normalize_utils.dart';

import '../models/purchase_row.dart';
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
  final List<PurchaseRow> purchaseRows;
  final List<Tds26QRow> tdsRows;

  final String buyerName;
  final String buyerPan;
  final String gstNo;

  const ReconciliationScreen({
    super.key,
    required this.purchaseRows,
    required this.tdsRows,
    this.buyerName = '',
    this.buyerPan = '',
    this.gstNo = '',
  });

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  List<ReconciliationRow> allRows = [];
  List<ReconciliationRow> filteredRows = [];

  List<String> sellerOptions = ['All Sellers'];
  List<String> financialYearOptions = ['All FY'];
  List<String> sectionOptions = ['All Sections'];

  Map<String, String> manualNameMapping = {};

  String selectedSeller = 'All Sellers';
  String selectedFinancialYear = 'All FY';
  String selectedSection = 'All Sections';
  String selectedStatus = 'All Status';

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

  @override
  void didUpdateWidget(covariant ReconciliationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final purchaseChanged = oldWidget.purchaseRows != widget.purchaseRows;
    final tdsChanged = oldWidget.tdsRows != widget.tdsRows;
    final buyerChanged =
        oldWidget.buyerName != widget.buyerName ||
            oldWidget.buyerPan != widget.buyerPan ||
            oldWidget.gstNo != widget.gstNo;

    if (purchaseChanged || tdsChanged || buyerChanged) {
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

      final purchaseNames = widget.purchaseRows
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

        final purchaseKey = normalizeName(purchaseRaw);
        if (purchaseKey.isEmpty) continue;

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

      for (final entry in manualNameMapping.entries) {
        final normalizedSource = normalizeName(entry.key);
        final mappedTarget = entry.value.trim();

        if (normalizedSource.isEmpty || mappedTarget.isEmpty) continue;

        nameMapping[normalizedSource] = mappedTarget;
      }

      final freshRows = await CalculationService.reconcile(
        buyerName: widget.buyerName,
        buyerPan: widget.buyerPan,
        purchaseRows: List<PurchaseRow>.from(widget.purchaseRows),
        tdsRows: List<Tds26QRow>.from(widget.tdsRows),
        nameMapping: nameMapping,
        includeAllRows: showAllRows,
      );

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

      final sections = freshRows
          .map((e) => normalizeSection(e.section))
          .toSet()
          .toList();

      sortSections(sections);

      final nextSellerOptions = ['All Sellers', ...sellers];
      final nextFinancialYearOptions = ['All FY', ...financialYears];
      final nextSectionOptions = ['All Sections', ...sections];

      final normalizedPrevSection = normalizeSection(prevSection);

      final nextSelectedSeller =
      nextSellerOptions.contains(prevSeller) ? prevSeller : 'All Sellers';

      final nextSelectedFinancialYear =
      nextFinancialYearOptions.contains(prevFY) ? prevFY : 'All FY';

      final nextSelectedSection =
      nextSectionOptions.contains(normalizedPrevSection)
          ? normalizedPrevSection
          : 'All Sections';

      final nextSelectedStatus =
      statusOptions.contains(prevStatus) ? prevStatus : 'All Status';

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

        sellerOptions = nextSellerOptions;
        financialYearOptions = nextFinancialYearOptions;
        sectionOptions = nextSectionOptions;

        selectedSeller = nextSelectedSeller;
        selectedFinancialYear = nextSelectedFinancialYear;
        selectedSection = nextSelectedSection;
        selectedStatus = nextSelectedStatus;
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
    final nextFilteredRows = _filterRows(
      rows: allRows,
      selectedSellerValue: selectedSeller,
      selectedFinancialYearValue: selectedFinancialYear,
      selectedSectionValue: selectedSection,
      selectedStatusValue: selectedStatus,
    );

    setState(() {
      filteredRows = nextFilteredRows;
    });
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

  Future<void> _exportExcel() async {
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
    final purchaseNames = widget.purchaseRows
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

    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualMappingScreen(
          purchaseParties: purchaseNames,
          tdsParties: tdsNames,
          initialMapping: manualNameMapping,
        ),
      ),
    );

    if (result == null) return;

    final cleanedResult = <String, String>{};

    for (final entry in result.entries) {
      final aliasName = entry.key.trim();
      final mappedName = entry.value.trim();

      if (aliasName.isEmpty || mappedName.isEmpty) continue;

      final normalizedAliasKey = normalizeName(aliasName);
      if (normalizedAliasKey.isEmpty) continue;

      cleanedResult[normalizedAliasKey] = mappedName;

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

    if (!mounted) return;

    setState(() {
      manualNameMapping = cleanedResult;
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
                  onPressed: filteredRows.isEmpty ? null : _exportExcel,
                  icon: const Icon(Icons.download),
                  label: const Text('Export Full'),
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
                setState(() => selectedSection = value);
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