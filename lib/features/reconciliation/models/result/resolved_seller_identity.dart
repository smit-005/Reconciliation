class ResolvedSellerIdentity {
  final String resolvedSellerId;
  final String resolvedSellerName;
  final String resolvedPan;
  final String identitySource;
  final double identityConfidence;
  final String identityNotes;
  final bool mappingAttempted;
  final String mappingSectionUsed;
  final String mappingHit;
  final List<String> identityFlags;
  final String originalSellerName;
  final String normalizedSellerName;
  final String originalPan;

  const ResolvedSellerIdentity({
    required this.resolvedSellerId,
    required this.resolvedSellerName,
    required this.resolvedPan,
    required this.identitySource,
    required this.identityConfidence,
    required this.identityNotes,
    this.mappingAttempted = false,
    this.mappingSectionUsed = '',
    this.mappingHit = 'none',
    required this.identityFlags,
    required this.originalSellerName,
    required this.normalizedSellerName,
    required this.originalPan,
  });
}
