import 'package:flutter/material.dart';
import 'seller_mapping_theme.dart';

class SellerMappingSummaryMetric {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const SellerMappingSummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class SellerMappingMetricCard extends StatelessWidget {
  final SellerMappingSummaryMetric metric;

  const SellerMappingMetricCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: metric.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 18, color: metric.color),
          const SizedBox(height: 14),
          Text(
            '${metric.value}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: SellerMappingTheme.titleTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: SellerMappingTheme.mutedTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class SellerMappingPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const SellerMappingPill({
    super.key,
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: compact
            ? const Color(0xFFF8FAFC)
            : SellerMappingTheme.primarySoft,
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
        border: Border.all(
          color: compact ? const Color(0xFFDCE4F2) : const Color(0xFFD4DFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 14 : 15,
            color: compact
                ? SellerMappingTheme.mutedTextColor
                : SellerMappingTheme.primaryColor,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12,
              fontWeight: FontWeight.w700,
              color: compact
                  ? SellerMappingTheme.titleTextColor
                  : SellerMappingTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class SellerMappingStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const SellerMappingStatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
