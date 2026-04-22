import 'package:reconciliation_app/core/utils/normalize_utils.dart';

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
  static const double _threshold194Q = 5000000.0;
  static const double _rate194Q = 0.001;
  static const double _singleLimit194C = 30000.0;
  static const double _yearlyLimit194C = 100000.0;
  static const double _threshold194J = 30000.0;
  static const double _threshold194I = 240000.0;
  static const double _threshold194H = 15000.0;
  static const double _rate194H = 0.05;

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
        return _apply194Q(
          cumulativePurchase,
          previousCumulative,
          currentAmount,
        );

      case '194C':
        return _apply194C(
          currentAmount,
          sectionCumulative,
          sellerPan: sellerPan,
        );

      case '194J':
        return _apply194J(currentAmount, sectionCumulative);

      case '194I':
        return _apply194I(currentAmount, sectionCumulative);

      case '194H':
        return _apply194H(currentAmount, sectionCumulative);

      default:
        return SectionRuleResult(
          applicableAmount: 0,
          expectedTds: 0,
          rate: 0,
        );
    }
  }

  // -------------------- 194Q --------------------
  static SectionRuleResult _apply194Q(
      double cumulative,
      double previous,
      double current,
      ) {
    double applicable = 0;

    if (previous >= _threshold194Q) {
      applicable = current;
    } else if (cumulative > _threshold194Q) {
      final remaining = _threshold194Q - previous;
      applicable = current - remaining;
      if (applicable < 0) applicable = 0;
    }

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: double.parse((applicable * _rate194Q).toStringAsFixed(2)),
      rate: _rate194Q,
    );
  }

  // -------------------- 194C --------------------
  static SectionRuleResult _apply194C(
      double amount,
      double sectionTotal,
      {
        String sellerPan = '',
      }) {
    final isApplicable =
        amount > _singleLimit194C || sectionTotal > _yearlyLimit194C;

    final applicable = isApplicable ? amount : 0.0;

    if (!isApplicable) {
      return SectionRuleResult(
        applicableAmount: 0.0,
        expectedTds: 0.0,
        rate: 0.0,
      );
    }

    final resolvedRate = _resolve194CRateFromPan(sellerPan);
    if (resolvedRate == null) {
      return SectionRuleResult(
        applicableAmount: applicable,
        expectedTds: 0.0,
        rate: 0.0,
        manualReviewRequired: true,
        reviewReason:
            'PAN/entity type unavailable, so expected TDS could not be confirmed.',
      );
    }

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: double.parse((applicable * resolvedRate).toStringAsFixed(2)),
      rate: resolvedRate,
    );
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
      reviewReason:
          'Service subtype is unavailable, so the correct 194J rate could not be confirmed from available section context.',
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
      reviewReason:
          'Rent subtype is unavailable, so the correct 194I rate could not be confirmed from available section context.',
    );
  }

  // -------------------- 194H --------------------
  static SectionRuleResult _apply194H(
      double amount,
      double sectionTotal,
      ) {
    final isApplicable = sectionTotal > _threshold194H;
    final applicable = isApplicable ? amount : 0.0;

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: double.parse((applicable * _rate194H).toStringAsFixed(2)),
      rate: _rate194H,
    );
  }

  // -------------------- CLEANER --------------------
  static String _clean(String value) {
    final v = value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

    if (v.contains('194Q')) return '194Q';
    if (v.contains('194C')) return '194C';
    if (v.contains('194J')) return '194J';
    if (v.contains('194I')) return '194I';
    if (v.contains('194H')) return '194H';

    return '';
  }

  static double? _resolve194CRateFromPan(String sellerPan) {
    final normalizedPan = normalizePan(sellerPan);
    if (!looksLikePan(normalizedPan)) {
      return null;
    }

    final entityCode = normalizedPan[3];
    if (entityCode == 'P' || entityCode == 'H') {
      return 0.01;
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
      return 0.02;
    }

    return null;
  }
}
