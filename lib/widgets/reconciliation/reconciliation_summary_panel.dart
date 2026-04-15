import 'package:flutter/material.dart';

import 'reconciliation_common_widgets.dart';
import 'reconciliation_analytics_panel.dart';

class ReconciliationSummaryPanel extends StatelessWidget {
  final String buyerName;
  final String buyerPan;
  final String gstNo;
  final String selectedSeller;
  final String selectedFinancialYear;
  final String selectedSection;
  final String selectedStatus;

  final int filteredRowsCount;
  final int totalSellers;
  final int totalSections;
  final double matchedPercentage;
  final double mismatchPercentage;
  final String topMismatchSection;

  final double basicAmount;
  final double applicableAmount;
  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double tdsDifference;
  final double amountDifference;

  final int matchedCount;
  final int timingDifferenceCount;
  final int shortDeductionCount;
  final int excessDeductionCount;
  final int purchaseOnlyCount;
  final int only26QCount;
  final int applicableButNo26QCount;

  final double shortDeductionAmount;
  final double excessDeductionAmount;
  final double timingDifferenceAmount;
  final double purchaseOnlyAmount;
  final double only26QAmount;
  final double netMismatchAmount;
  final double applicableButNo26QAmount;
  final double applicableButNo26QTds;

  final int manualMappingsCount;
  final int mismatchRowsCount;
  final Map<String, int> sectionCounts;

  const ReconciliationSummaryPanel({
    super.key,
    required this.buyerName,
    required this.buyerPan,
    required this.gstNo,
    required this.selectedSeller,
    required this.selectedFinancialYear,
    required this.selectedSection,
    required this.selectedStatus,
    required this.filteredRowsCount,
    required this.totalSellers,
    required this.totalSections,
    required this.matchedPercentage,
    required this.mismatchPercentage,
    required this.topMismatchSection,
    required this.basicAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.tdsDifference,
    required this.amountDifference,
    required this.matchedCount,
    required this.timingDifferenceCount,
    required this.shortDeductionCount,
    required this.excessDeductionCount,
    required this.purchaseOnlyCount,
    required this.only26QCount,
    required this.applicableButNo26QCount,
    required this.shortDeductionAmount,
    required this.excessDeductionAmount,
    required this.timingDifferenceAmount,
    required this.purchaseOnlyAmount,
    required this.only26QAmount,
    required this.netMismatchAmount,
    required this.applicableButNo26QAmount,
    required this.applicableButNo26QTds,
    required this.manualMappingsCount,
    required this.mismatchRowsCount,
    required this.sectionCounts,
  });

  String _fmt(double value) => value.toStringAsFixed(2);

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
          summaryTile('Buyer Name', buyerName.isEmpty ? '-' : buyerName),
          summaryTile('Buyer PAN', buyerPan.isEmpty ? '-' : buyerPan),
          summaryTile('GST No', gstNo.isEmpty ? '-' : gstNo),
          summaryTile('Seller Filter', selectedSeller),
          summaryTile('FY Filter', selectedFinancialYear),
          summaryTile('Section Filter', selectedSection),
          summaryTile('Status Filter', selectedStatus),
          summaryTile('Rows', filteredRowsCount.toString()),
          summaryTile('Total Sellers', totalSellers.toString()),
          summaryTile('Sections Found', totalSections.toString()),
          summaryTile('Matched %', '${matchedPercentage.toStringAsFixed(1)}%'),
          summaryTile('Mismatch %', '${mismatchPercentage.toStringAsFixed(1)}%'),
          summaryTile('Top Mismatch Section', topMismatchSection),
          summaryTile('Basic Amount', _fmt(basicAmount)),
          summaryTile('Applicable Amount', _fmt(applicableAmount)),
          summaryTile('26Q Amount', _fmt(tds26QAmount)),
          summaryTile('Expected TDS', _fmt(expectedTds)),
          summaryTile('Actual TDS', _fmt(actualTds)),
          summaryTile('TDS Difference', _fmt(tdsDifference)),
          summaryTile('Amount Difference', _fmt(amountDifference)),
          summaryTile('Matched', matchedCount.toString()),
          summaryTile('Timing Difference', timingDifferenceCount.toString()),
          summaryTile('Short Deduction', shortDeductionCount.toString()),
          summaryTile('Excess Deduction', excessDeductionCount.toString()),
          summaryTile('Purchase Only', purchaseOnlyCount.toString()),
          summaryTile('26Q Only', only26QCount.toString()),
          summaryTile('Applicable but no 26Q', applicableButNo26QCount.toString()),
          summaryTile('Short Deduction Amt', _fmt(shortDeductionAmount)),
          summaryTile('Excess Deduction Amt', _fmt(excessDeductionAmount)),
          summaryTile('Timing Difference Amt', _fmt(timingDifferenceAmount)),
          summaryTile('Purchase Only Amt', _fmt(purchaseOnlyAmount)),
          summaryTile('26Q Only Amt', _fmt(only26QAmount)),
          summaryTile('Net Mismatch', _fmt(netMismatchAmount)),
          summaryTile('Manual Mappings', manualMappingsCount.toString()),
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
          mismatchTile(
            label: 'Applicable but no 26Q Rows',
            value: applicableButNo26QCount.toString(),
            bgColor: Colors.red.shade50,
            textColor: Colors.red.shade700,
          ),
          mismatchTile(
            label: 'Applicable Amount Missing in 26Q',
            value: _fmt(applicableButNo26QAmount),
            bgColor: Colors.orange.shade50,
            textColor: Colors.orange.shade800,
          ),
          mismatchTile(
            label: 'Expected TDS Missing in 26Q',
            value: _fmt(applicableButNo26QTds),
            bgColor: Colors.deepOrange.shade50,
            textColor: Colors.deepOrange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildMismatchSummary() {
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
              mismatchTile(
                label: 'Mismatch Rows',
                value: mismatchRowsCount.toString(),
                bgColor: Colors.red.shade50,
                textColor: Colors.red.shade700,
              ),
              mismatchTile(
                label: 'Short Deduction TDS',
                value: _fmt(shortDeductionAmount),
                bgColor: Colors.orange.shade50,
                textColor: Colors.orange.shade800,
              ),
              mismatchTile(
                label: 'Excess Deduction TDS',
                value: _fmt(excessDeductionAmount),
                bgColor: Colors.red.shade50,
                textColor: Colors.red.shade700,
              ),
              mismatchTile(
                label: 'Timing Difference TDS',
                value: _fmt(timingDifferenceAmount),
                bgColor: Colors.teal.shade50,
                textColor: Colors.teal.shade700,
              ),
              mismatchTile(
                label: 'Purchase Only Rows',
                value: purchaseOnlyCount.toString(),
                bgColor: Colors.blue.shade50,
                textColor: Colors.blue.shade700,
              ),
              mismatchTile(
                label: '26Q Only Rows',
                value: only26QCount.toString(),
                bgColor: Colors.purple.shade50,
                textColor: Colors.purple.shade700,
              ),
              mismatchTile(
                label: 'Net Mismatch TDS',
                value: _fmt(netMismatchAmount),
                bgColor: Colors.amber.shade50,
                textColor: Colors.deepOrange.shade700,
              ),
            ],
          ),
        ],
      ),
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
            'Buyer, totals, analytics, mismatch cards and notes.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          children: [
            _buildTopSummaryCard(),
            const SizedBox(height: 16),
            ReconciliationAnalyticsPanel(
              mismatchRowsCount: mismatchRowsCount,
              mismatchPercentage: mismatchPercentage,
              matchedPercentage: matchedPercentage,
              topMismatchSection: topMismatchSection,
              totalSellers: totalSellers,
              totalSections: totalSections,
              sectionCounts: sectionCounts,
            ),
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
}