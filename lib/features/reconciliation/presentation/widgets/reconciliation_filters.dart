import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_filter_bar.dart';

class ReconciliationFilters extends StatelessWidget {
  final String selectedSeller;
  final String selectedFinancialYear;
  final String selectedSection;
  final String selectedStatus;

  final List<String> sellerOptions;
  final List<String> financialYearOptions;
  final List<String> sectionOptions;
  final List<String> statusOptions;

  final Function(String?) onSellerChanged;
  final Function(String?) onFinancialYearChanged;
  final Function(String?) onSectionChanged;
  final Function(String?) onStatusChanged;
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
        final isCompact = constraints.maxWidth < 920;
        final normalizedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 920.0;
        final fieldWidth = isCompact
            ? normalizedWidth
            : (normalizedWidth - (showSectionFilter ? 36 : 24)) /
                (showSectionFilter ? 4 : 3);

        return AppFilterBar(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _buildField(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: selectedSeller,
                decoration: _decoration('Seller Filter'),
                items: sellerOptions
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: onSellerChanged,
              ),
            ),
            _buildField(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: selectedFinancialYear,
                decoration: _decoration('Financial Year'),
                items: financialYearOptions
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: onFinancialYearChanged,
              ),
            ),
            if (showSectionFilter)
              _buildField(
                width: fieldWidth,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedSection,
                  decoration: _decoration('Section'),
                  items: sectionOptions
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: onSectionChanged,
                ),
              ),
            _buildField(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: _decoration('Status'),
                items: statusOptions
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColorScheme.textMuted,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColorScheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(
          color: AppColorScheme.primary,
          width: 1.2,
        ),
      ),
      filled: true,
      fillColor: const Color(0xFFFDFEFF),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 14,
      ),
    );
  }
}
