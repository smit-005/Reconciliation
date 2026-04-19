import 'package:flutter/material.dart';

import '../../features/upload/models/mapping_field_option.dart';

class MappingRequiredFieldsPanel extends StatelessWidget {
  final List<MappingFieldOption> requiredFields;
  final Map<String, bool> completionStatus;
  final List<String> errors;

  const MappingRequiredFieldsPanel({
    super.key,
    required this.requiredFields,
    required this.completionStatus,
    required this.errors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Required Fields',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          ...requiredFields.map((field) {
            final mapped = completionStatus[field.key] ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    mapped ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18,
                    color: mapped
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      field.label,
                      style: TextStyle(
                        color: mapped ? Colors.white : const Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (errors.isNotEmpty) ...[
            const Divider(color: Color(0xFF273247)),
            ...errors.map(
              (error) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
