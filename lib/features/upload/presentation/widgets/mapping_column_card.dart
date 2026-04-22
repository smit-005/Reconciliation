import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/upload/models/mapping_field_option.dart';

class MappingColumnCard extends StatelessWidget {
  final String columnLabel;
  final String columnKey;
  final String? sampleValue;
  final String? selectedValue;
  final bool hasDuplicate;
  final List<MappingFieldOption> options;
  final ValueChanged<String?> onChanged;

  const MappingColumnCard({
    super.key,
    required this.columnLabel,
    required this.columnKey,
    required this.sampleValue,
    required this.selectedValue,
    required this.hasDuplicate,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDuplicate ? const Color(0xFFEF4444) : const Color(0xFF273247),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            columnLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sampleValue?.trim().isNotEmpty == true
                ? sampleValue!
                : 'No sample value',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                selectedValue?.isNotEmpty == true ? selectedValue : null,
            dropdownColor: const Color(0xFF182235),
            decoration: InputDecoration(
              labelText: 'Map field',
              labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasDuplicate
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF334155),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF38BDF8)),
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Ignore column'),
              ),
              ...options.map(
                (option) => DropdownMenuItem<String>(
                  value: option.key,
                  child: Text(option.label),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
          if (hasDuplicate) ...[
            const SizedBox(height: 8),
            const Text(
              'This business field is mapped more than once.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFCA5A5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
