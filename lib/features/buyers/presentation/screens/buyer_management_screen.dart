import 'package:flutter/material.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final nameController = TextEditingController();
  final panController = TextEditingController();
  final gstController = TextEditingController();
  final searchController = TextEditingController();

  String? editingId;
  bool isLoading = true;
  bool isSaving = false;

  List<Buyer> get buyers => BuyerStore.getAll();

  @override
  void initState() {
    super.initState();
    _loadBuyers();
  }

  Future<void> _loadBuyers() async {
    setState(() {
      isLoading = true;
    });

    await BuyerStore.load();

    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  bool _isValidPan(String pan) {
    final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
    return regex.hasMatch(pan);
  }

  Future<void> saveBuyer() async {
    final name = nameController.text.trim();
    final pan = panController.text.trim().toUpperCase();
    final gstNumber = gstController.text.trim().toUpperCase();
    final wasEditing = editingId != null;

    if (name.isEmpty || pan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter buyer name and PAN')),
      );
      return;
    }

    if (!_isValidPan(pan)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid PAN format')),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    String? error;

    if (editingId == null) {
      error = await BuyerStore.add(name, pan, gstNumber);
    } else {
      error = await BuyerStore.update(editingId!, name, pan, gstNumber);
    }

    if (!mounted) return;

    setState(() {
      isSaving = false;
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    nameController.clear();
    panController.clear();
    gstController.clear();
    editingId = null;

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasEditing
              ? 'Buyer updated successfully'
              : 'Buyer added successfully',
        ),
      ),
    );
  }

  void editBuyer(Buyer buyer) {
    nameController.text = buyer.name;
    panController.text = buyer.pan;
    gstController.text = buyer.gstNumber;
    editingId = buyer.id;
    setState(() {});
  }

  Future<void> deleteBuyer(String id) async {
    await BuyerStore.delete(id);
    if (!mounted) return;
    setState(() {});
  }

  void clearForm() {
    nameController.clear();
    panController.clear();
    gstController.clear();
    editingId = null;
    setState(() {});
  }

  @override
  void dispose() {
    nameController.dispose();
    panController.dispose();
    gstController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    final filtered = buyers.where((b) {
      return b.name.toLowerCase().contains(query) ||
          b.pan.toLowerCase().contains(query) ||
          b.gstNumber.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buyer Management'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editingId == null ? 'Add Buyer' : 'Edit Buyer',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Buyer Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: panController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'PAN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: gstController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'GST Number',
                        hintText: 'GST Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSaving ? null : saveBuyer,
                            child: Text(
                              isSaving
                                  ? 'Saving...'
                                  : (editingId == null ? 'Add Buyer' : 'Update Buyer'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (editingId != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: clearForm,
                              child: const Text('Cancel'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search buyer by name, PAN or GST',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total Buyers: ${filtered.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                      child: Text('No buyers found'),
                    )
                        : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final b = filtered[index];

                        return Card(
                          child: ListTile(
                            title: Text(b.name),
                            subtitle: Text(
                              b.gstNumber.trim().isEmpty
                                  ? 'PAN: ${b.pan}'
                                  : 'PAN: ${b.pan}\nGST: ${b.gstNumber}',
                            ),
                            isThreeLine: b.gstNumber.trim().isNotEmpty,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => editBuyer(b),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => deleteBuyer(b.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
