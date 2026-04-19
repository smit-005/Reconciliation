import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/normalize_utils.dart';
import '../upload/models/excel_preview_data.dart';
import '../upload/models/manual_mapping_result.dart';
import '../upload/models/mapping_field_option.dart';
import '../../services/auto_mapping_service.dart';
import '../upload/services/import_mapping_service.dart';
import 'widgets/mapping_preview_table.dart';
import 'widgets/mapping_status_bar.dart';

class SellerManualMappingScreen extends StatefulWidget {
  final List<String> purchaseParties;
  final List<String> tdsParties;
  final Map<String, String> initialMapping;
  final Set<String> blockedAliases;

  const SellerManualMappingScreen({
    super.key,
    required this.purchaseParties,
    required this.tdsParties,
    this.initialMapping = const {},
    required this.blockedAliases,
  });

  @override
  State<SellerManualMappingScreen> createState() =>
      _SellerManualMappingScreenState();
}

class _SellerManualMappingScreenState extends State<SellerManualMappingScreen> {
  late Map<String, String> selectedMappings;
  late List<String> uniquePurchaseParties;
  late List<String> uniqueTdsParties;
  final Set<String> clearedAliases = {};

  String _mappingKey(String partyName) => normalizeName(partyName.trim());

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

  void _saveMappings() {
    Navigator.pop(context, {
      'mappings': selectedMappings,
      'clearedAliases': clearedAliases.toList(),
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
    return selectedMappings[purchaseKey];
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
                                    final purchaseKey =
                                        _mappingKey(purchaseParty);
                                    setState(() {
                                      if (purchaseKey.isEmpty) return;
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        clearedAliases.add(purchaseKey);
                                        selectedMappings.remove(purchaseKey);
                                      } else {
                                        clearedAliases.remove(purchaseKey);
                                        selectedMappings[purchaseKey] = value;
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

class ManualMappingScreen extends StatefulWidget {
  final ExcelPreviewData previewData;

  const ManualMappingScreen({
    super.key,
    required this.previewData,
  });

  @override
  State<ManualMappingScreen> createState() => _ManualMappingScreenState();
}

class _ManualMappingScreenState extends State<ManualMappingScreen> {
  static const List<String> purchaseRequiredFields = [
    'party_name',
    'date',
  ];
  static const List<List<String>> purchaseRequiredAnyOf = [
    ['basic_amount', 'bill_amount'],
  ];
  static const List<String> q26RequiredFields = [
    'party_name',
    'tds_amount',
    'date',
  ];
  static const List<String> genericLedgerRequiredFields = [
    'party_name',
    'date',
    'amount',
  ];

  late final List<MappingFieldOption> fieldOptions;
  late Map<String, String> selections;
  bool saveProfile = true;
  List<String> validationErrors = const [];

  @override
  void initState() {
    super.initState();
    fieldOptions = ImportMappingService.fieldOptionsFor(
      widget.previewData.fileType,
    );
    selections = {
      for (final entry in widget.previewData.suggestedMappings.entries)
        entry.key: _normalizeSelectionValue(entry.value),
    };
  }

  Map<String, String> get _canonicalMapping =>
      _normalizeCanonicalMapping(
        ImportMappingService.buildCanonicalMapping(
          {
            for (final entry in selections.entries)
              entry.key: _normalizeSelectionValue(entry.value),
          },
        ),
      );

  Map<String, String> _normalizeCanonicalMapping(Map<String, String> mapping) {
    final normalized = Map<String, String>.from(mapping);
    final panColumn = normalized.remove('pan_no');
    if (panColumn != null && panColumn.trim().isNotEmpty) {
      normalized['pan_number'] = panColumn;
    }
    final tdsColumn = normalized.remove('tds');
    if (tdsColumn != null && tdsColumn.trim().isNotEmpty) {
      normalized['tds_amount'] = tdsColumn;
    }
    final amountPaidColumn = normalized.remove('deducted_amount');
    if (amountPaidColumn != null && amountPaidColumn.trim().isNotEmpty) {
      normalized['amount_paid'] = amountPaidColumn;
    }
    if (_isGenericLedgerFile) {
      final amountColumn = normalized.remove('amount_paid');
      if (amountColumn != null && amountColumn.trim().isNotEmpty) {
        normalized['amount'] = amountColumn;
      }
      final descriptionColumn = normalized.remove('productname');
      if (descriptionColumn != null && descriptionColumn.trim().isNotEmpty) {
        normalized['description'] = descriptionColumn;
      }
      normalized.remove('tds_amount');
      normalized.remove('section');
    }
    return normalized;
  }

  Map<String, String> get _fieldLabels => {
        for (final option in fieldOptions) option.key: option.label,
      };

  bool get _isPurchaseFile =>
      widget.previewData.fileType == ImportMappingService.purchaseFileType;

  bool get _isTdsFile =>
      widget.previewData.fileType == ImportMappingService.tds26qFileType;

  bool get _isGenericLedgerFile =>
      widget.previewData.fileType == ImportMappingService.genericLedgerFileType;

  String _normalizeSelectionValue(String value) {
    switch (value.trim()) {
      case 'pan_no':
        return 'pan_number';
      case 'tds':
        return 'tds_amount';
      case 'deducted_amount':
        return _isGenericLedgerFile ? 'amount' : 'amount_paid';
      case 'amount_paid':
        return _isGenericLedgerFile ? 'amount' : 'amount_paid';
      case 'productname':
        return _isGenericLedgerFile ? 'description' : 'productname';
      default:
        return value.trim();
    }
  }

  List<String?> get _mappedFieldKeys {
    final canonicalKeys = _canonicalMapping.keys.toSet();
    return [
      if (canonicalKeys.contains('party_name')) 'party_name',
      if (canonicalKeys.contains('date') || canonicalKeys.contains('eom')) 'date',
      if (canonicalKeys.contains('basic_amount')) 'basic_amount',
      if (canonicalKeys.contains('bill_amount')) 'bill_amount',
      if (canonicalKeys.contains('amount')) 'amount',
      if (canonicalKeys.contains('tds_amount')) 'tds_amount',
      if (canonicalKeys.contains('pan_number')) 'pan_number',
      if (canonicalKeys.contains('gst_no')) 'gst_no',
      if (canonicalKeys.contains('bill_no')) 'bill_no',
      if (canonicalKeys.contains('description')) 'description',
    ];
  }

  bool hasRequiredFields(List<String?> mapped, List<String> required) {
    final mappedSet = mapped.whereType<String>().toSet();
    return required.every(mappedSet.contains);
  }

  bool hasAnyRequiredGroup(List<String?> mapped, List<List<String>> groups) {
    final mappedSet = mapped.whereType<String>().toSet();
    return groups.every(
      (group) => group.any(mappedSet.contains),
    );
  }

  bool isValidMapping(bool is26Q, List<String?> mapped) {
    if (_isGenericLedgerFile) {
      return hasRequiredFields(mapped, genericLedgerRequiredFields);
    }

    if (is26Q) {
      return hasRequiredFields(mapped, q26RequiredFields);
    }

    return hasRequiredFields(mapped, purchaseRequiredFields) &&
        hasAnyRequiredGroup(mapped, purchaseRequiredAnyOf);
  }

  List<String> get _requiredValidationMessages {
    final mappedSet = _mappedFieldKeys.whereType<String>().toSet();
    final messages = <String>[];

    if (!mappedSet.contains('party_name')) {
      messages.add('Party Name is required');
    }

    if (!mappedSet.contains('date')) {
      messages.add('Date is required');
    }

    if (_isGenericLedgerFile) {
      if (!mappedSet.contains('amount')) {
        messages.add('Amount is required');
      }
    } else if (_isTdsFile) {
      if (!mappedSet.contains('tds_amount')) {
        messages.add('TDS Amount is required');
      }
    } else if (!mappedSet.contains('basic_amount') &&
        !mappedSet.contains('bill_amount')) {
      messages.add('Map either Basic Amount or Bill Amount');
    }

    return messages;
  }

  bool get _isMappingValid => isValidMapping(_isTdsFile, _mappedFieldKeys);

  Map<String, bool> get _requiredCompletionStatus => {
        'date': _canonicalMapping.containsKey('date') ||
            _canonicalMapping.containsKey('eom'),
        'party_name': _canonicalMapping.containsKey('party_name'),
        'amount': _canonicalMapping.containsKey('amount'),
        'tds_amount': _canonicalMapping.containsKey('tds_amount'),
        'amount_column': _canonicalMapping.containsKey('bill_amount') ||
            _canonicalMapping.containsKey('basic_amount'),
      };

  Map<String, String> get _requiredFieldLabels {
    if (_isGenericLedgerFile) {
      return const {
        'party_name': 'Party Name',
        'date': 'Date',
        'amount': 'Amount',
      };
    }

    if (_isTdsFile) {
      return const {
        'party_name': 'Party Name',
        'tds_amount': 'TDS Amount',
        'date': 'Date',
      };
    }

    return const {
      'party_name': 'Party Name',
      'date': 'Date',
      'amount_column': 'Basic Amount / Bill Amount',
    };
  }

  Map<String, String> get _recommendedFieldLabels {
    if (_isGenericLedgerFile) {
      return const {
        'pan_number': 'PAN Number',
        'gst_no': 'GST No',
        'bill_no': 'Bill No',
        'description': 'Description',
      };
    }

    if (_isTdsFile) {
      return const {
        'pan_number': 'PAN Number',
        'section': 'Section',
        'amount_paid': 'Amount Paid',
      };
    }

    return const {
      'pan_number': 'PAN Number',
      'gst_no': 'GST No',
      'bill_no': 'Bill No',
    };
  }

  Set<String> get _requiredOptionKeys {
    if (_isGenericLedgerFile) {
      return const {
        'date',
        'party_name',
        'amount',
      };
    }

    if (_isTdsFile) {
      return const {
        'date_month',
        'party_name',
        'tds_amount',
      };
    }

    return const {
      'date',
      'eom',
      'party_name',
      'basic_amount',
      'bill_amount',
    };
  }

  int get _completedRequiredCount =>
      _requiredFieldLabels.keys.where((key) => _requiredCompletionStatus[key] ?? false).length;

  bool get _allRequiredMapped =>
      _isMappingValid;

  double get _displayConfidence {
    final base = widget.previewData.confidenceScore.clamp(0.0, 1.0);
    final completionRatio = _requiredFieldLabels.isEmpty
        ? base
        : _completedRequiredCount / _requiredFieldLabels.length;

    if (_allRequiredMapped) {
      return math.max(base, 0.7);
    }

    if (completionRatio >= 0.75) {
      return math.max(base, 0.55);
    }

    if (completionRatio >= 0.5) {
      return math.max(base, 0.35);
    }

    return base;
  }

  List<String> get _requiredColumnKeys {
    final keys = widget.previewData.columnKeys.where((columnKey) {
      final selected = selections[columnKey]?.trim() ?? '';
      final suggested = widget.previewData.suggestedMappings[columnKey]?.trim() ?? '';
      return _requiredOptionKeys.contains(selected) ||
          _requiredOptionKeys.contains(suggested);
    }).toList();

    return keys.isNotEmpty ? keys : widget.previewData.columnKeys.take(4).toList();
  }

  List<String> get _optionalColumnKeys => widget.previewData.columnKeys
      .where((columnKey) => !_requiredColumnKeys.contains(columnKey))
      .toList();

  Map<String, int> get _selectionCounts {
    final counts = <String, int>{};
    for (final value in selections.values) {
      final key = value.trim();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  bool _hasDuplicateFor(String? value) {
    final key = value?.trim() ?? '';
    if (key.isEmpty) return false;
    return (_selectionCounts[key] ?? 0) > 1;
  }

  void _updateSelection(String columnKey, String? value) {
    setState(() {
      final cleanedValue = value?.trim() ?? '';
      if (cleanedValue.isEmpty) {
        selections.remove(columnKey);
      } else {
        final duplicateKeys = selections.entries
            .where(
              (entry) =>
                  entry.key != columnKey && entry.value.trim() == cleanedValue,
            )
            .map((entry) => entry.key)
            .toList();
        for (final key in duplicateKeys) {
          selections.remove(key);
        }
        selections[columnKey] = cleanedValue;
      }
      validationErrors = _requiredValidationMessages;
    });
  }

  void _autoMapBestGuess() {
    setState(() {
      selections = {
        for (final entry in widget.previewData.suggestedMappings.entries)
          entry.key: _normalizeSelectionValue(entry.value),
      };
      validationErrors = _requiredValidationMessages;
    });
  }

  void _saveAndContinue() {
    final errors = [
      ..._requiredValidationMessages,
      ..._selectionCounts.entries
          .where((entry) => entry.value > 1)
          .map((entry) => '${_fieldLabels[entry.key] ?? entry.key} is mapped more than once'),
    ];

    if (errors.isNotEmpty) {
      setState(() {
        validationErrors = errors.toSet().toList();
      });
      return;
    }

    Navigator.pop(
      context,
      ManualMappingResult(
        fileType: widget.previewData.fileType,
        sheetName: widget.previewData.sheetName,
        headerRowIndex: widget.previewData.headerRowIndex,
        headersTrusted: widget.previewData.headersTrusted,
        saveProfile: saveProfile,
        rawToCanonicalMapping: Map<String, String>.from(selections),
        columnMapping: _canonicalMapping,
      ),
    );
  }

  Color _fieldStatusColor(bool isComplete) {
    return isComplete ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
  }

  bool _isLowConfidenceMapping(String columnKey) {
    final selected = selections[columnKey]?.trim() ?? '';
    if (selected.isEmpty) return false;

    final suggested = widget.previewData.suggestedMappings[columnKey]?.trim() ?? '';
    return _displayConfidence < 0.75 && selected == suggested;
  }

  BoxDecoration _panelDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderColor ?? const Color(0xFF273247)),
    );
  }

  Widget _buildFileInfoCard() {
    final confidencePercent = (_displayConfidence * 100).round();
    final confidenceColor = _displayConfidence < 0.75
        ? const Color(0xFFF59E0B)
        : const Color(0xFF38BDF8);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildInfoChip('File', widget.previewData.fileName),
                _buildInfoChip('Sheet', widget.previewData.sheetName),
                _buildInfoChip(
                  'Header',
                  'Row ${widget.previewData.headerRowIndex + 1}',
                ),
                _buildInfoChip(
                  'Confidence',
                  '$confidencePercent%',
                  accentColor: confidenceColor,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _autoMapBestGuess,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Auto Map Best Guess'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, {Color? accentColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accentColor ?? Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequiredFieldsPanel() {
    final visibleErrors = validationErrors.isNotEmpty
        ? validationErrors
        : _requiredValidationMessages;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(
        borderColor: _allRequiredMapped
            ? const Color(0xFF1F6F50)
            : const Color(0xFF7F1D1D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Required Fields',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isPurchaseFile
                ? 'Required: Party Name, Date, and Basic Amount or Bill Amount.'
                : _isGenericLedgerFile
                    ? 'Required: Party Name, Date, and Amount.'
                    : 'Required: Party Name, TDS Amount, and Date.',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          ..._requiredFieldLabels.entries.map((entry) {
            final isComplete = _requiredCompletionStatus[entry.key] ?? false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isComplete
                    ? const Color(0xFF052E16)
                    : const Color(0xFF450A0A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _fieldStatusColor(isComplete)),
              ),
              child: Row(
                children: [
                  Icon(
                    isComplete ? Icons.check_circle : Icons.error_outline,
                    color: _fieldStatusColor(isComplete),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_recommendedFieldLabels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Recommended: ${_recommendedFieldLabels.values.join(', ')}',
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
          if (visibleErrors.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...visibleErrors.map(
              (error) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumnsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView(
          children: [
            const Text(
              'Required Columns',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ..._requiredColumnKeys.map(_buildColumnCard),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                collapsedIconColor: const Color(0xFF94A3B8),
                iconColor: Colors.white,
                title: Text(
                  'Optional Columns (${_optionalColumnKeys.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Expand to map GST, PAN, product, or extra fields.',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                children: [
                  for (final columnKey in _optionalColumnKeys)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildColumnCard(columnKey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnCard(String columnKey) {
    final columnLabel = widget.previewData.columnLabels[columnKey] ?? columnKey;
    final sampleValue = widget.previewData.sampleRows.firstOrNull?[columnKey] ?? '';
    final selectedValue = selections[columnKey];
    final hasDuplicate = _hasDuplicateFor(selectedValue);
    final lowConfidence = _isLowConfidenceMapping(columnKey);

    Color borderColor = const Color(0xFF273247);
    Color backgroundColor = const Color(0xFF0B1220);

    if (hasDuplicate) {
      borderColor = const Color(0xFFEF4444);
      backgroundColor = const Color(0xFF2A0F14);
    } else if (lowConfidence) {
      borderColor = const Color(0xFFF59E0B);
      backgroundColor = const Color(0xFF2A1F0B);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      columnLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sampleValue.isEmpty ? 'Sample: (blank)' : 'Sample: $sampleValue',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (lowConfidence)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF78350F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Low confidence',
                    style: TextStyle(
                      color: Color(0xFFFDE68A),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedValue != null && selectedValue.isNotEmpty
                ? selectedValue
                : '',
            decoration: InputDecoration(
              labelText: 'Map this column',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
            ),
            dropdownColor: const Color(0xFF111827),
            style: const TextStyle(color: Colors.white),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text(
                  'Ignore column',
                  style: TextStyle(color: Color(0xFFCBD5E1)),
                ),
              ),
              ...fieldOptions.map(
                (option) => DropdownMenuItem<String>(
                  value: option.key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        option.description,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (value) =>
                _updateSelection(columnKey, (value ?? '').isEmpty ? null : value),
          ),
          if (hasDuplicate)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This field is already mapped from another column.',
                style: TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF020617),
        appBar: AppBar(
          backgroundColor: const Color(0xFF020617),
          elevation: 0,
          title: Text(
            widget.previewData.fileType == ImportMappingService.purchaseFileType
                ? 'Purchase Import Mapping'
                : widget.previewData.fileType ==
                        ImportMappingService.genericLedgerFileType
                    ? 'Generic Ledger Import Mapping'
                    : '26Q Import Mapping',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _buildFileInfoCard(),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 420,
                      child: Column(
                        children: [
                          _buildRequiredFieldsPanel(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildColumnsPanel(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: MappingPreviewTable(
                        previewData: widget.previewData,
                        selections: selections,
                        fieldLabels: _fieldLabels,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              MappingStatusBar(
                mappedCount:
                    selections.values.where((value) => value.trim().isNotEmpty).length,
                totalColumns: widget.previewData.columnKeys.length,
                warnings: [
                  ...widget.previewData.warnings,
                  ..._requiredValidationMessages,
                  if (widget.previewData.unmappedRawHeaders.isNotEmpty)
                    '${widget.previewData.unmappedRawHeaders.length} columns still need review',
                ],
                saveProfile: saveProfile,
                onSaveProfileChanged: (value) {
                  setState(() {
                    saveProfile = value;
                  });
                },
                onCancel: () => Navigator.pop(context),
                onConfirm: _isMappingValid ? _saveAndContinue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
