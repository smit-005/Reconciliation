import 'package:uuid/uuid.dart';

import 'package:reconciliation_app/core/utils/financial_year_utils.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_repository.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_repository.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

class BuyerFinancialYearStore {
  static final BuyerFinancialYearRepository _repository =
      BuyerFinancialYearRepository();
  static final BuyerRepository _buyerRepository = BuyerRepository();
  static final WorkspaceService _workspaceService = WorkspaceService();

  static Future<List<BuyerFinancialYear>> listActive(String buyerId) {
    return _repository.getActiveByBuyer(buyerId);
  }

  static Future<BuyerFinancialYear?> activeForBuyer(Buyer buyer) async {
    final activeId = buyer.activeFinancialYearId?.trim();
    if (activeId == null || activeId.isEmpty) {
      return null;
    }

    return _repository.getActiveByIdForBuyer(
      buyerId: buyer.id,
      financialYearId: activeId,
    );
  }

  static Future<String?> create({
    required Buyer buyer,
    required String fyLabel,
  }) async {
    final normalizedFyLabel = normalizeFinancialYearLabel(fyLabel);
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

  static Future<BuyerFinancialYear?> ensureCurrentForBuyer({
    required Buyer buyer,
    DateTime? now,
  }) async {
    final fyLabel = currentIndianFinancialYearLabel(now: now);
    final existing = await _repository.getByLabelForBuyer(
      buyerId: buyer.id,
      fyLabel: fyLabel,
    );
    if (existing != null) {
      return existing;
    }

    final error = await create(buyer: buyer, fyLabel: fyLabel);
    if (error != null) {
      return _repository.getByLabelForBuyer(
        buyerId: buyer.id,
        fyLabel: fyLabel,
      );
    }

    return _repository.getByLabelForBuyer(buyerId: buyer.id, fyLabel: fyLabel);
  }

  static Future<void> archive(String id) async {
    await _repository.archive(id);
    await _buyerRepository.clearActiveFinancialYearReference(id);
  }
}
