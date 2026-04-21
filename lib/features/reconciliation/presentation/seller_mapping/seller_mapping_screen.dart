import 'package:flutter/material.dart';

import '../../../../core/utils/normalize_utils.dart';
import '../../../../services/auto_mapping_service.dart';

class SellerMappingScreen extends StatefulWidget {
  final List<String> purchaseParties;
  final List<String> tdsParties;
  final Map<String, String> initialMapping;
  final Set<String> blockedAliases;
  final Map<String, List<String>> tdsPartyPans;
  final Map<String, List<String>> purchaseSections;
  final Map<String, String> purchasePartyPans;

  const SellerMappingScreen({
    super.key,
    required this.purchaseParties,
    required this.tdsParties,
    this.initialMapping = const {},
    required this.blockedAliases,
    this.tdsPartyPans = const {},
    this.purchaseSections = const {},
    this.purchasePartyPans = const {},
  });

  @override
  State<SellerMappingScreen> createState() => _SellerMappingScreenState();
}

class _SellerMappingScreenState extends State<SellerMappingScreen> {
  late Map<String, String> selectedMappings;
  late List<String> uniquePurchaseParties;
  late List<String> uniqueTdsParties;
  final Set<String> clearedAliases = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All';

  String _mappingKey(String partyName) => normalizeName(partyName.trim());

  String _getPurchasePan(String purchaseParty) {
    final exactPan = widget.purchasePartyPans[purchaseParty];
    if (exactPan != null && exactPan.trim().isNotEmpty) {
      return exactPan.trim().toUpperCase();
    }

    final normalizedPurchaseParty = _mappingKey(purchaseParty);
    for (final entry in widget.purchasePartyPans.entries) {
      if (_mappingKey(entry.key) != normalizedPurchaseParty) continue;
      final pan = entry.value.trim().toUpperCase();
      if (pan.isNotEmpty) return pan;
    }

    return '';
  }

  Set<String> _resolveTargetPans(String mappedName) {
    final exactPans = widget.tdsPartyPans[mappedName];
    if (exactPans != null) {
      return exactPans
          .map((pan) => pan.trim().toUpperCase())
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    final normalizedMappedName = _mappingKey(mappedName);
    for (final entry in widget.tdsPartyPans.entries) {
      if (_mappingKey(entry.key) != normalizedMappedName) continue;
      return entry.value
          .map((pan) => pan.trim().toUpperCase())
          .where((pan) => pan.isNotEmpty)
          .toSet();
    }

    return const <String>{};
  }

  Map<String, String> _buildAliasPanConflicts(Map<String, String> mappings) {
    final conflicts = <String, String>{};

    for (final entry in mappings.entries) {
      final aliasKey = _mappingKey(entry.key);
      final targetPans = _resolveTargetPans(entry.value);

      if (aliasKey.isEmpty || targetPans.length <= 1) continue;

      final sections = widget.purchaseSections[aliasKey] ?? const <String>[];
      final sectionSuffix = sections.isEmpty
          ? ''
          : ' Sections: ${sections.join(', ')}.';
      conflicts[aliasKey] =
          'This seller maps to different PANs. Section-wise mapping is required.$sectionSuffix';
    }

    return conflicts;
  }

  String _getPanForTdsParty(String? mappedName) {
    if (mappedName == null || mappedName.trim().isEmpty) return '';

    final pans = _resolveTargetPans(mappedName);
    if (pans.isEmpty) return '';
    if (pans.length == 1) return pans.first;

    return 'Multiple PANs';
  }

  String _getStatus({
    required String purchaseParty,
    required String? selectedValue,
    required String? rowConflict,
  }) {
    if (selectedValue == null || selectedValue.trim().isEmpty) {
      return 'Unmapped';
    }

    if (rowConflict != null && rowConflict.trim().isNotEmpty) {
      return 'PAN Conflict';
    }

    final purchasePan = _getPurchasePan(purchaseParty);
    final targetPan = _getPanForTdsParty(selectedValue);

    if (purchasePan.isEmpty ||
        targetPan.isEmpty ||
        targetPan == 'Multiple PANs') {
      return 'Missing PAN';
    }

    if (purchasePan == targetPan) {
      return 'Matched';
    }

    return 'PAN Conflict';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Matched':
        return Colors.green;
      case 'Missing PAN':
        return Colors.amber.shade800;
      case 'PAN Conflict':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusBackgroundColor(String status) {
    switch (status) {
      case 'Matched':
        return Colors.green.shade50;
      case 'Missing PAN':
        return Colors.amber.shade50;
      case 'PAN Conflict':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  String _getValidationMessage(String status) {
    switch (status) {
      case 'Matched':
        return 'PAN matched';
      case 'Missing PAN':
        return 'PAN not available, verify manually';
      case 'PAN Conflict':
        return 'PAN mismatch between purchase and 26Q party';
      default:
        return 'Select a 26Q party to create a mapping';
    }
  }

  Color _getValidationColor(String status) {
    switch (status) {
      case 'Matched':
        return Colors.green.shade800;
      case 'PAN Conflict':
        return Colors.red.shade800;
      case 'Missing PAN':
        return Colors.amber.shade900;
      default:
        return Colors.grey.shade700;
    }
  }

  Map<String, String> _sanitizeMappings(Map<String, String> mappings) {
    final validTargets = uniqueTdsParties.toSet();
    final cleaned = <String, String>{};

    for (final entry in mappings.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty || !validTargets.contains(value)) {
        continue;
      }
      cleaned[key] = value;
    }

    return cleaned;
  }

  List<String> _filteredPurchaseParties(
    Map<String, String> conflictMessages,
  ) {
    final query = _searchQuery.trim().toUpperCase();

    return uniquePurchaseParties.where((purchaseParty) {
      final purchaseKey = _mappingKey(purchaseParty);
      final selectedValue = _getSelectedValue(purchaseParty);
      final purchasePan = _getPurchasePan(purchaseParty);
      final selectedPan = _getPanForTdsParty(selectedValue);
      final status = _getStatus(
        purchaseParty: purchaseParty,
        selectedValue: selectedValue,
        rowConflict: conflictMessages[purchaseKey],
      );

      final matchesStatus = _statusFilter == 'All' || status == _statusFilter;
      if (!matchesStatus) return false;

      if (query.isEmpty) return true;

      final searchHaystack = <String>[
        purchaseParty,
        purchasePan,
        selectedValue ?? '',
        selectedPan,
        ...(widget.purchaseSections[purchaseKey] ?? const <String>[]),
      ].join(' ').toUpperCase();

      return searchHaystack.contains(query);
    }).toList();
  }

  void _applyAutoMap() {
    final autoResults = AutoMappingService.autoMapParties(
      purchaseParties: uniquePurchaseParties,
      tdsParties: uniqueTdsParties,
    );

    setState(() {
      for (final result in autoResults) {
        final purchaseKey = _mappingKey(result.purchaseParty);
        if (result.isMatched &&
            result.matchedTdsParty != null &&
            purchaseKey.isNotEmpty &&
            !widget.blockedAliases.contains(purchaseKey)) {
          clearedAliases.remove(purchaseKey);
          selectedMappings[purchaseKey] = result.matchedTdsParty!;
        }
      }
    });
  }

  void _clearVisibleMappings(Map<String, String> conflictMessages) {
    final visibleParties = _filteredPurchaseParties(conflictMessages);
    setState(() {
      for (final purchaseParty in visibleParties) {
        final purchaseKey = _mappingKey(purchaseParty);
        if (purchaseKey.isEmpty) continue;
        clearedAliases.add(purchaseKey);
        selectedMappings.remove(purchaseKey);
      }
    });
  }

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

    selectedMappings = _sanitizeMappings(
      Map<String, String>.from(widget.initialMapping),
    );

    final autoResults = AutoMappingService.autoMapParties(
      purchaseParties: uniquePurchaseParties,
      tdsParties: uniqueTdsParties,
    );

    for (final result in autoResults) {
      final purchaseKey = _mappingKey(result.purchaseParty);
      if (result.isMatched &&
          result.matchedTdsParty != null &&
          purchaseKey.isNotEmpty &&
          !widget.blockedAliases.contains(purchaseKey) &&
          !selectedMappings.containsKey(purchaseKey)) {
        selectedMappings[purchaseKey] = result.matchedTdsParty!;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _saveMappings() {
    final cleanedMappings = _sanitizeMappings(selectedMappings);
    final conflicts = _buildAliasPanConflicts(cleanedMappings);
    final validMappings = Map<String, String>.from(cleanedMappings)
      ..removeWhere((key, _) => conflicts.containsKey(_mappingKey(key)));

    Navigator.pop(context, {
      'mappings': validMappings,
      'clearedAliases': clearedAliases.toList(),
      'conflictedAliases': conflicts.keys.toList(),
      'conflictMessages': conflicts,
    });
  }

  void _clearMapping(String purchaseParty) {
    final purchaseKey = _mappingKey(purchaseParty);
    setState(() {
      if (purchaseKey.isEmpty) return;
      clearedAliases.add(purchaseKey);
      selectedMappings.remove(purchaseKey);
    });
  }

  String? _getSelectedValue(String purchaseParty) {
    final purchaseKey = _mappingKey(purchaseParty);
    if (purchaseKey.isEmpty) return null;
    final selectedValue = selectedMappings[purchaseKey];
    if (selectedValue == null || !uniqueTdsParties.contains(selectedValue)) {
      selectedMappings.remove(purchaseKey);
      return null;
    }
    return selectedValue;
  }

  Widget _buildTopToolbar(Map<String, String> conflictMessages) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search party name or PAN...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: const [
                'All',
                'Matched',
                'Unmapped',
                'Missing PAN',
                'PAN Conflict',
              ]
                  .map(
                    (status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(status),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _statusFilter = value;
                });
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _applyAutoMap,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Auto Map'),
          ),
          OutlinedButton.icon(
            onPressed: () => _clearVisibleMappings(conflictMessages),
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear Mapping'),
          ),
          ElevatedButton.icon(
            onPressed: _saveMappings,
            icon: const Icon(Icons.save),
            label: const Text('Save Mapping'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    Widget headerCell(String title, int flex, {Alignment? alignment}) {
      return Expanded(
        flex: flex,
        child: Align(
          alignment: alignment ?? Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          headerCell('Purchase Party', 4),
          headerCell('Purchase PAN', 2),
          headerCell('Mapped 26Q Party', 4),
          headerCell('26Q PAN', 2),
          headerCell('Status', 2),
          headerCell('Actions', 1, alignment: Alignment.center),
        ],
      ),
    );
  }

  Widget _buildTableRow({
    required String purchaseParty,
    required String? selectedValue,
    required String purchasePan,
    required String selectedPan,
    required String status,
    required Color statusColor,
    required String? rowConflict,
    required List<String> sections,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _getStatusBackgroundColor(status),
        border: Border(
          left: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(
            color: isLast ? Colors.grey.shade300 : Colors.grey.shade200,
          ),
        ),
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
                  purchaseParty,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Section: ${sections.join(', ')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                purchasePan.isEmpty ? '-' : purchasePan,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedValue != null &&
                          uniqueTdsParties.contains(selectedValue)
                      ? selectedValue
                      : null,
                  isDense: true,
                  decoration: const InputDecoration(
                    hintText: 'Select 26Q party',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  items: uniqueTdsParties
                      .map(
                        (tdsParty) => DropdownMenuItem<String>(
                          value: tdsParty,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tdsParty,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getPanForTdsParty(tdsParty).isEmpty
                                    ? 'PAN: Not available'
                                    : 'PAN: ${_getPanForTdsParty(tdsParty)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    final purchaseKey = _mappingKey(purchaseParty);
                    setState(() {
                      if (purchaseKey.isEmpty) return;
                      if (value == null || value.trim().isEmpty) {
                        clearedAliases.add(purchaseKey);
                        selectedMappings.remove(purchaseKey);
                      } else {
                        clearedAliases.remove(purchaseKey);
                        selectedMappings[purchaseKey] = value;
                      }
                    });
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _getValidationMessage(status),
                  style: TextStyle(
                    fontSize: 12,
                    color: _getValidationColor(status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (rowConflict != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    rowConflict,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                selectedPan.isEmpty ? '-' : selectedPan,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade900,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: IconButton(
                tooltip: 'Clear Seller Mapping',
                onPressed: () => _clearMapping(purchaseParty),
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conflictMessages = _buildAliasPanConflicts(selectedMappings);
    final visiblePurchaseParties = _filteredPurchaseParties(conflictMessages);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller Mapping'),
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
            const SizedBox(height: 12),
            _buildTopToolbar(conflictMessages),
            if (conflictMessages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Text(
                  '${conflictMessages.length} seller mapping conflict'
                  '${conflictMessages.length == 1 ? '' : 's'} detected. '
                  'Conflicted aliases will not be saved as global mappings.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: visiblePurchaseParties.isEmpty
                  ? const Center(
                      child: Text(
                        'No seller mapping rows found',
                        style: TextStyle(fontSize: 18),
                      ),
                    )
                  : Column(
                      children: [
                        _buildTableHeader(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: visiblePurchaseParties.length,
                            itemBuilder: (context, index) {
                              final purchaseParty = visiblePurchaseParties[index];
                              final isLast =
                                  index == visiblePurchaseParties.length - 1;
                              final purchaseKey = _mappingKey(purchaseParty);
                              final selectedValue = _getSelectedValue(purchaseParty);
                              final rowConflict = conflictMessages[purchaseKey];
                              final sections = widget.purchaseSections[purchaseKey] ??
                                  const <String>[];
                              final purchasePan = _getPurchasePan(purchaseParty);
                              final selectedPan = _getPanForTdsParty(selectedValue);
                              final status = _getStatus(
                                purchaseParty: purchaseParty,
                                selectedValue: selectedValue,
                                rowConflict: rowConflict,
                              );
                              final statusColor = _getStatusColor(status);

                              return _buildTableRow(
                                purchaseParty: purchaseParty,
                                selectedValue: selectedValue,
                                purchasePan: purchasePan,
                                selectedPan: selectedPan,
                                status: status,
                                statusColor: statusColor,
                                rowConflict: rowConflict,
                                sections: sections,
                                isLast: isLast,
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
