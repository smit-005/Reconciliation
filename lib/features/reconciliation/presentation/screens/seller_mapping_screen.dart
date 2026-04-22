import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';

class SellerMappingScreenRowData {
  final String purchasePartyDisplayName;
  final String normalizedAlias;
  final String sectionCode;
  final String purchasePan;
  final SellerMappingResolvedSuggestion? resolvedSuggestion;

  const SellerMappingScreenRowData({
    required this.purchasePartyDisplayName,
    required this.normalizedAlias,
    required this.sectionCode,
    required this.purchasePan,
    this.resolvedSuggestion,
  });
}

class SellerMappingResolvedSuggestion {
  final String mappedName;
  final String mappedPan;
  final String source;
  final String helperText;

  const SellerMappingResolvedSuggestion({
    required this.mappedName,
    required this.mappedPan,
    required this.source,
    this.helperText = '',
  });
}

class SellerMappingScreen extends StatefulWidget {
  final String buyerName;
  final String buyerPan;
  final String financialYearLabel;
  final String selectedSectionLabel;
  final List<SellerMappingScreenRowData> purchaseRows;
  final List<String> tdsParties;
  final List<SellerMapping> existingMappings;
  final Set<String> blockedAliases;
  final Map<String, List<String>> tdsPartyPans;

  const SellerMappingScreen({
    super.key,
    required this.buyerName,
    required this.buyerPan,
    required this.financialYearLabel,
    required this.selectedSectionLabel,
    required this.purchaseRows,
    required this.tdsParties,
    this.existingMappings = const [],
    required this.blockedAliases,
    this.tdsPartyPans = const {},
  });

  @override
  State<SellerMappingScreen> createState() => _SellerMappingScreenState();
}

class _SellerMappingRowVm {
  final String purchasePartyDisplayName;
  final String normalizedAlias;
  final String sectionCode;
  final String purchasePan;
  final SellerMapping? exactMapping;
  final SellerMapping? fallbackMapping;
  final SellerMappingResolvedSuggestion? resolvedSuggestion;

  const _SellerMappingRowVm({
    required this.purchasePartyDisplayName,
    required this.normalizedAlias,
    required this.sectionCode,
    required this.purchasePan,
    this.exactMapping,
    this.fallbackMapping,
    this.resolvedSuggestion,
  });

  String get rowKey => '${normalizedAlias}|${sectionCode}';
}

class _AutoMapDecision {
  final String autoMapReason;
  final double autoMapConfidence;
  final String? selectedCandidate;
  final bool blockedByPanConflict;
  final bool ambiguous;

  const _AutoMapDecision({
    required this.autoMapReason,
    required this.autoMapConfidence,
    this.selectedCandidate,
    this.blockedByPanConflict = false,
    this.ambiguous = false,
  });
}

class _TdsPartyCandidate {
  final String partyName;
  final String normalizedName;
  final List<String> tokens;
  final Set<String> pans;

  const _TdsPartyCandidate({
    required this.partyName,
    required this.normalizedName,
    required this.tokens,
    required this.pans,
  });
}

class _CandidateScore {
  final _TdsPartyCandidate candidate;
  final double score;

  const _CandidateScore({
    required this.candidate,
    required this.score,
  });
}

class _SellerMappingScreenState extends State<SellerMappingScreen> {
  static const Color _pageBackground = Color(0xFFF4F7FB);
  static const Color _surfaceColor = Colors.white;
  static const Color _primaryColor = Color(0xFF3559E0);
  static const Color _primarySoft = Color(0xFFEAF0FF);
  static const Color _successColor = Color(0xFF1F8F5F);
  static const Color _warningColor = Color(0xFFB7791F);
  static const Color _dangerColor = Color(0xFFC15353);
  static const Color _mutedTextColor = Color(0xFF667085);
  static const Color _titleTextColor = Color(0xFF101828);
  static const Color _borderColor = Color(0xFFD9E2F2);

  static const Set<String> _legalSuffixTokens = {
    'M',
    'S',
    'M/S',
    'MS',
    'PVT',
    'PRIVATE',
    'LTD',
    'LIMITED',
    'LLP',
    'CO',
    'COMPANY',
  };

  static const Set<String> _ignoredNameTokens = {
    'AND',
    'THE',
  };

  late Map<String, String> selectedMappings;
  late Map<String, _AutoMapDecision> autoMapDetails;
  late List<_SellerMappingRowVm> mappingRows;
  late List<String> uniqueTdsParties;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All';

  String _rowKey(String alias, String sectionCode) {
    return '${normalizeName(alias.trim())}|'
        '${normalizeSellerMappingSectionCode(sectionCode)}';
  }

  String _normalizeBusinessName(String value) {
    var text = value.toUpperCase().trim();
    text = text.replaceAll('&', ' AND ');
    text = text.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.isEmpty) return '';

    final tokens = text
        .split(' ')
        .where((token) => token.isNotEmpty)
        .where((token) => !_legalSuffixTokens.contains(token))
        .toList();

    return tokens.join(' ');
  }

  List<String> _tokenizeBusinessName(String value) {
    final normalized = _normalizeBusinessName(value);
    if (normalized.isEmpty) return const <String>[];

    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .where((token) => !_ignoredNameTokens.contains(token))
        .toList();
  }

  Set<String> _resolveTargetPans(String mappedName) {
    final exactPans = widget.tdsPartyPans[mappedName];
    if (exactPans != null) {
      return exactPans
          .map((pan) => normalizePan(pan))
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    final normalizedMappedName = normalizeName(mappedName.trim());
    for (final entry in widget.tdsPartyPans.entries) {
      if (normalizeName(entry.key) != normalizedMappedName) continue;
      return entry.value
          .map((pan) => normalizePan(pan))
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    return const <String>{};
  }

  List<_TdsPartyCandidate> _buildTdsCandidates() {
    return uniqueTdsParties
        .map(
          (partyName) => _TdsPartyCandidate(
            partyName: partyName,
            normalizedName: _normalizeBusinessName(partyName),
            tokens: _tokenizeBusinessName(partyName),
            pans: _resolveTargetPans(partyName),
          ),
        )
        .toList()
      ..sort((a, b) => a.partyName.compareTo(b.partyName));
  }

  String _getPanForTdsParty(String? mappedName) {
    if (mappedName == null || mappedName.trim().isEmpty) return '';

    final pans = _resolveTargetPans(mappedName);
    if (pans.isEmpty) return '';
    if (pans.length == 1) return pans.first;

    return 'Multiple PANs';
  }

  String? _normalizeToKnownTdsParty(String? mappedName) {
    if (mappedName == null || mappedName.trim().isEmpty) return null;

    final trimmed = mappedName.trim();
    if (uniqueTdsParties.contains(trimmed)) {
      return trimmed;
    }

    final normalized = normalizeName(trimmed);
    for (final party in uniqueTdsParties) {
      if (normalizeName(party) == normalized) {
        return party;
      }
    }

    return null;
  }

  bool _hasPanConflict({
    required String purchasePan,
    required Set<String> candidatePans,
  }) {
    if (purchasePan.isEmpty || candidatePans.isEmpty) return false;
    return !candidatePans.contains(purchasePan);
  }

  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }

    final maxLength = math.max(m, n);
    return maxLength == 0 ? 1.0 : 1.0 - (dp[m][n] / maxLength);
  }

  double _tokenOverlapScore(List<String> left, List<String> right) {
    if (left.isEmpty || right.isEmpty) return 0.0;

    final leftSet = left.toSet();
    final rightSet = right.toSet();
    final overlap = leftSet.intersection(rightSet).length;
    final maxCount = math.max(leftSet.length, rightSet.length);
    if (maxCount == 0) return 0.0;

    return overlap / maxCount;
  }

  double _combinedNameScore({
    required String normalizedPurchaseName,
    required List<String> purchaseTokens,
    required _TdsPartyCandidate candidate,
  }) {
    final charScore = _levenshteinSimilarity(
      normalizedPurchaseName,
      candidate.normalizedName,
    );
    final tokenScore = _tokenOverlapScore(purchaseTokens, candidate.tokens);
    return (charScore * 0.45) + (tokenScore * 0.55);
  }

  bool _isStrongTokenMatch(
    List<String> purchaseTokens,
    List<String> candidateTokens,
  ) {
    if (purchaseTokens.isEmpty || candidateTokens.isEmpty) return false;

    final purchaseSet = purchaseTokens.toSet();
    final candidateSet = candidateTokens.toSet();
    final overlap = purchaseSet.intersection(candidateSet).length;
    if (overlap < 2) return false;

    final purchaseCoverage = overlap / purchaseSet.length;
    final candidateCoverage = overlap / candidateSet.length;
    return purchaseCoverage >= 0.8 && candidateCoverage >= 0.8;
  }

  bool _isStrongPanCandidate({
    required String normalizedPurchaseName,
    required List<String> purchaseTokens,
    required _TdsPartyCandidate candidate,
  }) {
    if (candidate.normalizedName.isEmpty) return false;
    if (candidate.normalizedName == normalizedPurchaseName) return true;
    if (_isStrongTokenMatch(purchaseTokens, candidate.tokens)) return true;

    return _combinedNameScore(
          normalizedPurchaseName: normalizedPurchaseName,
          purchaseTokens: purchaseTokens,
          candidate: candidate,
        ) >=
        0.92;
  }

  List<_CandidateScore> _rankCandidatesByName({
    required _SellerMappingRowVm row,
    required List<_TdsPartyCandidate> candidates,
  }) {
    final normalizedPurchaseName =
        _normalizeBusinessName(row.purchasePartyDisplayName);
    final purchaseTokens = _tokenizeBusinessName(row.purchasePartyDisplayName);
    final purchasePan = normalizePan(row.purchasePan);

    final ranked = candidates
        .where(
          (candidate) => !_hasPanConflict(
            purchasePan: purchasePan,
            candidatePans: candidate.pans,
          ),
        )
        .map(
          (candidate) => _CandidateScore(
            candidate: candidate,
            score: _combinedNameScore(
              normalizedPurchaseName: normalizedPurchaseName,
              purchaseTokens: purchaseTokens,
              candidate: candidate,
            ),
          ),
        )
        .toList();

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.candidate.partyName.compareTo(b.candidate.partyName);
    });

    return ranked;
  }

  _AutoMapDecision _resolveAutoMapForRow(
    _SellerMappingRowVm row,
    List<_TdsPartyCandidate> candidates,
  ) {
    final purchasePan = normalizePan(row.purchasePan);
    final normalizedPurchaseName =
        _normalizeBusinessName(row.purchasePartyDisplayName);
    final purchaseTokens = _tokenizeBusinessName(row.purchasePartyDisplayName);

    _TdsPartyCandidate? candidateByName(String mappedName) {
      for (final candidate in candidates) {
        if (candidate.partyName == mappedName) return candidate;
      }
      return null;
    }

    _AutoMapDecision? evaluateSavedMapping(
      SellerMapping? mapping,
      String reason,
      double confidence,
    ) {
      if (mapping == null) return null;

      final mappedName = mapping.mappedName.trim();
      if (mappedName.isEmpty || !uniqueTdsParties.contains(mappedName)) {
        return null;
      }

      final candidate = candidateByName(mappedName);
      if (candidate == null) return null;

      if (_hasPanConflict(
        purchasePan: purchasePan,
        candidatePans: candidate.pans,
      )) {
        return const _AutoMapDecision(
          autoMapReason: 'pan_conflict_blocked',
          autoMapConfidence: 0.0,
          blockedByPanConflict: true,
        );
      }

      return _AutoMapDecision(
        autoMapReason: reason,
        autoMapConfidence: confidence,
        selectedCandidate: mappedName,
      );
    }

    final exactSavedDecision = evaluateSavedMapping(
      row.exactMapping,
      'saved_mapping_exact',
      0.99,
    );
    if (exactSavedDecision != null) return exactSavedDecision;

    final fallbackSavedDecision = evaluateSavedMapping(
      row.fallbackMapping,
      'saved_mapping_fallback',
      0.95,
    );
    if (fallbackSavedDecision != null) return fallbackSavedDecision;

    if (purchasePan.isNotEmpty) {
      final samePanCandidates = candidates
          .where((candidate) => candidate.pans.contains(purchasePan))
          .toList()
        ..sort((a, b) => a.partyName.compareTo(b.partyName));

      final strongSamePanCandidates = samePanCandidates
          .where(
            (candidate) => _isStrongPanCandidate(
              normalizedPurchaseName: normalizedPurchaseName,
              purchaseTokens: purchaseTokens,
              candidate: candidate,
            ),
          )
          .toList();

      if (strongSamePanCandidates.length == 1) {
        return _AutoMapDecision(
          autoMapReason: 'exact_pan_match',
          autoMapConfidence: 1.0,
          selectedCandidate: strongSamePanCandidates.first.partyName,
        );
      }

      if (strongSamePanCandidates.length > 1) {
        return const _AutoMapDecision(
          autoMapReason: 'ambiguous_candidate',
          autoMapConfidence: 0.0,
          ambiguous: true,
        );
      }
    }

    final exactNameCandidates = candidates
        .where((candidate) => candidate.normalizedName.isNotEmpty)
        .where((candidate) => candidate.normalizedName == normalizedPurchaseName)
        .toList()
      ..sort((a, b) => a.partyName.compareTo(b.partyName));

    if (exactNameCandidates.length == 1) {
      return _AutoMapDecision(
        autoMapReason: 'normalized_name_exact',
        autoMapConfidence: purchasePan.isEmpty ? 0.93 : 0.96,
        selectedCandidate: exactNameCandidates.first.partyName,
      );
    }

    if (exactNameCandidates.length > 1) {
      return const _AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    final strongTokenCandidates = candidates
        .where(
          (candidate) => _isStrongTokenMatch(
            purchaseTokens,
            candidate.tokens,
          ),
        )
        .toList()
      ..sort((a, b) => a.partyName.compareTo(b.partyName));

    if (strongTokenCandidates.length == 1) {
      return _AutoMapDecision(
        autoMapReason: 'strong_token_match',
        autoMapConfidence: purchasePan.isEmpty ? 0.88 : 0.91,
        selectedCandidate: strongTokenCandidates.first.partyName,
      );
    }

    if (strongTokenCandidates.length > 1) {
      return const _AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    if (purchasePan.isEmpty) {
      return const _AutoMapDecision(
        autoMapReason: 'no_safe_match',
        autoMapConfidence: 0.0,
      );
    }

    final rankedCandidates = _rankCandidatesByName(
      row: row,
      candidates: candidates,
    );
    if (rankedCandidates.isEmpty) {
      return const _AutoMapDecision(
        autoMapReason: 'no_safe_match',
        autoMapConfidence: 0.0,
      );
    }

    final best = rankedCandidates.first;
    final second = rankedCandidates.length > 1 ? rankedCandidates[1] : null;
    final bestScore = best.score;
    final secondScore = second?.score ?? 0.0;
    final scoreGap = bestScore - secondScore;

    if (bestScore >= 0.94 && scoreGap >= 0.05) {
      return _AutoMapDecision(
        autoMapReason: 'fuzzy_name_match',
        autoMapConfidence: bestScore,
        selectedCandidate: best.candidate.partyName,
      );
    }

    if (bestScore >= 0.9 && scoreGap < 0.05) {
      return const _AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    return const _AutoMapDecision(
      autoMapReason: 'no_safe_match',
      autoMapConfidence: 0.0,
    );
  }

  String _getStatus({
    required _SellerMappingRowVm row,
    required String? selectedValue,
  }) {
    if (selectedValue == null || selectedValue.trim().isEmpty) {
      return 'Unmapped';
    }

    final purchasePan = normalizePan(row.purchasePan);
    final targetPan = _getPanForTdsParty(selectedValue);

    if (purchasePan.isEmpty ||
        targetPan.isEmpty ||
        targetPan == 'Multiple PANs') {
      return 'Mapped (PAN missing)';
    }

    if (purchasePan == targetPan) {
      return 'Mapped';
    }

    return 'PAN Conflict';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Mapped':
        return Colors.green;
      case 'Mapped (PAN missing)':
        return Colors.amber.shade800;
      case 'PAN Conflict':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusBackgroundColor(String status) {
    switch (status) {
      case 'Mapped':
        return Colors.green.shade50;
      case 'Mapped (PAN missing)':
        return Colors.amber.shade50;
      case 'PAN Conflict':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  String _getValidationMessage(String status) {
    switch (status) {
      case 'Mapped':
        return 'PAN matched';
      case 'Mapped (PAN missing)':
        return 'Mapping is selected, but PAN is missing or not uniquely available';
      case 'PAN Conflict':
        return 'PAN mismatch between purchase and 26Q party';
      default:
        return 'Select a 26Q party for this alias and section';
    }
  }

  Color _getValidationColor(String status) {
    switch (status) {
      case 'Mapped':
        return Colors.green.shade800;
      case 'PAN Conflict':
        return Colors.red.shade800;
      case 'Mapped (PAN missing)':
        return Colors.amber.shade900;
      default:
        return Colors.grey.shade700;
    }
  }

  String? _getExplicitSelectedValue(_SellerMappingRowVm row) {
    final selectedValue = selectedMappings[row.rowKey];
    if (selectedValue == null || !uniqueTdsParties.contains(selectedValue)) {
      selectedMappings.remove(row.rowKey);
      return null;
    }
    return selectedValue;
  }

  String? _getResolvedSuggestionValue(_SellerMappingRowVm row) {
    if ((row.exactMapping?.mappedName.trim() ?? '').isNotEmpty) {
      return null;
    }

    return _normalizeToKnownTdsParty(row.resolvedSuggestion?.mappedName);
  }

  String? _getSelectedValue(_SellerMappingRowVm row) {
    return _getExplicitSelectedValue(row) ?? _getResolvedSuggestionValue(row);
  }

  List<_SellerMappingRowVm> _filteredRows() {
    final query = _searchQuery.trim().toUpperCase();

    return mappingRows.where((row) {
      final selectedValue = _getSelectedValue(row);
      final selectedPan = _getPanForTdsParty(selectedValue);
      final status = _getStatus(
        row: row,
        selectedValue: selectedValue,
      );

      final matchesStatus = _statusFilter == 'All' || status == _statusFilter;
      if (!matchesStatus) return false;

      if (query.isEmpty) return true;

      final searchHaystack = <String>[
        row.purchasePartyDisplayName,
        row.purchasePan,
        row.sectionCode,
        selectedValue ?? '',
        selectedPan,
        autoMapDetails[row.rowKey]?.autoMapReason ?? '',
        row.fallbackMapping?.mappedName ?? '',
        row.fallbackMapping?.mappedPan ?? '',
        row.resolvedSuggestion?.mappedName ?? '',
        row.resolvedSuggestion?.mappedPan ?? '',
        row.resolvedSuggestion?.helperText ?? '',
      ].join(' ').toUpperCase();

      return searchHaystack.contains(query);
    }).toList();
  }

  void _applyAutoMap() {
    final candidates = _buildTdsCandidates();
    final nextDetails = Map<String, _AutoMapDecision>.from(autoMapDetails);

    setState(() {
      for (final row in mappingRows) {
        if (widget.blockedAliases.contains(row.normalizedAlias)) continue;
        if (selectedMappings.containsKey(row.rowKey)) continue;

        final decision = _resolveAutoMapForRow(row, candidates);
        nextDetails[row.rowKey] = decision;

        final targetName = decision.selectedCandidate?.trim() ?? '';
        if (targetName.isEmpty) continue;
        selectedMappings[row.rowKey] = targetName;
      }

      autoMapDetails = nextDetails;
    });
  }

  void _clearVisibleMappings() {
    final visibleRows = _filteredRows();
    setState(() {
      for (final row in visibleRows) {
        selectedMappings.remove(row.rowKey);
        autoMapDetails.remove(row.rowKey);
      }
    });
  }

  void _clearMapping(_SellerMappingRowVm row) {
    setState(() {
      selectedMappings.remove(row.rowKey);
      autoMapDetails.remove(row.rowKey);
    });
  }

  @override
  void initState() {
    super.initState();

    uniqueTdsParties = widget.tdsParties
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final exactMappingsByKey = <String, SellerMapping>{};
    final fallbackMappingsByAlias = <String, SellerMapping>{};

    for (final mapping in widget.existingMappings) {
      final aliasKey = normalizeName(mapping.aliasName.trim());
      final sectionCode =
          normalizeSellerMappingSectionCode(mapping.sectionCode);
      if (aliasKey.isEmpty || mapping.mappedName.trim().isEmpty) continue;

      if (sectionCode == 'ALL') {
        fallbackMappingsByAlias[aliasKey] = mapping;
        continue;
      }

      exactMappingsByKey[_rowKey(aliasKey, sectionCode)] = mapping;
    }

    final rowMap = <String, _SellerMappingRowVm>{};
    for (final row in widget.purchaseRows) {
      final aliasKey = normalizeName(row.normalizedAlias.trim());
      final sectionCode =
          normalizeSellerMappingSectionCode(row.sectionCode);
      if (aliasKey.isEmpty) continue;

      final rowKey = _rowKey(aliasKey, sectionCode);
      final existing = rowMap[rowKey];
      final displayName = row.purchasePartyDisplayName.trim();
      final purchasePan = normalizePan(row.purchasePan);

      rowMap[rowKey] = _SellerMappingRowVm(
        purchasePartyDisplayName: displayName.isNotEmpty
            ? displayName
            : (existing?.purchasePartyDisplayName ?? ''),
        normalizedAlias: aliasKey,
        sectionCode: sectionCode,
        purchasePan: purchasePan.isNotEmpty
            ? purchasePan
            : (existing?.purchasePan ?? ''),
        exactMapping: exactMappingsByKey[rowKey] ?? existing?.exactMapping,
        fallbackMapping:
            fallbackMappingsByAlias[aliasKey] ?? existing?.fallbackMapping,
        resolvedSuggestion: row.resolvedSuggestion ?? existing?.resolvedSuggestion,
      );
    }

    mappingRows = rowMap.values.toList()
      ..sort((a, b) {
        final nameCompare = a.purchasePartyDisplayName.compareTo(
          b.purchasePartyDisplayName,
        );
        if (nameCompare != 0) return nameCompare;
        return a.sectionCode.compareTo(b.sectionCode);
      });

    selectedMappings = {
      for (final row in mappingRows)
        if ((row.exactMapping?.mappedName.trim() ?? '').isNotEmpty)
          row.rowKey: row.exactMapping!.mappedName.trim(),
    };

    autoMapDetails = {};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _saveMappings() {
    final upserts = <Map<String, String>>[];
    final deleted = <Map<String, String>>[];

    for (final row in mappingRows) {
      final currentMappedName = selectedMappings[row.rowKey]?.trim() ?? '';
      final existingExactName = row.exactMapping?.mappedName.trim() ?? '';

      if (currentMappedName.isEmpty) {
        if (existingExactName.isNotEmpty) {
          deleted.add({
            'aliasName': row.normalizedAlias,
            'sectionCode': row.sectionCode,
          });
        }
        continue;
      }

      if (currentMappedName == existingExactName) {
        continue;
      }

      upserts.add({
        'aliasName': row.normalizedAlias,
        'sectionCode': row.sectionCode,
        'mappedName': currentMappedName,
        'mappedPan': _getPanForTdsParty(currentMappedName),
      });
    }

    Navigator.pop(context, {
      'upserts': upserts,
      'deleted': deleted,
    });
  }

  String _buyerInitials() {
    final segments = widget.buyerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return 'BA';
    if (segments.length == 1) {
      return segments.first.substring(0, 1).toUpperCase();
    }
    return (segments.first.substring(0, 1) + segments.last.substring(0, 1))
        .toUpperCase();
  }

  List<_SellerMappingSummaryMetric> _buildSummaryMetrics() {
    var mapped = 0;
    var unmapped = 0;
    var conflicts = 0;

    for (final row in mappingRows) {
      final selectedValue = _getSelectedValue(row);
      final status = _getStatus(row: row, selectedValue: selectedValue);
      if (selectedValue != null && selectedValue.trim().isNotEmpty) {
        mapped++;
      }
      if (status == 'Unmapped') unmapped++;
      if (status == 'PAN Conflict') conflicts++;
    }

    return [
      _SellerMappingSummaryMetric(
        label: 'Total',
        value: mappingRows.length,
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF344054),
      ),
      _SellerMappingSummaryMetric(
        label: 'Mapped',
        value: mapped,
        icon: Icons.link_rounded,
        color: _successColor,
      ),
      _SellerMappingSummaryMetric(
        label: 'Unmapped',
        value: unmapped,
        icon: Icons.hourglass_empty_rounded,
        color: _warningColor,
      ),
      _SellerMappingSummaryMetric(
        label: 'Conflicts',
        value: conflicts,
        icon: Icons.warning_amber_rounded,
        color: _dangerColor,
      ),
    ];
  }

  Color _statusAccentColor(String status) {
    switch (status) {
      case 'Mapped':
        return _successColor;
      case 'Mapped (PAN missing)':
        return _warningColor;
      case 'PAN Conflict':
        return _dangerColor;
      default:
        return _mutedTextColor;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Mapped':
        return Icons.check_circle_rounded;
      case 'Mapped • Verify PAN':
        return Icons.help_outline_rounded;
      case 'PAN Conflict':
        return Icons.error_outline_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  IconData _statusIconSafe(String status) {
    switch (status) {
      case 'Mapped':
        return Icons.check_circle_rounded;
      case 'Mapped (PAN missing)':
        return Icons.help_outline_rounded;
      case 'PAN Conflict':
        return Icons.error_outline_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Color _rowBackgroundColor({
    required String status,
    required int index,
  }) {
    final base = index.isEven ? Colors.white : const Color(0xFFFBFCFE);
    if (status == 'PAN Conflict') {
      return Color.alphaBlend(
        _dangerColor.withValues(alpha: 0.08),
        base,
      );
    }
    if (status == 'Mapped • Verify PAN') {
      return Color.alphaBlend(
        _warningColor.withValues(alpha: 0.08),
        base,
      );
    }
    return base;
  }

  Color _rowBackgroundColorSafe({
    required String status,
    required int index,
  }) {
    final base = index.isEven ? Colors.white : const Color(0xFFFBFCFE);
    if (status == 'PAN Conflict') {
      return Color.alphaBlend(
        _dangerColor.withValues(alpha: 0.08),
        base,
      );
    }
    if (status == 'Mapped (PAN missing)') {
      return Color.alphaBlend(
        _warningColor.withValues(alpha: 0.08),
        base,
      );
    }
    return base;
  }

  List<String> _helperMessages({
    required _SellerMappingRowVm row,
    required String status,
    required String? selectedValue,
  }) {
    final messages = <String>[];
    final autoMapDetail = autoMapDetails[row.rowKey];
    final fallbackName = row.fallbackMapping?.mappedName.trim() ?? '';
    final suggestion = row.resolvedSuggestion;
    final explicitSelectedValue = _getExplicitSelectedValue(row);
    final exactMappedName = row.exactMapping?.mappedName.trim() ?? '';

    if (explicitSelectedValue != null && autoMapDetail == null) {
      if (exactMappedName.isNotEmpty && explicitSelectedValue == exactMappedName) {
        messages.add('Exact section mapping saved');
      } else if (explicitSelectedValue.isNotEmpty) {
        messages.add('Manual selection made; save to store exact section mapping');
      }
    }

    if (autoMapDetail != null) {
      switch (autoMapDetail.autoMapReason) {
        case 'saved_mapping_exact':
          messages.add('Auto-mapped from saved exact mapping');
          break;
        case 'saved_mapping_fallback':
          messages.add('Auto-mapped from saved fallback');
          break;
        case 'exact_pan_match':
          messages.add('Auto-mapped from exact PAN');
          break;
        case 'normalized_name_exact':
          messages.add('Auto-mapped from exact name');
          break;
        case 'strong_token_match':
          messages.add('Auto-mapped from strong token match');
          break;
        case 'fuzzy_name_match':
          messages.add('Auto-mapped from conservative fuzzy match');
          break;
        case 'pan_conflict_blocked':
          messages.add('Auto-map blocked due to PAN conflict');
          break;
        case 'ambiguous_candidate':
          messages.add('Auto-map found multiple close candidates');
          break;
        case 'no_safe_match':
          messages.add('No safe auto-map candidate found');
          break;
      }
    }

    if (suggestion != null &&
        suggestion.mappedName.trim().isNotEmpty &&
        explicitSelectedValue == null) {
      switch (suggestion.source) {
        case 'saved_fallback':
          messages.add('Global fallback currently used in reconciliation');
          break;
        case 'backend_inferred':
          messages.add(
            'Currently resolved in reconciliation as ${suggestion.mappedName}',
          );
          break;
      }
      messages.add(
        suggestion.helperText.trim().isNotEmpty
            ? suggestion.helperText.trim()
            : 'Visible as a suggestion only; save to store as exact section mapping',
      );
    }

    if (status == 'PAN Conflict') {
      messages.add('Conflict: purchase PAN and 26Q PAN differ');
    } else if (status == 'Mapped (PAN missing)') {
      messages.add('Mapping exists, but PAN still needs manual verification');
    } else if (status == 'Unmapped') {
      if (fallbackName.isNotEmpty) {
        messages.add('Global fallback mapping available');
      } else {
        messages.add('Select a 26Q party for this alias and section');
      }
    } else if (selectedValue != null && selectedValue.isNotEmpty) {
      messages.add('PAN verified against selected 26Q party');
    }

    if (fallbackName.isNotEmpty &&
        (row.exactMapping?.mappedName.trim() ?? '').isEmpty &&
        !messages.contains('Global fallback mapping available')) {
      messages.add('Global fallback mapping available');
    }

    return messages.take(2).toList();
  }

  Color _helperTextColor({
    required String status,
    required _AutoMapDecision? autoMapDetail,
  }) {
    if (status == 'PAN Conflict' ||
        autoMapDetail?.blockedByPanConflict == true) {
      return _dangerColor;
    }
    if (status == 'Mapped (PAN missing)' || autoMapDetail?.ambiguous == true) {
      return _warningColor;
    }
    if (autoMapDetail?.selectedCandidate != null ||
        rowHasResolvedSuggestion(status, autoMapDetail) ||
        status == 'Mapped') {
      return const Color(0xFF335C9E);
    }
    return _mutedTextColor;
  }

  bool rowHasResolvedSuggestion(String status, _AutoMapDecision? autoMapDetail) {
    return autoMapDetail == null &&
        (status == 'Mapped' || status == 'Mapped (PAN missing)');
  }

  Widget _buildHeader() {
    final selectedSection = widget.selectedSectionLabel.trim().isEmpty
        ? 'All Sections'
        : widget.selectedSectionLabel.trim();
    final fyLabel = widget.financialYearLabel.trim().isEmpty
        ? 'All FY'
        : widget.financialYearLabel.trim();
    final metrics = _buildSummaryMetrics();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.maybePop(context),
            style: IconButton.styleFrom(
              backgroundColor: _primarySoft,
              foregroundColor: _primaryColor,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 16),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF4A6CF7), Color(0xFF2744C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _buyerInitials(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seller Mapping',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _primaryColor,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.buyerName.trim().isEmpty
                      ? 'Unnamed Buyer'
                      : widget.buyerName.trim(),
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: _titleTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SellerMappingPill(
                      icon: Icons.badge_outlined,
                      label: widget.buyerPan.trim().isEmpty
                          ? 'PAN unavailable'
                          : widget.buyerPan.trim().toUpperCase(),
                    ),
                    _SellerMappingPill(
                      icon: Icons.calendar_today_outlined,
                      label: fyLabel,
                    ),
                    _SellerMappingPill(
                      icon: Icons.tune_rounded,
                      label: selectedSection,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Rows remain section-aware. Existing ALL mappings are shown as guidance only, and saving continues to create or update exact section mappings.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: _mutedTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.end,
            children: metrics
                .map((metric) => _SellerMappingMetricCard(metric: metric))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      side: const BorderSide(color: _borderColor),
      foregroundColor: _titleTextColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search party, PAN, section or mapped 26Q party',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _primaryColor, width: 1.2),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: InputDecoration(
                labelText: 'Status',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _primaryColor, width: 1.2),
                ),
              ),
              items: const [
                'All',
                'Mapped',
                'Unmapped',
                'Mapped (PAN missing)',
                'PAN Conflict',
              ]
                  .map(
                    (status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(status),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _statusFilter = value;
                });
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _applyAutoMap,
            style: buttonStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(_primaryColor),
              side: const WidgetStatePropertyAll(
                BorderSide(color: Color(0xFFBFCCF5)),
              ),
              backgroundColor: const WidgetStatePropertyAll(_primarySoft),
            ),
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Auto Map'),
          ),
          OutlinedButton.icon(
            onPressed: _clearVisibleMappings,
            style: buttonStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(_dangerColor),
              side: WidgetStatePropertyAll(
                BorderSide(color: _dangerColor.withValues(alpha: 0.28)),
              ),
            ),
            icon: const Icon(Icons.layers_clear_rounded),
            label: const Text('Clear Mapping'),
          ),
          FilledButton.icon(
            onPressed: _saveMappings,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Mapping'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    Widget headerCell(String title, int flex, {Alignment? alignment}) {
      return Expanded(
        flex: flex,
        child: Align(
          alignment: alignment ?? Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF344054),
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: _borderColor),
        ),
      ),
      child: Row(
        children: [
          headerCell('Purchase Party', 4),
          headerCell('Section', 2),
          headerCell('Purchase PAN', 2),
          headerCell('Mapped 26Q Party', 4),
          headerCell('26Q PAN', 2),
          headerCell('Status', 2),
          headerCell('Actions', 1, alignment: Alignment.center),
        ],
      ),
    );
  }

  Widget _buildPartyDropdown({
    required _SellerMappingRowVm row,
    required String? selectedValue,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('${row.rowKey}|${selectedValue ?? ''}'),
      initialValue:
          selectedValue != null && uniqueTdsParties.contains(selectedValue)
              ? selectedValue
              : null,
      isExpanded: true,
      itemHeight: 72,
      menuMaxHeight: 420,
      icon: const Icon(Icons.expand_more_rounded),
      decoration: InputDecoration(
        hintText: 'Select 26Q party',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 1.2),
        ),
      ),
      selectedItemBuilder: (context) {
        return uniqueTdsParties.map((tdsParty) {
          final pan = _getPanForTdsParty(tdsParty);
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 40,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tdsParty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _titleTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pan.isEmpty ? 'PAN not available' : 'PAN: $pan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: _mutedTextColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();
      },
      items: uniqueTdsParties.map((tdsParty) {
        final pan = _getPanForTdsParty(tdsParty);
        return DropdownMenuItem<String>(
          value: tdsParty,
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tdsParty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _titleTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  pan.isEmpty ? 'PAN not available' : 'PAN: $pan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    color: _mutedTextColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          autoMapDetails.remove(row.rowKey);
          if (value == null || value.trim().isEmpty) {
            selectedMappings.remove(row.rowKey);
          } else {
            selectedMappings[row.rowKey] = value;
          }
        });
      },
    );
  }

  Widget _buildTableRow({
    required _SellerMappingRowVm row,
    required String? selectedValue,
    required String selectedPan,
    required String status,
    required int index,
    required bool isLast,
  }) {
    final helperMessages = _helperMessages(
      row: row,
      status: status,
      selectedValue: selectedValue,
    );
    final autoMapDetail = autoMapDetails[row.rowKey];

    Widget cell({
      required int flex,
      required Widget child,
      Alignment alignment = Alignment.centerLeft,
    }) {
      return Expanded(
        flex: flex,
        child: Align(
          alignment: alignment,
          child: child,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _rowBackgroundColorSafe(status: status, index: index),
        border: Border(
          bottom: BorderSide(
            color: isLast ? _borderColor : const Color(0xFFE8EEF8),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cell(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                row.purchasePartyDisplayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: _titleTextColor,
                ),
              ),
            ),
          ),
          cell(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _SellerMappingPill(
                icon: Icons.grid_view_rounded,
                label: row.sectionCode,
                compact: true,
              ),
            ),
          ),
          cell(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                row.purchasePan.isEmpty ? 'Not available' : row.purchasePan,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: _titleTextColor,
                ),
              ),
            ),
          ),
          cell(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPartyDropdown(
                  row: row,
                  selectedValue: selectedValue,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      helperMessages.join('\n'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: _helperTextColor(
                          status: status,
                          autoMapDetail: autoMapDetail,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          cell(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                selectedPan.isEmpty ? 'Not available' : selectedPan,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: _titleTextColor,
                ),
              ),
            ),
          ),
          cell(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _SellerMappingStatusChip(
                icon: _statusIconSafe(status),
                label: status,
                color: _statusAccentColor(status),
              ),
            ),
          ),
          cell(
            flex: 1,
            alignment: Alignment.topCenter,
            child: IconButton(
              tooltip: 'Clear Seller Mapping',
              onPressed: () => _clearMapping(row),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.88),
                foregroundColor: _dangerColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _dangerColor.withValues(alpha: 0.18),
                  ),
                ),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.manage_search_rounded,
                size: 34,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No seller rows match the current filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _titleTextColor,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try clearing search or switching the status filter to see more mapping rows.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _mutedTextColor,
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _statusFilter = 'All';
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Clear Search and Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSection(List<_SellerMappingRowVm> visibleRows) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: visibleRows.isEmpty
            ? _buildEmptyState()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = math.max(constraints.maxWidth, 1180.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        children: [
                          _buildTableHeader(),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: visibleRows.length,
                              itemBuilder: (context, index) {
                                final row = visibleRows[index];
                                final isLast = index == visibleRows.length - 1;
                                final selectedValue = _getSelectedValue(row);
                                final selectedPan =
                                    _getPanForTdsParty(selectedValue);
                                final status = _getStatus(
                                  row: row,
                                  selectedValue: selectedValue,
                                );

                                return _buildTableRow(
                                  row: row,
                                  selectedValue: selectedValue,
                                  selectedPan: selectedPan,
                                  status: status,
                                  index: index,
                                  isLast: isLast,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildBottomBar(List<_SellerMappingRowVm> visibleRows) {
    final visibleCount = visibleRows.length;
    final totalCount = mappingRows.length;
    final conflictCount = mappingRows.where((row) {
      final selectedValue = _getSelectedValue(row);
      return _getStatus(row: row, selectedValue: selectedValue) ==
          'PAN Conflict';
    }).length;
    final missingPanCount = mappingRows.where((row) {
      final selectedValue = _getSelectedValue(row);
      return _getStatus(row: row, selectedValue: selectedValue) ==
          'Mapped (PAN missing)';
    }).length;

    final summaryText = visibleCount == totalCount
        ? 'Showing all $totalCount seller rows.'
        : 'Showing $visibleCount of $totalCount seller rows.';

    final reviewText = conflictCount > 0
        ? '$conflictCount conflict ${conflictCount == 1 ? 'needs' : 'need'} review before final reconciliation.'
        : missingPanCount > 0
            ? '$missingPanCount row ${missingPanCount == 1 ? 'has' : 'have'} mapped selections that still need PAN verification.'
            : 'All visible mappings are ready for reconciliation review.';

    final reviewColor = conflictCount > 0
        ? _dangerColor
        : missingPanCount > 0
            ? _warningColor
            : _successColor;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
        decoration: BoxDecoration(
          color: _surfaceColor.withValues(alpha: 0.96),
          border: const Border(
            top: BorderSide(color: _borderColor),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summaryText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _titleTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reviewText,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: reviewColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.maybePop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: const BorderSide(color: _borderColor),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to Upload'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _saveMappings,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Proceed to Reconciliation'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _filteredRows();

    return Scaffold(
      backgroundColor: _pageBackground,
      bottomNavigationBar: _buildBottomBar(visibleRows),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              _buildTopToolbar(),
              const SizedBox(height: 16),
              Expanded(
                child: _buildTableSection(visibleRows),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerMappingSummaryMetric {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _SellerMappingSummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _SellerMappingMetricCard extends StatelessWidget {
  final _SellerMappingSummaryMetric metric;

  const _SellerMappingMetricCard({
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: metric.color.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 18, color: metric.color),
          const SizedBox(height: 14),
          Text(
            '${metric.value}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _SellerMappingScreenState._titleTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _SellerMappingScreenState._mutedTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerMappingPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const _SellerMappingPill({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 8,
      ),
      decoration: BoxDecoration(
        color: compact
            ? const Color(0xFFF8FAFC)
            : _SellerMappingScreenState._primarySoft,
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
        border: Border.all(
          color: compact ? const Color(0xFFDCE4F2) : const Color(0xFFD4DFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 14 : 15,
            color: compact
                ? _SellerMappingScreenState._mutedTextColor
                : _SellerMappingScreenState._primaryColor,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12,
              fontWeight: FontWeight.w700,
              color: compact
                  ? _SellerMappingScreenState._titleTextColor
                  : _SellerMappingScreenState._primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerMappingStatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SellerMappingStatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
