import 'package:flutter_test/flutter_test.dart';

import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_row.dart';
import 'package:reconciliation_app/features/reconciliation/models/result/reconciliation_status.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/utils/reconciliation_export_row_scope.dart';
import 'package:reconciliation_app/features/reconciliation/utils/reconciliation_section_utils.dart';

void main() {
  test('section tab list adds Unsupported when unsupported sections exist', () {
    final tabs = reconciliationSectionTabsForRows(['194C', 'UNKNOWN', '194P']);

    expect(tabs, contains(unsupportedReconciliationSectionTab));
  });

  test('section tab list keeps supported-only rows unchanged', () {
    final tabs = reconciliationSectionTabsForRows(['194C', '194Q']);

    expect(tabs, isNot(contains(unsupportedReconciliationSectionTab)));
    expect(tabs, containsAll(['All', '194C', '194Q']));
  });

  test('Current View export row scope matches visible table rows', () {
    final belowThresholdHistory = _row(
      sellerName: 'Visible Seller',
      month: 'Apr-2025',
      status: ReconciliationStatus.belowThreshold,
      applicableAmount: 0,
      expectedTds: 0,
      actualTds: 0,
      tds26QAmount: 0,
      tdsDifference: 0,
    );
    final applicableVisibleRow = _row(
      sellerName: 'Visible Seller',
      month: 'May-2025',
      status: ReconciliationStatus.applicableButNo26Q,
    );
    final hiddenByUserFilter = _row(
      sellerName: 'Hidden Seller',
      month: 'Apr-2025',
      status: ReconciliationStatus.shortDeduction,
    );

    final visibleTableRows = [belowThresholdHistory, applicableVisibleRow];
    final exportRows = ReconciliationExportRowScope.currentViewRows(
      visibleTableRows: visibleTableRows,
    );

    expect(exportRows, orderedEquals(visibleTableRows));
    expect(exportRows, isNot(contains(hiddenByUserFilter)));
  });

  test('section and report scopes use full detail rows for selected FY', () {
    final belowThreshold194C = _row(
      sellerName: 'Below Threshold Contractor',
      section: '194C',
      status: ReconciliationStatus.belowThreshold,
      applicableAmount: 0,
      expectedTds: 0,
      actualTds: 0,
      tds26QAmount: 0,
      tdsDifference: 0,
    );
    final applicable194C = _row(
      sellerName: 'Applicable Contractor',
      section: '194C',
      status: ReconciliationStatus.applicableButNo26Q,
    );
    final otherSection = _row(sellerName: 'Interest Vendor', section: '194A');
    final otherFy = _row(
      sellerName: 'Old Contractor',
      section: '194C',
      financialYear: '2024-25',
    );

    final allRows = [applicable194C, otherSection, belowThreshold194C, otherFy];

    final sectionRows = ReconciliationExportRowScope.sectionRows(
      allRows: allRows,
      selectedSection: '194C',
      selectedFinancialYear: '2025-26',
    );
    final reportRows = ReconciliationExportRowScope.reportRows(
      allRows: allRows,
      selectedFinancialYear: '2025-26',
    );

    expect(sectionRows, containsAll([belowThreshold194C, applicable194C]));
    expect(sectionRows, isNot(contains(otherSection)));
    expect(sectionRows, isNot(contains(otherFy)));

    expect(reportRows, containsAll([belowThreshold194C, applicable194C]));
    expect(reportRows, contains(otherSection));
    expect(reportRows, isNot(contains(otherFy)));
  });

  test(
    'unsupported section scope includes UNKNOWN and explicit unsupported rows',
    () {
      final unknownRow = _row(
        sellerName: 'Unknown Section Seller',
        section: 'UNKNOWN',
        status: ReconciliationStatus.sectionMissing,
      );
      final unsupportedRow = _row(
        sellerName: 'Unsupported 194P Seller',
        section: '194P',
      );
      final supportedRow = _row(sellerName: 'Supported Contractor');
      final otherFy = _row(
        sellerName: 'Old Unsupported Seller',
        section: '194P',
        financialYear: '2024-25',
      );

      final sectionRows = ReconciliationExportRowScope.sectionRows(
        allRows: [supportedRow, unknownRow, unsupportedRow, otherFy],
        selectedSection: unsupportedReconciliationSectionTab,
        selectedFinancialYear: '2025-26',
      );

      expect(sectionRows, containsAll([unknownRow, unsupportedRow]));
      expect(sectionRows, isNot(contains(supportedRow)));
      expect(sectionRows, isNot(contains(otherFy)));
    },
  );
}

ReconciliationRow _row({
  String sellerName = 'Vendor',
  String section = '194C',
  String financialYear = '2025-26',
  String month = 'Apr-2025',
  String status = ReconciliationStatus.onlyIn26Q,
  double basicAmount = 25000,
  double? applicableAmount,
  double? tds26QAmount,
  double? expectedTds,
  double? actualTds,
  double? tdsDifference,
}) {
  final resolvedApplicableAmount = applicableAmount ?? basicAmount;
  final resolvedTds26QAmount = tds26QAmount ?? basicAmount;
  final resolvedExpectedTds = expectedTds ?? resolvedApplicableAmount * 0.10;
  final resolvedActualTds =
      actualTds ?? (status == ReconciliationStatus.matched ? 2500 : 0);
  final resolvedTdsDifference =
      tdsDifference ?? (status == ReconciliationStatus.matched ? 0 : 2500);

  return ReconciliationRow(
    buyerName: 'Radha Industries',
    buyerPan: 'ABCDE1234F',
    financialYear: financialYear,
    month: month,
    sellerName: sellerName,
    sellerPan: 'AAAAA1111A',
    section: section,
    resolvedSellerId: 'PAN:AAAAA1111A',
    resolvedSellerName: sellerName,
    resolvedPan: 'AAAAA1111A',
    basicAmount: basicAmount,
    applicableAmount: resolvedApplicableAmount,
    tds26QAmount: resolvedTds26QAmount,
    expectedTds: resolvedExpectedTds,
    actualTds: resolvedActualTds,
    tdsRateUsed: 0.10,
    amountDifference: 0,
    tdsDifference: resolvedTdsDifference,
    status: status,
    remarks: '',
    purchasePresent: true,
    tdsPresent: true,
    openingTimingBalance: 0,
    monthTdsDifference: 0,
    closingTimingBalance: 0,
  );
}
