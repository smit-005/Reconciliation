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

class SkippedSellerImpact {
  final String sellerName;
  final int total;
  final Map<String, int> reasonCounts;

  const SkippedSellerImpact({
    required this.sellerName,
    required this.total,
    required this.reasonCounts,
  });
}

class SkippedRowSummary {
  final int total;
  final Map<String, int> reasonCounts;
  final List<SkippedRowSample> samples;
  final List<SkippedSellerImpact> sellerImpacts;

  const SkippedRowSummary({
    required this.total,
    required this.reasonCounts,
    this.samples = const <SkippedRowSample>[],
    this.sellerImpacts = const <SkippedSellerImpact>[],
  });

  static const empty = SkippedRowSummary(
    total: 0,
    reasonCounts: <String, int>{},
    samples: <SkippedRowSample>[],
    sellerImpacts: <SkippedSellerImpact>[],
  );
}
