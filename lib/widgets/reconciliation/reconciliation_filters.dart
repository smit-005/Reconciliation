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
  });

  @override
  Widget build(BuildContext context) {
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
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onSellerChanged,
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
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onFinancialYearChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedSection,
            decoration: const InputDecoration(
              labelText: 'Section',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: sectionOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onSectionChanged,
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
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onStatusChanged,
          ),
        ),
      ],
    );
  }
}