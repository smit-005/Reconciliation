import 'package:flutter/material.dart';

class ReconciliationTopToolbar extends StatelessWidget {
  final String buyerName;
  final String buyerPan;
  final String gstNo;
  final Widget sectionTabs;
  final Widget filters;
  final bool showAllRows;
  final bool isRecalculating;
  final ValueChanged<bool> onShowAllRowsChanged;
  final VoidCallback? onRecalculate;
  final VoidCallback onManualMapping;

  const ReconciliationTopToolbar({
    super.key,
    required this.buyerName,
    required this.buyerPan,
    required this.gstNo,
    required this.sectionTabs,
    required this.filters,
    required this.showAllRows,
    required this.isRecalculating,
    required this.onShowAllRowsChanged,
    required this.onRecalculate,
    required this.onManualMapping,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7DCE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBuyerLine(),
          const SizedBox(height: 6),
          sectionTabs,
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1240;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filters,
                    const SizedBox(height: 6),
                    _buildActionRow(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: filters),
                  const SizedBox(width: 12),
                  _buildActionRow(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBuyerLine() {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          buyerName.isEmpty ? '-' : buyerName,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        _metaText('PAN', buyerPan.isEmpty ? '-' : buyerPan),
        _metaText('GST', gstNo.isEmpty ? '-' : gstNo),
      ],
    );
  }

  Widget _metaText(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF475569),
        ),
        children: [
          const TextSpan(
            text: '| ',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildRawModeSwitch(),
        FilledButton.icon(
          onPressed: onRecalculate,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          icon: isRecalculating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 16),
          label: Text(
            isRecalculating ? 'Recalculating...' : 'Recalculate',
          ),
        ),
        OutlinedButton.icon(
          onPressed: onManualMapping,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          icon: const Icon(Icons.link_rounded, size: 16),
          label: const Text('Seller Mapping'),
        ),
      ],
    );
  }

  Widget _buildRawModeSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Raw Mode',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: showAllRows,
              onChanged: onShowAllRowsChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
