import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/pan_propagation_mapping.dart';

void main() {
  group('buildPanPropagationMapping', () {
    test('keeps manual mappings for PAN propagation', () {
      final mapping = buildPanPropagationMapping(
        manualMappings: const [
          MapEntry(
            'Dev Cotton & Oil Industries',
            'Dev Cotton & Oil Industries',
          ),
        ],
        autoMappings: const [],
      );

      expect(mapping.keys, contains('DEVCOTTONANDOILINDUSTRIES'));
      expect(
        mapping['DEVCOTTONANDOILINDUSTRIES'],
        'Dev Cotton & Oil Industries',
      );
    });

    test('keeps section-aware manual mapping keys intact', () {
      final mapping = buildPanPropagationMapping(
        manualMappings: const [
          MapEntry('Shared Alias Vendor|194C', 'Contract Vendor'),
        ],
        autoMappings: const [],
      );

      expect(mapping.keys, contains('SHAREDALIASVENDOR|194C'));
      expect(mapping['SHAREDALIASVENDOR|194C'], 'Contract Vendor');
    });

    test('allows auto propagation only for exact normalized-name matches', () {
      final mapping = buildPanPropagationMapping(
        manualMappings: const [],
        autoMappings: const [
          (
            purchaseParty: 'Dev Cotton And Oil Industries',
            mappedTdsParty: 'Dev Cotton & Oil Industries',
          ),
          (
            purchaseParty: 'Dev Oil Industries',
            mappedTdsParty: 'Dev Cotton & Oil Industries',
          ),
        ],
      );

      expect(mapping.keys, contains('DEVCOTTONANDOILINDUSTRIES'));
      expect(mapping.keys, isNot(contains('DEVOILINDUSTRIES')));
    });
  });

  group('section-aware PAN propagation lookup', () {
    test('does not resolve PAN from another section for same seller name', () {
      final exactLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: false,
      );
      final normalizedLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: true,
      );

      final pan = resolveSectionAwarePanPropagation(
        exactTdsPanLookup: exactLookup,
        normalizedTdsPanLookup: normalizedLookup,
        mappedName: 'Shared Vendor',
        sectionCode: '194J_B',
      );

      expect(pan, isEmpty);
    });

    test('resolves PAN within the same section for same seller name', () {
      final exactLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: false,
      );
      final normalizedLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: true,
      );

      final pan = resolveSectionAwarePanPropagation(
        exactTdsPanLookup: exactLookup,
        normalizedTdsPanLookup: normalizedLookup,
        mappedName: 'Shared Vendor',
        sectionCode: '194C',
      );

      expect(pan, 'AAAAA1111A');
      expect(exactLookup, containsPair('SHARED VENDOR|194C', 'AAAAA1111A'));
      expect(normalizedLookup, containsPair('SHAREDVENDOR|194C', 'AAAAA1111A'));
    });

    test('does not resolve PAN when same section has multiple PANs', () {
      final exactLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
          (
            sellerName: 'Shared Vendor',
            panNumber: 'BBBBB2222B',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: false,
      );
      final normalizedLookup = buildSectionAwarePanPropagationLookup(
        candidates: const [
          (
            sellerName: 'Shared Vendor',
            panNumber: 'AAAAA1111A',
            sectionCode: '194C',
          ),
          (
            sellerName: 'Shared Vendor',
            panNumber: 'BBBBB2222B',
            sectionCode: '194C',
          ),
        ],
        normalizeSellerName: true,
      );

      final pan = resolveSectionAwarePanPropagation(
        exactTdsPanLookup: exactLookup,
        normalizedTdsPanLookup: normalizedLookup,
        mappedName: 'Shared Vendor',
        sectionCode: '194C',
      );

      expect(pan, isEmpty);
      expect(exactLookup, isNot(contains('SHARED VENDOR|194C')));
      expect(normalizedLookup, isNot(contains('SHAREDVENDOR|194C')));
    });
  });
}
