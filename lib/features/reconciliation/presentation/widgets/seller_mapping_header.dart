import 'package:flutter/material.dart';
import 'package:reconciliation_app/core/widgets/app_section_selector.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_models.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_summary_cards.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_theme.dart';
import 'package:reconciliation_app/features/reconciliation/utils/reconciliation_section_utils.dart';

class SellerMappingHeader extends StatelessWidget {
  final String buyerName;
  final String buyerPan;
  final String buyerGstNo;
  final String financialYearLabel;
  final SellerMappingListView activeListView;
  final ValueChanged<SellerMappingListView> onListViewChanged;
  final List<String> availableSectionCodes;
  final String activeSectionCode;
  final int Function(String sectionCode) needsActionCountForSection;
  final ValueChanged<String> onSectionChanged;
  final List<SellerMappingSummaryMetric> summaryMetrics;
  final VoidCallback onBack;

  const SellerMappingHeader({
    super.key,
    required this.buyerName,
    required this.buyerPan,
    required this.buyerGstNo,
    required this.financialYearLabel,
    required this.activeListView,
    required this.onListViewChanged,
    required this.availableSectionCodes,
    required this.activeSectionCode,
    required this.needsActionCountForSection,
    required this.onSectionChanged,
    required this.summaryMetrics,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: SellerMappingTheme.surfaceColor,
        border: const Border(
          bottom: BorderSide(color: SellerMappingTheme.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onBack,
                style: IconButton.styleFrom(
                  backgroundColor: SellerMappingTheme.primarySoft,
                  foregroundColor: SellerMappingTheme.primaryColor,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seller Mapping Audit',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: SellerMappingTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      buyerName.trim().isEmpty
                          ? 'Unnamed Buyer'
                          : buyerName.trim(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: SellerMappingTheme.titleTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<SellerMappingListView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SellerMappingListView.needsAction,
                    label: Text('Needs Action'),
                  ),
                  ButtonSegment(
                    value: SellerMappingListView.allSellers,
                    label: Text('All Sellers'),
                  ),
                ],
                selected: <SellerMappingListView>{activeListView},
                onSelectionChanged: (selection) {
                  onListViewChanged(selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SellerMappingPill(
                icon: Icons.badge_outlined,
                label: buyerPan.trim().isEmpty
                    ? 'PAN unavailable'
                    : buyerPan.trim().toUpperCase(),
              ),
              if (buyerGstNo.trim().isNotEmpty)
                SellerMappingPill(
                  icon: Icons.receipt_long_outlined,
                  label: buyerGstNo.trim().toUpperCase(),
                ),
              if (financialYearLabel.trim().isNotEmpty)
                SellerMappingPill(
                  icon: Icons.calendar_today_outlined,
                  label: financialYearLabel.trim(),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSectionSelector(
                  showContainer: false,
                  items: availableSectionCodes.map((sectionCode) {
                    final isSelected = activeSectionCode == sectionCode;
                    final count = needsActionCountForSection(sectionCode);
                    final isUnsupportedSection =
                        isUnsupportedReconciliationSection(sectionCode);
                    return AppSectionSelectorItem(
                      value: sectionCode,
                      label: isUnsupportedSection
                          ? unsupportedSectionDisplayLabel(sectionCode)
                          : compactSectionDisplayLabel(sectionCode),
                      subtitle: 'Needs action',
                      metricLabel: count.toString(),
                      isSelected: isSelected,
                      onTap: () => onSectionChanged(sectionCode),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: summaryMetrics
                    .where((metric) => metric.value > 0)
                    .map((metric) => SellerMappingMetricCard(metric: metric))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
