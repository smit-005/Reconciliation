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

  SellerMappingPreflightResult copyWith({
    List<SellerMappingScreenRowData>? reviewRows,
    List<String>? tdsParties,
    List<SellerMapping>? existingMappings,
    Set<String>? blockedAliases,
    Map<String, List<String>>? tdsPartyPans,
    int? pendingReviewCount,
  }) {
    return SellerMappingPreflightResult(
      reviewRows: reviewRows ?? this.reviewRows,
      tdsParties: tdsParties ?? this.tdsParties,
      existingMappings: existingMappings ?? this.existingMappings,
      blockedAliases: blockedAliases ?? this.blockedAliases,
      tdsPartyPans: tdsPartyPans ?? this.tdsPartyPans,
      pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
    );
  }

  bool get isSafeForReconciliation => pendingReviewCount == 0;
}

class SellerMappingPreflightService {
  static Future<SellerMappingPreflightResult> analyze({
    required String buyerName,
    required String buyerPan,
    required List<Tds26QRow> tdsRows,
    required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
  }) async {
    final preloadWatch = Stopwatch()..start();
    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final existingMappings = await SellerMappingService.getAllMappings(
      normalizedBuyerPan,
    );
    debugPrint(
      'PREFLIGHT PERF => step=load_existing_mappings ms=${preloadWatch.elapsedMilliseconds} '
      'mappings=${existingMappings.length}',
    );

    final analyzeWatch = Stopwatch()..start();
    final payload = await compute(_analyzeSellerMappingPreflightInIsolate, {
      'buyerPan': buyerPan,
      'tdsRows': tdsRows.map(_serializeTdsRowForIsolate).toList(),
      'sourceRowsBySection': {
        for (final entry in sourceRowsBySection.entries)
          entry.key: entry.value
              .map(_serializeNormalizedRowForIsolate)
              .toList(),
      },
      'existingMappings': existingMappings
          .map(_serializeSellerMappingForIsolate)
          .toList(),
    });
    debugPrint(
      'PREFLIGHT PERF => step=compute_analyze ms=${analyzeWatch.elapsedMilliseconds} '
      'tdsRows=${tdsRows.length} sourceRows=${sourceRowsBySection.values.fold<int>(0, (sum, rows) => sum + rows.length)}',
    );
    return _deserializePreflightResultForIsolate(
      Map<String, dynamic>.from(payload),
    );
  }

  static SellerMappingPreflightResult _analyzeWithExistingMappings({
    required String buyerPan,
    required List<Tds26QRow> tdsRows,
    required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
    required List<SellerMapping> existingMappings,
  }) {
    final normalizedBuyerPan = buyerPan.trim().toUpperCase();
    final lookupWatch = Stopwatch()..start();
    final savedMappingLookup = _SavedMappingLookup.build(existingMappings);
    debugPrint(
      'PREFLIGHT PERF => step=build_saved_mapping_lookup ms=${lookupWatch.elapsedMilliseconds} '
      'exactKeys=${savedMappingLookup.exactMappingKeysCount} '
      'fallbackKeys=${savedMappingLookup.fallbackMappingKeysCount} '
      'aliasKeys=${savedMappingLookup.savedAliasKeysCount}',
    );
    final tdsParties = _extractTdsParties(tdsRows);
    final tdsPartyPans = _buildTdsPartyPans(tdsRows);
    final savedAliasToPan = <String, String>{
      for (final mapping in existingMappings)
        if (normalizeSellerMappingSectionCode(mapping.sectionCode) == 'ALL')
          normalizeName(mapping.aliasName): normalizePan(mapping.mappedPan),
    };
    final validSourceRowsBySection = <String, List<NormalizedTransactionRow>>{};
    var droppedInvalidSellerKeys = 0;
    var keptSellerKeys = 0;

    for (final entry in sourceRowsBySection.entries) {
      for (final row in entry.value) {
        if (!_isValidSourceSellerKey(row.partyName)) {
          droppedInvalidSellerKeys += 1;
          continue;
        }
        validSourceRowsBySection
            .putIfAbsent(entry.key, () => <NormalizedTransactionRow>[])
            .add(row);
        keptSellerKeys += 1;
      }
    }
    debugPrint(
      'PREFLIGHT INPUT CLEANUP => droppedInvalidSellerKeys=$droppedInvalidSellerKeys keptSellerKeys=$keptSellerKeys',
    );

    final observations = <SellerIdentityObservation>[
      ...validSourceRowsBySection.values.expand(
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

    for (final entry in validSourceRowsBySection.entries) {
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
    final sourceAliasCandidateIndex = _SourceAliasCandidateIndex.build(
      sourceGroups: sourceGroups.values.toList(),
      existingMappings: existingMappings,
    );
    final uploadedSectionScope = sourceGroupsBySection.keys.toSet();

    final rows = <SellerMappingScreenRowData>[];
    final addedSourceAliases = <String>{};
    var pendingReviewCount = 0;
    var outOfScopeTdsOnlyCount = 0;
    var reviewedSeparateCount = 0;
    var reviewedSeparateSkippedBlockers = 0;
    var reducedCandidateHits = 0;
    final candidateLoopWatch = Stopwatch()..start();
    debugPrint(
      'PREFLIGHT PERF => step=candidate_match_loop_start tdsGroups=${tdsGroups.length} '
      'sourceGroups=${sourceGroups.length}',
    );

    for (final tdsGroup in tdsGroups.values) {
      final isSectionInUploadedScope = uploadedSectionScope.contains(
        tdsGroup.sectionCode,
      );
      final sourceCandidates = sourceAliasCandidateIndex.candidatesFor(
        tdsGroup,
      );
      final allSectionCandidates =
          sourceGroupsBySection[tdsGroup.sectionCode] ??
          const <_SourceAliasAccumulator>[];
      if (sourceCandidates.length < allSectionCandidates.length) {
        reducedCandidateHits += 1;
        debugPrint(
          'PREFLIGHT REDUCED CANDIDATES => section=${tdsGroup.sectionCode} seller=${tdsGroup.displayName} reduced=${sourceCandidates.length} total=${allSectionCandidates.length}',
        );
      }
      final matches = _matchSourceAliasesForTdsSeller(
        tdsGroup: tdsGroup,
        sourceCandidates: sourceCandidates,
        savedMappingLookup: savedMappingLookup,
      );
      reviewedSeparateCount += matches.reviewedSeparateCount;
      reviewedSeparateSkippedBlockers +=
          matches.reviewedSeparateSkippedBlockers;

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
            requiresDangerousReview:
                isSectionInUploadedScope && matches.requiresDangerousReview,
          ),
        );
        if (!isSectionInUploadedScope) {
          outOfScopeTdsOnlyCount += 1;
        }
        continue;
      }

      rows.addAll(
        matches.rows.map((match) {
          addedSourceAliases.add(
            '${match.sourceAlias.alias}|${match.sourceAlias.sectionCode}',
          );
          return SellerMappingScreenRowData(
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
            requiresDangerousReview:
                isSectionInUploadedScope && matches.requiresDangerousReview,
          );
        }),
      );
    }

    for (final sourceGroup in sourceGroups.values) {
      final key = '${sourceGroup.alias}|${sourceGroup.sectionCode}';
      if (!addedSourceAliases.contains(key)) {
        rows.add(
          SellerMappingScreenRowData(
            purchasePartyDisplayName: sourceGroup.displayName,
            normalizedAlias: sourceGroup.alias,
            sectionCode: sourceGroup.sectionCode,
            purchasePan: sourceGroup.sourcePan,
            purchaseGstNo: sourceGroup.sourceGst,
            resolvedSuggestion: sourceGroup.suggestedName.isNotEmpty
                ? SellerMappingResolvedSuggestion(
                    mappedName: sourceGroup.suggestedName,
                    mappedPan: sourceGroup.resolvedPan,
                    source: sourceGroup.suggestionSource,
                    helperText:
                        'Suggested 26Q seller based on fuzzy match or ledger data.',
                  )
                : null,
            preflightReasonCode: 'ledger_only',
            preflightReasonLabel: 'Purchase Only',
            preflightReasonDetail:
                'Source seller without a confirmed 26Q match.',
            requiresDangerousReview: false,
            isPurchaseOnly: true,
          ),
        );
      }
    }
    debugPrint(
      'PREFLIGHT PERF => step=candidate_match_loop_done ms=${candidateLoopWatch.elapsedMilliseconds} '
      'tdsGroups=${tdsGroups.length} sourceGroups=${sourceGroups.length}',
    );
    debugPrint(
      'PREFLIGHT REDUCED CANDIDATES => hits=$reducedCandidateHits tdsGroups=${tdsGroups.length}',
    );

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
    final uploadedSectionsLabel = uploadedSectionScope.toList()..sort();
    debugPrint(
      'PREFLIGHT SCOPE => uploadedSections=${uploadedSectionsLabel.join(",")} '
      'outOfScopeTdsOnly=$outOfScopeTdsOnlyCount pendingReviewCount=$pendingReviewCount',
    );
    debugPrint(
      'PREFLIGHT REVIEWED SEPARATE => count=$reviewedSeparateCount '
      'skippedBlockers=$reviewedSeparateSkippedBlockers',
    );

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
    required _SavedMappingLookup savedMappingLookup,
  }) {
    final exactSavedMatches = <_MatchedSourceAlias>[];
    final safePanMatches = <_MatchedSourceAlias>[];
    final safeNameMatches = <_MatchedSourceAlias>[];
    final riskyMatches = <_MatchedSourceAlias>[];
    final panConflictMatches = <_MatchedSourceAlias>[];
    var reviewedSeparateCount = 0;
    var reviewedSeparateSkippedBlockers = 0;

    _PreflightMatchResult buildResult({
      required List<_MatchedSourceAlias> rows,
      required bool requiresDangerousReview,
      required String reasonCode,
      required String reasonLabel,
      required String reasonDetail,
    }) {
      return _PreflightMatchResult(
        rows: rows,
        requiresDangerousReview: requiresDangerousReview,
        reasonCode: reasonCode,
        reasonLabel: reasonLabel,
        reasonDetail: reasonDetail,
        reviewedSeparateCount: reviewedSeparateCount,
        reviewedSeparateSkippedBlockers: reviewedSeparateSkippedBlockers,
      );
    }

    for (final source in sourceCandidates) {
      final reviewedSeparate = source.hasReviewedSeparateDisposition(
        savedMappingLookup,
      );
      if (reviewedSeparate && source.sectionCode == tdsGroup.sectionCode) {
        reviewedSeparateCount += 1;
        continue;
      }

      final savedExact = source.matchesSavedMapping(
        mappedName: tdsGroup.displayName,
        savedMappingLookup: savedMappingLookup,
        exactOnly: true,
      );
      final savedFallback = source.matchesSavedMapping(
        mappedName: tdsGroup.displayName,
        savedMappingLookup: savedMappingLookup,
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
          source.hasAnySavedMapping(savedMappingLookup)) {
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
      if (reviewedSeparateCount > 0) {
        reviewedSeparateSkippedBlockers += 1;
        return buildResult(
          rows: const <_MatchedSourceAlias>[],
          requiresDangerousReview: false,
          reasonCode: '',
          reasonLabel: '',
          reasonDetail:
              'Same-section source aliases were explicitly reviewed and kept separate from this 26Q seller.',
        );
      }
      final dangerousFlag = primaryDangerousSellerIdentityFlag(
        tdsGroup.identityFlags,
      );
      return buildResult(
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
      return buildResult(
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
      return buildResult(
        rows: allRows,
        requiresDangerousReview: false,
        reasonCode: '',
        reasonLabel: '',
        reasonDetail:
            'All same-section source aliases are safely resolved for this 26Q seller.',
      );
    }

    if (dangerousFlag != null) {
      return buildResult(
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
      return buildResult(
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
      return buildResult(
        rows: allRows,
        requiresDangerousReview: true,
        reasonCode: 'unresolved_identity',
        reasonLabel: 'Unresolved Identity',
        reasonDetail:
            'This 26Q seller has only a risky alias-style source match and needs review.',
      );
    }

    return buildResult(
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
    required _SavedMappingLookup savedMappingLookup,
    required bool exactOnly,
  }) {
    final normalizedMappedName = normalizeName(mappedName);
    if (savedMappingLookup.hasExactMapping(
      alias: alias,
      sectionCode: sectionCode,
      normalizedMappedName: normalizedMappedName,
    )) {
      return true;
    }
    if (exactOnly) {
      return false;
    }
    return savedMappingLookup.hasFallbackMapping(
      alias: alias,
      normalizedMappedName: normalizedMappedName,
    );
  }

  bool hasAnySavedMapping(_SavedMappingLookup savedMappingLookup) {
    return savedMappingLookup.hasAnySavedMapping(
      alias: alias,
      sectionCode: sectionCode,
    );
  }

  bool hasReviewedSeparateDisposition(_SavedMappingLookup savedMappingLookup) {
    return savedMappingLookup.hasReviewedSeparateDisposition(
      alias: alias,
      sectionCode: sectionCode,
    );
  }

  String get resolvedPan =>
      suggestedPan.isNotEmpty ? normalizePan(suggestedPan) : '';
}

class _SourceAliasCandidateIndex {
  final Map<String, List<_SourceAliasAccumulator>> _allBySection;
  final Map<String, List<_SourceAliasAccumulator>> _aliasBySectionAndName;
  final Map<String, List<_SourceAliasAccumulator>> _suggestedBySectionAndName;
  final Map<String, List<_SourceAliasAccumulator>> _panBySectionAndValue;
  final Map<String, List<_SourceAliasAccumulator>> _savedExactBySectionAndName;
  final Map<String, List<_SourceAliasAccumulator>>
  _savedFallbackBySectionAndName;

  const _SourceAliasCandidateIndex._({
    required Map<String, List<_SourceAliasAccumulator>> allBySection,
    required Map<String, List<_SourceAliasAccumulator>> aliasBySectionAndName,
    required Map<String, List<_SourceAliasAccumulator>>
    suggestedBySectionAndName,
    required Map<String, List<_SourceAliasAccumulator>> panBySectionAndValue,
    required Map<String, List<_SourceAliasAccumulator>>
    savedExactBySectionAndName,
    required Map<String, List<_SourceAliasAccumulator>>
    savedFallbackBySectionAndName,
  }) : _allBySection = allBySection,
       _aliasBySectionAndName = aliasBySectionAndName,
       _suggestedBySectionAndName = suggestedBySectionAndName,
       _panBySectionAndValue = panBySectionAndValue,
       _savedExactBySectionAndName = savedExactBySectionAndName,
       _savedFallbackBySectionAndName = savedFallbackBySectionAndName;

  factory _SourceAliasCandidateIndex.build({
    required List<_SourceAliasAccumulator> sourceGroups,
    required List<SellerMapping> existingMappings,
  }) {
    final allBySection = <String, List<_SourceAliasAccumulator>>{};
    final aliasBySectionAndName = <String, List<_SourceAliasAccumulator>>{};
    final suggestedBySectionAndName = <String, List<_SourceAliasAccumulator>>{};
    final panBySectionAndValue = <String, List<_SourceAliasAccumulator>>{};
    final savedExactBySectionAndName =
        <String, List<_SourceAliasAccumulator>>{};
    final savedFallbackBySectionAndName =
        <String, List<_SourceAliasAccumulator>>{};

    final exactSavedNamesByAliasAndSection = <String, Set<String>>{};
    final fallbackSavedNamesByAlias = <String, Set<String>>{};

    for (final mapping in existingMappings) {
      final alias = normalizeName(mapping.aliasName);
      final sectionCode = normalizeSellerMappingSectionCode(
        mapping.sectionCode,
      );
      final mappedName = normalizeName(mapping.mappedName);
      if (alias.isEmpty || mappedName.isEmpty) continue;

      if (sectionCode == 'ALL') {
        fallbackSavedNamesByAlias
            .putIfAbsent(alias, () => <String>{})
            .add(mappedName);
      } else {
        exactSavedNamesByAliasAndSection
            .putIfAbsent('$alias|$sectionCode', () => <String>{})
            .add(mappedName);
      }
    }

    void addToIndex(
      Map<String, List<_SourceAliasAccumulator>> index,
      String key,
      _SourceAliasAccumulator source,
    ) {
      index.putIfAbsent(key, () => <_SourceAliasAccumulator>[]).add(source);
    }

    for (final source in sourceGroups) {
      allBySection
          .putIfAbsent(source.sectionCode, () => <_SourceAliasAccumulator>[])
          .add(source);
      addToIndex(
        aliasBySectionAndName,
        '${source.sectionCode}|${source.alias}',
        source,
      );

      if (source.suggestedName.isNotEmpty) {
        addToIndex(
          suggestedBySectionAndName,
          '${source.sectionCode}|${normalizeName(source.suggestedName)}',
          source,
        );
      }
      if (source.sourcePan.isNotEmpty) {
        addToIndex(
          panBySectionAndValue,
          '${source.sectionCode}|${source.sourcePan}',
          source,
        );
      }
      if (source.resolvedPan.isNotEmpty) {
        addToIndex(
          panBySectionAndValue,
          '${source.sectionCode}|${source.resolvedPan}',
          source,
        );
      }

      for (final mappedName
          in exactSavedNamesByAliasAndSection['${source.alias}|${source.sectionCode}'] ??
              const <String>{}) {
        addToIndex(
          savedExactBySectionAndName,
          '${source.sectionCode}|$mappedName',
          source,
        );
      }
      for (final mappedName
          in fallbackSavedNamesByAlias[source.alias] ?? const <String>{}) {
        addToIndex(
          savedFallbackBySectionAndName,
          '${source.sectionCode}|$mappedName',
          source,
        );
      }
    }

    return _SourceAliasCandidateIndex._(
      allBySection: allBySection,
      aliasBySectionAndName: aliasBySectionAndName,
      suggestedBySectionAndName: suggestedBySectionAndName,
      panBySectionAndValue: panBySectionAndValue,
      savedExactBySectionAndName: savedExactBySectionAndName,
      savedFallbackBySectionAndName: savedFallbackBySectionAndName,
    );
  }

  List<_SourceAliasAccumulator> candidatesFor(_TdsSellerAccumulator tdsGroup) {
    final allSectionCandidates =
        _allBySection[tdsGroup.sectionCode] ??
        const <_SourceAliasAccumulator>[];
    final reduced = <String, _SourceAliasAccumulator>{};

    void addAll(Iterable<_SourceAliasAccumulator> values) {
      for (final value in values) {
        reduced['${value.alias}|${value.sectionCode}'] = value;
      }
    }

    addAll(
      _aliasBySectionAndName['${tdsGroup.sectionCode}|${tdsGroup.normalizedName}'] ??
          const <_SourceAliasAccumulator>[],
    );
    addAll(
      _suggestedBySectionAndName['${tdsGroup.sectionCode}|${tdsGroup.normalizedName}'] ??
          const <_SourceAliasAccumulator>[],
    );
    addAll(
      _savedExactBySectionAndName['${tdsGroup.sectionCode}|${tdsGroup.normalizedName}'] ??
          const <_SourceAliasAccumulator>[],
    );
    addAll(
      _savedFallbackBySectionAndName['${tdsGroup.sectionCode}|${tdsGroup.normalizedName}'] ??
          const <_SourceAliasAccumulator>[],
    );
    if (tdsGroup.effectivePan.isNotEmpty) {
      addAll(
        _panBySectionAndValue['${tdsGroup.sectionCode}|${tdsGroup.effectivePan}'] ??
            const <_SourceAliasAccumulator>[],
      );
    }

    if (reduced.isEmpty) {
      return allSectionCandidates;
    }
    return reduced.values.toList();
  }
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
  final int reviewedSeparateCount;
  final int reviewedSeparateSkippedBlockers;

  const _PreflightMatchResult({
    required this.rows,
    required this.requiresDangerousReview,
    required this.reasonCode,
    required this.reasonLabel,
    required this.reasonDetail,
    this.reviewedSeparateCount = 0,
    this.reviewedSeparateSkippedBlockers = 0,
  });
}

class _SavedMappingLookup {
  final Set<String> _exactMappingKeys;
  final Set<String> _fallbackMappingKeys;
  final Set<String> _savedAliasSectionKeys;
  final Set<String> _savedAliasFallbackKeys;
  final Set<String> _reviewedSeparateAliasSectionKeys;

  const _SavedMappingLookup._({
    required Set<String> exactMappingKeys,
    required Set<String> fallbackMappingKeys,
    required Set<String> savedAliasSectionKeys,
    required Set<String> savedAliasFallbackKeys,
    required Set<String> reviewedSeparateAliasSectionKeys,
  }) : _exactMappingKeys = exactMappingKeys,
       _fallbackMappingKeys = fallbackMappingKeys,
       _savedAliasSectionKeys = savedAliasSectionKeys,
       _savedAliasFallbackKeys = savedAliasFallbackKeys,
       _reviewedSeparateAliasSectionKeys = reviewedSeparateAliasSectionKeys;

  factory _SavedMappingLookup.build(List<SellerMapping> existingMappings) {
    final exactMappingKeys = <String>{};
    final fallbackMappingKeys = <String>{};
    final savedAliasSectionKeys = <String>{};
    final savedAliasFallbackKeys = <String>{};
    final reviewedSeparateAliasSectionKeys = <String>{};

    for (final mapping in existingMappings) {
      final alias = normalizeName(mapping.aliasName);
      final sectionCode = normalizeSellerMappingSectionCode(
        mapping.sectionCode,
      );
      final isReviewedSeparate = mapping.mappedName
          .trim()
          .toUpperCase()
          .startsWith('__SEPARATE__:');
      final normalizedMappedName = normalizeName(mapping.mappedName);

      if (alias.isEmpty || sectionCode.isEmpty) continue;

      savedAliasSectionKeys.add('$alias|$sectionCode');
      exactMappingKeys.add('$alias|$sectionCode|$normalizedMappedName');
      if (sectionCode != 'ALL' && isReviewedSeparate) {
        reviewedSeparateAliasSectionKeys.add('$alias|$sectionCode');
      }

      if (sectionCode == 'ALL' && !isReviewedSeparate) {
        savedAliasFallbackKeys.add(alias);
        fallbackMappingKeys.add('$alias|$normalizedMappedName');
      }
    }

    return _SavedMappingLookup._(
      exactMappingKeys: exactMappingKeys,
      fallbackMappingKeys: fallbackMappingKeys,
      savedAliasSectionKeys: savedAliasSectionKeys,
      savedAliasFallbackKeys: savedAliasFallbackKeys,
      reviewedSeparateAliasSectionKeys: reviewedSeparateAliasSectionKeys,
    );
  }

  int get exactMappingKeysCount => _exactMappingKeys.length;
  int get fallbackMappingKeysCount => _fallbackMappingKeys.length;
  int get savedAliasKeysCount =>
      _savedAliasSectionKeys.length + _savedAliasFallbackKeys.length;

  bool hasExactMapping({
    required String alias,
    required String sectionCode,
    required String normalizedMappedName,
  }) {
    return _exactMappingKeys.contains(
      '$alias|$sectionCode|$normalizedMappedName',
    );
  }

  bool hasFallbackMapping({
    required String alias,
    required String normalizedMappedName,
  }) {
    return _fallbackMappingKeys.contains('$alias|$normalizedMappedName');
  }

  bool hasAnySavedMapping({
    required String alias,
    required String sectionCode,
  }) {
    return _savedAliasSectionKeys.contains('$alias|$sectionCode') ||
        _savedAliasFallbackKeys.contains(alias);
  }

  bool hasReviewedSeparateDisposition({
    required String alias,
    required String sectionCode,
  }) {
    return _reviewedSeparateAliasSectionKeys.contains('$alias|$sectionCode');
  }
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

bool _isValidSourceSellerKey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;

  final hasAlphabetic = RegExp(r'[A-Za-z]').hasMatch(trimmed);
  final compact = trimmed.replaceAll(RegExp(r'[\s./\\_-]'), '');

  if (RegExp(r'^\d+$').hasMatch(compact)) {
    return false;
  }

  if (_looksLikeDateLikeSellerKey(trimmed)) {
    return false;
  }

  if (_looksLikeInvoiceOrBillSellerKey(trimmed)) {
    return false;
  }

  if (!hasAlphabetic && compact.length < 4) {
    return false;
  }

  return true;
}

bool _looksLikeDateLikeSellerKey(String value) {
  final trimmed = value.trim();
  return RegExp(r'^\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}$').hasMatch(trimmed) ||
      RegExp(r'^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$').hasMatch(trimmed);
}

bool _looksLikeInvoiceOrBillSellerKey(String value) {
  final normalized = value.trim().toUpperCase();
  final compact = normalized.replaceAll(RegExp(r'[\s./\\_-]'), '');
  if (compact.isEmpty) return false;

  if (RegExp(
    r'^(INV|INVOICE|BILL|DOC|VCH|VOUCHER|REF|CHQ)\d+$',
  ).hasMatch(compact)) {
    return true;
  }

  return !RegExp(r'[A-Z]').hasMatch(compact) &&
      RegExp(r'^\d{5,}$').hasMatch(compact);
}

Map<String, dynamic> _serializeNormalizedRowForIsolate(
  NormalizedTransactionRow row,
) {
  return {
    'sourceType': row.sourceType,
    'transactionDateRaw': row.transactionDateRaw,
    'month': row.month,
    'financialYear': row.financialYear,
    'partyName': row.partyName,
    'panNumber': row.panNumber,
    'gstNo': row.gstNo,
    'documentNo': row.documentNo,
    'description': row.description,
    'amount': row.amount,
    'taxableAmount': row.taxableAmount,
    'tdsAmount': row.tdsAmount,
    'section': row.section,
    'normalizedName': row.normalizedName,
    'normalizedPan': row.normalizedPan,
    'normalizedMonth': row.normalizedMonth,
    'normalizedSection': row.normalizedSection,
  };
}

NormalizedTransactionRow _deserializeNormalizedRowForIsolate(
  Map<String, dynamic> row,
) {
  return NormalizedTransactionRow(
    sourceType: row['sourceType'] as String? ?? '',
    transactionDateRaw: row['transactionDateRaw'] as String? ?? '',
    month: row['month'] as String? ?? '',
    financialYear: row['financialYear'] as String? ?? '',
    partyName: row['partyName'] as String? ?? '',
    panNumber: row['panNumber'] as String? ?? '',
    gstNo: row['gstNo'] as String? ?? '',
    documentNo: row['documentNo'] as String? ?? '',
    description: row['description'] as String? ?? '',
    amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
    taxableAmount: (row['taxableAmount'] as num?)?.toDouble() ?? 0.0,
    tdsAmount: (row['tdsAmount'] as num?)?.toDouble() ?? 0.0,
    section: row['section'] as String? ?? '',
    normalizedName: row['normalizedName'] as String? ?? '',
    normalizedPan: row['normalizedPan'] as String? ?? '',
    normalizedMonth: row['normalizedMonth'] as String? ?? '',
    normalizedSection: row['normalizedSection'] as String? ?? '',
  );
}

Map<String, dynamic> _serializeTdsRowForIsolate(Tds26QRow row) {
  return {
    'month': row.month,
    'financialYear': row.financialYear,
    'deducteeName': row.deducteeName,
    'panNumber': row.panNumber,
    'deductedAmount': row.deductedAmount,
    'tds': row.tds,
    'section': row.section,
    'normalizedName': row.normalizedName,
    'normalizedPan': row.normalizedPan,
    'normalizedMonth': row.normalizedMonth,
    'normalizedSection': row.normalizedSection,
  };
}

Tds26QRow _deserializeTdsRowForIsolate(Map<String, dynamic> row) {
  return Tds26QRow(
    month: row['month'] as String? ?? '',
    financialYear: row['financialYear'] as String? ?? '',
    deducteeName: row['deducteeName'] as String? ?? '',
    panNumber: row['panNumber'] as String? ?? '',
    deductedAmount: (row['deductedAmount'] as num?)?.toDouble() ?? 0.0,
    tds: (row['tds'] as num?)?.toDouble() ?? 0.0,
    section: row['section'] as String? ?? '',
    normalizedName: row['normalizedName'] as String? ?? '',
    normalizedPan: row['normalizedPan'] as String? ?? '',
    normalizedMonth: row['normalizedMonth'] as String? ?? '',
    normalizedSection: row['normalizedSection'] as String? ?? '',
  );
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
    'purchasePan': row.purchasePan,
    'purchaseGstNo': row.purchaseGstNo,
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
    purchasePan: row['purchasePan'] as String? ?? '',
    purchaseGstNo: row['purchaseGstNo'] as String? ?? '',
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

Map<String, dynamic> _serializePreflightResultForIsolate(
  SellerMappingPreflightResult result,
) {
  return {
    'reviewRows': result.reviewRows.map(_serializeScreenRowForIsolate).toList(),
    'tdsParties': result.tdsParties,
    'existingMappings': result.existingMappings
        .map(_serializeSellerMappingForIsolate)
        .toList(),
    'blockedAliases': result.blockedAliases.toList(),
    'tdsPartyPans': result.tdsPartyPans,
    'pendingReviewCount': result.pendingReviewCount,
  };
}

SellerMappingPreflightResult _deserializePreflightResultForIsolate(
  Map<String, dynamic> payload,
) {
  return SellerMappingPreflightResult(
    reviewRows: List<Map<String, dynamic>>.from(
      payload['reviewRows'] as List? ?? const [],
    ).map(_deserializeScreenRowForIsolate).toList(),
    tdsParties: List<String>.from(payload['tdsParties'] as List? ?? const []),
    existingMappings: List<Map<String, dynamic>>.from(
      payload['existingMappings'] as List? ?? const [],
    ).map(_deserializeSellerMappingForIsolate).toList(),
    blockedAliases: Set<String>.from(
      payload['blockedAliases'] as List? ?? const [],
    ),
    tdsPartyPans: Map<String, List<String>>.fromEntries(
      Map<String, dynamic>.from(
        payload['tdsPartyPans'] as Map? ?? const {},
      ).entries.map(
        (entry) => MapEntry(
          entry.key,
          List<String>.from(entry.value as List? ?? const []),
        ),
      ),
    ),
    pendingReviewCount: payload['pendingReviewCount'] as int? ?? 0,
  );
}

Future<Map<String, dynamic>> _analyzeSellerMappingPreflightInIsolate(
  Map<String, dynamic> payload,
) async {
  final sourceRowsBySection = <String, List<NormalizedTransactionRow>>{};
  final rawSourceRowsBySection = Map<String, dynamic>.from(
    payload['sourceRowsBySection'] as Map? ?? const {},
  );
  for (final entry in rawSourceRowsBySection.entries) {
    sourceRowsBySection[entry.key] = List<Map<String, dynamic>>.from(
      entry.value as List? ?? const [],
    ).map(_deserializeNormalizedRowForIsolate).toList();
  }

  final result = SellerMappingPreflightService._analyzeWithExistingMappings(
    buyerPan: payload['buyerPan'] as String? ?? '',
    tdsRows: List<Map<String, dynamic>>.from(
      payload['tdsRows'] as List? ?? const [],
    ).map(_deserializeTdsRowForIsolate).toList(),
    sourceRowsBySection: sourceRowsBySection,
    existingMappings: List<Map<String, dynamic>>.from(
      payload['existingMappings'] as List? ?? const [],
    ).map(_deserializeSellerMappingForIsolate).toList(),
  );

  return _serializePreflightResultForIsolate(result);
}
