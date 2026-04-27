import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/upload/models/column_mapping_result.dart';
import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';
import 'package:reconciliation_app/features/upload/models/mapping_field_option.dart';
import 'package:reconciliation_app/features/upload/presentation/widgets/mapping_preview_table.dart';
import 'package:reconciliation_app/features/upload/presentation/widgets/mapping_status_bar.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';

class ColumnMappingScreen extends StatefulWidget {
  final ExcelPreviewData previewData;

  const ColumnMappingScreen({super.key, required this.previewData});

  @override
  State<ColumnMappingScreen> createState() => _ColumnMappingScreenState();
}

class _ColumnMappingScreenState extends State<ColumnMappingScreen> {
  static const List<String> q26RequiredFields = [
    'party_name',
    'pan_number',
    'section',
    'amount_paid',
    'tds_amount',
    'date_month',
  ];
  static const List<String> genericLedgerRequiredFields = [
    'party_name',
    'date',
    'amount',
  ];

  late final List<MappingFieldOption> fieldOptions;
  late Map<String, String> selections;
  late final ScrollController _columnsScrollController;
  bool saveProfile = true;
  List<String> validationErrors = const [];

  @override
  void initState() {
    super.initState();
    _columnsScrollController = ScrollController();
    fieldOptions = ImportMappingService.fieldOptionsFor(
      widget.previewData.fileType,
    );
    selections = {
      for (final entry in widget.previewData.suggestedMappings.entries)
        entry.key: _normalizeSelectionValue(entry.value),
    };
  }

  @override
  void dispose() {
    _columnsScrollController.dispose();
    super.dispose();
  }

  Map<String, String> get _canonicalMapping => _normalizeCanonicalMapping(
    ImportMappingService.buildCanonicalMapping({
      for (final entry in selections.entries)
        entry.key: _normalizeSelectionValue(entry.value),
    }),
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
      if (canonicalKeys.contains('date')) 'date',
      if (canonicalKeys.contains('date_month')) 'date_month',
      if (canonicalKeys.contains('eom')) 'eom',
      if (canonicalKeys.contains('basic_amount')) 'basic_amount',
      if (canonicalKeys.contains('bill_amount')) 'bill_amount',
      if (canonicalKeys.contains('amount')) 'amount',
      if (canonicalKeys.contains('amount_paid')) 'amount_paid',
      if (canonicalKeys.contains('tds_amount')) 'tds_amount',
      if (canonicalKeys.contains('pan_number')) 'pan_number',
      if (canonicalKeys.contains('gst_no')) 'gst_no',
      if (canonicalKeys.contains('bill_no')) 'bill_no',
      if (canonicalKeys.contains('description')) 'description',
      if (canonicalKeys.contains('section')) 'section',
    ];
  }

  bool hasRequiredFields(List<String?> mapped, List<String> required) {
    final mappedSet = mapped.whereType<String>().toSet();
    return required.every(mappedSet.contains);
  }

  bool isValidMapping(bool is26Q, List<String?> mapped) {
    if (_isGenericLedgerFile) {
      return hasRequiredFields(mapped, genericLedgerRequiredFields) &&
          (mapped.contains('pan_number') || mapped.contains('gst_no'));
    }

    if (is26Q) {
      return hasRequiredFields(mapped, q26RequiredFields);
    }

    return hasRequiredFields(mapped, const ['party_name']) &&
        (mapped.contains('date') || mapped.contains('eom')) &&
        (mapped.contains('basic_amount') || mapped.contains('bill_amount')) &&
        (mapped.contains('pan_number') || mapped.contains('gst_no'));
  }

  List<String> get _requiredValidationMessages {
    final mappedSet = _mappedFieldKeys.whereType<String>().toSet();
    final messages = <String>[];

    if (!mappedSet.contains('party_name')) {
      messages.add('Party Name is required');
    }

    if (_isGenericLedgerFile) {
      if (!mappedSet.contains('date')) {
        messages.add('Date is required');
      }
      if (!mappedSet.contains('amount')) {
        messages.add('Amount is required');
      }
      if (!mappedSet.contains('pan_number') && !mappedSet.contains('gst_no')) {
        messages.add('PAN or GST No is required');
      }
      final amountColumnKey = _selectedColumnFor('amount');
      final amountColumnLabel = amountColumnKey == null
          ? ''
          : (widget.previewData.columnLabels[amountColumnKey] ??
                amountColumnKey);
      final normalizedAmountLabel = amountColumnLabel.trim().toLowerCase();
      if (normalizedAmountLabel.contains('closing balance')) {
        messages.add('Closing Balance cannot be used as Amount');
      }
    } else if (_isTdsFile) {
      if (!mappedSet.contains('date_month')) {
        messages.add('Date / Month is required');
      }
      if (!mappedSet.contains('pan_number')) {
        messages.add('PAN Number is required');
      }
      if (!mappedSet.contains('amount_paid')) {
        messages.add('Amount Paid is required');
      }
      if (!mappedSet.contains('tds_amount')) {
        messages.add('TDS Amount is required');
      }
      if (!mappedSet.contains('section')) {
        messages.add('Section is required');
      }
    } else {
      if (!mappedSet.contains('date') && !mappedSet.contains('eom')) {
        messages.add('Bill Date or EOM is required');
      }
      if (!mappedSet.contains('basic_amount') &&
          !mappedSet.contains('bill_amount')) {
        messages.add('Map either Basic Amount or Bill Amount');
      }
      if (!mappedSet.contains('pan_number') && !mappedSet.contains('gst_no')) {
        messages.add('PAN or GST No is required');
      }
    }

    return messages;
  }

  String? _selectedColumnFor(String canonicalKey) {
    for (final entry in selections.entries) {
      if (entry.value.trim() == canonicalKey) {
        return entry.key;
      }
    }
    return null;
  }

  bool get _isMappingValid => isValidMapping(_isTdsFile, _mappedFieldKeys);

  bool _hasDuplicateFor(String? fieldKey) {
    if (fieldKey == null || fieldKey.isEmpty) return false;
    return selections.values.where((v) => v == fieldKey).length > 1;
  }

  void _updateMapping(String fieldKey, String? selectedColumnKey) {
    setState(() {
      selections.removeWhere((k, v) => v == fieldKey);
      if (selectedColumnKey != null && selectedColumnKey.isNotEmpty) {
        selections.remove(selectedColumnKey);
        selections[selectedColumnKey] = fieldKey;
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
    final errors = [..._requiredValidationMessages];

    if (errors.isNotEmpty) {
      setState(() {
        validationErrors = errors.toSet().toList();
      });
      return;
    }

    Navigator.pop(
      context,
      ColumnMappingResult(
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



  double get _displayConfidence {
    return math.max(
      widget.previewData.confidenceScore.clamp(0.0, 1.0),
      _isMappingValid ? 0.7 : 0.0,
    );
  }

  bool _isLowConfidenceMapping(String fieldKey) {
    final selectedColumn = selections.entries
        .where((e) => e.value == fieldKey)
        .map((e) => e.key)
        .firstOrNull;
    if (selectedColumn == null) return false;

    final suggested =
        widget.previewData.suggestedMappings[selectedColumn]?.trim() ?? '';
    return _displayConfidence < 0.75 && fieldKey == suggested;
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

  Widget _buildFieldsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(
        borderColor: _isMappingValid
            ? const Color(0xFF1F6F50)
            : const Color(0xFF7F1D1D),
      ),
      child: ListView(
        controller: _columnsScrollController,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Text(
            'Field Mapping',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isPurchaseFile
                ? 'Required: Party Name, Date, Amount, and PAN/GST.'
                : _isGenericLedgerFile
                ? 'Required: Date, Party Name, Amount, and PAN/GST. Closing Balance is not allowed.'
                : 'Required: Party Name, PAN, Section, Amount Paid, TDS Amount, and Date.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          if (validationErrors.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...validationErrors.map(
              (error) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFFCA5A5),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ...fieldOptions.map(_buildFieldCard),
        ],
      ),
    );
  }

  Widget _buildFieldCard(MappingFieldOption field) {
    final mappedColumnKey = selections.entries
        .where((e) => e.value == field.key)
        .map((e) => e.key)
        .firstOrNull;

    String labelStatus;
    Color statusColor;

    if (mappedColumnKey != null) {
      labelStatus = 'Mapped';
      statusColor = const Color(0xFF22C55E);
    } else if (field.key == 'section' && _isGenericLedgerFile) {
      labelStatus = 'Conditional';
      statusColor = const Color(0xFFF59E0B);
    } else if (field.key == 'pan_number' || field.key == 'gst_no') {
      final hasIdentity =
          selections.containsValue('pan_number') ||
          selections.containsValue('gst_no');
      if (_isTdsFile && field.key == 'pan_number') {
        labelStatus = 'Missing';
        statusColor = const Color(0xFFEF4444);
      } else if (hasIdentity) {
        labelStatus = 'Optional';
        statusColor = const Color(0xFF94A3B8);
      } else {
        labelStatus = 'Missing';
        statusColor = const Color(0xFFEF4444);
      }
    } else if (field.key == 'date' || field.key == 'eom') {
      final hasDate =
          selections.containsValue('date') || selections.containsValue('eom');
      if (hasDate) {
        labelStatus = 'Optional';
        statusColor = const Color(0xFF94A3B8);
      } else if (field.requiredField) {
        labelStatus = 'Missing';
        statusColor = const Color(0xFFEF4444);
      } else {
        labelStatus = 'Optional';
        statusColor = const Color(0xFF94A3B8);
      }
    } else if (field.key == 'basic_amount' || field.key == 'bill_amount') {
      final hasAmount =
          selections.containsValue('basic_amount') ||
          selections.containsValue('bill_amount');
      if (hasAmount) {
        labelStatus = 'Optional';
        statusColor = const Color(0xFF94A3B8);
      } else if (field.requiredField || field.key == 'bill_amount') {
        labelStatus = 'Missing';
        statusColor = const Color(0xFFEF4444);
      } else {
        labelStatus = 'Optional';
        statusColor = const Color(0xFF94A3B8);
      }
    } else if (field.requiredField) {
      labelStatus = 'Missing';
      statusColor = const Color(0xFFEF4444);
    } else {
      labelStatus = 'Optional';
      statusColor = const Color(0xFF94A3B8);
    }

    final hasDuplicate = _hasDuplicateFor(field.key);
    final lowConfidence = _isLowConfidenceMapping(field.key);

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
      margin: const EdgeInsets.only(bottom: 12),
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
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (lowConfidence)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Low Confidence',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  labelStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (field.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              field.description,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(
              context,
            ).copyWith(canvasColor: const Color(0xFF1E293B)),
            child: DropdownButtonFormField<String>(
              initialValue: mappedColumnKey,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    'Not Mapped',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
                ...widget.previewData.columnKeys.map((colKey) {
                  final colLabel =
                      widget.previewData.columnLabels[colKey] ?? colKey;
                  return DropdownMenuItem<String>(
                    value: colKey,
                    child: Text(colLabel, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (val) => _updateMapping(field.key, val),
            ),
          ),
          if (hasDuplicate)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This field is already mapped from another column.',
                style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(scaffoldBackgroundColor: const Color(0xFF020617)),
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
                      child: SingleChildScrollView(
                        controller: ScrollController(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [_buildFieldsPanel()],
                        ),
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
                mappedCount: selections.values
                    .where((value) => value.trim().isNotEmpty)
                    .length,
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
