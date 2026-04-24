import 'package:reconciliation_app/features/reconciliation/models/config/section_rule.dart';

class SectionRuleRegistry {
  static const Map<String, SectionRuleConfig> rules = {
    '194Q': SectionRuleConfig(
      section: '194Q',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.cumulativePurchase,
          comparison: SectionComparisonOperator.greaterThan,
          value: 5000000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode:
          SectionApplicabilityMode.excessOnlyOnCrossingThenFullAmountAfterThreshold,
      rateConfig: SectionRateConfig.fixed(0.001),
    ),
    '194C': SectionRuleConfig(
      section: '194C',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.currentAmount,
          comparison: SectionComparisonOperator.greaterThan,
          value: 30000.0,
        ),
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 100000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.bySellerPanEntityType(
        individualOrHufRate: 0.01,
        otherEntityRate: 0.02,
      ),
    ),
    '194H': SectionRuleConfig(
      section: '194H',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 20000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.fixed(0.02),
    ),
    '194J_A': SectionRuleConfig(
      section: '194J_A',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 50000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.fixed(0.02),
    ),
    '194J_B': SectionRuleConfig(
      section: '194J_B',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 50000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.fixed(0.10),
    ),
    '194I_A': SectionRuleConfig(
      section: '194I_A',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 50000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.fixed(0.02),
    ),
    '194I_B': SectionRuleConfig(
      section: '194I_B',
      thresholds: [
        SectionThresholdRule(
          metric: SectionThresholdMetric.sectionCumulative,
          comparison: SectionComparisonOperator.greaterThan,
          value: 50000.0,
        ),
      ],
      thresholdMatchMode: SectionThresholdMatchMode.any,
      applicabilityMode: SectionApplicabilityMode.fullAmountWhenApplicable,
      rateConfig: SectionRateConfig.fixed(0.10),
    ),
  };

  static SectionRuleConfig? forSection(String section) => rules[section];
}
