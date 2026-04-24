import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/features/reconciliation/services/reconciliation_remark_templates.dart';
import 'package:reconciliation_app/features/reconciliation/services/section_rule_service.dart';

void main() {
  group('SectionRuleService 194Q config migration', () {
    test('below threshold has no applicability', () {
      final result = SectionRuleService.applyRule(
        section: '194Q',
        cumulativePurchase: 4990000,
        previousCumulative: 4900000,
        currentAmount: 90000,
        sectionCumulative: 90000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('crossing row applies excess amount only', () {
      final result = SectionRuleService.applyRule(
        section: '194Q',
        cumulativePurchase: 5030000,
        previousCumulative: 4980000,
        currentAmount: 50000,
        sectionCumulative: 50000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 30000);
      expect(result.rate, 0.001);
      expect(result.expectedTds, 30);
      expect(result.manualReviewRequired, isFalse);
    });

    test('post-threshold has full applicability', () {
      final result = SectionRuleService.applyRule(
        section: '194Q',
        cumulativePurchase: 5100000,
        previousCumulative: 5050000,
        currentAmount: 50000,
        sectionCumulative: 50000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 50000);
      expect(result.rate, 0.001);
      expect(result.expectedTds, 50);
      expect(result.manualReviewRequired, isFalse);
    });

    test('expected TDS equals applicable amount times 0.1 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194Q',
        cumulativePurchase: 5012345,
        previousCumulative: 4999999,
        currentAmount: 12346,
        sectionCumulative: 12346,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 12345);
      expect(result.rate, 0.001);
      expect(result.expectedTds, 12.35);
      expect(result.manualReviewRequired, isFalse);
    });
  });

  group('SectionRuleService 194C config pilot', () {
    test('below both thresholds returns zero amounts', () {
      final result = SectionRuleService.applyRule(
        section: '194C',
        cumulativePurchase: 25000,
        previousCumulative: 0,
        currentAmount: 25000,
        sectionCumulative: 25000,
        previousSectionCumulative: 0,
        sellerPan: 'ABCDE1234F',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('single transaction threshold uses individual rate', () {
      final result = SectionRuleService.applyRule(
        section: '194C',
        cumulativePurchase: 35000,
        previousCumulative: 0,
        currentAmount: 35000,
        sectionCumulative: 35000,
        previousSectionCumulative: 0,
        sellerPan: 'ABCPH1234K',
      );

      expect(result.applicableAmount, 35000);
      expect(result.rate, 0.01);
      expect(result.expectedTds, 350);
      expect(result.manualReviewRequired, isFalse);
    });

    test('aggregate threshold uses business rate', () {
      final result = SectionRuleService.applyRule(
        section: '194C',
        cumulativePurchase: 110000,
        previousCumulative: 90000,
        currentAmount: 20000,
        sectionCumulative: 110000,
        previousSectionCumulative: 90000,
        sellerPan: 'ABCFA1234K',
      );

      expect(result.applicableAmount, 20000);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 400);
      expect(result.manualReviewRequired, isFalse);
    });

    test('missing PAN keeps current manual review behavior', () {
      final result = SectionRuleService.applyRule(
        section: '194C',
        cumulativePurchase: 110000,
        previousCumulative: 90000,
        currentAmount: 20000,
        sectionCumulative: 110000,
        previousSectionCumulative: 90000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 20000);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isTrue);
      expect(
        result.reviewReason,
        ReconciliationRemarkTemplates.manualReview('194C'),
      );
    });
  });

  group('SectionRuleService 194H config migration', () {
    test('below threshold is not applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194H',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 15000,
        sectionCumulative: 15000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('crossing threshold is applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194H',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 5000,
        sectionCumulative: 21000,
        previousSectionCumulative: 16000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 5000);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 100);
      expect(result.manualReviewRequired, isFalse);
    });

    test('after threshold is applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194H',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 12000,
        sectionCumulative: 52000,
        previousSectionCumulative: 40000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 12000);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 240);
      expect(result.manualReviewRequired, isFalse);
    });

    test('expected TDS equals applicable amount times 2 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194H',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 12345,
        sectionCumulative: 32345,
        previousSectionCumulative: 20000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 12345);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 246.9);
      expect(result.manualReviewRequired, isFalse);
    });
  });

  group('SectionRuleService 194J split config migration', () {
    test('194J_A below threshold is not applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194J_A',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 20000,
        sectionCumulative: 20000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194J_A above threshold applies 2 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194J_A',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 10000,
        sectionCumulative: 60000,
        previousSectionCumulative: 50000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 10000);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 200);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194J_B below threshold is not applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194J_B',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 25000,
        sectionCumulative: 25000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194J_B above threshold applies 10 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194J_B',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 15000,
        sectionCumulative: 70000,
        previousSectionCumulative: 55000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 15000);
      expect(result.rate, 0.10);
      expect(result.expectedTds, 1500);
      expect(result.manualReviewRequired, isFalse);
    });
  });

  group('SectionRuleService 194I split config migration', () {
    test('194I_A below threshold is not applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194I_A',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 20000,
        sectionCumulative: 20000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194I_A above threshold applies 2 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194I_A',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 12000,
        sectionCumulative: 62000,
        previousSectionCumulative: 50000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 12000);
      expect(result.rate, 0.02);
      expect(result.expectedTds, 240);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194I_B below threshold is not applicable', () {
      final result = SectionRuleService.applyRule(
        section: '194I_B',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 30000,
        sectionCumulative: 30000,
        previousSectionCumulative: 0,
        sellerPan: '',
      );

      expect(result.applicableAmount, 0);
      expect(result.expectedTds, 0);
      expect(result.rate, 0);
      expect(result.manualReviewRequired, isFalse);
    });

    test('194I_B above threshold applies 10 percent', () {
      final result = SectionRuleService.applyRule(
        section: '194I_B',
        cumulativePurchase: 0,
        previousCumulative: 0,
        currentAmount: 18000,
        sectionCumulative: 68000,
        previousSectionCumulative: 50000,
        sellerPan: '',
      );

      expect(result.applicableAmount, 18000);
      expect(result.rate, 0.10);
      expect(result.expectedTds, 1800);
      expect(result.manualReviewRequired, isFalse);
    });
  });
}
