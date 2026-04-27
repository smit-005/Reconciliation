import 'package:flutter/material.dart';
import 'package:reconciliation_app/core/widgets/app_metric_card.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';

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
    return AppMetricCard(
      label: metric.label,
      value: '',
      icon: metric.icon,
      accentColor: metric.color,
      width: 130,
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
    return AppStatusBadge(
      icon: icon,
      label: label,
      tone: compact ? AppStatusBadgeTone.neutral : AppStatusBadgeTone.info,
    );
  }
}

class SellerMappingStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final AppStatusBadgeTone tone;

  const SellerMappingStatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(icon: icon, label: label, tone: tone);
  }
}
