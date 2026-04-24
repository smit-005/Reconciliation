import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/config/section_rule.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_remark_templates.dart';
import 'package:reconciliation_app/features/reconciliation/services/section_rule_registry.dart';

class SectionRuleResult {
  final double applicableAmount;
  final double expectedTds;
  final double rate;
  final bool manualReviewRequired;
  final String reviewReason;

  SectionRuleResult({
    required this.applicableAmount,
    required this.expectedTds,
    required this.rate,
    this.manualReviewRequired = false,
    this.reviewReason = '',
  });
}

class SectionRuleService {
  static const double _threshold194J = 30000.0;
  static const double _threshold194I = 240000.0;

  static SectionRuleResult applyRule({
    required String section,
    required double cumulativePurchase,
    required double previousCumulative,
    required double currentAmount,
    required double sectionCumulative,
    required double previousSectionCumulative,
    String sellerPan = '',
  }) {
    final sec = _clean(section);

    switch (sec) {
      case '194Q':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194Q')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
        );

      case '194C':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194C')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194C',
        );

      case '194H':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194H')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194H',
        );

      case '194J_A':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194J_A')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194J_A',
        );

      case '194J_B':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194J_B')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194J_B',
        );

      case '194J':
        return _apply194J(currentAmount, sectionCumulative);

      case '194I_A':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194I_A')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194I_A',
        );

      case '194I_B':
        return _applyConfiguredRule(
          config: SectionRuleRegistry.forSection('194I_B')!,
          currentAmount: currentAmount,
          sectionCumulative: sectionCumulative,
          cumulativePurchase: cumulativePurchase,
          previousCumulative: previousCumulative,
          sellerPan: sellerPan,
          manualReviewSectionCode: '194I_B',
        );

      case '194I':
        return _apply194I(currentAmount, sectionCumulative);

      default:
        return SectionRuleResult(
          applicableAmount: 0,
          expectedTds: 0,
          rate: 0,
        );
    }
  }

  static SectionRuleResult _applyConfiguredRule({
    required SectionRuleConfig config,
    required double currentAmount,
    required double sectionCumulative,
    required double cumulativePurchase,
    required double previousCumulative,
    required String sellerPan,
    String manualReviewSectionCode = '',
  }) {
    final isApplicable = _matchesThresholds(
      config: config,
      currentAmount: currentAmount,
      sectionCumulative: sectionCumulative,
      cumulativePurchase: cumulativePurchase,
    );
    final applicableAmount = isApplicable
        ? _resolveApplicableAmount(
            config: config,
            currentAmount: currentAmount,
            cumulativePurchase: cumulativePurchase,
            previousCumulative: previousCumulative,
          )
        : 0.0;

    if (!isApplicable) {
      return SectionRuleResult(
        applicableAmount: 0.0,
        expectedTds: 0.0,
        rate: 0.0,
      );
    }

    final resolvedRate = _resolveRate(
      config: config,
      sellerPan: sellerPan,
    );
    if (resolvedRate == null) {
      return SectionRuleResult(
        applicableAmount: applicableAmount,
        expectedTds: 0.0,
        rate: 0.0,
        manualReviewRequired: true,
        reviewReason:
            ReconciliationRemarkTemplates.manualReview(manualReviewSectionCode),
      );
    }

    return SectionRuleResult(
      applicableAmount: applicableAmount,
      expectedTds:
          double.parse((applicableAmount * resolvedRate).toStringAsFixed(2)),
      rate: resolvedRate,
    );
  }

  static bool _matchesThresholds({
    required SectionRuleConfig config,
    required double currentAmount,
    required double sectionCumulative,
    required double cumulativePurchase,
  }) {
    final matches = config.thresholds
        .map(
          (threshold) => _compareThreshold(
            actualValue: _resolveThresholdMetricValue(
              metric: threshold.metric,
              currentAmount: currentAmount,
              sectionCumulative: sectionCumulative,
              cumulativePurchase: cumulativePurchase,
            ),
            comparison: threshold.comparison,
            thresholdValue: threshold.value,
          ),
        )
        .toList();

    switch (config.thresholdMatchMode) {
      case SectionThresholdMatchMode.all:
        return matches.every((value) => value);
      case SectionThresholdMatchMode.any:
        return matches.any((value) => value);
    }
  }

  static double _resolveThresholdMetricValue({
    required SectionThresholdMetric metric,
    required double currentAmount,
    required double sectionCumulative,
    required double cumulativePurchase,
  }) {
    switch (metric) {
      case SectionThresholdMetric.currentAmount:
        return currentAmount;
      case SectionThresholdMetric.sectionCumulative:
        return sectionCumulative;
      case SectionThresholdMetric.cumulativePurchase:
        return cumulativePurchase;
    }
  }

  static bool _compareThreshold({
    required double actualValue,
    required SectionComparisonOperator comparison,
    required double thresholdValue,
  }) {
    switch (comparison) {
      case SectionComparisonOperator.greaterThan:
        return actualValue > thresholdValue;
    }
  }

  static double _resolveApplicableAmount({
    required SectionRuleConfig config,
    required double currentAmount,
    required double cumulativePurchase,
    required double previousCumulative,
  }) {
    switch (config.applicabilityMode) {
      case SectionApplicabilityMode.fullAmountWhenApplicable:
        return currentAmount;
      case SectionApplicabilityMode
            .excessOnlyOnCrossingThenFullAmountAfterThreshold:
        final thresholdValue = config.thresholds.first.value;
        if (previousCumulative >= thresholdValue) {
          return currentAmount;
        }
        final excessAmount = cumulativePurchase - thresholdValue;
        if (excessAmount <= 0) {
          return 0.0;
        }
        return excessAmount > currentAmount ? currentAmount : excessAmount;
    }
  }

  static double? _resolveRate({
    required SectionRuleConfig config,
    required String sellerPan,
  }) {
    switch (config.rateConfig.resolverType) {
      case SectionRateResolverType.fixed:
        return config.rateConfig.fixedRate;
      case SectionRateResolverType.sellerPanEntityType:
        return _resolveRateFromPanEntityType(
          sellerPan: sellerPan,
          individualOrHufRate: config.rateConfig.individualOrHufRate!,
          otherEntityRate: config.rateConfig.otherEntityRate!,
        );
    }
  }

  // -------------------- 194J --------------------
  static SectionRuleResult _apply194J(
      double amount,
      double sectionTotal,
      ) {
    final isApplicable =
        amount > _threshold194J || sectionTotal > _threshold194J;
    final applicable = isApplicable ? amount : 0.0;
    if (!isApplicable) {
      return SectionRuleResult(
        applicableAmount: 0.0,
        expectedTds: 0.0,
        rate: 0.0,
      );
    }

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: 0.0,
      rate: 0.0,
      manualReviewRequired: true,
      reviewReason: ReconciliationRemarkTemplates.manualReview('194J'),
    );
  }

  // -------------------- 194I --------------------
  static SectionRuleResult _apply194I(
      double amount,
      double sectionTotal,
      ) {
    final isApplicable = sectionTotal > _threshold194I;
    final applicable = isApplicable ? amount : 0.0;
    if (!isApplicable) {
      return SectionRuleResult(
        applicableAmount: 0.0,
        expectedTds: 0.0,
        rate: 0.0,
      );
    }

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: 0.0,
      rate: 0.0,
      manualReviewRequired: true,
      reviewReason: ReconciliationRemarkTemplates.manualReview('194I'),
    );
  }

  // -------------------- CLEANER --------------------
  static String _clean(String value) {
    final normalized = normalizeSection(value);
    if (normalized.isNotEmpty) {
      return normalized;
    }

    final v = value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

    if (v.contains('194I_A')) return '194I_A';
    if (v.contains('194I_B')) return '194I_B';
    if (v.contains('194J_A')) return '194J_A';
    if (v.contains('194J_B')) return '194J_B';
    if (v.contains('194Q')) return '194Q';
    if (v.contains('194C')) return '194C';
    if (v.contains('194J')) return '194J';
    if (v.contains('194I')) return '194I';
    if (v.contains('194H')) return '194H';

    return '';
  }

  static double? _resolveRateFromPanEntityType({
    required String sellerPan,
    required double individualOrHufRate,
    required double otherEntityRate,
  }) {
    final normalizedPan = normalizePan(sellerPan);
    if (!looksLikePan(normalizedPan)) {
      return null;
    }

    final entityCode = normalizedPan[3];
    if (entityCode == 'P' || entityCode == 'H') {
      return individualOrHufRate;
    }

    const businessEntityCodes = {
      'A',
      'B',
      'C',
      'F',
      'G',
      'J',
      'L',
      'T',
    };

    if (businessEntityCodes.contains(entityCode)) {
      return otherEntityRate;
    }

    return null;
  }
}
