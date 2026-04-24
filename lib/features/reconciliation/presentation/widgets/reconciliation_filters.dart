import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_compact_select_field.dart';
import 'package:reconciliation_app/core/widgets/app_filter_bar.dart';
import 'package:reconciliation_app/core/widgets/app_search_autocomplete_field.dart';

class ReconciliationFilters extends StatelessWidget {
  final String selectedSeller;
  final String selectedFinancialYear;
  final String selectedSection;
  final String selectedStatus;

  final List<String> sellerOptions;
  final List<String> financialYearOptions;
  final List<String> sectionOptions;
  final List<String> statusOptions;

  final ValueChanged<String> onSellerChanged;
  final ValueChanged<String> onFinancialYearChanged;
  final ValueChanged<String> onSectionChanged;
  final ValueChanged<String> onStatusChanged;
  final bool showSectionFilter;

  const ReconciliationFilters({
    super.key,
    required this.selectedSeller,
    required this.selectedFinancialYear,
    required this.selectedSection,
    required this.selectedStatus,
    required this.sellerOptions,
    required this.financialYearOptions,
    required this.sectionOptions,
    required this.statusOptions,
    required this.onSellerChanged,
    required this.onFinancialYearChanged,
    required this.onSectionChanged,
    required this.onStatusChanged,
    this.showSectionFilter = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        final normalizedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 920.0;
        final sellerFieldWidth = isCompact ? normalizedWidth : 360.0;
        final financialYearFieldWidth = isCompact ? normalizedWidth : 200.0;
        final statusFieldWidth = isCompact ? normalizedWidth : 190.0;
        final sectionFieldWidth = isCompact ? normalizedWidth : 190.0;

        return AppFilterBar(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _buildField(
              width: sellerFieldWidth,
              child: AppSearchAutocompleteField(
                value: selectedSeller,
                options: sellerOptions,
                hintText: 'Search seller or PAN...',
                labelText: 'Seller Search',
                onChanged: onSellerChanged,
                searchableTermsBuilder: (option) => <String>[option],
              ),
            ),
            _buildField(
              width: financialYearFieldWidth,
              child: AppCompactSelectField(
                value: selectedFinancialYear,
                options: financialYearOptions,
                labelText: 'Financial Year',
                onChanged: onFinancialYearChanged,
              ),
            ),
            if (showSectionFilter)
              _buildField(
                width: sectionFieldWidth,
                child: AppCompactSelectField(
                  value: selectedSection,
                  options: sectionOptions,
                  labelText: 'Section',
                  onChanged: onSectionChanged,
                ),
            ),
            _buildField(
              width: statusFieldWidth,
              child: AppCompactSelectField(
                value: selectedStatus,
                options: statusOptions,
                labelText: 'Status',
                onChanged: onStatusChanged,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildField({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }
}
