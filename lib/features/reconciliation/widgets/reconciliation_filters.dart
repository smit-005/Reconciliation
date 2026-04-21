import 'package:flutter/material.dart';

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
        final fieldWidth = isCompact
            ? constraints.maxWidth
            : (constraints.maxWidth - (showSectionFilter ? 36 : 24)) /
                (showSectionFilter ? 4 : 3);

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildField(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                value: selectedSeller,
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
                value: selectedFinancialYear,
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
                  value: selectedSection,
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
                value: selectedStatus,
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}
