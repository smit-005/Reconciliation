import 'package:flutter/material.dart';

import '../core/utils/calculation.dart';
import '../services/excel_export_service.dart';
import '../core/utils/auto_mapping.dart';
import '../services/mapping_service.dart';
import '../models/seller_mapping.dart';
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

  Map<String, String> manualNameMapping = {};

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

  String selectedSeller = 'All Sellers';
  String selectedFinancialYear = 'All FY';
  String selectedStatus = 'All Status';

  bool showAllRows = false;
  bool showSummaryPanel = false;
  bool _isRecalculating = false;

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
      final prevStatus = selectedStatus;

      final purchaseNames = widget.purchaseRows.map((e) => e.partyName).toList();
      final tdsNames = widget.tdsRows.map((e) => e.deducteeName).toList();

      final mappingResults = AutoMappingService.autoMapParties(
        purchaseParties: purchaseNames,
        tdsParties: tdsNames,
        threshold: 0.80,
      );

      final nameMapping = <String, String>{};

      for (final m in mappingResults) {
        final p = m.purchaseParty.trim();
        final t = m.matchedTdsParty?.trim();

        if (p.isEmpty || t == null || t.isEmpty) continue;

        // normal safe match
        if (m.isMatched) {
          nameMapping[p] = t;
          debugPrint('SAFE AUTO MAP => $p -> $t | score=${m.score}');
          continue;
        }

        // fallback for normalized exact match after typo cleanup
        final pNorm = AutoMappingService.normalizePartyName(p);
        final tNorm = AutoMappingService.normalizePartyName(t);

        if (pNorm == tNorm) {
          nameMapping[p] = t;
          debugPrint('FALLBACK MAP => $p -> $t | score=${m.score}');
        }
      }

// manual mapping override
      for (final entry in manualNameMapping.entries) {
        if (entry.key.trim().isEmpty || entry.value.trim().isEmpty) continue;
        nameMapping[entry.key.trim()] = entry.value.trim();
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

      final nextSellerOptions = ['All Sellers', ...sellers];
      final nextFinancialYearOptions = ['All FY', ...financialYears];

      final nextSelectedSeller =
      nextSellerOptions.contains(prevSeller) ? prevSeller : 'All Sellers';
      final nextSelectedFinancialYear = nextFinancialYearOptions.contains(prevFY)
          ? prevFY
          : 'All FY';
      final nextSelectedStatus =
      statusOptions.contains(prevStatus) ? prevStatus : 'All Status';

      final nextFilteredRows = _filterRows(
        rows: freshRows,
        selectedSellerValue: nextSelectedSeller,
        selectedFinancialYearValue: nextSelectedFinancialYear,
        selectedStatusValue: nextSelectedStatus,
      );

      if (!mounted) return;

      setState(() {
        allRows = freshRows;
        filteredRows = nextFilteredRows;

        sellerOptions = nextSellerOptions;
        financialYearOptions = nextFinancialYearOptions;

        selectedSeller = nextSelectedSeller;
        selectedFinancialYear = nextSelectedFinancialYear;
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
    required String selectedStatusValue,
  }) {
    var result = List<ReconciliationRow>.from(rows);

    String normalizePan(String pan) {
      final value = pan.trim().toUpperCase();
      if (value.isEmpty || value == '-' || value == 'NA' || value == 'N/A') {
        return '';
      }
      return value;
    }

    String buildSellerDisplayKey(ReconciliationRow row) {
      return row.sellerName.trim().toUpperCase();
    }

    if (selectedSellerValue != 'All Sellers') {
      result = result
          .where((row) => row.sellerName.trim() == selectedSellerValue.trim())
          .toList();
    }

    if (selectedFinancialYearValue != 'All FY') {
      result = result
          .where(
            (row) => row.financialYear.trim() == selectedFinancialYearValue.trim(),
      )
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

      final panA = normalizePan(a.sellerPan);
      final panB = normalizePan(b.sellerPan);
      final panCompare = panA.compareTo(panB);
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
        .fold(0.0, (sum, row) => sum + row.tdsDifference);
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

  Future<void> _openManualMappingScreen() async {
    final purchaseNames = widget.purchaseRows.map((e) => e.partyName).toList();
    final tdsNames = widget.tdsRows.map((e) => e.deducteeName).toList();

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

    if (result != null) {
      setState(() {
        manualNameMapping = result;
      });
      await _recalculateAll();
    }
  }

  Future<void> _exportPivotExcel() async {
    try {
      final filePath = await ExcelExportService.exportPivotSummaryExcel(
        rows: filteredRows,
        buyerName: widget.buyerName,
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

  Widget _summaryTile(String label, String value) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _mismatchTile({
    required String label,
    required String value,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildTopSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        children: [
          _summaryTile(
            'Buyer Name',
            widget.buyerName.isEmpty ? '-' : widget.buyerName,
          ),
          _summaryTile(
            'Buyer PAN',
            widget.buyerPan.isEmpty ? '-' : widget.buyerPan,
          ),
          _summaryTile('GST No', widget.gstNo.isEmpty ? '-' : widget.gstNo),
          _summaryTile('Seller Filter', selectedSeller),
          _summaryTile('FY Filter', selectedFinancialYear),
          _summaryTile('Status Filter', selectedStatus),
          _summaryTile('Rows', filteredRows.length.toString()),
          _summaryTile('Basic Amount', _fmt(_sum((e) => e.basicAmount))),
          _summaryTile(
            'Applicable Amount',
            _fmt(_sum((e) => e.applicableAmount)),
          ),
          _summaryTile('26Q Amount', _fmt(_sum((e) => e.tds26QAmount))),
          _summaryTile('Expected TDS', _fmt(_sum((e) => e.expectedTds))),
          _summaryTile('Actual TDS', _fmt(_sum((e) => e.actualTds))),
          _summaryTile('TDS Difference', _fmt(_sum((e) => e.tdsDifference))),
          _summaryTile(
            'Amount Difference',
            _fmt(_sum((e) => e.amountDifference)),
          ),
          _summaryTile('Matched', _countByStatus('Matched').toString()),
          _summaryTile(
            'Timing Difference',
            _countByStatus('Timing Difference').toString(),
          ),
          _summaryTile(
            'Short Deduction',
            _countByStatus('Short Deduction').toString(),
          ),
          _summaryTile(
            'Excess Deduction',
            _countByStatus('Excess Deduction').toString(),
          ),
          _summaryTile(
            'Purchase Only',
            _countByStatus('Purchase Only').toString(),
          ),
          _summaryTile('26Q Only', _countByStatus('26Q Only').toString()),
          _summaryTile(
            'Applicable but no 26Q',
            _applicableButNo26QCount().toString(),
          ),
          _summaryTile(
            'Short Deduction Amt',
            _fmt(_shortDeductionAmount()),
          ),
          _summaryTile(
            'Excess Deduction Amt',
            _fmt(_excessDeductionAmount()),
          ),
          _summaryTile(
            'Timing Difference Amt',
            _fmt(_timingDifferenceAmount()),
          ),
          _summaryTile('Net Mismatch', _fmt(_netMismatchAmount())),
          _summaryTile(
            'Manual Mappings',
            manualNameMapping.length.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicableNo26QSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          _mismatchTile(
            label: 'Applicable but no 26Q Rows',
            value: _applicableButNo26QCount().toString(),
            bgColor: Colors.red.shade50,
            textColor: Colors.red.shade700,
          ),
          _mismatchTile(
            label: 'Applicable Amount Missing in 26Q',
            value: _fmt(_applicableButNo26QAmount()),
            bgColor: Colors.orange.shade50,
            textColor: Colors.orange.shade800,
          ),
          _mismatchTile(
            label: 'Expected TDS Missing in 26Q',
            value: _fmt(_applicableButNo26QTds()),
            bgColor: Colors.deepOrange.shade50,
            textColor: Colors.deepOrange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildMismatchSummary() {
    final mismatchRows = filteredRows
        .where(
          (row) =>
      row.status == 'Short Deduction' ||
          row.status == 'Excess Deduction' ||
          row.status == 'Purchase Only' ||
          row.status == '26Q Only',
    )
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mismatch Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              _mismatchTile(
                label: 'Mismatch Rows',
                value: mismatchRows.toString(),
                bgColor: Colors.red.shade50,
                textColor: Colors.red.shade700,
              ),
              _mismatchTile(
                label: 'Short Deduction TDS',
                value: _fmt(_shortDeductionAmount()),
                bgColor: Colors.orange.shade50,
                textColor: Colors.orange.shade800,
              ),
              _mismatchTile(
                label: 'Excess Deduction TDS',
                value: _fmt(_excessDeductionAmount()),
                bgColor: Colors.red.shade50,
                textColor: Colors.red.shade700,
              ),
              _mismatchTile(
                label: 'Timing Difference TDS',
                value: _fmt(_timingDifferenceAmount()),
                bgColor: Colors.teal.shade50,
                textColor: Colors.teal.shade700,
              ),
              _mismatchTile(
                label: 'Purchase Only Rows',
                value: _countByStatus('Purchase Only').toString(),
                bgColor: Colors.blue.shade50,
                textColor: Colors.blue.shade700,
              ),
              _mismatchTile(
                label: '26Q Only Rows',
                value: _countByStatus('26Q Only').toString(),
                bgColor: Colors.purple.shade50,
                textColor: Colors.purple.shade700,
              ),
              _mismatchTile(
                label: 'Net Mismatch TDS',
                value: _fmt(_netMismatchAmount()),
                bgColor: Colors.amber.shade50,
                textColor: Colors.deepOrange.shade700,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedSeller,
            decoration: const InputDecoration(
              labelText: 'Seller',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: sellerOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                selectedSeller = value;
              });
              _applyFilters();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedFinancialYear,
            decoration: const InputDecoration(
              labelText: 'Financial Year',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: financialYearOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                selectedFinancialYear = value;
              });
              _applyFilters();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedStatus,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: statusOptions
                .map(
                  (e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                selectedStatus = value;
              });
              _applyFilters();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    if (filteredRows.isEmpty) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No rows found for selected filters.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    String normalizePan(String pan) {
      final value = pan.trim().toUpperCase();
      if (value.isEmpty || value == '-' || value == 'NA' || value == 'N/A') {
        return '';
      }
      return value;
    }

    String buildDisplayGroupKey(ReconciliationRow row) {
      return row.sellerName.trim().toUpperCase();
    }

    String resolveDisplayPan(List<ReconciliationRow> rows) {
      for (final row in rows) {
        final pan = normalizePan(row.sellerPan);
        if (pan.isNotEmpty) return pan;
      }
      return '-';
    }

    final grouped = <String, List<ReconciliationRow>>{};

    for (final row in filteredRows) {
      final key = buildDisplayGroupKey(row);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(row);
    }

    final groupKeys = grouped.keys.toList()..sort();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: groupKeys.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final key = groupKeys[index];
          final sourceRows = grouped[key]!;

          final rows = List<ReconciliationRow>.from(sourceRows)
            ..sort((a, b) {
              final fyCompare = a.financialYear.compareTo(b.financialYear);
              if (fyCompare != 0) return fyCompare;
              return CalculationService.compareMonthLabels(a.month, b.month);
            });

          final sellerName = rows.first.sellerName.trim().isEmpty
              ? '-'
              : rows.first.sellerName.trim();
          final sellerPan = resolveDisplayPan(rows);

          final totalBasic =
          rows.fold<double>(0.0, (sum, row) => sum + row.basicAmount);
          final totalApplicable =
          rows.fold<double>(0.0, (sum, row) => sum + row.applicableAmount);
          final total26Q =
          rows.fold<double>(0.0, (sum, row) => sum + row.tds26QAmount);
          final totalExpected =
          rows.fold<double>(0.0, (sum, row) => sum + row.expectedTds);
          final totalActual =
          rows.fold<double>(0.0, (sum, row) => sum + row.actualTds);

          final fyGroups = <String, List<ReconciliationRow>>{};
          for (final row in rows) {
            fyGroups.putIfAbsent(row.financialYear, () => []);
            fyGroups[row.financialYear]!.add(row);
          }

          final fyKeys = fyGroups.keys.toList()..sort();

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        sellerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      _miniInfoChip('PAN', sellerPan),
                      _miniInfoChip('Rows', rows.length.toString()),
                      _miniInfoChip('Basic', _fmt(totalBasic)),
                      _miniInfoChip('Applicable', _fmt(totalApplicable)),
                      _miniInfoChip('26Q', _fmt(total26Q)),
                      _miniInfoChip('Expected TDS', _fmt(totalExpected)),
                      _miniInfoChip('Actual TDS', _fmt(totalActual)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: fyKeys.map((fy) {
                      final fyRows = List<ReconciliationRow>.from(fyGroups[fy]!)
                        ..sort(
                              (a, b) => CalculationService.compareMonthLabels(
                            a.month,
                            b.month,
                          ),
                        );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildFinancialYearSection(fy, fyRows),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFinancialYearSection(
      String financialYear,
      List<ReconciliationRow> rows,
      ) {
    final totalBasic =
    rows.fold<double>(0.0, (sum, row) => sum + row.basicAmount);
    final totalApplicable =
    rows.fold<double>(0.0, (sum, row) => sum + row.applicableAmount);
    final total26Q =
    rows.fold<double>(0.0, (sum, row) => sum + row.tds26QAmount);
    final totalExpected =
    rows.fold<double>(0.0, (sum, row) => sum + row.expectedTds);
    final totalActual =
    rows.fold<double>(0.0, (sum, row) => sum + row.actualTds);
    final totalTdsDiff =
    rows.fold<double>(0.0, (sum, row) => sum + row.tdsDifference);
    final totalAmountDiff =
    rows.fold<double>(0.0, (sum, row) => sum + row.amountDifference);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'FY $financialYear',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _miniInfoChip('Basic', _fmt(totalBasic)),
                _miniInfoChip('Applicable', _fmt(totalApplicable)),
                _miniInfoChip('26Q', _fmt(total26Q)),
                _miniInfoChip('Expected', _fmt(totalExpected)),
                _miniInfoChip('Actual', _fmt(totalActual)),
                _miniInfoChip('TDS Diff', _fmt(totalTdsDiff)),
                _miniInfoChip('Amt Diff', _fmt(totalAmountDiff)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 68,
              headingRowColor: WidgetStatePropertyAll(Colors.blue.shade100),
              columns: const [
                DataColumn(
                  label: Text(
                    'Month',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Basic Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Applicable Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '26Q Amount',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Expected TDS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Actual TDS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'TDS Diff',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Amt Diff',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Remarks',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: [
                ...rows.map(
                      (row) => DataRow(
                    color: WidgetStatePropertyAll(_statusColor(row.status)),
                    cells: [
                      DataCell(Text(row.month.isEmpty ? '-' : row.month)),
                      DataCell(Text(_fmt(row.basicAmount))),
                      DataCell(Text(_fmt(row.applicableAmount))),
                      DataCell(Text(_fmt(row.tds26QAmount))),
                      DataCell(Text(_fmt(row.expectedTds))),
                      DataCell(Text(_fmt(row.actualTds))),
                      DataCell(Text(_fmt(row.tdsDifference))),
                      DataCell(Text(_fmt(row.amountDifference))),
                      DataCell(
                        Text(
                          row.status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _statusTextColor(row.status),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Text(row.remarks.isEmpty ? '-' : row.remarks),
                        ),
                      ),
                    ],
                  ),
                ),
                DataRow(
                  color: WidgetStatePropertyAll(Colors.amber.shade50),
                  cells: [
                    const DataCell(
                      Text(
                        'TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalBasic),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalApplicable),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(total26Q),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalExpected),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalActual),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalTdsDiff),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(
                      Text(
                        _fmt(totalAmountDiff),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: false,
          title: const Text(
            'Summary & Mismatch Insights',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Buyer, totals, mismatch cards and notes. Open when needed.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          children: [
            _buildTopSummaryCard(),
            const SizedBox(height: 16),
            _buildApplicableNo26QSummary(),
            const SizedBox(height: 16),
            _buildMismatchSummary(),
            const SizedBox(height: 16),
            _buildFooterNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.table_view_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              'Reconciliation Table',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Text(
                '${filteredRows.length} rows',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo.shade700,
                ),
              ),
            ),
            if (_isRecalculating) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildTable()),
      ],
    );
  }

  Widget _buildFooterNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: const Text(
        'Applicable but no 26Q means: Applicable Amount is greater than zero, so TDS should have been deducted, but no deducted amount / TDS is found in 26Q for that row. Relevant seller logic used: only sellers present in 26Q or sellers whose financial year purchase crosses ₹50,00,000 are included. Basic Amount is amount without GST. Applicable Amount starts only after cumulative ₹50,00,000 threshold in that FY. TDS rate is 0.1%.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
            _buildFilters(),
            if (showSummaryPanel) ...[
              const SizedBox(height: 16),
              _buildSummaryPanel(),
            ],
            const SizedBox(height: 16),
            Expanded(child: _buildTableSection()),
          ],
        ),
      ),
    );
  }
}