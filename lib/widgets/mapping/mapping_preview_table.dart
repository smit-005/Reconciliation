import 'package:flutter/material.dart';

import '../../models/excel_preview_data.dart';

class MappingPreviewTable extends StatelessWidget {
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
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(
                      const Color(0xFF182235),
                    ),
                    columns: previewData.columnKeys.map((columnKey) {
                      final label = previewData.columnLabels[columnKey] ?? columnKey;
                      final mappedKey = selections[columnKey];
                      final mappedLabel = mappedKey == null || mappedKey.isEmpty
                          ? ''
                          : fieldLabels[mappedKey] ?? mappedKey;
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
                    rows: previewData.sampleRows.map((row) {
                      return DataRow(
                        cells: previewData.columnKeys.map((columnKey) {
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
