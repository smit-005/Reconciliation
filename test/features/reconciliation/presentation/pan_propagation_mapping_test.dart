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
}
