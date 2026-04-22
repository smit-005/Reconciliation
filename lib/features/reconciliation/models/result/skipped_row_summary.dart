class SkippedRowSample {
  final String sourceType;
  final String reason;
  final String sellerName;
  final String month;

  const SkippedRowSample({
    required this.sourceType,
    required this.reason,
    required this.sellerName,
    required this.month,
  });
}

class SkippedRowSummary {
  final int total;
  final Map<String, int> reasonCounts;
  final List<SkippedRowSample> samples;

  const SkippedRowSummary({
    required this.total,
    required this.reasonCounts,
    this.samples = const <SkippedRowSample>[],
  });

  static const empty = SkippedRowSummary(
    total: 0,
    reasonCounts: <String, int>{},
    samples: <SkippedRowSample>[],
  );
}
