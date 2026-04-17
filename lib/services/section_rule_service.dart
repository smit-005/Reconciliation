class SectionRuleResult {
  final double applicableAmount;
  final double expectedTds;
  final double rate;

  SectionRuleResult({
    required this.applicableAmount,
    required this.expectedTds,
    required this.rate,
  });
}

class SectionRuleService {
  static SectionRuleResult applyRule({
    required String section,
    required double cumulativePurchase,
    required double previousCumulative,
    required double currentAmount,
    required double sectionCumulative,
    required double previousSectionCumulative,
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
        return _apply194C(currentAmount, sectionCumulative);

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
    const threshold = 5000000.0;
    const rate = 0.001;

    double applicable = 0;

    if (previous >= threshold) {
      applicable = current;
    } else if (cumulative > threshold) {
      final remaining = threshold - previous;
      applicable = current - remaining;
      if (applicable < 0) applicable = 0;
    }

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: double.parse((applicable * rate).toStringAsFixed(2)),
      rate: rate,
    );
  }

  // -------------------- 194C --------------------
  static SectionRuleResult _apply194C(
      double amount,
      double sectionTotal,
      ) {
    const singleLimit = 30000.0;
    const yearlyLimit = 100000.0;
    const rate = 0.02;

    final isApplicable =
        amount > singleLimit || sectionTotal > yearlyLimit;

    final applicable = isApplicable ? amount : 0.0;

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: double.parse((applicable * rate).toStringAsFixed(2)),
      rate: rate,
    );
  }

  // -------------------- 194J --------------------
  static SectionRuleResult _apply194J(
      double amount,
      double sectionTotal,
      ) {
    const threshold = 30000.0;
    const rate = 0.02;

    final isApplicable = amount > threshold || sectionTotal > threshold;
    final applicable = isApplicable ? amount : 0.0;

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: applicable * rate,
      rate: rate,
    );
  }

  // -------------------- 194I --------------------
  static SectionRuleResult _apply194I(
      double amount,
      double sectionTotal,
      ) {
    const threshold = 240000.0;
    const rate = 0.10;

    final isApplicable = sectionTotal > threshold;
    final applicable = isApplicable ? amount : 0.0;

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: applicable * rate,
      rate: rate,
    );
  }

  // -------------------- 194H --------------------
  static SectionRuleResult _apply194H(
      double amount,
      double sectionTotal,
      ) {
    const threshold = 15000.0;
    const rate = 0.05;

    final isApplicable = sectionTotal > threshold;
    final applicable = isApplicable ? amount : 0.0;

    return SectionRuleResult(
      applicableAmount: applicable,
      expectedTds: applicable * rate,
      rate: rate,
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
}