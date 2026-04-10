import 'package:flutter/material.dart';
import '../core/utils/auto_mapping.dart';

class ManualMappingScreen extends StatefulWidget {
  final List<String> purchaseParties;
  final List<String> tdsParties;
  final Map<String, String> initialMapping;

  const ManualMappingScreen({
    super.key,
    required this.purchaseParties,
    required this.tdsParties,
    this.initialMapping = const {},
  });

  @override
  State<ManualMappingScreen> createState() => _ManualMappingScreenState();
}

class _ManualMappingScreenState extends State<ManualMappingScreen> {
  late Map<String, String> selectedMappings;
  late List<String> uniquePurchaseParties;
  late List<String> uniqueTdsParties;

  @override
  void initState() {
    super.initState();

    uniquePurchaseParties = widget.purchaseParties
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    uniqueTdsParties = widget.tdsParties
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    selectedMappings = Map<String, String>.from(widget.initialMapping);

    final autoResults = AutoMappingService.autoMapParties(
      purchaseParties: uniquePurchaseParties,
      tdsParties: uniqueTdsParties,
    );

    for (final result in autoResults) {
      if (result.isMatched &&
          result.matchedTdsParty != null &&
          !selectedMappings.containsKey(result.purchaseParty.toUpperCase())) {
        selectedMappings[result.purchaseParty.toUpperCase()] =
        result.matchedTdsParty!;
      }
    }
  }

  void _saveMappings() {
    Navigator.pop(context, selectedMappings);
  }

  void _clearMapping(String purchaseParty) {
    setState(() {
      selectedMappings.remove(purchaseParty.toUpperCase());
    });
  }

  String? _getSelectedValue(String purchaseParty) {
    return selectedMappings[purchaseParty.toUpperCase()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Mapping'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: _saveMappings,
              icon: const Icon(Icons.save),
              label: const Text('Save Mapping'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Text(
                'Map Purchase seller names to 26Q names. '
                    'Auto-matched values are already selected. '
                    'Change only where needed.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: uniquePurchaseParties.isEmpty
                  ? const Center(
                child: Text(
                  'No purchase parties found',
                  style: TextStyle(fontSize: 18),
                ),
              )
                  : ListView.separated(
                itemCount: uniquePurchaseParties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final purchaseParty = uniquePurchaseParties[index];
                  final selectedValue = _getSelectedValue(purchaseParty);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Purchase Party',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                purchaseParty,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<String>(
                            value: selectedValue != null &&
                                uniqueTdsParties.contains(selectedValue)
                                ? selectedValue
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Map to 26Q Party',
                              border: OutlineInputBorder(),
                            ),
                            items: uniqueTdsParties
                                .map(
                                  (tdsParty) => DropdownMenuItem<String>(
                                value: tdsParty,
                                child: Text(tdsParty),
                              ),
                            )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                if (value == null || value.trim().isEmpty) {
                                  selectedMappings.remove(
                                    purchaseParty.toUpperCase(),
                                  );
                                } else {
                                  selectedMappings[purchaseParty
                                      .toUpperCase()] = value;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Clear Mapping',
                          onPressed: () => _clearMapping(purchaseParty),
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}