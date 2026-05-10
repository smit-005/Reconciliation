import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/core/config/tds_section_catalog.dart';

void main() {
  group('TdsSectionCatalog', () {
    test('exposes the supported section order including 194A', () {
      expect(TdsSectionCatalog.supportedSectionCodes, const [
        '194Q',
        '194A',
        '194C',
        '194H',
        '194I_A',
        '194I_B',
        '194J_A',
        '194J_B',
      ]);
      expect(TdsSectionCatalog.isSupported('194A'), isTrue);
    });

    test('normalizes supported section labels', () {
      expect(TdsSectionCatalog.normalizeCode('Section 194A interest'), '194A');
      expect(
        TdsSectionCatalog.normalizeCode('Section 194I(A) machinery rent'),
        '194I_A',
      );
      expect(
        TdsSectionCatalog.normalizeCode('Section 194J B professional fees'),
        '194J_B',
      );
    });

    test('provides display labels from the central catalog', () {
      expect(TdsSectionCatalog.displayLabel('194A'), '194A');
      expect(
        TdsSectionCatalog.displayLabel('194I_A'),
        '194I(a) Machinery / Plant / Equipment Rent',
      );
      expect(TdsSectionCatalog.displayLabel('UNKNOWN'), 'UNKNOWN');
    });
  });
}
