import 'package:reconciliation_app/core/config/tds_section_catalog.dart';
import 'package:reconciliation_app/features/reconciliation/models/config/section_rule.dart';
import 'package:reconciliation_app/features/reconciliation/services/section_rule_registry.dart';

class SectionRuleExportText {
  const SectionRuleExportText._();

  static List<SectionRuleExportInfo> allRules() {
    final sections = SectionRuleRegistry.rules.keys.toList()
      ..sort(TdsSectionCatalog.compare);
    return sections.map(ruleInfoForSection).nonNulls.toList();
  }

  static SectionRuleExportInfo? ruleInfoForSection(String section) {
    final normalized = TdsSectionCatalog.normalizeCode(section);
    final config = SectionRuleRegistry.forSection(
      normalized.isEmpty ? section.trim() : normalized,
    );
    if (config == null) return null;

    return SectionRuleExportInfo(
      section: config.section,
      natureOfPayment: _natureOfPayment(config.section),
      thresholdText: thresholdText(config),
      rateText: rateText(config.rateConfig),
      applicabilityText: applicabilityText(config.applicabilityMode),
      deductorText: config.section == '194Q' ? 'Buyer' : 'Any payer',
    );
  }

  static String summaryTextForSections(Iterable<String> sections) {
    final normalizedSections =
        sections
            .map(TdsSectionCatalog.normalizeCode)
            .where((section) => section.isNotEmpty)
            .toSet()
            .toList()
          ..sort(TdsSectionCatalog.compare);

    if (normalizedSections.isEmpty) {
      return 'No supported section rule applies; see row remarks.';
    }

    if (normalizedSections.length > 1) {
      return 'Multiple section-specific rules apply; see TDS Section Info.';
    }

    final info = ruleInfoForSection(normalizedSections.single);
    if (info == null) {
      return 'No supported section rule applies; see row remarks.';
    }

    return '${info.section}: ${info.thresholdText}; ${info.rateText}; ${info.applicabilityText}.';
  }

  static String thresholdText(SectionRuleConfig config) {
    if (config.thresholds.isEmpty) return 'No threshold';

    final separator = config.thresholdMatchMode == SectionThresholdMatchMode.all
        ? ' and '
        : ' or ';
    return config.thresholds.map(_thresholdRuleText).join(separator);
  }

  static String rateText(SectionRateConfig config) {
    switch (config.resolverType) {
      case SectionRateResolverType.fixed:
        return 'TDS rate ${_formatRate(config.fixedRate ?? 0)}';
      case SectionRateResolverType.sellerPanEntityType:
        return 'TDS rate ${_formatRate(config.individualOrHufRate ?? 0)} for Individual/HUF PAN, ${_formatRate(config.otherEntityRate ?? 0)} for others';
    }
  }

  static String applicabilityText(SectionApplicabilityMode mode) {
    switch (mode) {
      case SectionApplicabilityMode.fullAmountWhenApplicable:
        return 'full amount is applicable when threshold is crossed';
      case SectionApplicabilityMode
          .excessOnlyOnCrossingThenFullAmountAfterThreshold:
        return 'only excess is applicable in crossing period, then full amount after threshold';
    }
  }

  static String _thresholdRuleText(SectionThresholdRule rule) {
    final metric = switch (rule.metric) {
      SectionThresholdMetric.currentAmount => 'current amount',
      SectionThresholdMetric.sectionCumulative => 'section cumulative amount',
      SectionThresholdMetric.cumulativePurchase => 'FY cumulative purchase',
    };

    final comparison = switch (rule.comparison) {
      SectionComparisonOperator.greaterThan => 'exceeds',
    };

    return '$metric $comparison ${_formatAmount(rule.value)}';
  }

  static String _natureOfPayment(String section) {
    switch (section) {
      case '194Q':
        return 'Purchase of Goods';
      case '194A':
        return 'Interest other than Securities';
      case '194C':
        return 'Payment to Contractors';
      case '194H':
        return 'Commission/Brokerage';
      default:
        return TdsSectionCatalog.displayLabel(section);
    }
  }

  static String _formatRate(double rate) {
    final percent = rate * 100;
    if (percent == percent.roundToDouble()) {
      return '${percent.toStringAsFixed(0)}%';
    }
    return '${percent.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}%';
  }

  static String _formatAmount(double value) {
    final rounded = value.round();
    final digits = rounded.toString();
    if (digits.length <= 3) return 'Rs. $digits';

    final lastThree = digits.substring(digits.length - 3);
    var leading = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (leading.length > 2) {
      groups.insert(0, leading.substring(leading.length - 2));
      leading = leading.substring(0, leading.length - 2);
    }
    if (leading.isNotEmpty) groups.insert(0, leading);
    return 'Rs. ${groups.join(',')},$lastThree';
  }
}

class SectionRuleExportInfo {
  final String section;
  final String natureOfPayment;
  final String thresholdText;
  final String rateText;
  final String applicabilityText;
  final String deductorText;

  const SectionRuleExportInfo({
    required this.section,
    required this.natureOfPayment,
    required this.thresholdText,
    required this.rateText,
    required this.applicabilityText,
    required this.deductorText,
  });
}
