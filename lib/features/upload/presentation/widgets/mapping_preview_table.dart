import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';

class MappingPreviewTable extends StatefulWidget {
  final ExcelPreviewData previewData;
  final Map<String, String> selections;
  final Map<String, String> fieldLabels;

  const MappingPreviewTable({
    super.key,
    required this.previewData,
    required this.selections,
    required this.fieldLabels,
  });

  @override
  State<MappingPreviewTable> createState() => _MappingPreviewTableState();
}

class _MappingPreviewTableState extends State<MappingPreviewTable> {
  late final ScrollController _verticalController;
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _verticalController = ScrollController();
    _horizontalController = ScrollController();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                primary: false,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  primary: false,
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(
                      Color(0xFF182235),
                    ),
                    columns: widget.previewData.columnKeys.map((columnKey) {
                      final label =
                          widget.previewData.columnLabels[columnKey] ?? columnKey;
                      final mappedKey = widget.selections[columnKey];
                      final mappedLabel = mappedKey == null || mappedKey.isEmpty
                          ? ''
                          : widget.fieldLabels[mappedKey] ?? mappedKey;
                      return DataColumn(
                        label: SizedBox(
                          width: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (mappedLabel.isNotEmpty)
                                Text(
                                  mappedLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF7DD3FC),
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    rows: widget.previewData.sampleRows.map((row) {
                      return DataRow(
                        cells: widget.previewData.columnKeys.map((columnKey) {
                          final value = row[columnKey] ?? '';
                          return DataCell(
                            SizedBox(
                              width: 180,
                              child: Text(
                                value,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
