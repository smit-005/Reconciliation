class Rule194H {
  static const double threshold = 15000.0;
  static const double rate = 0.05;

  static Map<String, dynamic> calculate({
    required double currentAmount,
  }) {
    final applicable = currentAmount > threshold ? currentAmount : 0.0;
    final tds = applicable * rate;

    return {
      'applicableAmount': applicable,
      'expectedTds': tds,
      'rate': applicable > 0 ? rate : 0.0,
      'remarks': applicable > 0
          ? 'TDS applicable under 194H'
          : 'Below 194H threshold',
    };
  }
}