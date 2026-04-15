import '../../services/mapping_service.dart';

class PurchaseRow {
  final String date;
  final String month;
  final String billNo;
  final String partyName;
  final String gstNo;
  final String panNumber;
  final String productName;
  final double basicAmount;
  final double billAmount;

  PurchaseRow({
    required this.date,
    required this.month,
    required this.billNo,
    required this.partyName,
    required this.gstNo,
    required this.panNumber,
    required this.productName,
    required this.basicAmount,
    required this.billAmount,
  });

  factory PurchaseRow.fromMap(Map<String, dynamic> map) {
    final rawDate = _readAny(map, ['eom', 'date']) ?? '';
    final rawGst = (_readAny(map, ['gst_no']) ?? '').trim().toUpperCase();
    final rawPan = _normalizePan(_readAny(map, ['pan_number']) ?? '');
    final finalPan = rawPan.isNotEmpty ? rawPan : _extractPanFromGstin(rawGst);

    return PurchaseRow(
      date: rawDate,
      month: _normalizeMonth(rawDate),
      billNo: (_readAny(map, ['bill_no']) ?? '').trim(),
      partyName: (_readAny(map, ['party_name']) ?? '').trim(),
      gstNo: rawGst,
      panNumber: finalPan,
      productName: (_readAny(map, ['productname']) ?? '').trim(),
      basicAmount: _parseDouble(
        _readAny(map, ['basic_amount', 'product_amount', 'taxable_amount']),
      ),
      billAmount: _parseDouble(
        _readAny(map, ['bill_amount', 'total_amount', 'gross_amount']),
      ),
    );
  }
}

class Tds26QRow {
  final String month;
  final String deducteeName;
  final String panNumber;
  final double deductedAmount;
  final double tds;
  final String section;

  Tds26QRow({
    required this.month,
    required this.deducteeName,
    required this.panNumber,
    required this.deductedAmount,
    required this.tds,
    required this.section,
  });

  factory Tds26QRow.fromMap(Map<String, dynamic> map) {
    final rawDate = _readAny(map, ['date_month', 'date']) ?? '';

    return Tds26QRow(
      month: _normalizeMonth(rawDate),
      deducteeName: (_readAny(map, ['party_name', 'name']) ?? '').trim(),
      panNumber: _normalizePan(_readAny(map, ['pan_number']) ?? ''),
      deductedAmount: _parseDouble(_readAny(map, ['deducted_amount'])),
      tds: _parseDouble(_readAny(map, ['tds'])),
      section: _normalizeSection((_readAny(map, ['section']) ?? '').trim()),
    );
  }
}

class ReconciliationRow {
  final String buyerName;
  final String buyerPan;
  final String financialYear;
  final String month;

  final String sellerName;
  final String sellerPan;
  final String section;

  final double basicAmount;
  final double applicableAmount;

  final double tds26QAmount;
  final double expectedTds;
  final double actualTds;
  final double tdsRateUsed;

  final double amountDifference;
  final double tdsDifference;

  final String status;
  final String remarks;

  final bool purchasePresent;
  final bool tdsPresent;

  final double openingTimingBalance;
  final double monthTdsDifference;
  final double closingTimingBalance;

  ReconciliationRow({
    required this.buyerName,
    required this.buyerPan,
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.section,
    required this.basicAmount,
    required this.applicableAmount,
    required this.tds26QAmount,
    required this.expectedTds,
    required this.actualTds,
    required this.tdsRateUsed,
    required this.amountDifference,
    required this.tdsDifference,
    required this.status,
    required this.remarks,
    required this.purchasePresent,
    required this.tdsPresent,
    required this.openingTimingBalance,
    required this.monthTdsDifference,
    required this.closingTimingBalance,
  });

  ReconciliationRow copyWith({
    String? buyerName,
    String? buyerPan,
    String? financialYear,
    String? month,
    String? sellerName,
    String? sellerPan,
    String? section,
    double? basicAmount,
    double? applicableAmount,
    double? tds26QAmount,
    double? expectedTds,
    double? actualTds,
    double? tdsRateUsed,
    double? amountDifference,
    double? tdsDifference,
    String? status,
    String? remarks,
    bool? purchasePresent,
    bool? tdsPresent,
    double? openingTimingBalance,
    double? monthTdsDifference,
    double? closingTimingBalance,
  }) {
    return ReconciliationRow(
      buyerName: buyerName ?? this.buyerName,
      buyerPan: buyerPan ?? this.buyerPan,
      financialYear: financialYear ?? this.financialYear,
      month: month ?? this.month,
      sellerName: sellerName ?? this.sellerName,
      sellerPan: sellerPan ?? this.sellerPan,
      section: section ?? this.section,
      basicAmount: basicAmount ?? this.basicAmount,
      applicableAmount: applicableAmount ?? this.applicableAmount,
      tds26QAmount: tds26QAmount ?? this.tds26QAmount,
      expectedTds: expectedTds ?? this.expectedTds,
      actualTds: actualTds ?? this.actualTds,
      tdsRateUsed: tdsRateUsed ?? this.tdsRateUsed,
      amountDifference: amountDifference ?? this.amountDifference,
      tdsDifference: tdsDifference ?? this.tdsDifference,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      purchasePresent: purchasePresent ?? this.purchasePresent,
      tdsPresent: tdsPresent ?? this.tdsPresent,
      openingTimingBalance: openingTimingBalance ?? this.openingTimingBalance,
      monthTdsDifference: monthTdsDifference ?? this.monthTdsDifference,
      closingTimingBalance: closingTimingBalance ?? this.closingTimingBalance,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'Buyer Name': buyerName,
      'Buyer PAN': buyerPan,
      'Financial Year': financialYear,
      'Month': month,
      'Seller Name': sellerName,
      'Seller PAN': sellerPan,
      'Section': section,
      'Basic Amount': basicAmount,
      'Applicable Amount': applicableAmount,
      '26Q Amount': tds26QAmount,
      'Expected TDS': expectedTds,
      'Actual TDS': actualTds,
      'TDS Difference': tdsDifference,
      'Amount Difference': amountDifference,
      'Opening Timing Balance': openingTimingBalance,
      'Month TDS Difference': monthTdsDifference,
      'Closing Timing Balance': closingTimingBalance,
      'Status': status,
      'Remarks': remarks,
    };
  }
}

class _PurchaseGroup {
  final String financialYear;
  final String month;
  final String sellerName;
  final String sellerPan;
  final double basicAmount;
  final double billAmount;

  _PurchaseGroup({
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.basicAmount,
    required this.billAmount,
  });
}

class _TdsGroup {
  final String financialYear;
  final String month;
  final String sellerName;
  final String sellerPan;
  final double deductedAmount;
  final double actualTds;
  final String section;

  _TdsGroup({
    required this.financialYear,
    required this.month,
    required this.sellerName,
    required this.sellerPan,
    required this.deductedAmount,
    required this.actualTds,
    required this.section,
  });
}

class _SellerIdentity {
  final String originalName;
  final String mappedName;
  final String normalizedName;
  final String sellerPan;

  _SellerIdentity({
    required this.originalName,
    required this.mappedName,
    required this.normalizedName,
    required this.sellerPan,
  });
}

class _DisjointSet {
  final Map<String, String> _parent = {};

  void add(String value) {
    _parent.putIfAbsent(value, () => value);
  }

  String find(String value) {
    add(value);
    if (_parent[value] == value) return value;
    _parent[value] = find(_parent[value]!);
    return _parent[value]!;
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA == rootB) return;
    _parent[rootB] = rootA;
  }

  Set<String> values() => _parent.keys.toSet();
}

class CalculationService {
  static const double threshold = 5000000.0;
  static const double fixedTdsRate = 0.001;
  static const double tolerance = 1.0;

  static int compareMonthLabels(String a, String b) {
    return _compareMonthKeys(a, b);
  }

  static DateTime? monthLabelToDate(String value) {
    return _monthKeyToDate(value);
  }

  static Future<List<ReconciliationRow>> reconcile({
    required String buyerName,
    required String buyerPan,
    required List<PurchaseRow> purchaseRows,
    required List<Tds26QRow> tdsRows,
    Map<String, String>? nameMapping,
    bool includeAllRows = false,
  }) async {
    final normalizedBuyerPan = _normalizePan(buyerPan);
    final normalizedMapping = _normalizeNameMapping(nameMapping ?? {});

    final mappings = await MappingService.getAllMappings(normalizedBuyerPan);

    final savedAliasToPan = <String, String>{
      for (final m in mappings)
        normalizeName(m.aliasName): _normalizePan(m.mappedPan),
    };

    final sellerKeyResolver = _buildSellerKeyResolver(
      purchaseRows: purchaseRows,
      tdsRows: tdsRows,
      nameMapping: normalizedMapping,
      savedAliasToPan: savedAliasToPan,
    );

    final purchaseGroups = _groupPurchaseRows(
      purchaseRows,
      normalizedMapping,
      sellerKeyResolver,
    );

    final tdsGroups = _groupTdsRows(
      tdsRows,
      normalizedMapping,
      sellerKeyResolver,
    );

    final relevantSellerKeys = includeAllRows
        ? <String>{...purchaseGroups.keys, ...tdsGroups.keys}
        : _getRelevantSellerKeys(
      purchaseGroups: purchaseGroups,
      tdsGroups: tdsGroups,
    );

    final results = <ReconciliationRow>[];

    for (final sellerKey in relevantSellerKeys) {
      final purchaseByFyMonth = purchaseGroups[sellerKey] ?? {};
      final tdsByFyMonth = tdsGroups[sellerKey] ?? {};

      final allFyMonthKeys = <String>{
        ...purchaseByFyMonth.keys,
        ...tdsByFyMonth.keys,
      }.toList()
        ..sort(_compareFinancialYearMonthKeys);

      double cumulativeBasic = 0.0;
      String currentFy = '';
      final sellerRows = <ReconciliationRow>[];

      for (final fyMonthKey in allFyMonthKeys) {
        final purchase = purchaseByFyMonth[fyMonthKey];
        final tds = tdsByFyMonth[fyMonthKey];

        final financialYear = purchase?.financialYear ?? tds?.financialYear ?? '';
        final month = purchase?.month ?? tds?.month ?? '';

        if (financialYear != currentFy) {
          currentFy = financialYear;
          cumulativeBasic = 0.0;
        }

        final basicAmount = _round2(purchase?.basicAmount ?? 0.0);
        final previousCumulative = cumulativeBasic;
        cumulativeBasic += basicAmount;

        final applicableAmount = _round2(
          _calculateApplicableAmount(
            previousCumulative: previousCumulative,
            currentMonthBasic: basicAmount,
            threshold: threshold,
          ),
        );

        final deductedAmount = _round2(tds?.deductedAmount ?? 0.0);

        final sellerPan = _chooseSellerPan(
          purchasePan: purchase?.sellerPan ?? '',
          tdsPan: tds?.sellerPan ?? '',
          fallbackKey: sellerKey,
        );

        final tdsRateUsed = _getTdsRateForSellerPan(sellerPan);
        final expectedTds = _round2(applicableAmount * tdsRateUsed);
        final actualTds = _round2(tds?.actualTds ?? 0.0);

        final amountDifference = _round2(applicableAmount - deductedAmount);
        final tdsDifference = _round2(expectedTds - actualTds);

        final sellerName = _chooseSellerName(
          purchaseName: purchase?.sellerName ?? '',
          tdsName: tds?.sellerName ?? '',
        );

        final purchasePresent = purchase != null;
        final tdsPresent = tds != null;

        final baseStatus = _buildBaseStatus(
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          tdsDifference: tdsDifference,
        );

        final remarks = _buildRemarks(
          sellerPan: sellerPan,
          purchaseMissing: !purchasePresent,
          tdsMissing: !tdsPresent,
          amountDifference: amountDifference,
          status: baseStatus,
        );

        sellerRows.add(
          ReconciliationRow(
            buyerName: buyerName,
            buyerPan: normalizedBuyerPan,
            financialYear: financialYear,
            month: month,
            sellerName: sellerName,
            sellerPan: sellerPan,
            section: (tds?.section ?? '').trim(),
            basicAmount: basicAmount,
            applicableAmount: applicableAmount,
            tds26QAmount: deductedAmount,
            expectedTds: expectedTds,
            actualTds: actualTds,
            tdsRateUsed: tdsRateUsed,
            amountDifference: amountDifference,
            tdsDifference: tdsDifference,
            status: baseStatus,
            remarks: remarks,
            purchasePresent: purchasePresent,
            tdsPresent: tdsPresent,
            openingTimingBalance: 0.0,
            monthTdsDifference: _round2(actualTds - expectedTds),
            closingTimingBalance: 0.0,
          ),
        );
      }

      results.addAll(_applyTimingLogic(sellerRows));
    }

    results.sort((a, b) {
      final sellerNameCompare =
      a.sellerName.toUpperCase().compareTo(b.sellerName.toUpperCase());
      if (sellerNameCompare != 0) return sellerNameCompare;

      final panCompare =
      a.sellerPan.toUpperCase().compareTo(b.sellerPan.toUpperCase());
      if (panCompare != 0) return panCompare;

      final fyCompare = a.financialYear.compareTo(b.financialYear);
      if (fyCompare != 0) return fyCompare;

      return _compareMonthKeys(a.month, b.month);
    });

    return results;
  }

  static Map<String, String> _buildSellerKeyResolver({
    required List<PurchaseRow> purchaseRows,
    required List<Tds26QRow> tdsRows,
    required Map<String, String> nameMapping,
    required Map<String, String> savedAliasToPan,
  }) {
    final identities = <_SellerIdentity>[];

    for (final row in purchaseRows) {
      final mappedName = _applyNameMapping(row.partyName, nameMapping);
      identities.add(
        _SellerIdentity(
          originalName: row.partyName,
          mappedName: mappedName,
          normalizedName: normalizeName(
            mappedName.isNotEmpty ? mappedName : row.partyName,
          ),
          sellerPan: _normalizePan(row.panNumber),
        ),
      );
    }

    for (final row in tdsRows) {
      final mappedName = _applyNameMapping(row.deducteeName, nameMapping);
      identities.add(
        _SellerIdentity(
          originalName: row.deducteeName,
          mappedName: mappedName,
          normalizedName: normalizeName(
            mappedName.isNotEmpty ? mappedName : row.deducteeName,
          ),
          sellerPan: _normalizePan(row.panNumber),
        ),
      );
    }

    final dsu = _DisjointSet();

    for (final entry in nameMapping.entries) {
      final rawPurchase = entry.key.trim().toUpperCase();
      final rawTds = entry.value.trim().toUpperCase();

      final normPurchase = normalizeName(entry.key);
      final normTds = normalizeName(entry.value);

      final nodes = [
        'NAME:$rawPurchase',
        'NAME:$rawTds',
        'NAME:$normPurchase',
        'NAME:$normTds',
      ];

      for (final n in nodes) {
        if (n.replaceAll('NAME:', '').isEmpty) continue;
        dsu.add(n);
      }

      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          dsu.union(nodes[i], nodes[j]);
        }
      }
    }

    for (final entry in savedAliasToPan.entries) {
      final normAlias = normalizeName(entry.key);
      final mappedPan = _normalizePan(entry.value);

      final nameNode = 'NAME:$normAlias';
      final panNode = 'PAN:$mappedPan';

      if (normAlias.isNotEmpty) {
        dsu.add(nameNode);
      }

      if (mappedPan.isNotEmpty) {
        dsu.add(panNode);
      }

      if (normAlias.isNotEmpty && mappedPan.isNotEmpty) {
        dsu.union(nameNode, panNode);
      }
    }

    for (final identity in identities) {
      final pan = identity.sellerPan;
      final normName = identity.normalizedName;

      String? panNode;
      String? nameNode;

      if (pan.isNotEmpty) {
        panNode = 'PAN:$pan';
        dsu.add(panNode);
      }

      if (normName.isNotEmpty) {
        nameNode = 'NAME:$normName';
        dsu.add(nameNode);
      }

      if (panNode != null && nameNode != null) {
        dsu.union(panNode, nameNode);
      }
    }

    final groups = <String, Set<String>>{};
    for (final node in dsu.values()) {
      final root = dsu.find(node);
      groups.putIfAbsent(root, () => <String>{}).add(node);
    }

    final rootToCanonicalKey = <String, String>{};

    for (final entry in groups.entries) {
      final nodes = entry.value;

      final panNodes = nodes.where((e) => e.startsWith('PAN:')).toList()..sort();
      final nameNodes =
      nodes.where((e) => e.startsWith('NAME:')).toList()..sort();

      if (panNodes.isNotEmpty) {
        rootToCanonicalKey[entry.key] = panNodes.first.substring(4);
      } else if (nameNodes.isNotEmpty) {
        rootToCanonicalKey[entry.key] = nameNodes.first.substring(5);
      }
    }

    final resolver = <String, String>{};

    for (final node in dsu.values()) {
      final root = dsu.find(node);
      final canonical = rootToCanonicalKey[root];
      if (canonical == null || canonical.isEmpty) continue;

      if (node.startsWith('PAN:')) {
        resolver[node.substring(4)] = canonical;
      } else if (node.startsWith('NAME:')) {
        resolver[node.substring(5)] = canonical;
      }
    }

    return resolver;
  }

  static Set<String> _getRelevantSellerKeys({
    required Map<String, Map<String, _PurchaseGroup>> purchaseGroups,
    required Map<String, Map<String, _TdsGroup>> tdsGroups,
  }) {
    final relevant = <String>{};

    for (final sellerKey in tdsGroups.keys) {
      relevant.add(sellerKey);
    }

    for (final entry in purchaseGroups.entries) {
      final sellerKey = entry.key;
      final monthMap = entry.value;

      final fyTotals = <String, double>{};
      for (final group in monthMap.values) {
        fyTotals[group.financialYear] =
            (fyTotals[group.financialYear] ?? 0.0) + group.basicAmount;
      }

      final crossedThreshold = fyTotals.values.any((total) => total > threshold);
      if (crossedThreshold) {
        relevant.add(sellerKey);
      }
    }

    return relevant;
  }

  static List<ReconciliationRow> _applyTimingLogic(
      List<ReconciliationRow> rows,
      ) {
    if (rows.isEmpty) return rows;

    final sortedRows = [...rows]
      ..sort((a, b) {
        final fyCompare = a.financialYear.compareTo(b.financialYear);
        if (fyCompare != 0) return fyCompare;
        return _compareMonthKeys(a.month, b.month);
      });

    final groupedByFy = <String, List<ReconciliationRow>>{};
    for (final row in sortedRows) {
      groupedByFy.putIfAbsent(row.financialYear, () => []).add(row);
    }

    final output = <ReconciliationRow>[];

    for (final fy in groupedByFy.keys.toList()..sort()) {
      final fyRows = groupedByFy[fy]!;
      double runningBalance = 0.0;

      final monthProcessed = <ReconciliationRow>[];
      for (final row in fyRows) {
        final openingBalance = runningBalance;
        final monthDiff = _round2(row.actualTds - row.expectedTds);
        runningBalance = _round2(runningBalance + monthDiff);
        final closingBalance = runningBalance;

        monthProcessed.add(
          row.copyWith(
            openingTimingBalance: openingBalance,
            monthTdsDifference: monthDiff,
            closingTimingBalance: closingBalance,
          ),
        );
      }

      final totalExpected = _round2(
        monthProcessed.fold(0.0, (sum, row) => sum + row.expectedTds),
      );
      final totalActual = _round2(
        monthProcessed.fold(0.0, (sum, row) => sum + row.actualTds),
      );
      final totalDiff = _round2(totalActual - totalExpected);

      final hasBothSideMismatch =
          monthProcessed.any((e) => e.monthTdsDifference > tolerance) &&
              monthProcessed.any((e) => e.monthTdsDifference < -tolerance);

      final canBeTiming = totalDiff.abs() <= tolerance && hasBothSideMismatch;

      for (final row in monthProcessed) {
        String finalStatus = row.status;
        String finalRemarks = row.remarks;

        if (!row.purchasePresent && row.tdsPresent) {
          finalStatus = '26Q Only';
        } else if (row.purchasePresent && !row.tdsPresent) {
          finalStatus = 'Purchase Only';
        } else if (row.purchasePresent && row.tdsPresent) {
          final isPartialDeduction =
              row.applicableAmount > tolerance &&
                  row.tds26QAmount > tolerance &&
                  row.tds26QAmount < (row.applicableAmount - tolerance);

          final deductedBaseAlignedWithTds = row.actualTds > tolerance &&
              (row.tds26QAmount * row.tdsRateUsed - row.actualTds).abs() <= 2.0;

          if (row.monthTdsDifference.abs() <= tolerance &&
              row.openingTimingBalance.abs() <= tolerance &&
              row.closingTimingBalance.abs() <= tolerance) {
            finalStatus = 'Matched';
          } else if (canBeTiming) {
            finalStatus = 'Timing Difference';
          } else if (isPartialDeduction && deductedBaseAlignedWithTds) {
            finalStatus = 'Timing Difference';
          } else {
            if (row.monthTdsDifference < -tolerance) {
              finalStatus = 'Short Deduction';
            } else if (row.monthTdsDifference > tolerance) {
              finalStatus = 'Excess Deduction';
            } else {
              finalStatus =
              totalDiff < 0 ? 'Short Deduction' : 'Excess Deduction';
            }
          }
        }

        finalRemarks = _rebuildRemarksWithTiming(
          originalRemarks: finalRemarks,
          finalStatus: finalStatus,
          openingTimingBalance: row.openingTimingBalance,
          closingTimingBalance: row.closingTimingBalance,
        );

        output.add(
          row.copyWith(
            status: finalStatus,
            remarks: finalRemarks,
          ),
        );
      }
    }

    return output;
  }

  static Map<String, Map<String, _PurchaseGroup>> _groupPurchaseRows(
      List<PurchaseRow> rows,
      Map<String, String> nameMapping,
      Map<String, String> sellerKeyResolver,
      ) {
    final grouped = <String, Map<String, _PurchaseGroup>>{};

    for (final row in rows) {
      final sellerPan = _normalizePan(row.panNumber);
      final sellerName = _applyNameMapping(row.partyName, nameMapping);
      final normalizedSellerName =
      normalizeName(sellerName.isNotEmpty ? sellerName : row.partyName);
      final month = row.month;
      final financialYear = _financialYearFromMonthKey(month);

      if (month.isEmpty || financialYear.isEmpty) continue;
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) continue;

      final sellerKey = _resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final fyMonthKey = '$financialYear|$month';

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;

      final existing = monthMap[fyMonthKey];
      if (existing == null) {
        monthMap[fyMonthKey] = _PurchaseGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: sellerPan,
          basicAmount: row.basicAmount,
          billAmount: row.billAmount,
        );
      } else {
        monthMap[fyMonthKey] = _PurchaseGroup(
          financialYear: financialYear,
          month: month,
          sellerName:
          existing.sellerName.isNotEmpty ? existing.sellerName : sellerName,
          sellerPan:
          existing.sellerPan.isNotEmpty ? existing.sellerPan : sellerPan,
          basicAmount: existing.basicAmount + row.basicAmount,
          billAmount: existing.billAmount + row.billAmount,
        );
      }
    }

    return grouped;
  }

  static Map<String, Map<String, _TdsGroup>> _groupTdsRows(
      List<Tds26QRow> rows,
      Map<String, String> nameMapping,
      Map<String, String> sellerKeyResolver,
      ) {
    final grouped = <String, Map<String, _TdsGroup>>{};

    for (final row in rows) {
      final sellerPan = _normalizePan(row.panNumber);
      final sellerName = _applyNameMapping(row.deducteeName, nameMapping);
      final normalizedSellerName =
      normalizeName(sellerName.isNotEmpty ? sellerName : row.deducteeName);
      final month = row.month;
      final financialYear = _financialYearFromMonthKey(month);

      if (month.isEmpty || financialYear.isEmpty) continue;
      if (sellerPan.isEmpty && normalizedSellerName.isEmpty) continue;

      final sellerKey = _resolveSellerKey(
        sellerPan: sellerPan,
        normalizedSellerName: normalizedSellerName,
        resolver: sellerKeyResolver,
      );

      if (sellerKey.isEmpty) continue;

      final fyMonthKey = '$financialYear|$month';

      grouped.putIfAbsent(sellerKey, () => {});
      final monthMap = grouped[sellerKey]!;

      final existing = monthMap[fyMonthKey];
      if (existing == null) {
        monthMap[fyMonthKey] = _TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName: sellerName,
          sellerPan: sellerPan,
          deductedAmount: row.deductedAmount,
          actualTds: row.tds,
          section: row.section,
        );
      } else {
        monthMap[fyMonthKey] = _TdsGroup(
          financialYear: financialYear,
          month: month,
          sellerName:
          existing.sellerName.isNotEmpty ? existing.sellerName : sellerName,
          sellerPan:
          existing.sellerPan.isNotEmpty ? existing.sellerPan : sellerPan,
          deductedAmount: existing.deductedAmount + row.deductedAmount,
          actualTds: existing.actualTds + row.tds,
          section: existing.section.isNotEmpty ? existing.section : row.section,
        );
      }
    }

    return grouped;
  }

  static String _resolveSellerKey({
    required String sellerPan,
    required String normalizedSellerName,
    required Map<String, String> resolver,
  }) {
    if (sellerPan.isNotEmpty) {
      return resolver[sellerPan] ?? sellerPan;
    }
    if (normalizedSellerName.isNotEmpty) {
      return resolver[normalizedSellerName] ?? normalizedSellerName;
    }
    return '';
  }

  static double _calculateApplicableAmount({
    required double previousCumulative,
    required double currentMonthBasic,
    required double threshold,
  }) {
    final currentCumulative = previousCumulative + currentMonthBasic;

    if (currentCumulative <= threshold) return 0.0;
    if (previousCumulative >= threshold) return currentMonthBasic;

    return currentCumulative - threshold;
  }

  static double _getTdsRateForSellerPan(String sellerPan) {
    return fixedTdsRate;
  }

  static String _buildBaseStatus({
    required bool purchaseMissing,
    required bool tdsMissing,
    required double tdsDifference,
  }) {
    if (purchaseMissing && !tdsMissing) return '26Q Only';
    if (!purchaseMissing && tdsMissing) return 'Purchase Only';

    if (tdsDifference.abs() <= tolerance) return 'Matched';
    if (tdsDifference > 0) return 'Short Deduction';
    return 'Excess Deduction';
  }

  static String _buildRemarks({
    required String sellerPan,
    required bool purchaseMissing,
    required bool tdsMissing,
    required double amountDifference,
    required String status,
  }) {
    final remarks = <String>[];

    if (sellerPan.isEmpty) remarks.add('PAN missing');
    if (purchaseMissing) remarks.add('Not found in purchase');
    if (tdsMissing) remarks.add('Not found in 26Q');

    if (!purchaseMissing && !tdsMissing) {
      if (amountDifference.abs() > tolerance) {
        remarks.add('Amount mismatch');
      }

      if (status == 'Short Deduction') {
        remarks.add('TDS short');
      } else if (status == 'Excess Deduction') {
        remarks.add('TDS excess');
      }
    }

    return remarks.join(', ');
  }

  static String _rebuildRemarksWithTiming({
    required String originalRemarks,
    required String finalStatus,
    required double openingTimingBalance,
    required double closingTimingBalance,
  }) {
    final parts = originalRemarks
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    parts.removeWhere(
          (e) =>
      e == 'TDS short' ||
          e == 'TDS excess' ||
          e == 'Timing adjusted' ||
          e == 'Partial deduction / timing difference' ||
          e.startsWith('Opening timing balance') ||
          e.startsWith('Closing timing balance'),
    );

    if (finalStatus == 'Timing Difference') {
      parts.add('Partial deduction / timing difference');

      if (openingTimingBalance.abs() > tolerance) {
        parts.add(
          'Opening timing balance: ${openingTimingBalance.toStringAsFixed(2)}',
        );
      }

      if (closingTimingBalance.abs() > tolerance) {
        parts.add(
          'Closing timing balance: ${closingTimingBalance.toStringAsFixed(2)}',
        );
      }
    } else if (finalStatus == 'Short Deduction') {
      parts.add('TDS short');
    } else if (finalStatus == 'Excess Deduction') {
      parts.add('TDS excess');
    }

    return parts.join(', ');
  }

  static String _chooseSellerName({
    required String purchaseName,
    required String tdsName,
  }) {
    if (tdsName.trim().isNotEmpty) return tdsName.trim();
    if (purchaseName.trim().isNotEmpty) return purchaseName.trim();
    return '';
  }

  static String _chooseSellerPan({
    required String purchasePan,
    required String tdsPan,
    required String fallbackKey,
  }) {
    if (purchasePan.trim().isNotEmpty) return purchasePan.trim();
    if (tdsPan.trim().isNotEmpty) return tdsPan.trim();
    if (_looksLikePan(fallbackKey)) return fallbackKey.trim();
    return '';
  }

  static Map<String, String> _normalizeNameMapping(Map<String, String> mapping) {
    final result = <String, String>{};

    for (final entry in mapping.entries) {
      final key = normalizeName(entry.key);
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }

    return result;
  }

  static String _applyNameMapping(String name, Map<String, String> mapping) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final normalized = normalizeName(trimmed);
    return mapping[normalized] ?? trimmed;
  }
}

String normalizeName(String name) {
  var text = name.toUpperCase().trim();

  text = text.replaceAll('&', ' AND ');
  text = text.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
  text = text.replaceAll(RegExp(r'\bM/S\b'), ' ');
  text = text.replaceAll(RegExp(r'\bMS\b'), ' ');
  text = text.replaceAll(RegExp(r'\bPVT\b'), ' ');
  text = text.replaceAll(RegExp(r'\bPRIVATE\b'), ' ');
  text = text.replaceAll(RegExp(r'\bLTD\b'), ' ');
  text = text.replaceAll(RegExp(r'\bLIMITED\b'), ' ');
  text = text.replaceAll(RegExp(r'\bCO\b'), ' ');
  text = text.replaceAll(RegExp(r'\bCOMPANY\b'), ' ');
  text = text.replaceAll(RegExp(r'\bIND\b'), ' INDUSTRIES ');
  text = text.replaceAll(RegExp(r'\bINDUSTRY\b'), ' INDUSTRIES ');
  text = text.replaceAll(RegExp(r'\bLOGISTICS\b'), ' LOGISTICS ');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  text = text.trim();

  return text;
}

String? _readAny(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return null;
}

double _parseDouble(dynamic value) {
  if (value == null) return 0.0;

  final text = value.toString().trim();
  if (text.isEmpty) return 0.0;

  final cleaned = text.replaceAll(',', '').replaceAll('₹', '');
  return double.tryParse(cleaned) ?? 0.0;
}

String _normalizePan(String value) {
  return value.trim().toUpperCase();
}

String _normalizeSection(String value) {
  final text = value.trim().toUpperCase();

  if (text.startsWith('194Q')) return '194Q';
  if (text.startsWith('194C')) return '194C';
  if (text.startsWith('194J')) return '194J';
  if (text.startsWith('194H')) return '194H';

  return text;
}

bool _looksLikePan(String value) {
  final text = value.trim().toUpperCase();
  final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  return panRegex.hasMatch(text);
}

String _extractPanFromGstin(String gstin) {
  final clean = gstin.trim().toUpperCase();

  if (clean.length != 15) return '';

  final pan = clean.substring(2, 12);
  final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  return panRegex.hasMatch(pan) ? pan : '';
}

double _round2(double value) {
  return double.parse(value.toStringAsFixed(2));
}

String _normalizeMonth(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';

  final parsed = _tryParseDate(value);
  if (parsed == null) return value;

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  return '${months[parsed.month - 1]}-${parsed.year}';
}

DateTime? _tryParseDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final direct = DateTime.tryParse(text);
  if (direct != null) return DateTime(direct.year, direct.month, direct.day);

  final numeric = double.tryParse(text);
  if (numeric != null) {
    final excelEpoch = DateTime(1899, 12, 30);
    final date = excelEpoch.add(Duration(days: numeric.floor()));
    return DateTime(date.year, date.month, date.day);
  }

  final cleaned = text.replaceAll('/', '-').replaceAll('.', '-');
  final parts = cleaned.split('-');

  if (parts.length == 3) {
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);

    if (a != null && b != null && c != null) {
      if (a > 1900) {
        return DateTime(a, b, c);
      } else if (c > 1900) {
        return DateTime(c, b, a);
      }
    }
  }

  return null;
}

int _compareMonthKeys(String a, String b) {
  final da = _monthKeyToDate(a);
  final db = _monthKeyToDate(b);

  if (da == null && db == null) return a.compareTo(b);
  if (da == null) return -1;
  if (db == null) return 1;

  return da.compareTo(db);
}

DateTime? _monthKeyToDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;

  final parts = text.split('-');
  if (parts.length != 2) return _tryParseDate(text);

  const monthMap = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  final month = monthMap[parts[0]];
  final year = int.tryParse(parts[1]);

  if (month == null || year == null) return null;
  return DateTime(year, month, 1);
}

String _financialYearFromMonthKey(String monthKey) {
  final date = _monthKeyToDate(monthKey);
  if (date == null) return '';

  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endYear = startYear + 1;

  return '$startYear-${endYear.toString().substring(2)}';
}

int _compareFinancialYearMonthKeys(String a, String b) {
  final aParts = a.split('|');
  final bParts = b.split('|');

  final aFy = aParts.isNotEmpty ? aParts[0] : '';
  final bFy = bParts.isNotEmpty ? bParts[0] : '';

  final fyCompare = aFy.compareTo(bFy);
  if (fyCompare != 0) return fyCompare;

  final aMonth = aParts.length > 1 ? aParts[1] : '';
  final bMonth = bParts.length > 1 ? bParts[1] : '';

  return _compareMonthKeys(aMonth, bMonth);
}