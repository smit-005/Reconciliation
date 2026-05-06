import 'package:uuid/uuid.dart';

import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_repository.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

class BuyerFinancialYearStore {
  static final BuyerFinancialYearRepository _repository =
      BuyerFinancialYearRepository();
  static final WorkspaceService _workspaceService = WorkspaceService();

  static Future<List<BuyerFinancialYear>> listActive(String buyerId) {
    return _repository.getActiveByBuyer(buyerId);
  }

  static Future<String?> create({
    required Buyer buyer,
    required String fyLabel,
  }) async {
    final normalizedFyLabel = _normalizeFyLabel(fyLabel);
    if (normalizedFyLabel == null) {
      return 'Enter FY in 2024-25 format';
    }

    final exists = await _repository.existsForBuyer(
      buyerId: buyer.id,
      fyLabel: normalizedFyLabel,
    );
    if (exists) {
      return 'Financial year already exists for this buyer';
    }

    final workspaceRelativePath = await _workspaceService
        .createFinancialYearFolder(
          buyerWorkspaceRelativePath: buyer.workspaceRelativePath,
          fyLabel: normalizedFyLabel,
        );
    final now = DateTime.now().toIso8601String();
    final financialYear = BuyerFinancialYear(
      id: const Uuid().v4(),
      buyerId: buyer.id,
      fyLabel: normalizedFyLabel,
      workspaceRelativePath: workspaceRelativePath ?? '',
      createdAt: now,
      updatedAt: now,
    );

    await _repository.create(financialYear);
    return null;
  }

  static Future<void> archive(String id) => _repository.archive(id);

  static String? _normalizeFyLabel(String value) {
    final trimmed = value.trim().toUpperCase().replaceFirst(
      RegExp(r'^FY[_\s-]*'),
      '',
    );
    final match = RegExp(r'^(\d{4})[-/](\d{2}|\d{4})$').firstMatch(trimmed);
    if (match == null) {
      return null;
    }

    final startYear = match.group(1)!;
    final rawEndYear = match.group(2)!;
    final endYear = rawEndYear.length == 4
        ? rawEndYear.substring(2)
        : rawEndYear;

    return '$startYear-$endYear';
  }
}
