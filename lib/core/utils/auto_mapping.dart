class AutoMappingResult {
  final String purchaseParty;
  final String? matchedTdsParty;
  final double score;
  final bool isMatched;

  AutoMappingResult({
    required this.purchaseParty,
    required this.matchedTdsParty,
    required this.score,
    required this.isMatched,
  });
}

class AutoMappingService {
  static List<AutoMappingResult> autoMapParties({
    required List<String> purchaseParties,
    required List<String> tdsParties,
    double threshold = 0.80,
  }) {
    final uniquePurchase = purchaseParties
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final uniqueTds = tdsParties
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final results = <AutoMappingResult>[];

    for (final purchaseParty in uniquePurchase) {
      String? bestMatch;
      double bestScore = 0.0;

      for (final tdsParty in uniqueTds) {
        final score = _similarityScore(purchaseParty, tdsParty);

        if (score > bestScore) {
          bestScore = score;
          bestMatch = tdsParty;
        }
      }

      final isSafeMatch = bestMatch != null &&
          bestScore >= threshold &&
          _isSafeBusinessNameMatch(purchaseParty, bestMatch);

      results.add(
        AutoMappingResult(
          purchaseParty: purchaseParty,
          matchedTdsParty: bestMatch, // IMPORTANT: always keep best match
          score: bestScore,
          isMatched: isSafeMatch,
        ),
      );
    }

    return results;
  }

  static String normalizePartyName(String input) {
    var text = input.toUpperCase().trim();

    text = text.replaceAll('&', ' AND ');
    text = text.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    text = text.replaceAll(RegExp(r'\bM/S\b'), ' ');
    text = text.replaceAll(RegExp(r'\bMS\b'), ' ');
    text = text.replaceAll(RegExp(r'\bPVT\b'), ' ');
    text = text.replaceAll(RegExp(r'\bPRIVATE\b'), ' ');
    text = text.replaceAll(RegExp(r'\bLTD\b'), ' ');
    text = text.replaceAll(RegExp(r'\bLIMITED\b'), ' ');
    text = text.replaceAll(RegExp(r'\bINDUSTRY\b'), ' ');
    text = text.replaceAll(RegExp(r'\bINDUSTRIES\b'), ' ');
    text = text.replaceAll(RegExp(r'\bTRADER\b'), ' ');
    text = text.replaceAll(RegExp(r'\bTRADERS\b'), ' ');
    text = text.replaceAll(RegExp(r'\bENTERPRISE\b'), ' ');
    text = text.replaceAll(RegExp(r'\bENTERPRISES\b'), ' ');
    text = text.replaceAll(RegExp(r'\bCO\b'), ' ');
    text = text.replaceAll(RegExp(r'\bCOMPANY\b'), ' ');
    text = text.replaceAll(RegExp(r'\bTHE\b'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  static bool _isSafeBusinessNameMatch(String a, String b) {
    final na = normalizePartyName(a);
    final nb = normalizePartyName(b);

    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;

    final aWords = na.split(' ').where((e) => e.isNotEmpty).toList();
    final bWords = nb.split(' ').where((e) => e.isNotEmpty).toList();

    if (aWords.isEmpty || bWords.isEmpty) return false;

    if (aWords.first != bWords.first) return false;

    final tailA = aWords.skip(1).join(' ');
    final tailB = bWords.skip(1).join(' ');

    if (tailA.isEmpty && tailB.isEmpty) return true;
    if (tailA == tailB) return true;

    if (_levenshteinDistance(tailA, tailB) <= 1) return true;

    final commonWords = aWords.toSet().intersection(bWords.toSet()).length;
    final minWords =
    aWords.length < bWords.length ? aWords.length : bWords.length;

    return minWords > 0 && commonWords >= (minWords - 1);
  }

  static double _similarityScore(String a, String b) {
    final na = normalizePartyName(a);
    final nb = normalizePartyName(b);

    if (na.isEmpty || nb.isEmpty) return 0.0;
    if (na == nb) return 1.0;

    final aWords = na.split(' ').where((e) => e.isNotEmpty).toSet();
    final bWords = nb.split(' ').where((e) => e.isNotEmpty).toSet();

    final commonWords = aWords.intersection(bWords).length;
    final maxWords =
    aWords.length > bWords.length ? aWords.length : bWords.length;
    final wordScore = maxWords == 0 ? 0.0 : commonWords / maxWords;

    final editScore = _levenshteinSimilarity(na, nb);

    return (wordScore * 0.6) + (editScore * 0.4);
  }

  static double _levenshteinSimilarity(String s1, String s2) {
    final distance = _levenshteinDistance(s1, s2);
    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (distance / maxLen);
  }

  static int _levenshteinDistance(String s, String t) {
    final m = s.length;
    final n = t.length;

    if (m == 0) return n;
    if (n == 0) return m;

    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (int i = 0; i <= m; i++) {
      dp[i][0] = i;
    }

    for (int j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;

        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return dp[m][n];
  }
}