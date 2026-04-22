import 'package:flutter/material.dart';

class ReconciliationBottomActionBar extends StatelessWidget {
  final VoidCallback? onExportCurrentSection;
  final VoidCallback? onExportAllSections;
  final VoidCallback? onExportPivot;

  const ReconciliationBottomActionBar({
    super.key,
    required this.onExportCurrentSection,
    required this.onExportAllSections,
    required this.onExportPivot,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: onExportCurrentSection,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export Current Section'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onExportAllSections,
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: const Text('Export All Sections'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onExportPivot,
                    icon: const Icon(Icons.table_chart_rounded),
                    label: const Text('Export Pivot'),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onExportCurrentSection,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export Current Section'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExportAllSections,
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: const Text('Export All Sections'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExportPivot,
                    icon: const Icon(Icons.table_chart_rounded),
                    label: const Text('Export Pivot'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
