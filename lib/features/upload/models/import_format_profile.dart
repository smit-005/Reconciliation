class ImportFormatProfile {
  final int? id;
  final String buyerId;
  final String fileType;
  final String sheetNamePattern;
  final int headerRowIndex;
  final bool headersTrusted;
  final Map<String, String> columnMapping;
  final String sampleSignature;
  final String lastUsedAt;

  const ImportFormatProfile({
    this.id,
    required this.buyerId,
    required this.fileType,
    required this.sheetNamePattern,
    required this.headerRowIndex,
    required this.headersTrusted,
    required this.columnMapping,
    required this.sampleSignature,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'file_type': fileType,
      'sheet_name_pattern': sheetNamePattern,
      'header_row_index': headerRowIndex,
      'headers_trusted': headersTrusted ? 1 : 0,
      'column_mapping_json': columnMapping.entries
          .map((e) => '${e.key}=${e.value}')
          .join('||'),
      'sample_signature': sampleSignature,
      'last_used_at': lastUsedAt,
    };
  }

  factory ImportFormatProfile.fromMap(Map<String, dynamic> map) {
    final rawMapping = (map['column_mapping_json'] ?? '').toString();
    final parsedMapping = <String, String>{};

    for (final part in rawMapping.split('||')) {
      if (!part.contains('=')) continue;
      final idx = part.indexOf('=');
      parsedMapping[part.substring(0, idx)] = part.substring(idx + 1);
    }

    return ImportFormatProfile(
      id: map['id'] as int?,
      buyerId: (map['buyer_id'] ?? '').toString(),
      fileType: (map['file_type'] ?? '').toString(),
      sheetNamePattern: (map['sheet_name_pattern'] ?? '').toString(),
      headerRowIndex: (map['header_row_index'] ?? 0) as int,
      headersTrusted: (map['headers_trusted'] ?? 0) == 1,
      columnMapping: parsedMapping,
      sampleSignature: (map['sample_signature'] ?? '').toString(),
      lastUsedAt: (map['last_used_at'] ?? '').toString(),
    );
  }
}
