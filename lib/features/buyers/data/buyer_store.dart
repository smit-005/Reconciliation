import 'package:uuid/uuid.dart';

import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';
import 'buyer_repository.dart';

class BuyerStore {
  static final BuyerRepository _repository = BuyerRepository();
  static final WorkspaceService _workspaceService = WorkspaceService();
  static final List<Buyer> _buyers = [];

  static List<Buyer> getAll() => List.unmodifiable(_buyers);

  static Future<void> load() async {
    final buyers = await _repository.getAllBuyers();
    _buyers
      ..clear()
      ..addAll(buyers);
  }

  static Future<String?> add(
    String name,
    String pan,
    String gstNumber, {
    DateTime? currentDateForTest,
  }) async {
    final normalizedName = name.trim();
    final normalizedPan = pan.trim().toUpperCase();
    final normalizedGstNumber = gstNumber.trim().toUpperCase();

    final exists = await _repository.panExists(normalizedPan);
    if (exists) {
      return 'Buyer with this PAN already exists';
    }

    final buyerId = const Uuid().v4();
    final workspaceRelativePath = await _workspaceService.createBuyerFolder(
      buyerId: buyerId,
      name: normalizedName,
      pan: normalizedPan,
    );

    var buyer = Buyer(
      id: buyerId,
      name: normalizedName,
      pan: normalizedPan,
      gstNumber: normalizedGstNumber,
      workspaceRelativePath: workspaceRelativePath ?? '',
    );

    await _repository.addBuyer(buyer);
    final currentFinancialYear =
        await BuyerFinancialYearStore.ensureCurrentForBuyer(
          buyer: buyer,
          now: currentDateForTest,
        );
    if (currentFinancialYear != null) {
      await _repository.updateActiveFinancialYearId(
        buyer.id,
        currentFinancialYear.id,
      );
      buyer = buyer.copyWith(activeFinancialYearId: currentFinancialYear.id);
    }

    _buyers.add(buyer);
    _buyers.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return null;
  }

  static Future<String?> update(
    String id,
    String name,
    String pan,
    String gstNumber,
  ) async {
    final normalizedName = name.trim();
    final normalizedPan = pan.trim().toUpperCase();
    final normalizedGstNumber = gstNumber.trim().toUpperCase();

    final exists = await _repository.panExists(normalizedPan, excludeId: id);
    if (exists) {
      return 'Another buyer with this PAN already exists';
    }

    final currentIndex = _buyers.indexWhere((buyer) => buyer.id == id);
    final currentBuyer = currentIndex == -1 ? null : _buyers[currentIndex];

    final updatedBuyer = Buyer(
      id: id,
      name: normalizedName,
      pan: normalizedPan,
      gstNumber: normalizedGstNumber,
      workspaceRelativePath: currentBuyer?.workspaceRelativePath ?? '',
      activeFinancialYearId: currentBuyer?.activeFinancialYearId,
    );

    await _repository.updateBuyer(updatedBuyer);

    final index = _buyers.indexWhere((b) => b.id == id);
    if (index != -1) {
      _buyers[index] = updatedBuyer;
      _buyers.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    return null;
  }

  static Future<void> setActiveFinancialYear(
    String buyerId,
    String? financialYearId,
  ) async {
    final normalizedFinancialYearId = financialYearId?.trim();
    await _repository.updateActiveFinancialYearId(
      buyerId,
      normalizedFinancialYearId == null || normalizedFinancialYearId.isEmpty
          ? null
          : normalizedFinancialYearId,
    );

    final index = _buyers.indexWhere((buyer) => buyer.id == buyerId);
    if (index != -1) {
      _buyers[index] = _buyers[index].copyWith(
        activeFinancialYearId: normalizedFinancialYearId,
        clearActiveFinancialYearId:
            normalizedFinancialYearId == null ||
            normalizedFinancialYearId.isEmpty,
      );
    }
  }

  static Future<void> archive(String id) async {
    await _repository.archiveBuyer(id);
    _buyers.removeWhere((b) => b.id == id);
  }
}
