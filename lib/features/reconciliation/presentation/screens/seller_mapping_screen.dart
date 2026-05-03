import 'dart:math' as math;
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/widgets/app_compact_select_field.dart';
import 'package:reconciliation_app/core/widgets/app_search_autocomplete_field.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_summary_cards.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_theme.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_review_view.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_two_panel_body.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_models.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/models/reconciliation_view_mode.dart';

class SellerMappingScreenRowData {
  final String purchasePartyDisplayName;
  final String normalizedAlias;
  final String sectionCode;
  final String tdsDisplayName;
  final String tdsPan;
  final String purchasePan;
  final String purchaseGstNo;
  final int sourceRowCount;
  final int tdsRowCount;
  final SellerMappingResolvedSuggestion? resolvedSuggestion;
  final bool isReadOnly;
  final bool isAboveThreshold;
  final bool hasReconciliationMismatch;
  final bool hasNameOrPanConflict;
  final bool hasApplicableTdsImpact;
  final bool is26QUnmatched;
  final bool hasMissingOrUncertainPan;
  final String preflightReasonCode;
  final String preflightReasonLabel;
  final String preflightReasonDetail;
  final bool requiresDangerousReview;
  final bool isPurchaseOnly;

  const SellerMappingScreenRowData({
    required this.purchasePartyDisplayName,
    required this.normalizedAlias,
    required this.sectionCode,
    this.tdsDisplayName = '',
    this.tdsPan = '',
    required this.purchasePan,
    this.purchaseGstNo = '',
    this.sourceRowCount = 0,
    this.tdsRowCount = 0,
    this.resolvedSuggestion,
    this.isReadOnly = false,
    this.isAboveThreshold = false,
    this.hasReconciliationMismatch = false,
    this.hasNameOrPanConflict = false,
    this.hasApplicableTdsImpact = false,
    this.is26QUnmatched = false,
    this.hasMissingOrUncertainPan = false,
    this.preflightReasonCode = '',
    this.preflightReasonLabel = '',
    this.preflightReasonDetail = '',
    this.requiresDangerousReview = false,
    this.isPurchaseOnly = false,
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

class SellerMappingScreenResult {
  final List<Map<String, String>> upserts;
  final List<Map<String, String>> deleted;
  final int dangerousRemaining;
  final int unreviewedExceptionCount;
  final Map<String, String> selectedMappings;
  final Set<String> clearedRowKeys;

  const SellerMappingScreenResult({
    this.upserts = const <Map<String, String>>[],
    this.deleted = const <Map<String, String>>[],
    this.dangerousRemaining = 0,
    this.unreviewedExceptionCount = 0,
    this.selectedMappings = const <String, String>{},
    this.clearedRowKeys = const <String>{},
  });
}

class SellerMappingScreen extends StatefulWidget {
  final SellerMappingScreenMode mode;
  final String buyerName;
  final String buyerPan;
  final String financialYearLabel;
  final String selectedSectionLabel;
  final ReconciliationViewMode initialViewMode;
  final List<SellerMappingScreenRowData> purchaseRows;
  final List<String> tdsParties;
  final List<SellerMapping> existingMappings;
  final Set<String> blockedAliases;
  final Map<String, List<String>> tdsPartyPans;
  final int rawSourceRowCount;
  final String buyerGstNo;
  final Map<String, String> initialSelectedMappings;
  final Set<String> initialClearedRowKeys;

  const SellerMappingScreen({
    super.key,
    this.mode = SellerMappingScreenMode.standard,
    required this.buyerName,
    required this.buyerPan,
    required this.financialYearLabel,
    required this.selectedSectionLabel,
    this.initialViewMode = ReconciliationViewMode.summary,
    required this.purchaseRows,
    required this.tdsParties,
    this.existingMappings = const [],
    required this.blockedAliases,
    this.tdsPartyPans = const {},
    this.rawSourceRowCount = 0,
    this.buyerGstNo = '',
    this.initialSelectedMappings = const <String, String>{},
    this.initialClearedRowKeys = const <String>{},
  });

  @override
  State<SellerMappingScreen> createState() => _SellerMappingScreenState();
}

enum SellerMappingScreenMode { standard, preflight }

enum SellerMappingWorkspaceView { working, review }

class _SellerMappingDisplayRow {
  final SellerMappingRowVm row;
  final String? selectedValue;
  final String selectedPan;
  final String status;
  final AutoMapDecision? autoMapDetail;
  final List<String> helperMessages;
  final int index;
  final bool isLast;

  const _SellerMappingDisplayRow({
    required this.row,
    required this.selectedValue,
    required this.selectedPan,
    required this.status,
    required this.autoMapDetail,
    required this.helperMessages,
    required this.index,
    required this.isLast,
  });
}

class _SellerFilterRowState {
  final String? selectedValue;
  final String selectedPan;
  final String status;
  final AutoMapDecision? autoMapDetail;
  final String searchHaystack;
  final bool matchesNeedsAction;
  final bool matchesAboveThreshold;
  final bool matchesUnmatched26Q;
  final bool isDangerousRowExplicitlyResolved;
  final bool isUnresolvedDangerousPreflightRow;

  const _SellerFilterRowState({
    required this.selectedValue,
    required this.selectedPan,
    required this.status,
    required this.autoMapDetail,
    required this.searchHaystack,
    required this.matchesNeedsAction,
    required this.matchesAboveThreshold,
    required this.matchesUnmatched26Q,
    required this.isDangerousRowExplicitlyResolved,
    required this.isUnresolvedDangerousPreflightRow,
  });
}

class _LedgerLinkOption {
  final String linkedRowKey;
  final String displayValue;
  final String subtitle;
  final List<String> searchableTerms;

  const _LedgerLinkOption({
    required this.linkedRowKey,
    required this.displayValue,
    required this.subtitle,
    required this.searchableTerms,
  });
}

class _SellerMappingScreenState extends State<SellerMappingScreen> {
  static const List<String> _sectionTabOrder = <String>[
    '194Q',
    '194C',
    '194H',
    '194I_A',
    '194I_B',
    '194J_A',
    '194J_B',
  ];
  static const int _initialVisibleRowLimit = 100;
  static const int _visibleRowIncrement = 100;
  static const String _separatePrefix = '__SEPARATE__:';
  static const String _timingDifferencePrefix = '__TIMING_DIFFERENCE__:';
  static const String _missingInBooksPrefix = '__MISSING_IN_BOOKS__:';
  static const String _linkLedgerPrefix = '__LINK_LEDGER__:';

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

  static const Set<String> _ignoredNameTokens = {'AND', 'THE'};

  Map<String, String> selectedMappings = <String, String>{};
  Map<String, AutoMapDecision> autoMapDetails = <String, AutoMapDecision>{};
  List<String> uniqueTdsParties = <String>[];
  Map<String, List<SellerMappingScreenRowData>> _rowDataBySection =
      <String, List<SellerMappingScreenRowData>>{};
  Map<String, SellerMapping> _exactMappingsByKey = <String, SellerMapping>{};
  Map<String, SellerMapping> _fallbackMappingsByAlias =
      <String, SellerMapping>{};
  String _activeSectionCode = '194Q';
  final Map<String, List<SellerMappingRowVm>> _mappingRowsBySectionCache =
      <String, List<SellerMappingRowVm>>{};
  final Set<String> _clearedRowKeys = <String>{};
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _statusFilter = 'All';
  SellerMappingListView _activeListView = SellerMappingListView.needsAction;
  SellerMappingWorkspaceView _activeWorkspaceView =
      SellerMappingWorkspaceView.working;
  int _visibleRowLimit = _initialVisibleRowLimit;
  List<SellerMappingRowVm>? _cachedFilteredRows;
  Map<SellerMappingListView, int>? _cachedListViewCounts;
  Map<String, _SellerFilterRowState> _rowStateByKey =
      <String, _SellerFilterRowState>{};
  final Stopwatch _screenOpenStopwatch = Stopwatch()..start();
  bool _isInitializing = true;
  bool _firstFrameLogged = false;

  void _invalidateViewCaches({bool resetPage = false}) {
    _cachedFilteredRows = null;
    _cachedListViewCounts = null;
    if (resetPage) {
      _visibleRowLimit = _initialVisibleRowLimit;
    }
  }

  String _rowKey(Object? alias, Object? sectionCode) {
    final safeAlias = sellerMappingSafeText(alias);
    final safeSection = sellerMappingSafeText(sectionCode);
    return '${normalizePan(widget.buyerPan)}|'
        '${normalizeName(safeAlias)}|'
        '${normalizeSellerMappingSectionCode(safeSection)}';
  }

  bool get _isPreflightMode => widget.mode == SellerMappingScreenMode.preflight;

  String _separateSelectionValue(SellerMappingRowVm row) {
    return '$_separatePrefix${row.rowKey}';
  }

  bool _isSeparateSelection(SellerMappingRowVm row, Object? value) {
    return sellerMappingSafeText(value) == _separateSelectionValue(row);
  }

  String _timingDifferenceValue(SellerMappingRowVm row) {
    return '$_timingDifferencePrefix${row.rowKey}';
  }

  bool _isTimingDifferenceSelection(SellerMappingRowVm row, Object? value) {
    return sellerMappingSafeText(value) == _timingDifferenceValue(row);
  }

  String _missingInBooksValue(SellerMappingRowVm row) {
    return '$_missingInBooksPrefix${row.rowKey}';
  }

  bool _isMissingInBooksSelection(SellerMappingRowVm row, Object? value) {
    return sellerMappingSafeText(value) == _missingInBooksValue(row);
  }

  String _linkLedgerValue(Object? linkedRowKey) =>
      '$_linkLedgerPrefix${sellerMappingSafeText(linkedRowKey)}';

  bool _isLinkLedgerSelection(Object? value) {
    return sellerMappingSafeText(value).startsWith(_linkLedgerPrefix);
  }

  String _linkedLedgerRowKey(Object? value) {
    if (!_isLinkLedgerSelection(value)) {
      return '';
    }
    return sellerMappingSafeText(value).substring(_linkLedgerPrefix.length);
  }

  List<String> get _availableSectionCodes {
    return _sectionTabOrder
        .where((section) => (_rowDataBySection[section] ?? const []).isNotEmpty)
        .toList();
  }

  List<SellerMappingRowVm> _rowsForActiveSection() {
    return _rowsForSection(_activeSectionCode);
  }

  List<SellerMappingRowVm> _rowsForSection(String sectionCode) {
    return _mappingRowsBySectionCache.putIfAbsent(
      sectionCode,
      () => _buildRowsForSection(sectionCode),
    );
  }

  List<SellerMappingRowVm> _buildRowsForSection(String sectionCode) {
    final sourceRows = List<SellerMappingScreenRowData>.from(
      _rowDataBySection[sectionCode] ?? const [],
    );

    final builtRows = <SellerMappingRowVm>[];
    for (var index = 0; index < sourceRows.length; index++) {
      final row = sourceRows[index];
      final aliasKey = normalizeName(row.normalizedAlias.trim());
      final normalizedSection = normalizeSellerMappingSectionCode(
        row.sectionCode,
      );
      if (aliasKey.isEmpty) continue;

      final displayName = row.purchasePartyDisplayName.trim();
      final purchasePan = normalizePan(row.purchasePan);
      final tdsDisplayName = row.tdsDisplayName.trim();
      final tdsPan = normalizePan(row.tdsPan);

      final exactMappingKey = _rowKey(aliasKey, normalizedSection);
      builtRows.add(
        SellerMappingRowVm(
          purchasePartyDisplayName: displayName.isNotEmpty ? displayName : '',
          normalizedAlias: aliasKey,
          sectionCode: normalizedSection,
          rowIndex: index,
          tdsDisplayName: tdsDisplayName,
          tdsPan: tdsPan,
          purchasePan: purchasePan.isNotEmpty ? purchasePan : '',
          purchaseGstNo: row.purchaseGstNo.trim().isNotEmpty
              ? row.purchaseGstNo.trim()
              : '',
          sourceRowCount: row.sourceRowCount,
          tdsRowCount: row.tdsRowCount,
          exactMapping: _exactMappingsByKey[exactMappingKey],
          fallbackMapping: _fallbackMappingsByAlias[aliasKey],
          resolvedSuggestion: row.resolvedSuggestion,
          isReadOnly: row.isReadOnly,
          isAboveThreshold: row.isAboveThreshold,
          hasReconciliationMismatch: row.hasReconciliationMismatch,
          hasNameOrPanConflict: row.hasNameOrPanConflict,
          hasApplicableTdsImpact: row.hasApplicableTdsImpact,
          is26QUnmatched: row.is26QUnmatched,
          hasMissingOrUncertainPan: row.hasMissingOrUncertainPan,
          preflightReasonCode: row.preflightReasonCode.trim(),
          preflightReasonLabel: row.preflightReasonLabel.trim(),
          preflightReasonDetail: row.preflightReasonDetail.trim(),
          requiresDangerousReview: row.requiresDangerousReview,
          isPurchaseOnly: row.isPurchaseOnly,
        ),
      );
    }

    builtRows.sort((a, b) {
      final nameCompare = resolveTdsSellerTitle(
        a,
      ).compareTo(resolveTdsSellerTitle(b));
      if (nameCompare != 0) return nameCompare;
      return a.sectionCode.compareTo(b.sectionCode);
    });

    return builtRows;
  }

  String _normalizeBusinessName(Object? value) {
    var text = sellerMappingSafeText(value).toUpperCase();
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

  List<String> _tokenizeBusinessName(Object? value) {
    final normalized = _normalizeBusinessName(value);
    if (normalized.isEmpty) return const <String>[];

    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .where((token) => !_ignoredNameTokens.contains(token))
        .toList();
  }

  Set<String> _resolveTargetPans(Object? mappedName) {
    final safeMappedName = sellerMappingSafeText(mappedName);
    final exactPans = widget.tdsPartyPans[safeMappedName];
    if (exactPans != null) {
      return exactPans
          .map((pan) => normalizePan(pan))
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    final normalizedMappedName = normalizeName(safeMappedName);
    for (final entry in widget.tdsPartyPans.entries) {
      if (normalizeName(entry.key) != normalizedMappedName) continue;
      return entry.value
          .map((pan) => normalizePan(pan))
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    return const <String>{};
  }

  List<TdsPartyCandidate> _buildTdsCandidates() {
    return uniqueTdsParties
        .map(
          (partyName) => TdsPartyCandidate(
            partyName: partyName,
            normalizedName: _normalizeBusinessName(partyName),
            tokens: _tokenizeBusinessName(partyName),
            pans: _resolveTargetPans(partyName),
          ),
        )
        .toList()
      ..sort((a, b) => a.partyName.compareTo(b.partyName));
  }

  String _getPanForTdsParty(Object? mappedName) {
    if (sellerMappingSafeText(mappedName).isEmpty) return '';

    final pans = _resolveTargetPans(mappedName);
    if (pans.isEmpty) return '';
    if (pans.length == 1) return pans.first;

    return 'Multiple PANs';
  }

  String _getPanForSelection(SellerMappingRowVm row, Object? selectedValue) {
    if (_isSeparateSelection(row, selectedValue) ||
        _isTimingDifferenceSelection(row, selectedValue) ||
        _isMissingInBooksSelection(row, selectedValue) ||
        _isLinkLedgerSelection(selectedValue)) {
      return row.purchasePan;
    }
    return _getPanForTdsParty(selectedValue);
  }

  SellerMappingRowVm? _linkedLedgerRowForSelection({
    required String sectionCode,
    required Object? selectedValue,
  }) {
    final linkedRowKey = _linkedLedgerRowKey(selectedValue);
    if (linkedRowKey.isEmpty) {
      return null;
    }
    for (final candidate in _rowsForSection(sectionCode)) {
      if (candidate.is26QUnmatched) {
        continue;
      }
      if (candidate.rowKey == linkedRowKey) {
        return candidate;
      }
    }
    return null;
  }

  bool _isReviewed26QDecision(SellerMappingRowVm row, String? selectedValue) {
    if (!row.is26QUnmatched || selectedValue == null) {
      return false;
    }
    return _isLinkLedgerSelection(selectedValue) ||
        _isTimingDifferenceSelection(row, selectedValue) ||
        _isMissingInBooksSelection(row, selectedValue) ||
        (_isPreflightMode && _isSeparateSelection(row, selectedValue));
  }

  String? _normalizeToKnownTdsParty(Object? mappedName) {
    if (sellerMappingSafeText(mappedName).isEmpty) return null;

    final trimmed = sellerMappingSafeText(mappedName);
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

  double _levenshteinSimilarity(Object? left, Object? right) {
    final a = sellerMappingSafeText(left);
    final b = sellerMappingSafeText(right);
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
    required TdsPartyCandidate candidate,
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
    required TdsPartyCandidate candidate,
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

  List<CandidateScore> _rankCandidatesByName({
    required SellerMappingRowVm row,
    required List<TdsPartyCandidate> candidates,
  }) {
    final normalizedPurchaseName = _normalizeBusinessName(
      row.purchasePartyDisplayName,
    );
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
          (candidate) => CandidateScore(
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

  AutoMapDecision _resolveAutoMapForRow(
    SellerMappingRowVm row,
    List<TdsPartyCandidate> candidates,
  ) {
    final purchasePan = normalizePan(row.purchasePan);
    final normalizedPurchaseName = _normalizeBusinessName(
      row.purchasePartyDisplayName,
    );
    final purchaseTokens = _tokenizeBusinessName(row.purchasePartyDisplayName);

    TdsPartyCandidate? candidateByName(String mappedName) {
      for (final candidate in candidates) {
        if (candidate.partyName == mappedName) return candidate;
      }
      return null;
    }

    AutoMapDecision? evaluateSavedMapping(
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
        return const AutoMapDecision(
          autoMapReason: 'pan_conflict_blocked',
          autoMapConfidence: 0.0,
          blockedByPanConflict: true,
        );
      }

      return AutoMapDecision(
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
      final samePanCandidates =
          candidates
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
        return AutoMapDecision(
          autoMapReason: 'exact_pan_match',
          autoMapConfidence: 1.0,
          selectedCandidate: strongSamePanCandidates.first.partyName,
        );
      }

      if (strongSamePanCandidates.length > 1) {
        return const AutoMapDecision(
          autoMapReason: 'ambiguous_candidate',
          autoMapConfidence: 0.0,
          ambiguous: true,
        );
      }
    }

    final exactNameCandidates =
        candidates
            .where((candidate) => candidate.normalizedName.isNotEmpty)
            .where(
              (candidate) => candidate.normalizedName == normalizedPurchaseName,
            )
            .toList()
          ..sort((a, b) => a.partyName.compareTo(b.partyName));

    if (exactNameCandidates.length == 1) {
      return AutoMapDecision(
        autoMapReason: 'normalized_name_exact',
        autoMapConfidence: purchasePan.isEmpty ? 0.93 : 0.96,
        selectedCandidate: exactNameCandidates.first.partyName,
      );
    }

    if (exactNameCandidates.length > 1) {
      return const AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    final strongTokenCandidates =
        candidates
            .where(
              (candidate) =>
                  _isStrongTokenMatch(purchaseTokens, candidate.tokens),
            )
            .toList()
          ..sort((a, b) => a.partyName.compareTo(b.partyName));

    if (strongTokenCandidates.length == 1) {
      return AutoMapDecision(
        autoMapReason: 'strong_token_match',
        autoMapConfidence: purchasePan.isEmpty ? 0.88 : 0.91,
        selectedCandidate: strongTokenCandidates.first.partyName,
      );
    }

    if (strongTokenCandidates.length > 1) {
      return const AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    if (purchasePan.isEmpty) {
      return const AutoMapDecision(
        autoMapReason: 'no_safe_match',
        autoMapConfidence: 0.0,
      );
    }

    final rankedCandidates = _rankCandidatesByName(
      row: row,
      candidates: candidates,
    );
    if (rankedCandidates.isEmpty) {
      return const AutoMapDecision(
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
      return AutoMapDecision(
        autoMapReason: 'fuzzy_name_match',
        autoMapConfidence: bestScore,
        selectedCandidate: best.candidate.partyName,
      );
    }

    if (bestScore >= 0.9 && scoreGap < 0.05) {
      return const AutoMapDecision(
        autoMapReason: 'ambiguous_candidate',
        autoMapConfidence: 0.0,
        ambiguous: true,
      );
    }

    return const AutoMapDecision(
      autoMapReason: 'no_safe_match',
      autoMapConfidence: 0.0,
    );
  }

  String _getStatus({
    required SellerMappingRowVm row,
    required Object? selectedValue,
  }) {
    if (_isTimingDifferenceSelection(row, selectedValue)) {
      return 'Timing Difference';
    }
    if (_isMissingInBooksSelection(row, selectedValue)) {
      return 'Missing in Books';
    }

    if (row.is26QUnmatched) {
      if (_isLinkLedgerSelection(selectedValue)) {
        return 'Linked to Ledger';
      }
      if (_isPreflightMode && _isSeparateSelection(row, selectedValue)) {
        return 'Marked Separate';
      }
      return '26Q Unmatched';
    }

    if (_isPreflightMode &&
        selectedValue != null &&
        _isSeparateSelection(row, selectedValue)) {
      return 'Marked Separate';
    }

    if (sellerMappingSafeText(selectedValue).isEmpty) {
      if (row.isPurchaseOnly) {
        return 'Purchase Only';
      }
      if (_isPreflightMode &&
          row.requiresDangerousReview &&
          sellerMappingSafeText(row.preflightReasonLabel).isNotEmpty) {
        return sellerMappingSafeText(row.preflightReasonLabel);
      }
      return 'Unmapped';
    }

    final purchasePan = normalizePan(row.purchasePan);
    final targetPan = _getPanForSelection(row, selectedValue);

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

  bool _isDangerousPreflightStatus(String status) {
    return status == 'Conflicting PAN' ||
        status == 'Ambiguous Identity' ||
        status == 'Unresolved Identity';
  }

  bool _hasLedgerDataForSection(String sectionCode) {
    final normalizedSection = normalizeSellerMappingSectionCode(sectionCode);
    final sectionRows = _rowDataBySection[normalizedSection] ?? const [];
    return sectionRows.any((row) => !row.is26QUnmatched);
  }

  String _statusChipLabel(Object? value, {SellerMappingRowVm? row}) {
    final status = sellerMappingSafeText(value);
    if (row != null &&
        row.is26QUnmatched &&
        status == '26Q Unmatched' &&
        !_hasLedgerDataForSection(row.sectionCode)) {
      return 'Ledger Not Available';
    }
    if (status == 'Conflicting PAN' ||
        status == 'Ambiguous Identity' ||
        status == 'Unresolved Identity') {
      return 'Needs Review';
    }
    return status.isEmpty ? 'Unmapped' : status;
  }

  String? _getExplicitSelectedValue(SellerMappingRowVm row) {
    if (_clearedRowKeys.contains(row.rowKey)) {
      return null;
    }

    final selectedValue = selectedMappings[row.rowKey];
    if (selectedValue == null) {
      return null;
    }
    if (_isSeparateSelection(row, selectedValue) ||
        _isTimingDifferenceSelection(row, selectedValue) ||
        _isMissingInBooksSelection(row, selectedValue) ||
        _isLinkLedgerSelection(selectedValue)) {
      return selectedValue;
    }
    if (!uniqueTdsParties.contains(selectedValue)) {
      selectedMappings.remove(row.rowKey);
      return null;
    }
    return selectedValue;
  }

  // ignore: unused_element
  String? _getResolvedSuggestionValue(SellerMappingRowVm row) {
    if (_clearedRowKeys.contains(row.rowKey)) {
      return null;
    }

    if (_isPreflightMode && row.requiresDangerousReview) {
      return null;
    }

    return _normalizeToKnownTdsParty(row.resolvedSuggestion?.mappedName);
  }

  String? _getSelectedValue(SellerMappingRowVm row) {
    return _getExplicitSelectedValue(row);
  }

  bool _is26QAuditRow(SellerMappingRowVm row) {
    return row.tdsRowCount > 0 || row.is26QUnmatched;
  }

  List<SellerMappingRowVm> _rowsForCurrentViewScope() =>
      _rowsForActiveSection();

  bool _isDangerousRowExplicitlyResolved(SellerMappingRowVm row) {
    if (!_isPreflightMode ||
        row.isPurchaseOnly ||
        !row.requiresDangerousReview) {
      return false;
    }

    final explicitSelectedValue = _getExplicitSelectedValue(row);
    if (explicitSelectedValue == null || explicitSelectedValue.trim().isEmpty) {
      return false;
    }
    if (_isSeparateSelection(row, explicitSelectedValue)) {
      return true;
    }

    final selectedPan = _getPanForSelection(row, explicitSelectedValue);
    if (selectedPan == 'Multiple PANs') {
      return false;
    }

    final status = _getStatus(row: row, selectedValue: explicitSelectedValue);
    return status != 'PAN Conflict' && !_isDangerousPreflightStatus(status);
  }

  bool _isUnresolvedDangerousPreflightRow(SellerMappingRowVm row) {
    if (!_isPreflightMode ||
        row.isPurchaseOnly ||
        !row.requiresDangerousReview) {
      return false;
    }
    return !_isDangerousRowExplicitlyResolved(row);
  }

  bool _matchesNeedsAction({
    required SellerMappingRowVm row,
    required String? selectedValue,
    required String status,
  }) {
    if (row.isPurchaseOnly) {
      return false;
    }

    if (_isUnresolvedDangerousPreflightRow(row)) {
      return true;
    }

    if (row.is26QUnmatched) {
      if (!_hasLedgerDataForSection(row.sectionCode)) {
        return false;
      }
      return status == '26Q Unmatched';
    }

    return status == 'Unmapped' || status == 'PAN Conflict';
  }

  String _buildSearchHaystack({
    required SellerMappingRowVm row,
    required Object? selectedValue,
    required Object? selectedPan,
    required Object? status,
  }) {
    return <Object?>[
      row.purchasePartyDisplayName,
      resolveTdsSellerTitle(row),
      resolveLedgerSellerTitle(row),
      row.normalizedAlias,
      row.sectionCode,
      sectionDisplayLabel(row.sectionCode),
      row.purchasePan,
      row.purchaseGstNo,
      selectedValue ?? '',
      selectedPan,
      status,
      row.exactMapping?.mappedName ?? '',
      row.exactMapping?.mappedPan ?? '',
      row.fallbackMapping?.mappedName ?? '',
      row.fallbackMapping?.mappedPan ?? '',
      row.resolvedSuggestion?.mappedName ?? '',
      row.resolvedSuggestion?.mappedPan ?? '',
      row.preflightReasonLabel,
      row.preflightReasonDetail,
    ].map(sellerMappingSafeText).join(' | ').toUpperCase();
  }

  _SellerFilterRowState _buildFilterRowState(SellerMappingRowVm row) {
    final selectedValue = _getSelectedValue(row);
    final selectedPan = _getPanForSelection(row, selectedValue);
    final status = _getStatus(row: row, selectedValue: selectedValue);
    final matchesNeedsAction = _matchesNeedsAction(
      row: row,
      selectedValue: selectedValue,
      status: status,
    );

    return _SellerFilterRowState(
      selectedValue: selectedValue,
      selectedPan: selectedPan,
      status: status,
      autoMapDetail: autoMapDetails[row.rowKey],
      searchHaystack: _buildSearchHaystack(
        row: row,
        selectedValue: selectedValue,
        selectedPan: selectedPan,
        status: status,
      ),
      matchesNeedsAction: matchesNeedsAction,
      matchesAboveThreshold: row.isAboveThreshold,
      matchesUnmatched26Q: row.is26QUnmatched,
      isDangerousRowExplicitlyResolved: _isDangerousRowExplicitlyResolved(row),
      isUnresolvedDangerousPreflightRow: _isUnresolvedDangerousPreflightRow(
        row,
      ),
    );
  }

  void _rebuildDerivedRowStateCache() {
    final nextState = <String, _SellerFilterRowState>{};
    final seenRowKeys = <String>{};

    for (final rows in _mappingRowsBySectionCache.values) {
      for (final row in rows) {
        if (!seenRowKeys.add(row.rowKey)) {
          continue;
        }
        nextState[row.rowKey] = _buildFilterRowState(row);
      }
    }

    _rowStateByKey = nextState;
  }

  List<SellerMappingRowVm> _filteredRows() {
    if (_cachedFilteredRows != null) return _cachedFilteredRows!;

    final stopwatch = Stopwatch()..start();
    final activeRows = _rowsForCurrentViewScope()
        .where(_is26QAuditRow)
        .toList(growable: false);

    _cachedFilteredRows = activeRows.where((row) {
      final state = _rowStateByKey[row.rowKey];
      if (state == null) {
        return false;
      }

      return _matchesWorkingVisibleFilters(row, state);
    }).toList();
    stopwatch.stop();
    debugPrint(
      'SELLER FILTER PERF => ms=${stopwatch.elapsedMilliseconds} '
      'scope=${activeRows.length} result=${_cachedFilteredRows!.length} '
      'query="${_searchQuery.trim()}" section=$_activeSectionCode '
      'view=${_activeListView.name} status=$_statusFilter',
    );
    return _cachedFilteredRows!;
  }

  bool _matchesWorkingVisibleFilters(
    SellerMappingRowVm row,
    _SellerFilterRowState state,
  ) {
    if (!_is26QAuditRow(row)) return false;

    if (_statusFilter != 'Only in Ledger') {
      if (!_matchesListViewFromState(state, _activeListView)) {
        return false;
      }
    }

    if (!_matchesStatusFilter(state)) return false;

    final query = _searchQuery.trim().toUpperCase();
    if (query.isEmpty) return true;
    return state.searchHaystack.contains(query);
  }

  bool _matchesReviewVisibleFilters(
    SellerMappingRowVm row,
    _SellerFilterRowState state,
  ) {
    if (!_is26QAuditRow(row)) return false;
    if (!_matchesReviewStatusFilter(state)) return false;

    final query = _searchQuery.trim().toUpperCase();
    if (query.isEmpty) return true;
    return state.searchHaystack.contains(query);
  }

  bool _matchesStatusFilter(_SellerFilterRowState state) {
    switch (_statusFilter) {
      case 'All':
        return true;
      case 'Mapped':
        return state.status == 'Mapped' ||
            state.status == 'Mapped (PAN missing)' ||
            state.status == 'Linked to Ledger' ||
            state.status == 'Timing Difference' ||
            state.status == 'Missing in Books' ||
            state.status == 'Marked Separate';
      case 'Unmapped':
        return state.status == '26Q Unmatched' ||
            state.status == 'Unmapped' ||
            state.status == 'PAN Conflict' ||
            _isDangerousPreflightStatus(state.status);
      case 'Only in Ledger':
        return true; // ✅ DO NOT filter LEFT panel
      case 'Conflict':
      case 'PAN Conflict':
        return state.status == 'PAN Conflict' ||
            state.status == 'Conflicting PAN' ||
            _isDangerousPreflightStatus(state.status);
      default:
        return state.status == _statusFilter;
    }
  }

  bool _matchesReviewStatusFilter(_SellerFilterRowState state) {
    switch (_statusFilter) {
      case 'All':
        return true;
      case 'Mapped':
        // Review View uses the audit buckets, not only the raw Working View status.
        // These are the rows counted under the Review View "Mapped" chip.
        return state.status == 'Mapped' ||
            state.status == 'Mapped (PAN missing)' ||
            state.status == 'Linked to Ledger' ||
            state.status == 'Timing Difference' ||
            state.status == 'Missing in Books' ||
            state.status == 'Marked Separate';
      case 'Unmapped':
        // In Review View, "Unmapped" means a 26Q seller still pending review.
        // Exceptions like Missing in Books / Timing Difference are not unmapped.
        return state.status == '26Q Unmatched' ||
            state.status == 'Unmapped' ||
            state.status == 'PAN Conflict' ||
            _isDangerousPreflightStatus(state.status);
      case 'Only in Ledger':
        return state.status == 'Purchase Only';
      case 'Conflict':
      case 'PAN Conflict':
        return state.status == 'PAN Conflict' ||
            state.status == 'Conflicting PAN' ||
            _isDangerousPreflightStatus(state.status);
      default:
        return state.status == _statusFilter;
    }
  }

  List<SellerMappingRowVm> _reviewFilteredRows() {
    final activeRows = _rowsForActiveSection();

    return activeRows
        .where((row) {
          final state = _rowStateByKey[row.rowKey];
          if (state == null) return false;

          return _matchesReviewVisibleFilters(row, state);
        })
        .toList(growable: false);
  }

  _SellerMappingDisplayRow _buildDisplayRowView({
    required SellerMappingRowVm row,
    required int index,
    required bool isLast,
  }) {
    final state = _rowStateByKey[row.rowKey];
    final selectedValue = state?.selectedValue;
    final status =
        state?.status ?? _getStatus(row: row, selectedValue: selectedValue);
    return _SellerMappingDisplayRow(
      row: row,
      selectedValue: selectedValue,
      selectedPan:
          state?.selectedPan ?? _getPanForSelection(row, selectedValue),
      status: status,
      autoMapDetail: state?.autoMapDetail ?? autoMapDetails[row.rowKey],
      helperMessages: _helperMessages(
        row: row,
        status: status,
        selectedValue: selectedValue,
      ),
      index: index,
      isLast: isLast,
    );
  }

  void _applyAutoMap() {
    final candidates = _buildTdsCandidates();
    final nextDetails = Map<String, AutoMapDecision>.from(autoMapDetails);
    final activeRows = _rowsForActiveSection();

    setState(() {
      for (final row in activeRows) {
        if (row.isReadOnly) continue;
        if (widget.blockedAliases.contains(row.normalizedAlias)) continue;
        if (_clearedRowKeys.contains(row.rowKey)) continue;
        if (selectedMappings.containsKey(row.rowKey)) continue;

        final decision = _resolveAutoMapForRow(row, candidates);
        nextDetails[row.rowKey] = decision;

        final targetName = decision.selectedCandidate?.trim() ?? '';
        if (targetName.isEmpty) continue;
        _clearedRowKeys.remove(row.rowKey);
        selectedMappings[row.rowKey] = targetName;
      }

      autoMapDetails = nextDetails;
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  void _clearVisibleMappings() {
    final visibleRows = _filteredRows();
    setState(() {
      for (final row in visibleRows) {
        if (row.isReadOnly) continue;
        _clearedRowKeys.add(row.rowKey);
        selectedMappings.remove(row.rowKey);
        autoMapDetails.remove(row.rowKey);
      }
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches(resetPage: true);
    });
  }

  void _clearMapping(SellerMappingRowVm row) {
    if (row.isReadOnly && !row.is26QUnmatched) return;
    setState(() {
      _clearedRowKeys.add(row.rowKey);
      selectedMappings.remove(row.rowKey);
      autoMapDetails.remove(row.rowKey);
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_firstFrameLogged) return;
      _firstFrameLogged = true;
      debugPrint(
        'SELLER SCREEN PERF => firstFrame ms=${_screenOpenStopwatch.elapsedMilliseconds}',
      );
      _hydrateScreenAfterFirstFrame();
    });
  }

  Future<void> _hydrateScreenAfterFirstFrame() async {
    await Future<void>.delayed(Duration.zero);
    final prepareWatch = Stopwatch()..start();
    final preparedState = _prepareInitialState();
    prepareWatch.stop();
    debugPrint(
      'SELLER SCREEN PERF => prepareInput ms=${prepareWatch.elapsedMilliseconds}',
    );

    final buildWatch = Stopwatch()..start();
    final isolatePayload = preparedState.toIsolatePayload();
    final payload = _shouldUseComputeForViewModels
        ? await compute(_buildSellerScreenViewModelsInIsolate, isolatePayload)
        : _buildSellerScreenViewModelsInIsolate(isolatePayload);
    buildWatch.stop();
    debugPrint(
      'SELLER SCREEN PERF => buildViewModels ms=${buildWatch.elapsedMilliseconds}',
    );

    if (!mounted) return;

    final readyState = _SellerMappingScreenReadyState.fromIsolatePayload(
      Map<String, dynamic>.from(payload),
    );
    final knownRowKeys = readyState.mappingRowsBySection.values
        .expand((rows) => rows)
        .map((row) => row.rowKey)
        .toSet();
    final hydratedSelectedMappings = Map<String, String>.from(
      readyState.selectedMappings,
    );
    for (final entry in widget.initialSelectedMappings.entries) {
      if (!knownRowKeys.contains(entry.key)) continue;
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      hydratedSelectedMappings[entry.key] = value;
    }
    final hydratedClearedRowKeys = widget.initialClearedRowKeys
        .where(knownRowKeys.contains)
        .toSet();
    for (final rowKey in hydratedClearedRowKeys) {
      hydratedSelectedMappings.remove(rowKey);
    }

    setState(() {
      uniqueTdsParties = preparedState.uniqueTdsParties;
      _rowDataBySection = preparedState.rowDataBySection;
      _exactMappingsByKey = preparedState.exactMappingsByKey;
      _fallbackMappingsByAlias = preparedState.fallbackMappingsByAlias;
      _mappingRowsBySectionCache
        ..clear()
        ..addAll(readyState.mappingRowsBySection);
      selectedMappings = hydratedSelectedMappings;
      autoMapDetails = <String, AutoMapDecision>{};
      _clearedRowKeys
        ..clear()
        ..addAll(hydratedClearedRowKeys);
      _activeSectionCode = readyState.activeSectionCode;
      _rebuildDerivedRowStateCache();
      _isInitializing = false;
      _invalidateViewCaches(resetPage: true);
    });

    final filterWatch = Stopwatch()..start();
    _filteredRows();
    filterWatch.stop();
    debugPrint(
      'SELLER SCREEN PERF => applyFilters ms=${filterWatch.elapsedMilliseconds}',
    );
  }

  _SellerMappingScreenPreparedState _prepareInitialState() {
    final uniqueTdsParties =
        widget.tdsParties
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final exactMappingsByKey = <String, SellerMapping>{};
    final fallbackMappingsByAlias = <String, SellerMapping>{};

    for (final mapping in widget.existingMappings) {
      final aliasKey = normalizeName(mapping.aliasName.trim());
      final sectionCode = normalizeSellerMappingSectionCode(
        mapping.sectionCode,
      );
      if (aliasKey.isEmpty || mapping.mappedName.trim().isEmpty) continue;

      if (sectionCode == 'ALL') {
        fallbackMappingsByAlias[aliasKey] = mapping;
        continue;
      }

      exactMappingsByKey[_rowKey(aliasKey, sectionCode)] = mapping;
    }

    final rowDataBySection = <String, List<SellerMappingScreenRowData>>{
      for (final section in _sectionTabOrder)
        section: <SellerMappingScreenRowData>[],
    };

    for (final row in widget.purchaseRows) {
      final sectionCode = normalizeSellerMappingSectionCode(row.sectionCode);
      rowDataBySection.putIfAbsent(
        sectionCode,
        () => <SellerMappingScreenRowData>[],
      );
      rowDataBySection[sectionCode]!.add(row);
    }

    return _SellerMappingScreenPreparedState(
      buyerPan: widget.buyerPan,
      selectedSectionLabel: widget.selectedSectionLabel,
      isPreflightMode: _isPreflightMode,
      uniqueTdsParties: uniqueTdsParties,
      rowDataBySection: rowDataBySection,
      exactMappingsByKey: exactMappingsByKey,
      fallbackMappingsByAlias: fallbackMappingsByAlias,
    );
  }

  bool get _shouldUseComputeForViewModels =>
      !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _saveMappings() {
    final upserts = <Map<String, String>>[];
    final deleted = <Map<String, String>>[];
    final rowsToPersist = _mappingRowsBySectionCache.values
        .expand((rows) => rows)
        .toList();
    final dangerousRows = <String, SellerMappingRowVm>{};

    for (final row in rowsToPersist) {
      if (_isPreflightMode &&
          row.requiresDangerousReview &&
          !row.isPurchaseOnly) {
        dangerousRows[row.rowKey] = row;
      }

      final currentMappedName = selectedMappings[row.rowKey]?.trim() ?? '';
      final existingExactName = row.exactMapping?.mappedName.trim() ?? '';

      if (_isTimingDifferenceSelection(row, currentMappedName) ||
          _isMissingInBooksSelection(row, currentMappedName)) {
        upserts.add({
          'aliasName': row.normalizedAlias,
          'sectionCode': row.sectionCode,
          'mappedName': currentMappedName,
          'mappedPan': '',
        });
        continue;
      }

      if (_isLinkLedgerSelection(currentMappedName)) {
        final linkedRow = _linkedLedgerRowForSelection(
          sectionCode: row.sectionCode,
          selectedValue: currentMappedName,
        );
        if (linkedRow != null) {
          upserts.add({
            'aliasName': linkedRow.normalizedAlias,
            'sectionCode': row.sectionCode,
            'mappedName': row.purchasePartyDisplayName,
            'mappedPan': row.resolvedSuggestion?.mappedPan.trim() ?? '',
          });
          if (existingExactName.isNotEmpty) {
            deleted.add({
              'aliasName': row.normalizedAlias,
              'sectionCode': row.sectionCode,
            });
          }
        }
        continue;
      }

      if (row.is26QUnmatched) {
        if (existingExactName.isNotEmpty &&
            _clearedRowKeys.contains(row.rowKey)) {
          deleted.add({
            'aliasName': row.normalizedAlias,
            'sectionCode': row.sectionCode,
          });
        }
        continue;
      }

      if (row.isReadOnly) {
        continue;
      }
      final effectiveMappedName = currentMappedName;

      if (effectiveMappedName.isEmpty) {
        if (existingExactName.isNotEmpty &&
            _clearedRowKeys.contains(row.rowKey)) {
          deleted.add({
            'aliasName': row.normalizedAlias,
            'sectionCode': row.sectionCode,
          });
        }
        continue;
      }

      // In preflight mode, always upsert mapped rows so that the upload
      // screen's next preflight refresh sees the section-level saved alias
      // and suppresses any stale dangerous flags.
      if (effectiveMappedName == existingExactName && !_isPreflightMode) {
        continue;
      }

      upserts.add({
        'aliasName': row.normalizedAlias,
        'sectionCode': row.sectionCode,
        'mappedName': effectiveMappedName,
        'mappedPan': _isSeparateSelection(row, effectiveMappedName)
            ? row.purchasePan
            : _getPanForTdsParty(effectiveMappedName),
      });
    }

    final dangerousRowCount = dangerousRows.length;
    final dangerousSuggestionOnlyCount = dangerousRows.values.where((row) {
      if (_isDangerousRowExplicitlyResolved(row)) return false;
      final suggested = _normalizeToKnownTdsParty(
        row.resolvedSuggestion?.mappedName,
      );
      return suggested != null && suggested.trim().isNotEmpty;
    }).length;
    final dangerousExplicitlyResolvedCount = dangerousRows.values
        .where(_isDangerousRowExplicitlyResolved)
        .length;
    final dangerousRemaining = dangerousRows.values
        .where((row) => !_isDangerousRowExplicitlyResolved(row))
        .length;
    final unreviewedExceptionCount = _mappingRowsBySectionCache.values
        .expand((rows) => rows)
        .where((row) {
          if (!row.is26QUnmatched) {
            return false;
          }
          if (!_hasLedgerDataForSection(row.sectionCode)) {
            return false;
          }
          final selectedValue = selectedMappings[row.rowKey]?.trim() ?? '';
          return !_isReviewed26QDecision(row, selectedValue);
        })
        .length;

    debugPrint(
      'SELLER MAP PREFLIGHT STATE dangerousRows=$dangerousRowCount '
      'dangerousSuggestionOnly=$dangerousSuggestionOnlyCount '
      'dangerousExplicitlyResolved=$dangerousExplicitlyResolvedCount '
      'dangerousRemaining=$dangerousRemaining '
      'unreviewedExceptionCount=$unreviewedExceptionCount',
    );

    Navigator.pop(
      context,
      SellerMappingScreenResult(
        upserts: upserts,
        deleted: deleted,
        dangerousRemaining: dangerousRemaining,
        unreviewedExceptionCount: unreviewedExceptionCount,
        selectedMappings: Map<String, String>.from(selectedMappings),
        clearedRowKeys: Set<String>.from(_clearedRowKeys),
      ),
    );
  }

  List<SellerMappingSummaryMetric> _buildSummaryMetrics() {
    final visibleRows = _filteredRows();
    var mapped = 0;
    var unmapped = 0;
    var conflicts = 0;
    var verifyPan = 0;

    for (final row in visibleRows) {
      final state = _rowStateByKey[row.rowKey];
      if (state == null) continue;
      if (state.selectedValue != null &&
          state.selectedValue!.trim().isNotEmpty) {
        mapped++;
      }
      if (state.status == 'Unmapped') unmapped++;
      if (state.status == 'PAN Conflict' || state.status == 'Conflicting PAN') {
        conflicts++;
      }
      if (state.status == 'Mapped (PAN missing)') verifyPan++;
    }

    return [
      SellerMappingSummaryMetric(
        label: _activeListView == SellerMappingListView.allSellers
            ? 'Total'
            : 'Visible',
        value: visibleRows.length,
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF344054),
      ),
      SellerMappingSummaryMetric(
        label: 'Mapped',
        value: mapped,
        icon: Icons.link_rounded,
        color: SellerMappingTheme.successColor,
      ),
      SellerMappingSummaryMetric(
        label: 'Unmapped',
        value: unmapped,
        icon: Icons.hourglass_empty_rounded,
        color: SellerMappingTheme.warningColor,
      ),
      SellerMappingSummaryMetric(
        label: 'Conflicts',
        value: conflicts,
        icon: Icons.warning_amber_rounded,
        color: SellerMappingTheme.dangerColor,
      ),
      SellerMappingSummaryMetric(
        label: '26Q Unmatched',
        value: visibleRows.where((row) => row.is26QUnmatched).length,
        icon: Icons.link_off_rounded,
        color: const Color(0xFF7C3AED),
      ),
      SellerMappingSummaryMetric(
        label: 'Verify PAN',
        value: verifyPan,
        icon: Icons.rule_folder_outlined,
        color: SellerMappingTheme.warningColor,
      ),
    ];
  }

  int _needsActionCountForSection(String sectionCode) {
    return _rowsForSection(sectionCode).where((row) {
      final state = _rowStateByKey[row.rowKey];
      if (state == null) return false;

      if (_activeWorkspaceView == SellerMappingWorkspaceView.review) {
        return _matchesReviewVisibleFilters(row, state);
      }
      return _matchesWorkingVisibleFilters(row, state);
    }).length;
  }

  Iterable<SellerMappingRowVm> _allSectionRows() sync* {
    for (final sectionCode in _availableSectionCodes) {
      yield* _rowsForSection(sectionCode);
    }
  }

  int _dangerousUnresolvedCount() {
    return _allSectionRows().where((row) {
      final state = _rowStateByKey[row.rowKey];
      return state?.isUnresolvedDangerousPreflightRow ?? false;
    }).length;
  }

  int _unreviewedExceptionCount() {
    return _allSectionRows().where((row) {
      if (!row.is26QUnmatched) {
        return false;
      }
      if (!_hasLedgerDataForSection(row.sectionCode)) {
        return false;
      }
      final selectedValue = _rowStateByKey[row.rowKey]?.selectedValue;
      return !_isReviewed26QDecision(row, selectedValue);
    }).length;
  }

  bool _canContinue() {
    return _dangerousUnresolvedCount() == 0 && _unreviewedExceptionCount() == 0;
  }

  void _logAuditViewSnapshot() {
    debugPrint(
      'SELLER AUDIT SNAPSHOT => rawSourceRows=${widget.rawSourceRowCount} '
      'groupedSellers=${_rowsForCurrentViewScope().length} '
      'selectedSection=$_activeSectionCode '
      'needsActionCount=${_listViewCounts()[SellerMappingListView.needsAction] ?? 0} '
      'allSellersCount=${_listViewCounts()[SellerMappingListView.allSellers] ?? 0} '
      'dangerousUnresolved=${_dangerousUnresolvedCount()} '
      'unreviewedExceptionCount=${_unreviewedExceptionCount()}',
    );
  }

  AppStatusBadgeTone _statusTone(String status) {
    switch (status) {
      case 'Mapped':
        return AppStatusBadgeTone.success;
      case 'Marked Separate':
        return AppStatusBadgeTone.info;
      case 'Purchase Only':
        return AppStatusBadgeTone.neutral;
      case '26Q Unmatched':
        return AppStatusBadgeTone.warning;
      case 'Linked to Ledger':
      case 'Timing Difference':
      case 'Missing in Books':
        return AppStatusBadgeTone.info;
      case 'Conflicting PAN':
      case 'Ambiguous Identity':
      case 'Unresolved Identity':
      case 'Mapped (PAN missing)':
        return status == 'Mapped (PAN missing)'
            ? AppStatusBadgeTone.warning
            : AppStatusBadgeTone.danger;
      case 'PAN Conflict':
        return AppStatusBadgeTone.danger;
      default:
        return AppStatusBadgeTone.neutral;
    }
  }

  IconData _statusIconSafe(String status) {
    switch (status) {
      case 'Mapped':
        return Icons.check_circle_rounded;
      case 'Marked Separate':
        return Icons.account_tree_rounded;
      case 'Purchase Only':
        return Icons.store_outlined;
      case '26Q Unmatched':
        return Icons.link_off_rounded;
      case 'Linked to Ledger':
        return Icons.account_tree_rounded;
      case 'Timing Difference':
        return Icons.schedule_rounded;
      case 'Missing in Books':
        return Icons.bookmark_remove_rounded;
      case 'Conflicting PAN':
        return Icons.warning_rounded;
      case 'Ambiguous Identity':
        return Icons.help_center_rounded;
      case 'Unresolved Identity':
        return Icons.person_off_rounded;
      case 'Mapped (PAN missing)':
        return Icons.help_outline_rounded;
      case 'PAN Conflict':
        return Icons.error_outline_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Color _rowBackgroundColorSafe({required String status, required int index}) {
    final base = index.isEven ? Colors.white : const Color(0xFFFBFCFE);
    if (status == 'PAN Conflict' ||
        status == 'Conflicting PAN' ||
        status == 'Ambiguous Identity' ||
        status == 'Unresolved Identity') {
      return Color.alphaBlend(
        SellerMappingTheme.dangerColor.withValues(alpha: 0.08),
        base,
      );
    }
    if (status == '26Q Unmatched') {
      return Color.alphaBlend(
        const Color(0xFF7C3AED).withValues(alpha: 0.08),
        base,
      );
    }
    if (status == 'Linked to Ledger' ||
        status == 'Timing Difference' ||
        status == 'Missing in Books') {
      return Color.alphaBlend(
        const Color(0xFF2563EB).withValues(alpha: 0.06),
        base,
      );
    }
    if (status == 'Purchase Only') {
      return Color.alphaBlend(
        const Color(0xFF64748B).withValues(alpha: 0.05),
        base,
      );
    }
    if (status == 'Mapped (PAN missing)') {
      return Color.alphaBlend(
        SellerMappingTheme.warningColor.withValues(alpha: 0.08),
        base,
      );
    }
    return base;
  }

  List<String> _helperMessages({
    required SellerMappingRowVm row,
    required String status,
    required String? selectedValue,
  }) {
    if (_clearedRowKeys.contains(row.rowKey) &&
        (selectedValue == null || selectedValue.trim().isEmpty)) {
      return const <String>[];
    }

    final messages = <String>[];
    final autoMapDetail = autoMapDetails[row.rowKey];
    final fallbackName = row.fallbackMapping?.mappedName.trim() ?? '';
    final suggestion = row.resolvedSuggestion;
    final explicitSelectedValue = _getExplicitSelectedValue(row);

    if (explicitSelectedValue != null && autoMapDetail == null) {
      if (_isDangerousPreflightStatus(status)) {
        messages.add('Review this saved selection before reconciliation');
      } else if (status == 'Unmapped') {
        messages.add('Select a 26Q party for this alias and section');
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
        case 'tds_only':
          messages.add(
            '26Q seller is currently unmatched to any purchase alias',
          );
          break;
        case 'saved_exact':
        case 'saved_fallback':
        case 'backend_inferred':
        case 'preflight_resolved':
          break;
      }
      if (_isDangerousPreflightStatus(status) ||
          status == 'Unmapped' ||
          status == '26Q Unmatched') {
        messages.add(
          suggestion.helperText.trim().isNotEmpty
              ? suggestion.helperText.trim()
              : 'Visible as a suggestion only; save to store as exact section mapping',
        );
      }
    }

    if (status == '26Q Unmatched') {
      messages.add('Review the 26Q-only seller and link it manually if needed');
    } else if (status == 'Linked to Ledger') {
      messages.add(
        'This 26Q seller is linked to an existing same-section ledger seller.',
      );
    } else if (status == 'Timing Difference') {
      messages.add(
        'Reviewed exception: keep this 26Q seller out of the current books timing.',
      );
    } else if (status == 'Missing in Books') {
      messages.add(
        'Reviewed exception: this 26Q seller is classified as missing in books.',
      );
    } else if (status == 'Marked Separate') {
      messages.add('This seller will stay separate from 26Q after saving');
    } else if (_isPreflightMode &&
        row.preflightReasonDetail.trim().isNotEmpty &&
        _isDangerousPreflightStatus(status)) {
      messages.add(row.preflightReasonDetail.trim());
    } else if (status == 'PAN Conflict') {
      messages.add('Conflict: purchase PAN and 26Q PAN differ');
      if (explicitSelectedValue == null) {
        messages.add('Please Mark Separate or select a valid party');
      }
    } else if (status == 'Mapped (PAN missing)') {
      messages.add('Mapping exists, but PAN still needs manual verification');
    } else if (status == 'Unmapped') {
      if (fallbackName.isNotEmpty) {
        messages.add('Global fallback mapping available');
      } else {
        messages.add('Select a 26Q party for this alias and section');
      }
    } else if (selectedValue != null &&
        selectedValue.isNotEmpty &&
        _isDangerousPreflightStatus(status)) {
      messages.add('PAN verified against selected 26Q party');
    }

    if (fallbackName.isNotEmpty &&
        (row.exactMapping?.mappedName.trim() ?? '').isEmpty &&
        !messages.contains('Global fallback mapping available') &&
        (status == 'Unmapped' || _isDangerousPreflightStatus(status))) {
      messages.add('Global fallback mapping available');
    }

    return messages.take(2).toList();
  }

  Color _helperTextColor({
    required String status,
    required AutoMapDecision? autoMapDetail,
  }) {
    if (status == '26Q Unmatched') {
      return const Color(0xFF6D28D9);
    }
    if (status == 'Linked to Ledger' ||
        status == 'Timing Difference' ||
        status == 'Missing in Books') {
      return const Color(0xFF1D4ED8);
    }
    if (status == 'PAN Conflict' ||
        autoMapDetail?.blockedByPanConflict == true) {
      return SellerMappingTheme.dangerColor;
    }
    if (status == 'Mapped (PAN missing)' || autoMapDetail?.ambiguous == true) {
      return SellerMappingTheme.warningColor;
    }
    if (autoMapDetail?.selectedCandidate != null ||
        rowHasResolvedSuggestion(status, autoMapDetail) ||
        status == 'Mapped') {
      return const Color(0xFF335C9E);
    }
    return SellerMappingTheme.mutedTextColor;
  }

  bool rowHasResolvedSuggestion(String status, AutoMapDecision? autoMapDetail) {
    return autoMapDetail == null &&
        (status == 'Mapped' || status == 'Mapped (PAN missing)');
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: SellerMappingTheme.surfaceColor,
        border: const Border(
          bottom: BorderSide(color: SellerMappingTheme.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.maybePop(context),
                style: IconButton.styleFrom(
                  backgroundColor: SellerMappingTheme.primarySoft,
                  foregroundColor: SellerMappingTheme.primaryColor,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seller Mapping Audit',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: SellerMappingTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.buyerName.trim().isEmpty
                          ? 'Unnamed Buyer'
                          : widget.buyerName.trim(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: SellerMappingTheme.titleTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<SellerMappingListView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: SellerMappingListView.needsAction,
                    label: Text('Needs Action'),
                  ),
                  ButtonSegment(
                    value: SellerMappingListView.allSellers,
                    label: Text('All Sellers'),
                  ),
                ],
                selected: <SellerMappingListView>{_activeListView},
                onSelectionChanged: (selection) {
                  setState(() {
                    _activeListView = selection.first;
                    _invalidateViewCaches(resetPage: true);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SellerMappingPill(
                icon: Icons.badge_outlined,
                label: widget.buyerPan.trim().isEmpty
                    ? 'PAN unavailable'
                    : widget.buyerPan.trim().toUpperCase(),
              ),
              if (widget.buyerGstNo.trim().isNotEmpty)
                SellerMappingPill(
                  icon: Icons.receipt_long_outlined,
                  label: widget.buyerGstNo.trim().toUpperCase(),
                ),
              if (widget.financialYearLabel.trim().isNotEmpty)
                SellerMappingPill(
                  icon: Icons.calendar_today_outlined,
                  label: widget.financialYearLabel.trim(),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableSectionCodes.map((sectionCode) {
                    final isSelected = _activeSectionCode == sectionCode;
                    final count = _needsActionCountForSection(sectionCode);
                    return ChoiceChip(
                      label: Text(
                        '${sectionDisplayLabel(sectionCode)}($count)',
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _activeSectionCode = sectionCode;
                          _invalidateViewCaches(resetPage: true);
                        });
                      },
                      selectedColor: SellerMappingTheme.primarySoft,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? SellerMappingTheme.primaryColor
                            : SellerMappingTheme.borderColor,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? SellerMappingTheme.primaryColor
                            : SellerMappingTheme.titleTextColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: _buildSummaryMetrics()
                    .where((metric) => metric.value > 0)
                    .map((metric) => SellerMappingMetricCard(metric: metric))
                    .toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: SellerMappingTheme.surfaceColor,
        border: const Border(
          bottom: BorderSide(color: SellerMappingTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                if (_searchDebounce?.isActive ?? false) {
                  _searchDebounce!.cancel();
                }
                _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                  setState(() {
                    _searchQuery = value;
                    _invalidateViewCaches(resetPage: true);
                  });
                });
              },
              decoration: InputDecoration(
                hintText: 'Search party, PAN, section or mapped 26Q party',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _invalidateViewCaches(resetPage: true);
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: SellerMappingTheme.borderColor,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: SellerMappingTheme.borderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: SellerMappingTheme.primaryColor,
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 270,
            child: SegmentedButton<SellerMappingWorkspaceView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: SellerMappingWorkspaceView.working,
                  label: Text('Working View'),
                  icon: Icon(Icons.compare_arrows_rounded, size: 18),
                ),
                ButtonSegment(
                  value: SellerMappingWorkspaceView.review,
                  label: Text('Review View'),
                  icon: Icon(Icons.fact_check_outlined, size: 18),
                ),
              ],
              selected: <SellerMappingWorkspaceView>{_activeWorkspaceView},
              onSelectionChanged: (selection) {
                setState(() {
                  _activeWorkspaceView = selection.first;
                  _invalidateViewCaches(resetPage: true);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 210,
            child: AppCompactSelectField(
              value: _statusFilter,
              labelText: 'Status',
              options: const [
                'All',
                'Mapped',
                'Unmapped',
                'Only in Ledger',
                'Conflict',
                'Timing Difference',
                'Missing in Books',
              ],
              onChanged: (value) {
                setState(() {
                  _statusFilter = value;
                  _invalidateViewCaches(resetPage: true);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _applyAutoMap,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Auto Map'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _clearVisibleMappings,
            icon: const Icon(Icons.layers_clear_rounded),
            label: const Text('Clear Visible'),
          ),
        ],
      ),
    );
  }

  void _setMappedParty(SellerMappingRowVm row, String? value) {
    if (row.isReadOnly && !row.is26QUnmatched) return;
    setState(() {
      autoMapDetails.remove(row.rowKey);
      final normalizedValue = _normalizeToKnownTdsParty(value)?.trim() ?? '';
      if (normalizedValue.isEmpty) {
        _clearedRowKeys.add(row.rowKey);
        selectedMappings.remove(row.rowKey);
      } else {
        _clearedRowKeys.remove(row.rowKey);
        selectedMappings[row.rowKey] = normalizedValue;
      }
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  List<_LedgerLinkOption> _ledgerLinkOptionsForSection(String sectionCode) {
    final candidateRows = <SellerMappingRowVm>[];
    final seenRowKeys = <String>{};
    final displayNameCounts = <String, int>{};

    for (final row in _rowsForSection(sectionCode)) {
      if (row.is26QUnmatched || !seenRowKeys.add(row.rowKey)) {
        continue;
      }
      if (row.sourceRowCount <= 0) {
        debugPrint(
          'SELLER UI WARN => candidate source contains non-ledger row '
          'rowKey=${row.rowKey} section=${row.sectionCode}',
        );
        continue;
      }
      candidateRows.add(row);
      final displayName = resolveLedgerSellerTitle(row);
      displayNameCounts[displayName] =
          (displayNameCounts[displayName] ?? 0) + 1;
    }

    final options =
        candidateRows.map((row) {
          final displayName = resolveLedgerSellerTitle(row);
          final identityParts = <String>[
            'Alias ${row.normalizedAlias}',
            if (row.purchasePan.isNotEmpty) 'PAN ${row.purchasePan}',
            if (row.purchaseGstNo.isNotEmpty) 'GST ${row.purchaseGstNo}',
          ];
          final subtitle = identityParts.join(' | ');
          final displayValue = (displayNameCounts[displayName] ?? 0) > 1
              ? '$displayName ($subtitle)'
              : displayName;
          return _LedgerLinkOption(
            linkedRowKey: row.rowKey,
            displayValue: displayValue,
            subtitle: subtitle,
            searchableTerms: <String>[
              displayName,
              row.normalizedAlias,
              row.purchasePan,
              row.purchaseGstNo,
              sectionDisplayLabel(row.sectionCode),
            ],
          );
        }).toList()..sort(
          (a, b) => sellerMappingSafeText(
            a.displayValue,
          ).compareTo(sellerMappingSafeText(b.displayValue)),
        );

    return options;
  }

  _LedgerLinkOption? _ledgerLinkOptionByDisplayValue({
    required String sectionCode,
    required String displayValue,
  }) {
    for (final option in _ledgerLinkOptionsForSection(sectionCode)) {
      if (option.displayValue == displayValue) {
        return option;
      }
    }
    return null;
  }

  String _linkedLedgerLabel(SellerMappingRowVm row, Object? selectedValue) {
    final linkedRow = _linkedLedgerRowForSelection(
      sectionCode: row.sectionCode,
      selectedValue: selectedValue,
    );
    if (linkedRow == null) {
      return '';
    }
    for (final option in _ledgerLinkOptionsForSection(row.sectionCode)) {
      if (option.linkedRowKey == linkedRow.rowKey) {
        return option.displayValue;
      }
    }
    return resolveLedgerSellerTitle(linkedRow);
  }

  void _setLinkedLedgerSeller(SellerMappingRowVm row, String? displayValue) {
    final option = displayValue == null
        ? null
        : _ledgerLinkOptionByDisplayValue(
            sectionCode: row.sectionCode,
            displayValue: displayValue,
          );
    setState(() {
      autoMapDetails.remove(row.rowKey);
      if (option == null) {
        _clearedRowKeys.add(row.rowKey);
        selectedMappings.remove(row.rowKey);
      } else {
        _clearedRowKeys.remove(row.rowKey);
        selectedMappings[row.rowKey] = _linkLedgerValue(option.linkedRowKey);
      }
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  void _linkToLedgerRow(SellerMappingRowVm row, SellerMappingRowVm ledgerRow) {
    setState(() {
      autoMapDetails.remove(row.rowKey);
      _clearedRowKeys.remove(row.rowKey);
      selectedMappings[row.rowKey] = _linkLedgerValue(ledgerRow.rowKey);
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  void _setExceptionDecision(SellerMappingRowVm row, String? value) {
    setState(() {
      autoMapDetails.remove(row.rowKey);
      if (value == null || value.isEmpty) {
        _clearedRowKeys.add(row.rowKey);
        selectedMappings.remove(row.rowKey);
      } else {
        _clearedRowKeys.remove(row.rowKey);
        selectedMappings[row.rowKey] = value;
      }
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  bool _canAcceptSuggestion(SellerMappingRowVm row) {
    if (_getExplicitSelectedValue(row) != null) return false;

    final suggested = _normalizeToKnownTdsParty(
      row.resolvedSuggestion?.mappedName,
    );
    if (suggested == null || suggested.trim().isEmpty) return false;

    final statusIfAccepted = _getStatus(row: row, selectedValue: suggested);
    if (_isDangerousPreflightStatus(statusIfAccepted)) return false;

    return true;
  }

  void _acceptSuggestedMapping(SellerMappingRowVm row) {
    final suggested = _normalizeToKnownTdsParty(
      row.resolvedSuggestion?.mappedName,
    );
    if (suggested == null || suggested.trim().isEmpty) return;
    _setMappedParty(row, suggested);
  }

  void _markSeparate(SellerMappingRowVm row) {
    if (row.isReadOnly) return;
    setState(() {
      autoMapDetails.remove(row.rowKey);
      _clearedRowKeys.remove(row.rowKey);
      selectedMappings[row.rowKey] = _separateSelectionValue(row);
      _rebuildDerivedRowStateCache();
      _invalidateViewCaches();
    });
  }

  Widget _buildPartyAutocomplete({
    required SellerMappingRowVm row,
    required String? selectedValue,
  }) {
    if (row.is26QUnmatched) {
      final ledgerLinkOptions = _ledgerLinkOptionsForSection(row.sectionCode);
      return AppSearchAutocompleteField(
        key: ValueKey('${row.rowKey}|ledger|${selectedValue ?? ''}'),
        value: _linkedLedgerLabel(row, selectedValue),
        options: ledgerLinkOptions
            .map((option) => option.displayValue)
            .toList(),
        hintText: 'Link to existing ledger seller',
        allowFreeText: false,
        maxVisibleOptions: 8,
        optionsMaxHeight: 320,
        searchableTermsBuilder: (option) {
          final match = _ledgerLinkOptionByDisplayValue(
            sectionCode: row.sectionCode,
            displayValue: option,
          );
          return match?.searchableTerms ?? <String>[option];
        },
        optionSubtitleBuilder: (option) {
          return _ledgerLinkOptionByDisplayValue(
            sectionCode: row.sectionCode,
            displayValue: option,
          )?.subtitle;
        },
        decoration: InputDecoration(
          hintText: 'Select same-section ledger seller',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SellerMappingTheme.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SellerMappingTheme.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: SellerMappingTheme.primaryColor,
              width: 1.2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.trim().isEmpty) {
            _setLinkedLedgerSeller(row, null);
          }
        },
        onSelected: (value) => _setLinkedLedgerSeller(row, value),
      );
    }

    if (row.isReadOnly) {
      final displayValue = selectedValue?.trim().isNotEmpty == true
          ? selectedValue!.trim()
          : 'No purchase alias linked';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SellerMappingTheme.borderColor),
        ),
        child: Text(
          displayValue,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: SellerMappingTheme.titleTextColor,
          ),
        ),
      );
    }

    return AppSearchAutocompleteField(
      key: ValueKey('${row.rowKey}|${selectedValue ?? ''}'),
      value: selectedValue ?? '',
      options: uniqueTdsParties,
      hintText: 'Search 26Q party or PAN...',
      allowFreeText: false,
      maxVisibleOptions: 8,
      optionsMaxHeight: 340,
      searchableTermsBuilder: (option) => <String>[
        option,
        _getPanForTdsParty(option),
      ],
      optionSubtitleBuilder: (option) {
        final pan = _getPanForTdsParty(option);
        return pan.isEmpty ? 'PAN not available' : 'PAN: $pan';
      },
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
          borderSide: const BorderSide(color: SellerMappingTheme.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SellerMappingTheme.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SellerMappingTheme.primaryColor,
            width: 1.2,
          ),
        ),
      ),
      onChanged: (value) {
        if (value.trim().isEmpty) {
          _setMappedParty(row, null);
          return;
        }

        final exactMatch = _normalizeToKnownTdsParty(value);
        if (exactMatch != null) {
          _setMappedParty(row, exactMatch);
        }
      },
      onSelected: (value) => _setMappedParty(row, value),
    );
  }

  bool _hasExplicitSelection(SellerMappingRowVm row, String? selectedValue) {
    final explicit = _getExplicitSelectedValue(row);
    if (explicit == null || explicit.trim().isEmpty) {
      return false;
    }
    if (row.is26QUnmatched) {
      return explicit == selectedValue;
    }
    return !_isSeparateSelection(row, explicit) || explicit == selectedValue;
  }

  bool _canSkipSafely(SellerMappingRowVm row, String status) {
    if (row.is26QUnmatched || row.requiresDangerousReview) {
      return false;
    }
    return status == 'Mapped' ||
        status == 'Mapped (PAN missing)' ||
        status == 'Purchase Only';
  }

  Widget _buildRoundActionIcon({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback? onPressed,
    Color activeColor = SellerMappingTheme.primaryColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: isActive ? activeColor : Colors.white,
          foregroundColor: isActive ? Colors.white : activeColor,
          disabledBackgroundColor: const Color(0xFFF1F5F9),
          disabledForegroundColor: const Color(0xFF94A3B8),
          side: BorderSide(
            color: isActive ? activeColor : SellerMappingTheme.borderColor,
          ),
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(10),
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildSellerCard({
    required SellerMappingRowVm row,
    required int index,
  }) {
    final rowView = _buildDisplayRowView(
      row: row,
      index: index,
      isLast: index == _filteredRows().length - 1,
    );
    final selectedValue = rowView.selectedValue;
    final status = rowView.status;
    final sectionLabel = sectionDisplayLabel(row.sectionCode);
    final suggestion = row.resolvedSuggestion?.mappedName.trim() ?? '';
    final issueTone = _statusTone(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _rowBackgroundColorSafe(status: status, index: index),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SellerMappingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.purchasePartyDisplayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: SellerMappingTheme.titleTextColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SellerMappingPill(
                          icon: Icons.grid_view_rounded,
                          label: sectionLabel,
                          compact: true,
                        ),
                        if (row.purchasePan.isNotEmpty)
                          SellerMappingPill(
                            icon: Icons.badge_outlined,
                            label: row.purchasePan,
                            compact: true,
                          ),
                        if (row.purchaseGstNo.isNotEmpty)
                          SellerMappingPill(
                            icon: Icons.receipt_long_outlined,
                            label: row.purchaseGstNo,
                            compact: true,
                          ),
                        SellerMappingStatusChip(
                          icon: _statusIconSafe(status),
                          label: _statusChipLabel(status, row: row),
                          tone: issueTone,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildRoundActionIcon(
                    icon: Icons.auto_awesome_rounded,
                    tooltip: 'Accept suggested match',
                    isActive:
                        !row.is26QUnmatched &&
                        selectedValue ==
                            _normalizeToKnownTdsParty(
                              row.resolvedSuggestion?.mappedName,
                            ),
                    onPressed: _canAcceptSuggestion(row)
                        ? () => _acceptSuggestedMapping(row)
                        : null,
                  ),
                  _buildRoundActionIcon(
                    icon: Icons.account_tree_rounded,
                    tooltip: 'Treat as separate seller',
                    isActive: _isSeparateSelection(row, selectedValue),
                    onPressed: row.is26QUnmatched || row.isReadOnly
                        ? null
                        : () => _markSeparate(row),
                    activeColor: const Color(0xFF7C3AED),
                  ),
                  _buildRoundActionIcon(
                    icon: Icons.task_alt_rounded,
                    tooltip: 'Keep current mapping',
                    isActive: _hasExplicitSelection(row, selectedValue),
                    onPressed:
                        (!row.is26QUnmatched &&
                            selectedValue != null &&
                            selectedValue.trim().isNotEmpty &&
                            !_isSeparateSelection(row, selectedValue))
                        ? () => _setMappedParty(row, selectedValue)
                        : null,
                    activeColor: SellerMappingTheme.successColor,
                  ),
                  _buildRoundActionIcon(
                    icon: Icons.schedule_outlined,
                    tooltip: 'Review later',
                    isActive: false,
                    onPressed: _canSkipSafely(row, status)
                        ? () => _clearMapping(row)
                        : null,
                    activeColor: SellerMappingTheme.warningColor,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SellerMappingPill(
                icon: Icons.format_list_numbered_rounded,
                label: '26Q rows ${row.tdsRowCount}',
                compact: true,
              ),
              SellerMappingPill(
                icon: Icons.source_outlined,
                label: 'Source rows ${row.sourceRowCount}',
                compact: true,
              ),
              if (suggestion.isNotEmpty)
                SellerMappingPill(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'Suggested: $suggestion',
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPartyAutocomplete(row: row, selectedValue: selectedValue),
          if (row.is26QUnmatched) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRoundActionIcon(
                  icon: Icons.schedule_rounded,
                  tooltip: 'Mark as Timing Difference',
                  isActive: _isTimingDifferenceSelection(row, selectedValue),
                  onPressed: () =>
                      _setExceptionDecision(row, _timingDifferenceValue(row)),
                  activeColor: SellerMappingTheme.warningColor,
                ),
                _buildRoundActionIcon(
                  icon: Icons.bookmark_remove_rounded,
                  tooltip: 'Mark as Missing in Books',
                  isActive: _isMissingInBooksSelection(row, selectedValue),
                  onPressed: () =>
                      _setExceptionDecision(row, _missingInBooksValue(row)),
                  activeColor: SellerMappingTheme.dangerColor,
                ),
                _buildRoundActionIcon(
                  icon: Icons.restart_alt_rounded,
                  tooltip: 'Clear exception decision',
                  isActive: false,
                  onPressed: () => _clearMapping(row),
                  activeColor: SellerMappingTheme.mutedTextColor,
                ),
              ],
            ),
          ],
          if (rowView.helperMessages.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              rowView.helperMessages.join(' '),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _helperTextColor(
                  status: status,
                  autoMapDetail: rowView.autoMapDetail,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final showNeedsActionState =
        _isPreflightMode &&
        _activeListView == SellerMappingListView.needsAction &&
        _searchQuery.trim().isEmpty &&
        _statusFilter == 'All';

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
                color: SellerMappingTheme.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.manage_search_rounded,
                size: 34,
                color: SellerMappingTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              showNeedsActionState
                  ? 'No sellers currently need action'
                  : 'No seller rows match the current filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: SellerMappingTheme.titleTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showNeedsActionState
                  ? 'Needs Action is empty right now. Switch views only if you want to inspect additional sellers.'
                  : 'Try clearing search or switching the status filter to see more mapping rows.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: SellerMappingTheme.mutedTextColor,
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _statusFilter = 'All';
                  _invalidateViewCaches(resetPage: true);
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

  Widget _buildTableSection(List<SellerMappingRowVm> visibleRows) {
    final activeSectionRows = _rowsForActiveSection();
    final ledgerCandidateRows = activeSectionRows
        .where((row) {
          if (row.sourceRowCount > 0) {
            return true;
          }
          if (!row.is26QUnmatched) {
            debugPrint(
              'SELLER UI WARN => candidate source contains non-ledger row '
              'rowKey=${row.rowKey} section=${row.sectionCode}',
            );
          }
          return false;
        })
        .toList(growable: false);

    return SellerMappingTwoPanelBody(
      visibleRows: visibleRows,
      ledgerCandidateRows: ledgerCandidateRows,
      searchQuery: _searchQuery,
      showAllSellersMode: _activeListView == SellerMappingListView.allSellers,
      tdsParties: uniqueTdsParties,
      tdsPartyPans: widget.tdsPartyPans,
      selectedValueForRow: _getSelectedValue,
      selectedPanForRow: (row) =>
          _getPanForSelection(row, _getSelectedValue(row)),
      statusForRow: (row) =>
          _getStatus(row: row, selectedValue: _getSelectedValue(row)),
      helperMessagesForRow: (row) {
        final selectedValue = _getSelectedValue(row);
        final status = _getStatus(row: row, selectedValue: selectedValue);
        return _helperMessages(
          row: row,
          status: status,
          selectedValue: selectedValue,
        );
      },
      canAcceptSuggestion: _canAcceptSuggestion,
      onAcceptSuggestion: _acceptSuggestedMapping,
      onLinkToTds: _setMappedParty,
      onLinkToLedgerRow: _linkToLedgerRow,
      onKeepSeparate: _markSeparate,
      onClear: _clearMapping,
      onMarkTimingDifference: (row) =>
          _setExceptionDecision(row, _timingDifferenceValue(row)),
      onMarkMissingInBooks: (row) =>
          _setExceptionDecision(row, _missingInBooksValue(row)),
    );
  }

  Widget _buildBottomBar(List<SellerMappingRowVm> visibleRows) {
    final dangerousCount = _dangerousUnresolvedCount();
    final unreviewedExceptionCount = _unreviewedExceptionCount();
    final canContinue = _canContinue();
    final totalReviewSellers = _rowsForCurrentViewScope()
        .where(_is26QAuditRow)
        .length;
    final summaryText =
        '${visibleRows.length} visible of $totalReviewSellers review sellers in ${sectionDisplayLabel(_activeSectionCode)}.';
    final reviewText = canContinue
        ? 'All blocking identities and unmatched 26Q exceptions are reviewed.'
        : '$dangerousCount dangerous identity ${dangerousCount == 1 ? 'issue remains' : 'issues remain'} and '
              '$unreviewedExceptionCount unmatched 26Q ${unreviewedExceptionCount == 1 ? 'exception is' : 'exceptions are'} still unreviewed.';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
        decoration: BoxDecoration(
          color: SellerMappingTheme.surfaceColor.withValues(alpha: 0.96),
          border: const Border(
            top: BorderSide(color: SellerMappingTheme.borderColor),
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
                      color: SellerMappingTheme.titleTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reviewText,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: canContinue
                          ? SellerMappingTheme.successColor
                          : SellerMappingTheme.dangerColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: canContinue ? _saveMappings : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                backgroundColor: SellerMappingTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Save & Continue'),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesListViewFromState(
    _SellerFilterRowState state,
    SellerMappingListView view,
  ) {
    switch (view) {
      case SellerMappingListView.needsAction:
        return state.matchesNeedsAction;
      case SellerMappingListView.allSellers:
        return true;
    }
  }

  Map<SellerMappingListView, int> _listViewCounts() {
    if (_cachedListViewCounts != null) return _cachedListViewCounts!;
    final stopwatch = Stopwatch()..start();
    final counts = <SellerMappingListView, int>{
      for (final view in SellerMappingListView.values) view: 0,
    };
    for (final view in SellerMappingListView.values) {
      final rowsForView = _rowsForActiveSection()
          .where(_is26QAuditRow)
          .toList(growable: false);
      for (final row in rowsForView) {
        final state = _rowStateByKey[row.rowKey];
        if (state != null && _matchesListViewFromState(state, view)) {
          counts[view] = (counts[view] ?? 0) + 1;
        }
      }
    }
    stopwatch.stop();
    _cachedListViewCounts = counts;
    debugPrint(
      'SELLER FILTER PERF => listCountsMs=${stopwatch.elapsedMilliseconds} '
      'section=$_activeSectionCode view=${_activeListView.name}',
    );
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        try {
          return _buildSellerMappingScaffold(context);
        } catch (e, st) {
          debugPrint('SELLER CRASH => $e');
          debugPrint('$st');
          return const Scaffold(body: Center(child: Text('UI Error')));
        }
      },
    );
  }

  Widget _buildSellerMappingScaffold(BuildContext context) {
    if (_isInitializing) {
      return _buildLoadingScaffold();
    }

    final allFiltered =
        _activeWorkspaceView == SellerMappingWorkspaceView.review
        ? _reviewFilteredRows()
        : _filteredRows();
    final visibleCount = math.min(_visibleRowLimit, allFiltered.length);
    final visibleRows = allFiltered.isNotEmpty
        ? allFiltered.sublist(0, visibleCount)
        : <SellerMappingRowVm>[];
    _logAuditViewSnapshot();
    debugPrint(
      'SELLER ROW BUILD PERF => visibleRows=$visibleCount totalFiltered=${allFiltered.length} mode=lazy',
    );

    final stopwatch = Stopwatch()..start();

    final body = Scaffold(
      backgroundColor: SellerMappingTheme.pageBackground,
      bottomNavigationBar: _buildBottomBar(allFiltered),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTopToolbar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  children: [
                    Expanded(
                      child:
                          _activeWorkspaceView ==
                              SellerMappingWorkspaceView.review
                          ? SellerMappingReviewView(
                              rows: allFiltered,
                              allRowsForSection: _rowsForActiveSection(),
                              activeSectionLabel: sectionDisplayLabel(
                                _activeSectionCode,
                              ),
                              statusForRow: (row) {
                                final state = _rowStateByKey[row.rowKey];
                                return state?.status ??
                                    _getStatus(
                                      row: row,
                                      selectedValue: _getSelectedValue(row),
                                    );
                              },
                              selectedValueForRow: _getSelectedValue,
                              selectedPanForRow: (row) => _getPanForSelection(
                                row,
                                _getSelectedValue(row),
                              ),
                              linkedLedgerRowForRow: (row) =>
                                  _linkedLedgerRowForSelection(
                                    sectionCode: row.sectionCode,
                                    selectedValue: _getSelectedValue(row),
                                  ),
                            )
                          : _buildTableSection(visibleRows),
                    ),
                    if (_activeWorkspaceView ==
                            SellerMappingWorkspaceView.working &&
                        visibleCount < allFiltered.length)
                      _buildLoadMore(allFiltered),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    stopwatch.stop();
    debugPrint(
      'SELLER MAP PERF pageMs=${stopwatch.elapsedMilliseconds} rowsRendered=${visibleRows.length}',
    );

    return body;
  }

  Widget _buildLoadMore(List<SellerMappingRowVm> allFiltered) {
    final remaining = math.max(allFiltered.length - _visibleRowLimit, 0);
    final nextLoadCount = math.min(_visibleRowIncrement, remaining);

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        children: [
          Text(
            'Showing ${math.min(_visibleRowLimit, allFiltered.length)} of ${allFiltered.length} seller rows.',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: SellerMappingTheme.mutedTextColor,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              setState(() {
                _visibleRowLimit += _visibleRowIncrement;
              });
            },
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(
              nextLoadCount > 0 ? 'Load More ($nextLoadCount)' : 'Load More',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScaffold() {
    return Scaffold(
      backgroundColor: SellerMappingTheme.pageBackground,
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: SellerMappingTheme.surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SellerMappingTheme.borderColor),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                SizedBox(height: 16),
                Text(
                  'Preparing seller mapping review...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SellerMappingTheme.titleTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerMappingScreenPreparedState {
  final String buyerPan;
  final String selectedSectionLabel;
  final bool isPreflightMode;
  final List<String> uniqueTdsParties;
  final Map<String, List<SellerMappingScreenRowData>> rowDataBySection;
  final Map<String, SellerMapping> exactMappingsByKey;
  final Map<String, SellerMapping> fallbackMappingsByAlias;

  const _SellerMappingScreenPreparedState({
    required this.buyerPan,
    required this.selectedSectionLabel,
    required this.isPreflightMode,
    required this.uniqueTdsParties,
    required this.rowDataBySection,
    required this.exactMappingsByKey,
    required this.fallbackMappingsByAlias,
  });

  Map<String, dynamic> toIsolatePayload() {
    return {
      'buyerPan': buyerPan,
      'selectedSectionLabel': selectedSectionLabel,
      'isPreflightMode': isPreflightMode,
      'uniqueTdsParties': uniqueTdsParties,
      'rowDataBySection': {
        for (final entry in rowDataBySection.entries)
          entry.key: entry.value.map(_serializeScreenRowForIsolate).toList(),
      },
      'exactMappingsByKey': {
        for (final entry in exactMappingsByKey.entries)
          entry.key: _serializeSellerMappingForIsolate(entry.value),
      },
      'fallbackMappingsByAlias': {
        for (final entry in fallbackMappingsByAlias.entries)
          entry.key: _serializeSellerMappingForIsolate(entry.value),
      },
    };
  }
}

class _SellerMappingScreenReadyState {
  final Map<String, List<SellerMappingRowVm>> mappingRowsBySection;
  final Map<String, String> selectedMappings;
  final String activeSectionCode;

  const _SellerMappingScreenReadyState({
    required this.mappingRowsBySection,
    required this.selectedMappings,
    required this.activeSectionCode,
  });

  factory _SellerMappingScreenReadyState.fromIsolatePayload(
    Map<String, dynamic> payload,
  ) {
    final mappingRowsBySection = <String, List<SellerMappingRowVm>>{};
    final rawMappingRows = Map<String, dynamic>.from(
      payload['mappingRowsBySection'] as Map? ?? const {},
    );
    for (final entry in rawMappingRows.entries) {
      mappingRowsBySection[entry.key] = List<Map<String, dynamic>>.from(
        entry.value as List? ?? const [],
      ).map(_deserializeRowVmForIsolate).toList();
    }

    return _SellerMappingScreenReadyState(
      mappingRowsBySection: mappingRowsBySection,
      selectedMappings: Map<String, String>.from(
        payload['selectedMappings'] as Map? ?? const {},
      ),
      activeSectionCode: payload['activeSectionCode'] as String? ?? '194Q',
    );
  }
}

Map<String, dynamic> _buildSellerScreenViewModelsInIsolate(
  Map<String, dynamic> payload,
) {
  final buyerPan = payload['buyerPan'] as String? ?? '';
  final selectedSectionLabel = payload['selectedSectionLabel'] as String? ?? '';
  final uniqueTdsParties = List<String>.from(
    payload['uniqueTdsParties'] as List? ?? const <String>[],
  );

  final rowDataBySection = <String, List<SellerMappingScreenRowData>>{};
  final rawRowDataBySection = Map<String, dynamic>.from(
    payload['rowDataBySection'] as Map? ?? const {},
  );
  for (final entry in rawRowDataBySection.entries) {
    rowDataBySection[entry.key] = List<Map<String, dynamic>>.from(
      entry.value as List? ?? const [],
    ).map(_deserializeScreenRowForIsolate).toList();
  }

  final exactMappingsByKey = <String, SellerMapping>{};
  final rawExactMappings = Map<String, dynamic>.from(
    payload['exactMappingsByKey'] as Map? ?? const {},
  );
  for (final entry in rawExactMappings.entries) {
    exactMappingsByKey[entry.key] = _deserializeSellerMappingForIsolate(
      Map<String, dynamic>.from(entry.value as Map),
    );
  }

  final fallbackMappingsByAlias = <String, SellerMapping>{};
  final rawFallbackMappings = Map<String, dynamic>.from(
    payload['fallbackMappingsByAlias'] as Map? ?? const {},
  );
  for (final entry in rawFallbackMappings.entries) {
    fallbackMappingsByAlias[entry.key] = _deserializeSellerMappingForIsolate(
      Map<String, dynamic>.from(entry.value as Map),
    );
  }

  final availableSectionCodes = _availableSectionCodesForIsolate(
    rowDataBySection: rowDataBySection,
  );
  final selectedMappings = <String, String>{};
  final mappingRowsBySection = <String, List<SellerMappingRowVm>>{};

  for (final sectionCode in availableSectionCodes) {
    mappingRowsBySection[sectionCode] = _buildRowsForSectionInIsolate(
      buyerPan: buyerPan,
      sectionCode: sectionCode,
      rowDataBySection: rowDataBySection,
      exactMappingsByKey: exactMappingsByKey,
      fallbackMappingsByAlias: fallbackMappingsByAlias,
    );
  }

  for (final sectionCode in availableSectionCodes) {
    for (final row in mappingRowsBySection[sectionCode] ?? const []) {
      final exactMappedName = row.exactMapping?.mappedName.trim() ?? '';
      if (exactMappedName.toUpperCase().startsWith(
            _SellerMappingScreenState._separatePrefix,
          ) ||
          exactMappedName.toUpperCase().startsWith(
            _SellerMappingScreenState._timingDifferencePrefix,
          ) ||
          exactMappedName.toUpperCase().startsWith(
            _SellerMappingScreenState._missingInBooksPrefix,
          )) {
        selectedMappings[row.rowKey] = exactMappedName;
        continue;
      }
      final hydratedValue =
          _normalizeToKnownTdsPartyForIsolate(
            uniqueTdsParties,
            row.exactMapping?.mappedName,
          ) ??
          _normalizeToKnownTdsPartyForIsolate(
            uniqueTdsParties,
            row.fallbackMapping?.mappedName,
          );
      if (hydratedValue == null || hydratedValue.trim().isEmpty) continue;
      selectedMappings[row.rowKey] = hydratedValue.trim();
    }
  }

  final preferredSection = normalizeSellerMappingSectionCode(
    selectedSectionLabel.trim(),
  );
  final fallbackSection = availableSectionCodes.firstWhere(
    (sectionCode) => sectionCode != 'ALL',
    orElse: () =>
        availableSectionCodes.isNotEmpty ? availableSectionCodes.first : '194Q',
  );
  final canUsePreferredSection =
      availableSectionCodes.contains(preferredSection) &&
      preferredSection != 'ALL';

  return {
    'mappingRowsBySection': {
      for (final entry in mappingRowsBySection.entries)
        entry.key: entry.value.map(_serializeRowVmForIsolate).toList(),
    },
    'selectedMappings': selectedMappings,
    'activeSectionCode': canUsePreferredSection
        ? preferredSection
        : fallbackSection,
  };
}

List<String> _availableSectionCodesForIsolate({
  required Map<String, List<SellerMappingScreenRowData>> rowDataBySection,
}) {
  final presentSections = _SellerMappingScreenState._sectionTabOrder
      .where((section) => (rowDataBySection[section] ?? const []).isNotEmpty)
      .toList();
  return presentSections;
}

List<SellerMappingRowVm> _buildRowsForSectionInIsolate({
  required String buyerPan,
  required String sectionCode,
  required Map<String, List<SellerMappingScreenRowData>> rowDataBySection,
  required Map<String, SellerMapping> exactMappingsByKey,
  required Map<String, SellerMapping> fallbackMappingsByAlias,
}) {
  final sourceRows = List<SellerMappingScreenRowData>.from(
    rowDataBySection[sectionCode] ?? const [],
  );

  final builtRows = <SellerMappingRowVm>[];
  for (var index = 0; index < sourceRows.length; index++) {
    final row = sourceRows[index];
    final aliasKey = normalizeName(row.normalizedAlias.trim());
    final normalizedSection = normalizeSellerMappingSectionCode(
      row.sectionCode,
    );
    if (aliasKey.isEmpty) continue;

    final exactMappingKey =
        '${normalizePan(buyerPan)}|$aliasKey|$normalizedSection';
    final displayName = row.purchasePartyDisplayName.trim();
    final purchasePan = normalizePan(row.purchasePan);
    final tdsDisplayName = row.tdsDisplayName.trim();
    final tdsPan = normalizePan(row.tdsPan);

    builtRows.add(
      SellerMappingRowVm(
        purchasePartyDisplayName: displayName.isNotEmpty ? displayName : '',
        normalizedAlias: aliasKey,
        sectionCode: normalizedSection,
        rowIndex: index,
        tdsDisplayName: tdsDisplayName,
        tdsPan: tdsPan,
        purchasePan: purchasePan.isNotEmpty ? purchasePan : '',
        purchaseGstNo: row.purchaseGstNo.trim().isNotEmpty
            ? row.purchaseGstNo.trim()
            : '',
        sourceRowCount: row.sourceRowCount,
        tdsRowCount: row.tdsRowCount,
        exactMapping: exactMappingsByKey[exactMappingKey],
        fallbackMapping: fallbackMappingsByAlias[aliasKey],
        resolvedSuggestion: row.resolvedSuggestion,
        isReadOnly: row.isReadOnly,
        isAboveThreshold: row.isAboveThreshold,
        hasReconciliationMismatch: row.hasReconciliationMismatch,
        hasNameOrPanConflict: row.hasNameOrPanConflict,
        hasApplicableTdsImpact: row.hasApplicableTdsImpact,
        is26QUnmatched: row.is26QUnmatched,
        hasMissingOrUncertainPan: row.hasMissingOrUncertainPan,
        preflightReasonCode: row.preflightReasonCode.trim(),
        preflightReasonLabel: row.preflightReasonLabel.trim(),
        preflightReasonDetail: row.preflightReasonDetail.trim(),
        requiresDangerousReview: row.requiresDangerousReview,
        isPurchaseOnly: row.isPurchaseOnly,
      ),
    );
  }

  builtRows.sort((a, b) {
    final nameCompare = resolveTdsSellerTitle(
      a,
    ).compareTo(resolveTdsSellerTitle(b));
    if (nameCompare != 0) return nameCompare;
    return a.sectionCode.compareTo(b.sectionCode);
  });

  return builtRows;
}

String? _normalizeToKnownTdsPartyForIsolate(
  List<String> uniqueTdsParties,
  String? mappedName,
) {
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

Map<String, dynamic> _serializeSellerMappingForIsolate(SellerMapping mapping) {
  return {
    'id': mapping.id,
    'buyer_name': mapping.buyerName,
    'buyer_pan': mapping.buyerPan,
    'alias_name': mapping.aliasName,
    'section_code': mapping.sectionCode,
    'mapped_pan': mapping.mappedPan,
    'mapped_name': mapping.mappedName,
  };
}

SellerMapping _deserializeSellerMappingForIsolate(Map<String, dynamic> row) {
  return SellerMapping.fromMap(row);
}

Map<String, dynamic> _serializeScreenRowForIsolate(
  SellerMappingScreenRowData row,
) {
  return {
    'purchasePartyDisplayName': row.purchasePartyDisplayName,
    'normalizedAlias': row.normalizedAlias,
    'sectionCode': row.sectionCode,
    'tdsDisplayName': row.tdsDisplayName,
    'tdsPan': row.tdsPan,
    'purchasePan': row.purchasePan,
    'purchaseGstNo': row.purchaseGstNo,
    'sourceRowCount': row.sourceRowCount,
    'tdsRowCount': row.tdsRowCount,
    'resolvedSuggestion': row.resolvedSuggestion == null
        ? null
        : {
            'mappedName': row.resolvedSuggestion!.mappedName,
            'mappedPan': row.resolvedSuggestion!.mappedPan,
            'source': row.resolvedSuggestion!.source,
            'helperText': row.resolvedSuggestion!.helperText,
          },
    'isReadOnly': row.isReadOnly,
    'isAboveThreshold': row.isAboveThreshold,
    'hasReconciliationMismatch': row.hasReconciliationMismatch,
    'hasNameOrPanConflict': row.hasNameOrPanConflict,
    'hasApplicableTdsImpact': row.hasApplicableTdsImpact,
    'is26QUnmatched': row.is26QUnmatched,
    'hasMissingOrUncertainPan': row.hasMissingOrUncertainPan,
    'preflightReasonCode': row.preflightReasonCode,
    'preflightReasonLabel': row.preflightReasonLabel,
    'preflightReasonDetail': row.preflightReasonDetail,
    'requiresDangerousReview': row.requiresDangerousReview,
    'isPurchaseOnly': row.isPurchaseOnly,
  };
}

SellerMappingScreenRowData _deserializeScreenRowForIsolate(
  Map<String, dynamic> row,
) {
  final suggestion = row['resolvedSuggestion'] as Map?;
  return SellerMappingScreenRowData(
    purchasePartyDisplayName: row['purchasePartyDisplayName'] as String? ?? '',
    normalizedAlias: row['normalizedAlias'] as String? ?? '',
    sectionCode: row['sectionCode'] as String? ?? '',
    tdsDisplayName: row['tdsDisplayName'] as String? ?? '',
    tdsPan: row['tdsPan'] as String? ?? '',
    purchasePan: row['purchasePan'] as String? ?? '',
    purchaseGstNo: row['purchaseGstNo'] as String? ?? '',
    sourceRowCount: row['sourceRowCount'] as int? ?? 0,
    tdsRowCount: row['tdsRowCount'] as int? ?? 0,
    resolvedSuggestion: suggestion == null
        ? null
        : SellerMappingResolvedSuggestion(
            mappedName: suggestion['mappedName'] as String? ?? '',
            mappedPan: suggestion['mappedPan'] as String? ?? '',
            source: suggestion['source'] as String? ?? '',
            helperText: suggestion['helperText'] as String? ?? '',
          ),
    isReadOnly: row['isReadOnly'] as bool? ?? false,
    isAboveThreshold: row['isAboveThreshold'] as bool? ?? false,
    hasReconciliationMismatch:
        row['hasReconciliationMismatch'] as bool? ?? false,
    hasNameOrPanConflict: row['hasNameOrPanConflict'] as bool? ?? false,
    hasApplicableTdsImpact: row['hasApplicableTdsImpact'] as bool? ?? false,
    is26QUnmatched: row['is26QUnmatched'] as bool? ?? false,
    hasMissingOrUncertainPan: row['hasMissingOrUncertainPan'] as bool? ?? false,
    preflightReasonCode: row['preflightReasonCode'] as String? ?? '',
    preflightReasonLabel: row['preflightReasonLabel'] as String? ?? '',
    preflightReasonDetail: row['preflightReasonDetail'] as String? ?? '',
    requiresDangerousReview: row['requiresDangerousReview'] as bool? ?? false,
    isPurchaseOnly: row['isPurchaseOnly'] as bool? ?? false,
  );
}

Map<String, dynamic> _serializeRowVmForIsolate(SellerMappingRowVm row) {
  return {
    'purchasePartyDisplayName': row.purchasePartyDisplayName,
    'normalizedAlias': row.normalizedAlias,
    'sectionCode': row.sectionCode,
    'rowIndex': row.rowIndex,
    'tdsDisplayName': row.tdsDisplayName,
    'tdsPan': row.tdsPan,
    'purchasePan': row.purchasePan,
    'purchaseGstNo': row.purchaseGstNo,
    'sourceRowCount': row.sourceRowCount,
    'tdsRowCount': row.tdsRowCount,
    'exactMapping': row.exactMapping == null
        ? null
        : _serializeSellerMappingForIsolate(row.exactMapping!),
    'fallbackMapping': row.fallbackMapping == null
        ? null
        : _serializeSellerMappingForIsolate(row.fallbackMapping!),
    'resolvedSuggestion': row.resolvedSuggestion == null
        ? null
        : {
            'mappedName': row.resolvedSuggestion!.mappedName,
            'mappedPan': row.resolvedSuggestion!.mappedPan,
            'source': row.resolvedSuggestion!.source,
            'helperText': row.resolvedSuggestion!.helperText,
          },
    'isReadOnly': row.isReadOnly,
    'isAboveThreshold': row.isAboveThreshold,
    'hasReconciliationMismatch': row.hasReconciliationMismatch,
    'hasNameOrPanConflict': row.hasNameOrPanConflict,
    'hasApplicableTdsImpact': row.hasApplicableTdsImpact,
    'is26QUnmatched': row.is26QUnmatched,
    'hasMissingOrUncertainPan': row.hasMissingOrUncertainPan,
    'preflightReasonCode': row.preflightReasonCode,
    'preflightReasonLabel': row.preflightReasonLabel,
    'preflightReasonDetail': row.preflightReasonDetail,
    'requiresDangerousReview': row.requiresDangerousReview,
    'isPurchaseOnly': row.isPurchaseOnly,
  };
}

SellerMappingRowVm _deserializeRowVmForIsolate(Map<String, dynamic> row) {
  final exactMapping = row['exactMapping'] as Map?;
  final fallbackMapping = row['fallbackMapping'] as Map?;
  final resolvedSuggestion = row['resolvedSuggestion'] as Map?;

  return SellerMappingRowVm(
    purchasePartyDisplayName: row['purchasePartyDisplayName'] as String? ?? '',
    normalizedAlias: row['normalizedAlias'] as String? ?? '',
    sectionCode: row['sectionCode'] as String? ?? '',
    rowIndex: row['rowIndex'] as int? ?? 0,
    tdsDisplayName: row['tdsDisplayName'] as String? ?? '',
    tdsPan: row['tdsPan'] as String? ?? '',
    purchasePan: row['purchasePan'] as String? ?? '',
    purchaseGstNo: row['purchaseGstNo'] as String? ?? '',
    sourceRowCount: row['sourceRowCount'] as int? ?? 0,
    tdsRowCount: row['tdsRowCount'] as int? ?? 0,
    exactMapping: exactMapping == null
        ? null
        : _deserializeSellerMappingForIsolate(
            Map<String, dynamic>.from(exactMapping),
          ),
    fallbackMapping: fallbackMapping == null
        ? null
        : _deserializeSellerMappingForIsolate(
            Map<String, dynamic>.from(fallbackMapping),
          ),
    resolvedSuggestion: resolvedSuggestion == null
        ? null
        : SellerMappingResolvedSuggestion(
            mappedName: resolvedSuggestion['mappedName'] as String? ?? '',
            mappedPan: resolvedSuggestion['mappedPan'] as String? ?? '',
            source: resolvedSuggestion['source'] as String? ?? '',
            helperText: resolvedSuggestion['helperText'] as String? ?? '',
          ),
    isReadOnly: row['isReadOnly'] as bool? ?? false,
    isAboveThreshold: row['isAboveThreshold'] as bool? ?? false,
    hasReconciliationMismatch:
        row['hasReconciliationMismatch'] as bool? ?? false,
    hasNameOrPanConflict: row['hasNameOrPanConflict'] as bool? ?? false,
    hasApplicableTdsImpact: row['hasApplicableTdsImpact'] as bool? ?? false,
    is26QUnmatched: row['is26QUnmatched'] as bool? ?? false,
    hasMissingOrUncertainPan: row['hasMissingOrUncertainPan'] as bool? ?? false,
    preflightReasonCode: row['preflightReasonCode'] as String? ?? '',
    preflightReasonLabel: row['preflightReasonLabel'] as String? ?? '',
    preflightReasonDetail: row['preflightReasonDetail'] as String? ?? '',
    requiresDangerousReview: row['requiresDangerousReview'] as bool? ?? false,
    isPurchaseOnly: row['isPurchaseOnly'] as bool? ?? false,
  );
}
