import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/upload/models/excel_preview_data.dart';

class FileInfoCard extends StatelessWidget {
  final ExcelPreviewData previewData;

  const FileInfoCard({
    super.key,
    required this.previewData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidencePct = (previewData.confidenceScore * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF273247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            previewData.fileName,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _chip(
                label: 'Type',
                value: previewData.fileType.toUpperCase(),
              ),
              _chip(
                label: 'Sheet',
                value: previewData.sheetName,
              ),
              _chip(
                label: 'Header Row',
                value: (previewData.headerRowIndex + 1).toString(),
              ),
              _chip(
                label: 'Confidence',
                value: '$confidencePct%',
              ),
              _chip(
                label: 'Mode',
                value: previewData.headersTrusted ? 'Header-based' : 'Pattern-based',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF182235),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30415D)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
