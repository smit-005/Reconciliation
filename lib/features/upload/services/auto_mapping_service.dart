import 'package:flutter/foundation.dart';

class AutoMappingResult {
  final String purchaseParty;
  final String? matchedTdsParty;
  final double score;
  final bool isMatched;
  final String normalizedPurchaseParty;
  final String normalizedMatchedTdsParty;

  AutoMappingResult({
    required this.purchaseParty,
    required this.matchedTdsParty,
    required this.score,
    required this.isMatched,
    required this.normalizedPurchaseParty,
    required this.normalizedMatchedTdsParty,
  });

  factory AutoMappingResult.fromIsolateMap(Map<Object?, Object?> map) {
    return AutoMappingResult(
      purchaseParty: map['purchaseParty']?.toString() ?? '',
      matchedTdsParty: map['matchedTdsParty']?.toString(),
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      isMatched: map['isMatched'] == true,
      normalizedPurchaseParty:
          map['normalizedPurchaseParty']?.toString() ?? '',
      normalizedMatchedTdsParty:
          map['normalizedMatchedTdsParty']?.toString() ?? '',
    );
  }

  Map<String, Object?> toIsolateMap() {
    return <String, Object?>{
      'purchaseParty': purchaseParty,
      'matchedTdsParty': matchedTdsParty,
      'score': score,
      'isMatched': isMatched,
      'normalizedPurchaseParty': normalizedPurchaseParty,
      'normalizedMatchedTdsParty': normalizedMatchedTdsParty,
    };
  }
}

class AutoMappingBatchResult {
  final List<AutoMappingResult> results;
  final int normalizationMs;
  final int matchingMs;

  const AutoMappingBatchResult({
    required this.results,
    required this.normalizationMs,
    required this.matchingMs,
  });
}

class _PartyProfile {
  final String raw;
  final String normalized;
  final List<String> orderedWords;
  final Set<String> words;
  final String tail;
  final String firstWord;
  final String compactPrefix;
  final String soundex;

  const _PartyProfile({
    required this.raw,
    required this.normalized,
    required this.orderedWords,
    required this.words,
    required this.tail,
    required this.firstWord,
    required this.compactPrefix,
    required this.soundex,
  });
}

class AutoMappingService {
  static Future<AutoMappingBatchResult> autoMapPartiesInBackground({
    required List<String> purchaseParties,
    required List<String> tdsParties,
    double threshold = 0.80,
  }) async {
    final payload = <String, Object>{
      'purchaseParties': List<String>.from(purchaseParties),
      'tdsParties': List<String>.from(tdsParties),
      'threshold': threshold,
    };

    final result = await compute(_autoMapPartiesIsolateEntry, payload);
    return AutoMappingBatchResult(
      results: (result['results'] as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .map(AutoMappingResult.fromIsolateMap)
          .toList(),
      normalizationMs: (result['normalizationMs'] as num?)?.toInt() ?? 0,
      matchingMs: (result['matchingMs'] as num?)?.toInt() ?? 0,
    );
  }

  static AutoMappingBatchResult autoMapParties({
    required List<String> purchaseParties,
    required List<String> tdsParties,
    double threshold = 0.80,
  }) {
    final normalizationWatch = Stopwatch()..start();
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

    final purchaseProfiles = uniquePurchase.map(_buildProfile).toList();
    final tdsProfiles = uniqueTds.map(_buildProfile).toList();
    final exactNormalizedIndex = <String, List<_PartyProfile>>{};
    final firstWordIndex = <String, List<_PartyProfile>>{};
    final compactPrefixIndex = <String, List<_PartyProfile>>{};
    final soundexIndex = <String, List<_PartyProfile>>{};
    final tokenIndex = <String, List<_PartyProfile>>{};

    for (final profile in tdsProfiles) {
      exactNormalizedIndex
          .putIfAbsent(profile.normalized, () => <_PartyProfile>[])
          .add(profile);
      if (profile.firstWord.isNotEmpty) {
        firstWordIndex.putIfAbsent(profile.firstWord, () => <_PartyProfile>[]).add(
          profile,
        );
      }
      if (profile.compactPrefix.isNotEmpty) {
        compactPrefixIndex
            .putIfAbsent(profile.compactPrefix, () => <_PartyProfile>[])
            .add(profile);
      }
      if (profile.soundex.isNotEmpty) {
        soundexIndex.putIfAbsent(profile.soundex, () => <_PartyProfile>[]).add(
          profile,
        );
      }
      for (final token in profile.words) {
        tokenIndex.putIfAbsent(token, () => <_PartyProfile>[]).add(profile);
      }
    }
    normalizationWatch.stop();

    final matchingWatch = Stopwatch()..start();
    final results = <AutoMappingResult>[];
    var candidateCountBefore = 0;
    var candidateCountAfter = 0;
    var levenshteinCalls = 0;

    for (final purchaseProfile in purchaseProfiles) {
      candidateCountBefore += tdsProfiles.length;
      _PartyProfile? bestMatch;
      double bestScore = 0.0;
      final exactMatches = exactNormalizedIndex[purchaseProfile.normalized];

      if (exactMatches != null && exactMatches.isNotEmpty) {
        final chosen = exactMatches.first;
        results.add(
          AutoMappingResult(
            purchaseParty: purchaseProfile.raw,
            matchedTdsParty: chosen.raw,
            score: 1.0,
            isMatched: true,
            normalizedPurchaseParty: purchaseProfile.normalized,
            normalizedMatchedTdsParty: chosen.normalized,
          ),
        );
        candidateCountAfter += exactMatches.length;
        continue;
      }

      final candidateProfiles = _buildCandidateProfiles(
        purchaseProfile: purchaseProfile,
        allProfiles: tdsProfiles,
        firstWordIndex: firstWordIndex,
        compactPrefixIndex: compactPrefixIndex,
        soundexIndex: soundexIndex,
        tokenIndex: tokenIndex,
      );
      candidateCountAfter += candidateProfiles.length;
      levenshteinCalls += candidateProfiles.length;

      for (final tdsProfile in candidateProfiles) {
        final score = _similarityScoreFromProfiles(purchaseProfile, tdsProfile);

        if (score > bestScore) {
          bestScore = score;
          bestMatch = tdsProfile;
        }
      }

      final isSafeMatch = bestMatch != null &&
          bestScore >= threshold &&
          _isSafeBusinessNameMatchProfiles(purchaseProfile, bestMatch);

      results.add(
        AutoMappingResult(
          purchaseParty: purchaseProfile.raw,
          matchedTdsParty: bestMatch?.raw,
          score: bestScore,
          isMatched: isSafeMatch,
          normalizedPurchaseParty: purchaseProfile.normalized,
          normalizedMatchedTdsParty: bestMatch?.normalized ?? '',
        ),
      );
    }

    matchingWatch.stop();
    debugPrint(
      'AUTO MAP CORE PERF => normalize ${normalizationWatch.elapsedMilliseconds} ms | '
      'match ${matchingWatch.elapsedMilliseconds} ms | '
      'purchaseNames=${purchaseProfiles.length} tdsNames=${tdsProfiles.length} | '
      'candidatesBefore=$candidateCountBefore candidatesAfter=$candidateCountAfter | '
      'levenshteinCalls=$levenshteinCalls',
    );

    return AutoMappingBatchResult(
      results: results,
      normalizationMs: normalizationWatch.elapsedMilliseconds,
      matchingMs: matchingWatch.elapsedMilliseconds,
    );
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
    text = text.replaceAll(RegExp(r'\bCO\b'), ' ');
    text = text.replaceAll(RegExp(r'\bCOMPANY\b'), ' ');
    text = text.replaceAll(RegExp(r'\bTHE\b'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  static _PartyProfile _buildProfile(String input) {
    final normalized = normalizePartyName(input);
    final orderedWords = normalized.split(' ').where((e) => e.isNotEmpty).toList();
    final words = orderedWords.toSet();
    final firstWord = orderedWords.isEmpty ? '' : orderedWords.first;
    final compact = normalized.replaceAll(' ', '');
    final compactPrefix = compact.length <= 4 ? compact : compact.substring(0, 4);
    final soundex = _soundex(firstWord);

    return _PartyProfile(
      raw: input,
      normalized: normalized,
      orderedWords: orderedWords,
      words: words,
      tail: orderedWords.skip(1).join(' '),
      firstWord: firstWord,
      compactPrefix: compactPrefix,
      soundex: soundex,
    );
  }

  static List<_PartyProfile> _buildCandidateProfiles({
    required _PartyProfile purchaseProfile,
    required List<_PartyProfile> allProfiles,
    required Map<String, List<_PartyProfile>> firstWordIndex,
    required Map<String, List<_PartyProfile>> compactPrefixIndex,
    required Map<String, List<_PartyProfile>> soundexIndex,
    required Map<String, List<_PartyProfile>> tokenIndex,
  }) {
    final candidatesByKey = <String, _PartyProfile>{};

    void addAll(Iterable<_PartyProfile> profiles) {
      for (final profile in profiles) {
        candidatesByKey[profile.raw] = profile;
      }
    }

    if (purchaseProfile.firstWord.isNotEmpty) {
      addAll(firstWordIndex[purchaseProfile.firstWord] ?? const <_PartyProfile>[]);
    }
    if (purchaseProfile.compactPrefix.isNotEmpty) {
      addAll(
        compactPrefixIndex[purchaseProfile.compactPrefix] ?? const <_PartyProfile>[],
      );
    }
    if (purchaseProfile.soundex.isNotEmpty) {
      addAll(soundexIndex[purchaseProfile.soundex] ?? const <_PartyProfile>[]);
    }

    final tokenOverlapCounts = <String, int>{};
    for (final token in purchaseProfile.words) {
      final tokenMatches = tokenIndex[token] ?? const <_PartyProfile>[];
      for (final profile in tokenMatches) {
        candidatesByKey[profile.raw] = profile;
        tokenOverlapCounts[profile.raw] = (tokenOverlapCounts[profile.raw] ?? 0) + 1;
      }
    }

    final filtered = candidatesByKey.values.where((profile) {
      final overlapCount = tokenOverlapCounts[profile.raw] ?? 0;
      if (overlapCount > 0) return true;
      if (purchaseProfile.firstWord.isNotEmpty &&
          profile.firstWord == purchaseProfile.firstWord) {
        return true;
      }
      if (purchaseProfile.compactPrefix.isNotEmpty &&
          profile.compactPrefix == purchaseProfile.compactPrefix) {
        return true;
      }
      return purchaseProfile.soundex.isNotEmpty &&
          profile.soundex == purchaseProfile.soundex;
    }).toList()
      ..sort((a, b) => a.raw.compareTo(b.raw));

    if (filtered.isNotEmpty) {
      return filtered;
    }

    return allProfiles;
  }

  static bool _isSafeBusinessNameMatch(String a, String b) {
    final na = _buildProfile(a);
    final nb = _buildProfile(b);
    return _isSafeBusinessNameMatchProfiles(na, nb);
  }

  static bool _isSafeBusinessNameMatchProfiles(
    _PartyProfile a,
    _PartyProfile b,
  ) {
    if (a.normalized.isEmpty || b.normalized.isEmpty) return false;
    if (a.normalized == b.normalized) return true;

    final aWords = a.words.toList();
    final bWords = b.words.toList();

    if (aWords.isEmpty || bWords.isEmpty) return false;

    final commonWords = a.words.intersection(b.words).length;
    if (commonWords == 0) return false;

    final tailA = a.tail;
    final tailB = b.tail;

    if (tailA.isEmpty && tailB.isEmpty) return true;
    if (tailA == tailB) return true;

    if (_levenshteinDistance(tailA, tailB) <= 1) return true;

    final minWords =
    aWords.length < bWords.length ? aWords.length : bWords.length;

    return minWords > 0 && commonWords >= (minWords - 1);
  }

  static double _similarityScore(String a, String b) {
    return _similarityScoreFromProfiles(_buildProfile(a), _buildProfile(b));
  }

  static double _similarityScoreFromProfiles(_PartyProfile a, _PartyProfile b) {
    if (a.normalized.isEmpty || b.normalized.isEmpty) return 0.0;
    if (a.normalized == b.normalized) return 1.0;

    final commonWords = a.words.intersection(b.words).length;
    final maxWords = a.words.length > b.words.length ? a.words.length : b.words.length;
    final wordScore = maxWords == 0 ? 0.0 : commonWords / maxWords;

    final editScore = _levenshteinSimilarity(a.normalized, b.normalized);

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

    var previous = List<int>.generate(n + 1, (index) => index);
    var current = List<int>.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      current[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        current[j] = [deletion, insertion, substitution].reduce(
          (a, b) => a < b ? a : b,
        );
      }
      final nextPrevious = current;
      current = previous;
      previous = nextPrevious;
    }

    return previous[n];
  }

  static String _soundex(String input) {
    if (input.isEmpty) return '';

    final upper = input.toUpperCase();
    final firstLetter = upper[0];
    final buffer = StringBuffer(firstLetter);
    var previousCode = _soundexCode(firstLetter);

    for (var i = 1; i < upper.length; i++) {
      final code = _soundexCode(upper[i]);
      if (code.isEmpty) {
        previousCode = '';
        continue;
      }
      if (code == previousCode) {
        continue;
      }
      buffer.write(code);
      previousCode = code;
      if (buffer.length == 4) {
        break;
      }
    }

    while (buffer.length < 4) {
      buffer.write('0');
    }

    return buffer.toString();
  }

  static String _soundexCode(String character) {
    switch (character) {
      case 'B':
      case 'F':
      case 'P':
      case 'V':
        return '1';
      case 'C':
      case 'G':
      case 'J':
      case 'K':
      case 'Q':
      case 'S':
      case 'X':
      case 'Z':
        return '2';
      case 'D':
      case 'T':
        return '3';
      case 'L':
        return '4';
      case 'M':
      case 'N':
        return '5';
      case 'R':
        return '6';
      default:
        return '';
    }
  }
}

Map<String, Object> _autoMapPartiesIsolateEntry(Map<String, Object> payload) {
  final purchaseParties = (payload['purchaseParties'] as List<Object?>)
      .whereType<String>()
      .toList();
  final tdsParties =
      (payload['tdsParties'] as List<Object?>).whereType<String>().toList();
  final threshold = (payload['threshold'] as num?)?.toDouble() ?? 0.80;

  final result = AutoMappingService.autoMapParties(
    purchaseParties: purchaseParties,
    tdsParties: tdsParties,
    threshold: threshold,
  );

  return <String, Object>{
    'results': result.results.map((entry) => entry.toIsolateMap()).toList(),
    'normalizationMs': result.normalizationMs,
    'matchingMs': result.matchingMs,
  };
}
