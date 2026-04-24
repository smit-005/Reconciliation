enum SectionThresholdMetric {
  currentAmount,
  sectionCumulative,
  cumulativePurchase,
}

enum SectionComparisonOperator {
  greaterThan,
}

enum SectionThresholdMatchMode {
  any,
  all,
}

enum SectionApplicabilityMode {
  fullAmountWhenApplicable,
  excessOnlyOnCrossingThenFullAmountAfterThreshold,
}

enum SectionRateResolverType {
  fixed,
  sellerPanEntityType,
}

class SectionThresholdRule {
  final SectionThresholdMetric metric;
  final SectionComparisonOperator comparison;
  final double value;

  const SectionThresholdRule({
    required this.metric,
    required this.comparison,
    required this.value,
  });
}

class SectionRateConfig {
  final SectionRateResolverType resolverType;
  final double? fixedRate;
  final double? individualOrHufRate;
  final double? otherEntityRate;

  const SectionRateConfig.fixed(double rate)
      : resolverType = SectionRateResolverType.fixed,
        fixedRate = rate,
        individualOrHufRate = null,
        otherEntityRate = null;

  const SectionRateConfig.bySellerPanEntityType({
    required double individualOrHufRate,
    required double otherEntityRate,
  }) : resolverType = SectionRateResolverType.sellerPanEntityType,
       fixedRate = null,
       individualOrHufRate = individualOrHufRate,
       otherEntityRate = otherEntityRate;
}

class SectionRuleConfig {
  final String section;
  final List<SectionThresholdRule> thresholds;
  final SectionThresholdMatchMode thresholdMatchMode;
  final SectionApplicabilityMode applicabilityMode;
  final SectionRateConfig rateConfig;

  const SectionRuleConfig({
    required this.section,
    required this.thresholds,
    required this.thresholdMatchMode,
    required this.applicabilityMode,
    required this.rateConfig,
  });
}
