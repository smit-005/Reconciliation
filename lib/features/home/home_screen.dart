import 'package:flutter/material.dart';
import '../upload/excel_upload_screen.dart';
import '../buyers/buyer_management_screen.dart';
import '../../data/local/buyer_store.dart';
import '../../models/buyer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final searchController = TextEditingController();
  String? selectedBuyerId;
  bool isLoading = true;

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

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buyers = BuyerStore.getAll();

    final query = searchController.text.trim().toLowerCase();

    final filtered = buyers.where((b) {
      return b.name.toLowerCase().contains(query) ||
          b.pan.toLowerCase().contains(query);
    }).toList();

    Buyer? selectedBuyer;
    if (selectedBuyerId != null) {
      try {
        selectedBuyer = buyers.firstWhere((b) => b.id == selectedBuyerId);
      } catch (_) {
        selectedBuyer = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TDS Reconciliation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BuyerManagementScreen(),
                ),
              ).then((_) => _loadBuyers());
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search Buyer...',
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
                      'Total Buyers: ${buyers.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No buyers available'))
                        : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final b = filtered[index];
                        final selected = b.id == selectedBuyerId;

                        return Card(
                          color: selected ? Colors.blue.shade50 : Colors.white,
                          child: ListTile(
                            title: Text(b.name),
                            subtitle: Text(b.pan),
                            onTap: () {
                              setState(() {
                                selectedBuyerId = b.id;
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 3,
              child: selectedBuyer == null
                  ? const Center(
                child: Text(
                  'Select a buyer to continue',
                  style: TextStyle(fontSize: 18),
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedBuyer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text('PAN: ${selectedBuyer.pan}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload Purchase & 26Q'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExcelUploadScreen(
                              selectedBuyerId: selectedBuyer!.id,
                              selectedBuyerName: selectedBuyer.name,
                              selectedBuyerPan: selectedBuyer.pan,
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
