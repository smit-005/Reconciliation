import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/features/reconciliation/models/normalized/normalized_transaction_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/raw/tds_26q_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/seller_mapping.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/screens/seller_mapping_screen.dart';
import 'package:reconciliation_app/features/reconciliation/services/seller_mapping_service.dart';

/// Service for preparing seller mapping data independent of reconciliation
/// This decouples seller mapping initialization from the ReconciliationScreen
class SellerMappingPreparationService {
  /// Build all required data for SellerMappingScreen
  static Future<SellerMappingPreparationResult> prepareMappingData({
    required String buyerName,
    required String buyerPan,
    required List<Tds26QRow> tdsRows,
    required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
  }) async {
    // Load existing mappings from DB
    final existingMappings = await SellerMappingService.getAllMappings(
      buyerPan.trim().toUpperCase(),
    );

    // Extract TDS parties
    final tdsParties = _extractTdsParties(tdsRows);

    // Build TDS party PANs lookup
    final tdsPartyPans = _buildTdsPartyPans(tdsRows);

    // Collect all purchase row data
    final purchaseRowsData = _buildPurchaseRowsData(
      sourceRowsBySection: sourceRowsBySection,
      tdsParties: tdsParties,
      buyerPan: buyerPan,
      existingMappings: existingMappings,
    );

    // Extract blocked aliases
    final blockedAliases = _extractBlockedAliases(purchaseRowsData);

    return SellerMappingPreparationResult(
      purchaseRows: purchaseRowsData,
      tdsParties: tdsParties,
      existingMappings: existingMappings,
      blockedAliases: blockedAliases,
      tdsPartyPans: tdsPartyPans,
    );
  }

  /// Load and normalize existing manual mappings into a map
  static Future<Map<String, String>> loadManualMappings(String buyerPan) async {
    final mappings = await SellerMappingService.getAllMappings(
      buyerPan.trim().toUpperCase(),
    );

    final latest = <String, String>{};
    final mappingsByAlias = <String, List<SellerMapping>>{};

    for (final mapping in mappings) {
      final aliasKey = normalizeName(mapping.aliasName.trim());
      if (aliasKey.isEmpty) continue;
      mappingsByAlias.putIfAbsent(aliasKey, () => <SellerMapping>[]);
      mappingsByAlias[aliasKey]!.add(mapping);
    }

    for (final entry in mappingsByAlias.entries) {
      final mappedNames = entry.value
          .map((mapping) => mapping.mappedName.trim())
          .where((name) => name.isNotEmpty)
          .toSet();

      if (mappedNames.length != 1) continue;
      latest[entry.key] = mappedNames.first;
    }

    return latest;
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
      if (name.isNotEmpty && pan.isNotEmpty) {
        result.putIfAbsent(name, () => <String>[]);
        if (!result[name]!.contains(pan)) {
          result[name]!.add(pan);
        }
      }
    }
    return result;
  }

  static List<SellerMappingScreenRowData> _buildPurchaseRowsData({
    required Map<String, List<NormalizedTransactionRow>> sourceRowsBySection,
    required List<String> tdsParties,
    required String buyerPan,
    required List<SellerMapping> existingMappings,
  }) {
    final rowsData = <SellerMappingScreenRowData>[];
    final seen = <String>{};

    for (final section in sourceRowsBySection.keys) {
      final rows = sourceRowsBySection[section] ?? [];

      for (final row in rows) {
        final aliasKey = _buildAliasKey(row.partyName, row.section);
        if (seen.contains(aliasKey)) continue;
        seen.add(aliasKey);

        final normalizedAlias = normalizeName(row.partyName.trim());
        final sectionCode = normalizeSellerMappingSectionCode(row.section);

        // Check for existing mapping suggestion
        final exactMapping = existingMappings
            .where(
              (m) =>
                  normalizeName(m.aliasName) == normalizedAlias &&
                  normalizeSellerMappingSectionCode(m.sectionCode) ==
                      sectionCode,
            )
            .firstOrNull;

        final fallbackMapping = existingMappings
            .where(
              (m) =>
                  normalizeName(m.aliasName) == normalizedAlias &&
                  normalizeSellerMappingSectionCode(m.sectionCode) == 'ALL',
            )
            .firstOrNull;

        final resolvedMapping = exactMapping ?? fallbackMapping;

        SellerMappingResolvedSuggestion? resolvedSuggestion;
        if (resolvedMapping != null) {
          resolvedSuggestion = SellerMappingResolvedSuggestion(
            mappedName: resolvedMapping.mappedName,
            mappedPan: resolvedMapping.mappedPan,
            source: exactMapping != null ? 'Exact Match' : 'Fallback (All)',
          );
        }

        rowsData.add(
          SellerMappingScreenRowData(
            purchasePartyDisplayName: row.partyName.trim(),
            normalizedAlias: normalizedAlias,
            sectionCode: sectionCode,
            purchasePan: normalizePan(row.panNumber),
            resolvedSuggestion: resolvedSuggestion,
            isReadOnly: false,
            isAboveThreshold: false,
            hasReconciliationMismatch: false,
            hasNameOrPanConflict: false,
            hasApplicableTdsImpact: false,
            is26QUnmatched: false,
            hasMissingOrUncertainPan: false,
          ),
        );
      }
    }

    return rowsData;
  }

  static String _buildAliasKey(String sellerName, String section) {
    return '${normalizeName(sellerName.trim())}|${normalizeSellerMappingSectionCode(section)}';
  }

  static Set<String> _extractBlockedAliases(
    List<SellerMappingScreenRowData> rowsData,
  ) {
    // In the future, this can be used to block certain aliases from being mapped
    return {};
  }
}

class SellerMappingPreparationResult {
  final List<SellerMappingScreenRowData> purchaseRows;
  final List<String> tdsParties;
  final List<SellerMapping> existingMappings;
  final Set<String> blockedAliases;
  final Map<String, List<String>> tdsPartyPans;

  const SellerMappingPreparationResult({
    required this.purchaseRows,
    required this.tdsParties,
    required this.existingMappings,
    required this.blockedAliases,
    required this.tdsPartyPans,
  });

  bool get hasData => purchaseRows.isNotEmpty;
  int get purchaseRowCount => purchaseRows.length;
  int get tdsPartyCount => tdsParties.length;
}
