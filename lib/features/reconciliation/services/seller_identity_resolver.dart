import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/resolved_seller_identity.dart';

class SellerIdentityObservation {
  final String originalName;
  final String mappedName;
  final String normalizedName;
  final String originalPan;
  final String normalizedPan;

  const SellerIdentityObservation({
    required this.originalName,
    required this.mappedName,
    required this.normalizedName,
    required this.originalPan,
    required this.normalizedPan,
  });
}

class SellerIdentityResolver {
  final Map<String, String> _aliasToPan;
  final Map<String, SellerMapping> _sectionMappings;
  final Map<String, Set<String>> _nameToPans;
  final Map<String, Set<String>> _panToNames;
  final Map<String, int> _namePanObservationCounts;
  final Map<String, String> _nameDisplay;
  final Map<String, String> _panDisplay;

  SellerIdentityResolver._({
    required Map<String, String> aliasToPan,
    required Map<String, SellerMapping> sectionMappings,
    required Map<String, Set<String>> nameToPans,
    required Map<String, Set<String>> panToNames,
    required Map<String, int> namePanObservationCounts,
    required Map<String, String> nameDisplay,
    required Map<String, String> panDisplay,
  }) : _aliasToPan = aliasToPan,
       _sectionMappings = sectionMappings,
       _nameToPans = nameToPans,
       _panToNames = panToNames,
       _namePanObservationCounts = namePanObservationCounts,
       _nameDisplay = nameDisplay,
       _panDisplay = panDisplay;

  factory SellerIdentityResolver.build({
    required List<SellerIdentityObservation> observations,
    required List<SellerMapping> savedMappings,
    required Map<String, String> savedAliasToPan,
  }) {
    final aliasToPan = <String, String>{};
    final sectionMappings = <String, SellerMapping>{};
    final nameToPans = <String, Set<String>>{};
    final panToNames = <String, Set<String>>{};
    final namePanObservationCounts = <String, int>{};
    final nameDisplay = <String, String>{};
    final panDisplay = <String, String>{};

    void rememberDisplay(
      Map<String, String> target,
      String key,
      String candidate,
    ) {
      final trimmed = candidate.trim();
      if (key.isEmpty || trimmed.isEmpty) return;
      final existing = target[key];
      if (existing == null || trimmed.length < existing.length) {
        target[key] = trimmed;
      }
    }

    for (final entry in savedAliasToPan.entries) {
      final alias = normalizeName(entry.key);
      final pan = normalizePan(entry.value);
      if (alias.isEmpty || !looksLikePan(pan)) continue;
      aliasToPan[alias] = pan;
    }

    for (final mapping in savedMappings) {
      final alias = normalizeName(mapping.aliasName);
      final sectionCode = normalizeSellerMappingSectionCode(mapping.sectionCode);
      if (alias.isEmpty || sectionCode.isEmpty) continue;
      sectionMappings['$alias|$sectionCode'] = mapping.copyWith(
        aliasName: alias,
        sectionCode: sectionCode,
      );
    }

    for (final item in observations) {
      final normalizedName = normalizeName(item.normalizedName);
      final normalizedPan = normalizePan(item.normalizedPan);
      final displayName = item.mappedName.trim().isNotEmpty
          ? item.mappedName.trim()
          : item.originalName.trim();

      rememberDisplay(nameDisplay, normalizedName, displayName);
      rememberDisplay(panDisplay, normalizedPan, displayName);

      if (normalizedName.isNotEmpty &&
          normalizedPan.isNotEmpty &&
          looksLikePan(normalizedPan)) {
        nameToPans.putIfAbsent(normalizedName, () => <String>{}).add(normalizedPan);
        panToNames.putIfAbsent(normalizedPan, () => <String>{}).add(normalizedName);
        final observationKey = '$normalizedName|$normalizedPan';
        namePanObservationCounts[observationKey] =
            (namePanObservationCounts[observationKey] ?? 0) + 1;
      }
    }

    return SellerIdentityResolver._(
      aliasToPan: aliasToPan,
      sectionMappings: sectionMappings,
      nameToPans: nameToPans,
      panToNames: panToNames,
      namePanObservationCounts: namePanObservationCounts,
      nameDisplay: nameDisplay,
      panDisplay: panDisplay,
    );
  }

  ResolvedSellerIdentity resolve({
    required String buyerPan,
    required String originalName,
    required String mappedName,
    required String originalPan,
    required String sectionCode,
  }) {
    final normalizedBuyerPan = normalizePan(buyerPan);
    final normalizedName = normalizeName(
      mappedName.trim().isNotEmpty ? mappedName : originalName,
    );
    final normalizedAliasName = normalizeName(
      originalName.trim().isNotEmpty ? originalName : mappedName,
    );
    final normalizedPan = normalizePan(originalPan);
    final normalizedSectionCode = normalizeSellerMappingSectionCode(sectionCode);
    final flags = <String>{};
    final mappingAttempted =
        normalizedBuyerPan.isNotEmpty && normalizedAliasName.isNotEmpty;
    final exactMapping = mappingAttempted
        ? _sectionMappings['$normalizedAliasName|$normalizedSectionCode']
        : null;
    final fallbackMapping = mappingAttempted
        ? _sectionMappings['$normalizedAliasName|ALL']
        : null;
    final activeMapping = exactMapping ?? fallbackMapping;
    final mappingHit = exactMapping != null
        ? 'exact'
        : (fallbackMapping != null ? 'fallback' : 'none');
    final mappingSectionUsed = exactMapping != null
        ? normalizedSectionCode
        : (fallbackMapping != null ? 'ALL' : normalizedSectionCode);

    if (activeMapping != null) {
      final mappedPan = normalizePan(activeMapping.mappedPan);
      final mappedResolvedName = activeMapping.mappedName.trim().isNotEmpty
          ? activeMapping.mappedName.trim()
          : (mappedName.trim().isNotEmpty ? mappedName.trim() : originalName.trim());

      if (looksLikePan(normalizedPan) &&
          looksLikePan(mappedPan) &&
          normalizedPan != mappedPan) {
        flags.add('conflicting_pan');
        flags.add('ambiguous_identity');

        return _resolveWithoutMapping(
          normalizedName: normalizedName,
          normalizedPan: normalizedPan,
          originalName: originalName,
          mappingAttempted: mappingAttempted,
          mappingSectionUsed: mappingSectionUsed,
          mappingHit: mappingHit,
          extraFlags: flags,
          extraNotes:
              'Section-aware mapping was found for $mappingSectionUsed but ignored because mapped PAN $mappedPan conflicts with row PAN $normalizedPan.',
        );
      }

      final resolvedPan = looksLikePan(mappedPan)
          ? mappedPan
          : (looksLikePan(normalizedPan) ? normalizedPan : '');
      final resolvedSellerId = looksLikePan(resolvedPan)
          ? 'PAN:$resolvedPan'
          : 'NAME:${normalizeName(mappedResolvedName)}';
      final mappingNotes = mappingHit == 'exact'
          ? 'Resolved using exact section mapping for $mappingSectionUsed.'
          : 'Resolved using ALL fallback mapping because no exact section mapping matched $normalizedSectionCode.';

      final mappingFlags = <String>{
        if (mappingHit == 'exact') 'mapping_exact',
        if (mappingHit == 'fallback') 'mapping_fallback',
        if (looksLikePan(resolvedPan)) 'pan_verified',
      }.toList()
        ..sort();

      return ResolvedSellerIdentity(
        resolvedSellerId: resolvedSellerId,
        resolvedSellerName: mappedResolvedName.isEmpty
            ? _displayNameForName(normalizedName, originalName)
            : mappedResolvedName,
        resolvedPan: resolvedPan,
        identitySource:
            mappingHit == 'exact' ? 'mapping_exact' : 'mapping_fallback',
        identityConfidence: 1.0,
        identityNotes: mappingNotes,
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: mappingFlags,
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: normalizedPan,
      );
    }

    return _resolveWithoutMapping(
      normalizedName: normalizedName,
      normalizedPan: normalizedPan,
      originalName: originalName,
      mappingAttempted: mappingAttempted,
      mappingSectionUsed: mappingSectionUsed,
      mappingHit: mappingHit,
      extraFlags: flags,
    );
  }

  ResolvedSellerIdentity _resolveWithoutMapping({
    required String normalizedName,
    required String normalizedPan,
    required String originalName,
    required bool mappingAttempted,
    required String mappingSectionUsed,
    required String mappingHit,
    Set<String>? extraFlags,
    String extraNotes = '',
  }) {
    final flags = <String>{...?extraFlags};

    if (looksLikePan(normalizedPan)) {
      flags.add('pan_verified');
      final conflictingNames = _panToNames[normalizedPan] ?? const <String>{};
      if (conflictingNames.length > 1) {
        flags.add('ambiguous_identity');
        flags.add('conflicting_pan');
      }

      return ResolvedSellerIdentity(
        resolvedSellerId: 'PAN:$normalizedPan',
        resolvedSellerName: _displayNameForPan(normalizedPan, normalizedName, originalName),
        resolvedPan: normalizedPan,
        identitySource: 'pan',
        identityConfidence: conflictingNames.length > 1 ? 0.78 : 1.0,
        identityNotes: [
          conflictingNames.length > 1
              ? 'PAN matched directly, but this PAN is associated with multiple normalized seller names in the imported data.'
              : 'PAN matched directly from source data.',
          extraNotes,
        ].where((value) => value.trim().isNotEmpty).join(' '),
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: flags.toList()..sort(),
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: normalizedPan,
      );
    }

    final aliasPan = _aliasToPan[normalizedName] ?? '';
    if (looksLikePan(aliasPan)) {
      flags.add('alias_matched');
      return ResolvedSellerIdentity(
        resolvedSellerId: 'PAN:$aliasPan',
        resolvedSellerName: _displayNameForPan(aliasPan, normalizedName, originalName),
        resolvedPan: aliasPan,
        identitySource: 'alias',
        identityConfidence: 0.92,
        identityNotes: [
          'Resolved using saved alias mapping because PAN was missing in the current row.',
          extraNotes,
        ].where((value) => value.trim().isNotEmpty).join(' '),
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: flags.toList()..sort(),
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: '',
      );
    }

    final candidatePans = _nameToPans[normalizedName] ?? const <String>{};
    if (normalizedName.isNotEmpty && candidatePans.length == 1) {
      flags.add('name_only_match');
      final matchedPan = candidatePans.first;
      final observationCount =
          _namePanObservationCounts['$normalizedName|$matchedPan'] ?? 0;

      if (observationCount < 2) {
        flags.add('unresolved_identity');
        return ResolvedSellerIdentity(
          resolvedSellerId: 'NAME:$normalizedName',
          resolvedSellerName: _displayNameForName(normalizedName, originalName),
          resolvedPan: '',
          identitySource: 'normalized_name',
          identityConfidence: 0.45,
          identityNotes: [
            'PAN missing and only one weak PAN observation exists for this normalized seller name, so it was not auto-merged.',
            extraNotes,
          ].where((value) => value.trim().isNotEmpty).join(' '),
          mappingAttempted: mappingAttempted,
          mappingSectionUsed: mappingSectionUsed,
          mappingHit: mappingHit,
          identityFlags: flags.toList()..sort(),
          originalSellerName: originalName.trim(),
          normalizedSellerName: normalizedName,
          originalPan: '',
        );
      }

      return ResolvedSellerIdentity(
        resolvedSellerId: 'PAN:$matchedPan',
        resolvedSellerName: _displayNameForPan(matchedPan, normalizedName, originalName),
        resolvedPan: matchedPan,
        identitySource: 'normalized_name',
        identityConfidence: 0.8,
        identityNotes: [
          'PAN missing in this row; resolved to the only PAN repeatedly seen for this normalized seller name.',
          extraNotes,
        ].where((value) => value.trim().isNotEmpty).join(' '),
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: flags.toList()..sort(),
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: '',
      );
    }

    if (normalizedName.isNotEmpty && candidatePans.length > 1) {
      flags.add('ambiguous_identity');
      flags.add('conflicting_pan');
      return ResolvedSellerIdentity(
        resolvedSellerId: 'NAME:$normalizedName',
        resolvedSellerName: _displayNameForName(normalizedName, originalName),
        resolvedPan: '',
        identitySource: 'normalized_name',
        identityConfidence: 0.35,
        identityNotes: [
          'PAN missing and the same normalized seller name appears with multiple PANs, so the row was kept name-scoped instead of being merged unsafely.',
          extraNotes,
        ].where((value) => value.trim().isNotEmpty).join(' '),
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: flags.toList()..sort(),
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: '',
      );
    }

    if (normalizedName.isNotEmpty) {
      flags.add('unresolved_identity');
      flags.add('name_only_match');
      return ResolvedSellerIdentity(
        resolvedSellerId: 'NAME:$normalizedName',
        resolvedSellerName: _displayNameForName(normalizedName, originalName),
        resolvedPan: '',
        identitySource: 'normalized_name',
        identityConfidence: 0.55,
        identityNotes: [
          'PAN missing; resolved by normalized seller name only.',
          extraNotes,
        ].where((value) => value.trim().isNotEmpty).join(' '),
        mappingAttempted: mappingAttempted,
        mappingSectionUsed: mappingSectionUsed,
        mappingHit: mappingHit,
        identityFlags: flags.toList()..sort(),
        originalSellerName: originalName.trim(),
        normalizedSellerName: normalizedName,
        originalPan: '',
      );
    }

    flags.add('unresolved_identity');
    return ResolvedSellerIdentity(
      resolvedSellerId: 'FALLBACK:${originalName.trim().toUpperCase()}',
      resolvedSellerName: originalName.trim().isEmpty ? 'Unknown Seller' : originalName.trim(),
      resolvedPan: '',
      identitySource: 'fallback',
      identityConfidence: 0.1,
      identityNotes: [
        'Seller name and PAN were both unavailable after normalization.',
        extraNotes,
      ].where((value) => value.trim().isNotEmpty).join(' '),
      mappingAttempted: mappingAttempted,
      mappingSectionUsed: mappingSectionUsed,
      mappingHit: mappingHit,
      identityFlags: flags.toList()..sort(),
      originalSellerName: originalName.trim(),
      normalizedSellerName: '',
      originalPan: '',
    );
  }

  String _displayNameForPan(
    String pan,
    String normalizedName,
    String originalName,
  ) {
    return _panDisplay[pan]?.trim().isNotEmpty == true
        ? _panDisplay[pan]!.trim()
        : _displayNameForName(normalizedName, originalName);
  }

  String _displayNameForName(String normalizedName, String originalName) {
    return _nameDisplay[normalizedName]?.trim().isNotEmpty == true
        ? _nameDisplay[normalizedName]!.trim()
        : (originalName.trim().isEmpty ? 'Unknown Seller' : originalName.trim());
  }
}
