class Rule194C {
  static const double singleThreshold = 30000.0;
  static const double rate = 0.02; // keep simple for now

  static Map<String, dynamic> calculate({
    required double currentAmount,
  }) {
    final applicable = currentAmount > singleThreshold ? currentAmount : 0.0;
    final tds = applicable * rate;

    return {
      'applicableAmount': applicable,
      'expectedTds': tds,
      'rate': applicable > 0 ? rate : 0.0,
      'remarks': applicable > 0
          ? 'TDS applicable under 194C'
          : 'Below 194C threshold',
    };
  }
}