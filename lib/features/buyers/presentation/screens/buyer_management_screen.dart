import 'package:flutter/material.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_store.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/excel_upload_screen.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

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
  final fyController = TextEditingController();
  final workspaceService = WorkspaceService();

  String? editingId;
  String? selectedBuyerId;
  String? selectedFinancialYearId;
  List<BuyerFinancialYear> selectedFinancialYears = [];
  bool isLoading = true;
  bool isSaving = false;
  bool isLoadingFinancialYears = false;
  bool isSavingFinancialYear = false;

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

  Buyer? _selectedBuyerFrom(List<Buyer> source) {
    final id = selectedBuyerId;
    if (id == null) {
      return null;
    }

    for (final buyer in source) {
      if (buyer.id == id) {
        return buyer;
      }
    }

    return null;
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

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter buyer name')));
      return;
    }

    if (pan.isNotEmpty && !_isValidPan(pan)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter valid PAN format')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
    selectBuyer(buyer);
  }

  Future<void> selectBuyer(Buyer buyer) async {
    setState(() {
      selectedBuyerId = buyer.id;
      selectedFinancialYearId = null;
      isLoadingFinancialYears = true;
    });

    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    if (!mounted || selectedBuyerId != buyer.id) return;
    final activeFinancialYearId = buyer.activeFinancialYearId?.trim();
    final selectedActiveFinancialYear = activeFinancialYearId == null
        ? null
        : financialYears.any(
            (financialYear) => financialYear.id == activeFinancialYearId,
          )
        ? activeFinancialYearId
        : null;
    setState(() {
      selectedFinancialYears = financialYears;
      selectedFinancialYearId = selectedActiveFinancialYear;
      isLoadingFinancialYears = false;
    });
  }

  Future<void> archiveBuyer(String id) async {
    await BuyerStore.archive(id);
    if (!mounted) return;
    if (selectedBuyerId == id) {
      selectedBuyerId = null;
      selectedFinancialYearId = null;
      selectedFinancialYears = [];
    }
    setState(() {});
  }

  Future<void> openBuyerFolder(Buyer buyer) async {
    if (buyer.workspaceRelativePath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workspace folder is linked yet')),
      );
      return;
    }

    final opened = await workspaceService.openFolder(
      buyer.workspaceRelativePath,
    );
    if (!mounted || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Buyer folder was not found. Check workspace settings.'),
      ),
    );
  }

  Future<void> addFinancialYear(Buyer buyer) async {
    fyController.clear();

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Financial Year'),
          content: TextField(
            controller: fyController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Financial year',
              hintText: '2024-25',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (shouldCreate != true) {
      return;
    }

    setState(() => isSavingFinancialYear = true);
    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: fyController.text,
    );
    if (!mounted) return;

    setState(() => isSavingFinancialYear = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    await selectBuyer(buyer);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Financial year added')));
  }

  Future<void> archiveFinancialYear(
    Buyer buyer,
    BuyerFinancialYear financialYear,
  ) async {
    await BuyerFinancialYearStore.archive(financialYear.id);
    if (!mounted) return;
    final remainingFinancialYears = await BuyerFinancialYearStore.listActive(
      buyer.id,
    );
    if (!mounted) return;

    String? nextActiveFinancialYearId = buyer.activeFinancialYearId;
    if (buyer.activeFinancialYearId == financialYear.id) {
      nextActiveFinancialYearId = remainingFinancialYears.isEmpty
          ? null
          : remainingFinancialYears.first.id;
      await BuyerStore.setActiveFinancialYear(
        buyer.id,
        nextActiveFinancialYearId,
      );
      if (!mounted) return;
    }

    if (selectedFinancialYearId == financialYear.id) {
      selectedFinancialYearId = nextActiveFinancialYearId;
    }
    setState(() {
      selectedFinancialYears = remainingFinancialYears;
    });
  }

  Future<void> openFinancialYearFolder(BuyerFinancialYear financialYear) async {
    if (financialYear.workspaceRelativePath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No FY folder is linked yet')),
      );
      return;
    }

    final opened = await workspaceService.openFolder(
      financialYear.workspaceRelativePath,
    );
    if (!mounted || opened) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('FY folder was not found')));
  }

  void clearForm() {
    nameController.clear();
    panController.clear();
    gstController.clear();
    editingId = null;
    setState(() {});
  }

  BuyerFinancialYear? _selectedFinancialYearFrom(
    List<BuyerFinancialYear> source,
  ) {
    final id = selectedFinancialYearId;
    if (id == null) {
      return null;
    }

    for (final financialYear in source) {
      if (financialYear.id == id) {
        return financialYear;
      }
    }

    return null;
  }

  void _startReconciliation(Buyer buyer) {
    final financialYear = _selectedFinancialYearFrom(selectedFinancialYears);
    if (financialYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a financial year to continue')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelUploadScreen(
          selectedBuyerId: buyer.id,
          selectedBuyerName: buyer.name,
          selectedBuyerPan: buyer.pan,
          selectedFinancialYearId: financialYear.id,
          selectedFinancialYearLabel: financialYear.fyLabel,
        ),
      ),
    );
  }

  Future<void> makeDefaultFinancialYear(
    Buyer buyer,
    BuyerFinancialYear financialYear,
  ) async {
    await BuyerStore.setActiveFinancialYear(buyer.id, financialYear.id);
    if (!mounted) return;
    setState(() {
      selectedFinancialYearId = financialYear.id;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Default FY updated')));
  }

  @override
  void dispose() {
    nameController.dispose();
    panController.dispose();
    gstController.dispose();
    searchController.dispose();
    fyController.dispose();
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
    final selectedBuyer = _selectedBuyerFrom(buyers);

    return Scaffold(
      appBar: AppBar(title: const Text('Buyer Management')),
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
                              hintText: 'Optional',
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
                                        : (editingId == null
                                              ? 'Add Buyer'
                                              : 'Update Buyer'),
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
                        if (selectedBuyer != null) ...[
                          _FinancialYearPanel(
                            buyer: selectedBuyer,
                            financialYears: selectedFinancialYears,
                            selectedFinancialYearId: selectedFinancialYearId,
                            activeFinancialYearId:
                                selectedBuyer.activeFinancialYearId,
                            isLoading: isLoadingFinancialYears,
                            isSaving: isSavingFinancialYear,
                            onAdd: () => addFinancialYear(selectedBuyer),
                            onSelect: (financialYear) {
                              setState(() {
                                selectedFinancialYearId = financialYear.id;
                              });
                            },
                            onStart: () => _startReconciliation(selectedBuyer),
                            onOpenFolder: openFinancialYearFolder,
                            onMakeDefault: (financialYear) =>
                                makeDefaultFinancialYear(
                                  selectedBuyer,
                                  financialYear,
                                ),
                            onArchive: (financialYear) => archiveFinancialYear(
                              selectedBuyer,
                              financialYear,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(child: Text('No buyers found'))
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final b = filtered[index];

                                    return Card(
                                      child: ListTile(
                                        selected: b.id == selectedBuyerId,
                                        onTap: () => selectBuyer(b),
                                        title: Text(b.name),
                                        subtitle: Text(
                                          [
                                            b.pan.trim().isEmpty
                                                ? 'PAN: Not available'
                                                : 'PAN: ${b.pan}',
                                            if (b.gstNumber.trim().isNotEmpty)
                                              'GST: ${b.gstNumber}',
                                          ].join('\n'),
                                        ),
                                        isThreeLine:
                                            b.gstNumber.trim().isNotEmpty ||
                                            b.pan.trim().isEmpty,
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (b.workspaceRelativePath
                                                .trim()
                                                .isNotEmpty)
                                              IconButton(
                                                tooltip: 'Open folder',
                                                icon: const Icon(
                                                  Icons.folder_open,
                                                ),
                                                onPressed: () =>
                                                    openBuyerFolder(b),
                                              ),
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              onPressed: () => editBuyer(b),
                                            ),
                                            IconButton(
                                              tooltip: 'Archive buyer',
                                              icon: const Icon(Icons.archive),
                                              onPressed: () =>
                                                  archiveBuyer(b.id),
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

class _FinancialYearPanel extends StatelessWidget {
  final Buyer buyer;
  final List<BuyerFinancialYear> financialYears;
  final String? selectedFinancialYearId;
  final String? activeFinancialYearId;
  final bool isLoading;
  final bool isSaving;
  final VoidCallback onAdd;
  final ValueChanged<BuyerFinancialYear> onSelect;
  final VoidCallback onStart;
  final ValueChanged<BuyerFinancialYear> onOpenFolder;
  final ValueChanged<BuyerFinancialYear> onMakeDefault;
  final ValueChanged<BuyerFinancialYear> onArchive;

  const _FinancialYearPanel({
    required this.buyer,
    required this.financialYears,
    required this.selectedFinancialYearId,
    required this.activeFinancialYearId,
    required this.isLoading,
    required this.isSaving,
    required this.onAdd,
    required this.onSelect,
    required this.onStart,
    required this.onOpenFolder,
    required this.onMakeDefault,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Financial Years - ${buyer.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onAdd,
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add, size: 18),
                label: Text(isSaving ? 'Adding...' : 'Add FY'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (financialYears.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No financial years added yet'),
            )
          else
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: financialYears.length,
                itemBuilder: (context, index) {
                  final financialYear = financialYears[index];
                  final isSelected =
                      financialYear.id == selectedFinancialYearId;
                  final isDefault = financialYear.id == activeFinancialYearId;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: isSelected,
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onTap: () => onSelect(financialYear),
                    title: Row(
                      children: [
                        Flexible(child: Text(financialYear.fyLabel)),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('Default'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                            labelStyle: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(financialYear.status),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isDefault)
                          IconButton(
                            tooltip: 'Make default FY',
                            icon: const Icon(Icons.star_border_rounded),
                            onPressed: () => onMakeDefault(financialYear),
                          ),
                        if (financialYear.workspaceRelativePath
                            .trim()
                            .isNotEmpty)
                          IconButton(
                            tooltip: 'Open FY folder',
                            icon: const Icon(Icons.folder_open),
                            onPressed: () => onOpenFolder(financialYear),
                          ),
                        IconButton(
                          tooltip: 'Archive FY',
                          icon: const Icon(Icons.archive),
                          onPressed: () => onArchive(financialYear),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isLoading || isSaving ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start Reconciliation'),
            ),
          ),
        ],
      ),
    );
  }
}
