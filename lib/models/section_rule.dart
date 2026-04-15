class SectionRule {
  final String section;
  final double? threshold;
  final double rate;
  final bool isCumulative;

  const SectionRule({
    required this.section,
    this.threshold,
    required this.rate,
    this.isCumulative = false,
  });
}