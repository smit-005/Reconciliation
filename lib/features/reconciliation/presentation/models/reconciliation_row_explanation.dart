class ReconciliationRowExplanationValue {
  final String label;
  final String value;

  const ReconciliationRowExplanationValue({
    required this.label,
    required this.value,
  });
}

class ReconciliationRowExplanation {
  final String reasonCategory;
  final List<ReconciliationRowExplanationValue> comparedValues;
  final String computedDifferenceLabel;
  final String computedDifferenceValue;
  final String explanation;
  final String identityImpact;
  final List<String> supportingNotes;

  const ReconciliationRowExplanation({
    required this.reasonCategory,
    required this.comparedValues,
    required this.computedDifferenceLabel,
    required this.computedDifferenceValue,
    required this.explanation,
    this.identityImpact = '',
    this.supportingNotes = const <String>[],
  });
}
