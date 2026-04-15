class Rule194Q {
  static const double threshold = 5000000.0; // 50 lakh
  static const double rate = 0.001; // 0.1%

  static Map<String, dynamic> calculate({
    required double cumulativePurchase,
    required double previousCumulative,
    required double currentAmount,
  }) {
    final prevExcess =
    previousCumulative > threshold ? previousCumulative - threshold : 0.0;

    final currExcess =
    cumulativePurchase > threshold ? cumulativePurchase - threshold : 0.0;

    final applicable = (currExcess - prevExcess).clamp(0.0, currentAmount);
    final tds = applicable * rate;

    return {
      'applicableAmount': applicable.toDouble(),
      'expectedTds': tds.toDouble(),
      'rate': rate,
      'remarks': applicable > 0
          ? 'TDS applicable under 194Q'
          : 'Below threshold',
    };
  }
}