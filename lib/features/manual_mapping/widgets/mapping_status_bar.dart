import 'package:flutter/material.dart';

class MappingStatusBar extends StatelessWidget {
  final int mappedCount;
  final int totalColumns;
  final List<String> warnings;
  final bool saveProfile;
  final ValueChanged<bool> onSaveProfileChanged;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  const MappingStatusBar({
    super.key,
    required this.mappedCount,
    required this.totalColumns,
    required this.warnings,
    required this.saveProfile,
    required this.onSaveProfileChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$mappedCount of $totalColumns columns mapped',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  warnings.isEmpty
                      ? 'Ready to save and continue import.'
                      : warnings.join('  •  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF131D2B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: saveProfile,
                  onChanged: (value) => onSaveProfileChanged(value ?? false),
                  activeColor: const Color(0xFF38BDF8),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Text(
                    'Save format profile',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF475569)),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF082F49),
            ),
            child: const Text('Save Column Mapping'),
          ),
        ],
      ),
    );
  }
}
