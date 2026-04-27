import 'package:flutter/foundation.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/resolved_seller_identity.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_identity_resolver.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

const Set<String> dangerousSellerIdentityFlags = {
  'conflicting_pan',
  'ambiguous_identity',
  'unresolved_identity',
};

bool hasDangerousSellerIdentityFlags(Iterable<String> flags) {
  return flags.any(dangerousSellerIdentityFlags.contains);
}

String? primaryDangerousSellerIdentityFlag(Iterable<String> flags) {
  for (final flag in dangerousSellerIdentityFlags) {
    if (flags.contains(flag)) {
      return flag;
    }
  }
  return null;
}

class SellerMappingPreflightResult {
  final List<SellerMappingScreenRowData> reviewRows;
  final List<String> tdsParties;
  final List<SellerMapping> existingMappings;
  final Set<String> blockedAliases;
  final Map<String, List<String>> tdsPartyPans;
  final int pendingReviewCount;

  const SellerMappingPreflightResult({
    required this.reviewRows,
    required this.tdsParties,
    required this.existingMappings,
    required this.blockedAliases,
    required this.tdsPartyPans,
    required this.pendingReviewCount,
  });

  bool get isSafeForReconciliation => pendingReviewCount == 0;
}

class SellerMappingPreflightService {
  static Future<SellerMappingPreflightResult> analyze({
    required String buyerName,
    required String buyerPan,
    required List<Tds26QRow> tdsRows,
    required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
  }) async {
    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final existingMappings = await SellerMappingService.getAllMappings(
      normalizedBuyerPan,
    );

    final tdsParties = _extractTdsParties(tdsRows);
    final tdsPartyPans = _buildTdsPartyPans(tdsRows);
    final savedAliasToPan = <String, String>{
      for (final mapping in existingMappings)
        if (normalizeSellerMappingSectionCode(mapping.sectionCode) == 'ALL')
          normalizeName(mapping.aliasName): normalizePan(mapping.mappedPan),
    };

    final observations = <SellerIdentityObservation>[
      ...sourceRowsBySection.values.expand(
        (rows) => rows.map(
          (row) => SellerIdentityObservation(
            originalName: row.partyName,
            mappedName: row.partyName,
            normalizedName: row.normalizedName,
            originalPan: row.panNumber,
            normalizedPan: row.normalizedPan,
          ),
        ),
      ),
      ...tdsRows.map(
        (row) => SellerIdentityObservation(
          originalName: row.deducteeName,
          mappedName: row.deducteeName,
          normalizedName: row.normalizedName,
          originalPan: row.panNumber,
          normalizedPan: row.normalizedPan,
        ),
      ),
    ];

    final resolver = SellerIdentityResolver.build(
      observations: observations,
      savedMappings: existingMappings,
      savedAliasToPan: savedAliasToPan,
    );

    final sourceGroups = <String, _SourceAliasAccumulator>{};

    for (final entry in sourceRowsBySection.entries) {
      for (final row in entry.value) {
        final normalizedAlias = normalizeName(row.partyName.trim());
        final sectionCode = normalizeSellerMappingSectionCode(row.section);
        if (normalizedAlias.isEmpty || sectionCode.isEmpty) continue;

        final identity = resolver.resolve(
          buyerPan: normalizedBuyerPan,
          originalName: row.partyName,
          mappedName: row.partyName,
          originalPan: row.panNumber,
          sectionCode: sectionCode,
        );

        final key = '$normalizedAlias|$sectionCode';
        final accumulator = sourceGroups.putIfAbsent(
          key,
          () => _SourceAliasAccumulator(
            alias: normalizedAlias,
            sectionCode: sectionCode,
            displayName: row.partyName.trim(),
            sourcePan: normalizePan(row.panNumber),
            sourceGst: row.gstNo.trim().toUpperCase(),
          ),
        );
        accumulator.add(identity);
      }
    }

    final tdsGroups = <String, _TdsSellerAccumulator>{};
    for (final row in tdsRows) {
      final normalizedName = normalizeName(row.deducteeName.trim());
      final sectionCode = normalizeSellerMappingSectionCode(row.section);
      final normalizedPan = normalizePan(row.panNumber);
      if (normalizedName.isEmpty || sectionCode.isEmpty) continue;

      final identity = resolver.resolve(
        buyerPan: normalizedBuyerPan,
        originalName: row.deducteeName,
        mappedName: row.deducteeName,
        originalPan: row.panNumber,
        sectionCode: sectionCode,
      );

      final key = '$normalizedName|$sectionCode';
      final accumulator = tdsGroups.putIfAbsent(
        key,
        () => _TdsSellerAccumulator(
          normalizedName: normalizedName,
          sectionCode: sectionCode,
          displayName: row.deducteeName.trim(),
          tdsPan: normalizedPan,
        ),
      );
      accumulator.add(identity);
    }

    final sourceGroupsBySection = <String, List<_SourceAliasAccumulator>>{};
    for (final group in sourceGroups.values) {
      sourceGroupsBySection.putIfAbsent(
        group.sectionCode,
        () => <_SourceAliasAccumulator>[],
      );
      sourceGroupsBySection[group.sectionCode]!.add(group);
    }

    final rows = <SellerMappingScreenRowData>[];
    var pendingReviewCount = 0;

    for (final tdsGroup in tdsGroups.values) {
      final matches = _matchSourceAliasesForTdsSeller(
        tdsGroup: tdsGroup,
        sourceCandidates:
            sourceGroupsBySection[tdsGroup.sectionCode] ??
            const <_SourceAliasAccumulator>[],
        existingMappings: existingMappings,
      );

      if (matches.rows.isEmpty) {
        rows.add(
          SellerMappingScreenRowData(
            purchasePartyDisplayName: tdsGroup.displayName,
            normalizedAlias: tdsGroup.normalizedName,
            sectionCode: tdsGroup.sectionCode,
            purchasePan: '',
            resolvedSuggestion: SellerMappingResolvedSuggestion(
              mappedName: tdsGroup.displayName,
              mappedPan: tdsGroup.effectivePan,
              source: 'tds_only',
              helperText:
                  '26Q seller has no same-section source alias candidates in preflight review.',
            ),
            isReadOnly: true,
            is26QUnmatched: true,
            preflightReasonCode: matches.reasonCode,
            preflightReasonLabel: matches.reasonLabel,
            preflightReasonDetail: matches.reasonDetail,
            requiresDangerousReview: matches.requiresDangerousReview,
          ),
        );
        continue;
      }

      rows.addAll(
        matches.rows.map(
          (match) => SellerMappingScreenRowData(
            purchasePartyDisplayName: match.sourceAlias.displayName,
            normalizedAlias: match.sourceAlias.alias,
            sectionCode: match.sourceAlias.sectionCode,
            purchasePan: match.sourceAlias.sourcePan,
            purchaseGstNo: match.sourceAlias.sourceGst,
            resolvedSuggestion: SellerMappingResolvedSuggestion(
              mappedName: tdsGroup.displayName,
              mappedPan: tdsGroup.effectivePan,
              source: match.suggestionSource,
              helperText: match.helperText,
            ),
            hasNameOrPanConflict:
                matches.reasonCode == 'conflicting_pan' ||
                matches.reasonCode == 'ambiguous_identity',
            hasMissingOrUncertainPan:
                matches.reasonCode == 'unresolved_identity',
            hasApplicableTdsImpact: true,
            preflightReasonCode: matches.reasonCode,
            preflightReasonLabel: matches.reasonLabel,
            preflightReasonDetail: matches.reasonDetail,
            requiresDangerousReview: matches.requiresDangerousReview,
          ),
        ),
      );
    }

    rows.sort((a, b) {
      if (a.requiresDangerousReview != b.requiresDangerousReview) {
        return a.requiresDangerousReview ? -1 : 1;
      }
      final sectionCompare = a.sectionCode.compareTo(b.sectionCode);
      if (sectionCompare != 0) return sectionCompare;
      return a.purchasePartyDisplayName.compareTo(b.purchasePartyDisplayName);
    });

    // Calculate unique dangerous aliases to align count with the UI row deduplication
    final uniqueDangerousAliases = <String>{};
    for (final row in rows) {
      final hasSavedMapping =
          row.resolvedSuggestion?.source.startsWith('saved_') ?? false;
      debugPrint(
        'PRECHECK row=${row.purchasePartyDisplayName} status=${row.preflightReasonCode} hasSavedMapping=$hasSavedMapping blocked=${row.requiresDangerousReview}',
      );

      if (row.requiresDangerousReview) {
        uniqueDangerousAliases.add('${row.normalizedAlias}|${row.sectionCode}');
      }
    }
    pendingReviewCount = uniqueDangerousAliases.length;

    return SellerMappingPreflightResult(
      reviewRows: rows,
      tdsParties: tdsParties,
      existingMappings: existingMappings,
      blockedAliases: const <String>{},
      tdsPartyPans: tdsPartyPans,
      pendingReviewCount: pendingReviewCount,
    );
  }

  static _PreflightMatchResult _matchSourceAliasesForTdsSeller({
    required _TdsSellerAccumulator tdsGroup,
    required List<_SourceAliasAccumulator> sourceCandidates,
    required List<SellerMapping> existingMappings,
  }) {
    final exactSavedMatches = <_MatchedSourceAlias>[];
    final safePanMatches = <_MatchedSourceAlias>[];
    final safeNameMatches = <_MatchedSourceAlias>[];
    final riskyMatches = <_MatchedSourceAlias>[];
    final panConflictMatches = <_MatchedSourceAlias>[];

    for (final source in sourceCandidates) {
      final savedExact = source.matchesSavedMapping(
        mappedName: tdsGroup.displayName,
        existingMappings: existingMappings,
        exactOnly: true,
      );
      final savedFallback = source.matchesSavedMapping(
        mappedName: tdsGroup.displayName,
        existingMappings: existingMappings,
        exactOnly: false,
      );
      final nameExact = source.alias == tdsGroup.normalizedName;
      final panExact =
          tdsGroup.effectivePan.isNotEmpty &&
          (source.sourcePan == tdsGroup.effectivePan ||
              source.resolvedPan == tdsGroup.effectivePan);
      final suggestedNameMatch =
          source.suggestedName.isNotEmpty &&
          normalizeName(source.suggestedName) == tdsGroup.normalizedName;
      final hasPanConflict =
          tdsGroup.effectivePan.isNotEmpty &&
          source.sourcePan.isNotEmpty &&
          source.sourcePan != tdsGroup.effectivePan &&
          (nameExact || suggestedNameMatch);

      if (!savedExact &&
          !savedFallback &&
          source.hasAnySavedMapping(existingMappings)) {
        continue;
      }

      if (!(savedExact ||
          savedFallback ||
          nameExact ||
          panExact ||
          suggestedNameMatch ||
          hasPanConflict)) {
        continue;
      }

      final suggestionSource = savedExact
          ? 'saved_exact'
          : savedFallback
          ? 'saved_fallback'
          : 'backend_inferred';
      final helperText = <String>[
        if (savedExact) 'Saved exact alias already points to this 26Q seller.',
        if (!savedExact && savedFallback)
          'Saved fallback alias currently points to this 26Q seller.',
        if (panExact) 'PAN matches this 26Q seller.',
        if (!panExact && nameExact)
          'Source alias name exactly matches this 26Q seller.',
        if (!panExact && !nameExact && suggestedNameMatch)
          'Identity resolver already suggests this 26Q seller.',
      ].join(' ');

      final matched = _MatchedSourceAlias(
        sourceAlias: source,
        suggestionSource: suggestionSource,
        helperText: helperText,
      );

      if (savedExact) {
        exactSavedMatches.add(matched);
        continue;
      }
      if (savedFallback) {
        safeNameMatches.add(matched);
        continue;
      }
      if (hasPanConflict) {
        panConflictMatches.add(matched);
        continue;
      }
      if (panExact) {
        safePanMatches.add(matched);
        continue;
      }
      if (nameExact) {
        safeNameMatches.add(matched);
        continue;
      }
      riskyMatches.add(matched);
    }

    final allRows = <_MatchedSourceAlias>[
      ...exactSavedMatches,
      ...safePanMatches,
      ...safeNameMatches,
      ...riskyMatches,
      ...panConflictMatches,
    ];

    if (allRows.isEmpty) {
      final dangerousFlag = primaryDangerousSellerIdentityFlag(
        tdsGroup.identityFlags,
      );
      return _PreflightMatchResult(
        rows: const <_MatchedSourceAlias>[],
        requiresDangerousReview:
            dangerousFlag != null && dangerousFlag != 'unresolved_identity',
        reasonCode: dangerousFlag ?? '',
        reasonLabel: _reasonLabel(dangerousFlag),
        reasonDetail: tdsGroup.identityNotes.toSet().join(' | '),
      );
    }

    final dangerousFlag =
        primaryDangerousSellerIdentityFlag(tdsGroup.identityFlags) ??
        (tdsGroup.pans.length > 1 ? 'conflicting_pan' : null);

    final safeDirectMatches = <_MatchedSourceAlias>[
      ...exactSavedMatches,
      ...safePanMatches,
      ...safeNameMatches,
    ];

    final allSaved =
        allRows.isNotEmpty &&
        allRows.every((r) => r.suggestionSource.startsWith('saved_'));

    if (allSaved) {
      return _PreflightMatchResult(
        rows: allRows,
        requiresDangerousReview: false,
        reasonCode: '',
        reasonLabel: '',
        reasonDetail:
            'All same-section source aliases are safely resolved via saved mappings.',
      );
    }

    // Identity is considered "resolved" for preflight if all matched rows are "safe"
    // (saved, PAN, or exact name) and there are no conflicts or risky suggestions.
    // Exception: statutory PAN conflicts (multiple PANs in the 26Q file) must always
    // be reviewed even if matches exist.
    final matchesAreSafeAndResolved =
        safeDirectMatches.length == allRows.length &&
        safeDirectMatches.isNotEmpty &&
        panConflictMatches.isEmpty &&
        riskyMatches.isEmpty;

    final isStatutoryPanConflict = tdsGroup.pans.length > 1;

    if (matchesAreSafeAndResolved && !isStatutoryPanConflict) {
      return _PreflightMatchResult(
        rows: allRows,
        requiresDangerousReview: false,
        reasonCode: '',
        reasonLabel: '',
        reasonDetail:
            'All same-section source aliases are safely resolved for this 26Q seller.',
      );
    }

    if (dangerousFlag != null) {
      return _PreflightMatchResult(
        rows: allRows,
        requiresDangerousReview: true,
        reasonCode: dangerousFlag,
        reasonLabel: _reasonLabel(dangerousFlag),
        reasonDetail: tdsGroup.identityNotes.toSet().join(' | '),
      );
    }

    if (panConflictMatches.isNotEmpty &&
        safeDirectMatches.isEmpty &&
        riskyMatches.isEmpty) {
      return _PreflightMatchResult(
        rows: allRows,
        requiresDangerousReview: true,
        reasonCode: 'conflicting_pan',
        reasonLabel: 'Conflicting PAN',
        reasonDetail:
            'Same-section source aliases conflict with the 26Q PAN for this seller and need review.',
      );
    }

    if (riskyMatches.length == 1 &&
        safeDirectMatches.isEmpty &&
        panConflictMatches.isEmpty) {
      return _PreflightMatchResult(
        rows: allRows,
        requiresDangerousReview: true,
        reasonCode: 'unresolved_identity',
        reasonLabel: 'Unresolved Identity',
        reasonDetail:
            'This 26Q seller has only a risky alias-style source match and needs review.',
      );
    }

    return _PreflightMatchResult(
      rows: allRows,
      requiresDangerousReview: true,
      reasonCode: panConflictMatches.isNotEmpty
          ? 'conflicting_pan'
          : 'ambiguous_identity',
      reasonLabel: panConflictMatches.isNotEmpty
          ? 'Conflicting PAN'
          : 'Ambiguous Identity',
      reasonDetail: panConflictMatches.isNotEmpty
          ? 'Multiple same-section source aliases point toward this 26Q seller, and at least one has a PAN conflict.'
          : 'Multiple same-section source aliases point toward this 26Q seller and need review.',
    );
  }

  static List<String> _extractTdsParties(List<Tds26QRow> tdsRows) {
    final parties = <String>{};
    for (final row in tdsRows) {
      final name = row.deducteeName.trim();
      if (name.isNotEmpty) {
        parties.add(name);
      }
    }
    return parties.toList()..sort();
  }

  static Map<String, List<String>> _buildTdsPartyPans(List<Tds26QRow> tdsRows) {
    final result = <String, List<String>>{};
    for (final row in tdsRows) {
      final name = row.deducteeName.trim();
      final pan = normalizePan(row.panNumber);
      if (name.isEmpty || pan.isEmpty) continue;
      result.putIfAbsent(name, () => <String>[]);
      if (!result[name]!.contains(pan)) {
        result[name]!.add(pan);
      }
    }
    return result;
  }
}

class _SourceAliasAccumulator {
  final String alias;
  final String sectionCode;
  String displayName;
  String sourcePan;
  String sourceGst;
  final Set<String> identityFlags = <String>{};
  final List<String> identityNotes = <String>[];
  String suggestedName = '';
  String suggestedPan = '';
  String suggestionSource = '';

  _SourceAliasAccumulator({
    required this.alias,
    required this.sectionCode,
    required this.displayName,
    required this.sourcePan,
    required this.sourceGst,
  });

  void add(ResolvedSellerIdentity identity) {
    identityFlags.addAll(identity.identityFlags);
    final notes = identity.identityNotes.trim();
    if (notes.isNotEmpty) {
      identityNotes.add(notes);
    }

    if (displayName.isEmpty && identity.originalSellerName.trim().isNotEmpty) {
      displayName = identity.originalSellerName.trim();
    }
    if (sourcePan.isEmpty && normalizePan(identity.originalPan).isNotEmpty) {
      sourcePan = normalizePan(identity.originalPan);
    }

    if (suggestedName.isEmpty &&
        identity.resolvedSellerName.trim().isNotEmpty) {
      suggestedName = identity.resolvedSellerName.trim();
      suggestedPan = identity.resolvedPan.trim();
      suggestionSource = identity.identitySource.trim();
    }
  }

  bool matchesSavedMapping({
    required String mappedName,
    required List<SellerMapping> existingMappings,
    required bool exactOnly,
  }) {
    final normalizedMappedName = normalizeName(mappedName);
    final exactMapping = existingMappings
        .where(
          (mapping) =>
              normalizeName(mapping.aliasName) == alias &&
              normalizeSellerMappingSectionCode(mapping.sectionCode) ==
                  sectionCode &&
              normalizeName(mapping.mappedName) == normalizedMappedName,
        )
        .firstOrNull;
    if (exactMapping != null) {
      return true;
    }
    if (exactOnly) {
      return false;
    }
    final fallbackMapping = existingMappings
        .where(
          (mapping) =>
              normalizeName(mapping.aliasName) == alias &&
              normalizeSellerMappingSectionCode(mapping.sectionCode) == 'ALL' &&
              normalizeName(mapping.mappedName) == normalizedMappedName,
        )
        .firstOrNull;
    return fallbackMapping != null;
  }

  bool hasAnySavedMapping(List<SellerMapping> existingMappings) {
    return existingMappings.any((mapping) {
      final mAlias = normalizeName(mapping.aliasName);
      final mSection = normalizeSellerMappingSectionCode(mapping.sectionCode);
      return mAlias == alias && (mSection == sectionCode || mSection == 'ALL');
    });
  }

  String get resolvedPan =>
      suggestedPan.isNotEmpty ? normalizePan(suggestedPan) : '';
}

class _TdsSellerAccumulator {
  final String normalizedName;
  final String sectionCode;
  String displayName;
  String tdsPan;
  final Set<String> pans = <String>{};
  final Set<String> identityFlags = <String>{};
  final List<String> identityNotes = <String>[];

  _TdsSellerAccumulator({
    required this.normalizedName,
    required this.sectionCode,
    required this.displayName,
    required this.tdsPan,
  });

  void add(ResolvedSellerIdentity identity) {
    identityFlags.addAll(identity.identityFlags);
    final notes = identity.identityNotes.trim();
    if (notes.isNotEmpty) {
      identityNotes.add(notes);
    }
    if (displayName.isEmpty && identity.originalSellerName.trim().isNotEmpty) {
      displayName = identity.originalSellerName.trim();
    }
    if (tdsPan.isEmpty && normalizePan(identity.originalPan).isNotEmpty) {
      tdsPan = normalizePan(identity.originalPan);
    }
    final normalizedPan = normalizePan(identity.originalPan);
    if (normalizedPan.isNotEmpty) {
      pans.add(normalizedPan);
    }
  }

  String get effectivePan => pans.length == 1 ? pans.first : '';
}

class _MatchedSourceAlias {
  final _SourceAliasAccumulator sourceAlias;
  final String suggestionSource;
  final String helperText;

  const _MatchedSourceAlias({
    required this.sourceAlias,
    required this.suggestionSource,
    required this.helperText,
  });
}

class _PreflightMatchResult {
  final List<_MatchedSourceAlias> rows;
  final bool requiresDangerousReview;
  final String reasonCode;
  final String reasonLabel;
  final String reasonDetail;

  const _PreflightMatchResult({
    required this.rows,
    required this.requiresDangerousReview,
    required this.reasonCode,
    required this.reasonLabel,
    required this.reasonDetail,
  });
}

String _reasonLabel(String? flag) {
  switch (flag) {
    case 'conflicting_pan':
      return 'Conflicting PAN';
    case 'ambiguous_identity':
      return 'Ambiguous Identity';
    case 'unresolved_identity':
      return 'Unresolved Identity';
    default:
      return 'Safe';
  }
}
