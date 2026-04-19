import 'package:uuid/uuid.dart';

import '../../models/buyer.dart';
import 'buyer_repository.dart';

class BuyerStore {
  static final BuyerRepository _repository = BuyerRepository();
  static final List<Buyer> _buyers = [];

  static List<Buyer> getAll() => List.unmodifiable(_buyers);

  static Future<void> load() async {
    final buyers = await _repository.getAllBuyers();
    _buyers
      ..clear()
      ..addAll(buyers);
  }

  static Future<String?> add(String name, String pan) async {
    final normalizedName = name.trim();
    final normalizedPan = pan.trim().toUpperCase();

    final exists = await _repository.panExists(normalizedPan);
    if (exists) {
      return 'Buyer with this PAN already exists';
    }

    final buyer = Buyer(
      id: const Uuid().v4(),
      name: normalizedName,
      pan: normalizedPan,
    );

    await _repository.addBuyer(buyer);
    _buyers.add(buyer);
    _buyers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return null;
  }

  static Future<String?> update(String id, String name, String pan) async {
    final normalizedName = name.trim();
    final normalizedPan = pan.trim().toUpperCase();

    final exists = await _repository.panExists(normalizedPan, excludeId: id);
    if (exists) {
      return 'Another buyer with this PAN already exists';
    }

    final updatedBuyer = Buyer(
      id: id,
      name: normalizedName,
      pan: normalizedPan,
    );

    await _repository.updateBuyer(updatedBuyer);

    final index = _buyers.indexWhere((b) => b.id == id);
    if (index != -1) {
      _buyers[index] = updatedBuyer;
      _buyers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return null;
  }

  static Future<void> delete(String id) async {
    await _repository.deleteBuyer(id);
    _buyers.removeWhere((b) => b.id == id);
  }
}
