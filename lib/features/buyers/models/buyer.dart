class Buyer {
  final String id;
  final String name;
  final String pan;
  final String gstNumber;
  final String? archivedAt;
  final String workspaceRelativePath;
  final String? activeFinancialYearId;

  Buyer({
    required this.id,
    required this.name,
    required this.pan,
    this.gstNumber = '',
    this.archivedAt,
    this.workspaceRelativePath = '',
    this.activeFinancialYearId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id.trim(),
      'name': name.trim(),
      'pan': pan.trim().toUpperCase(),
      'gst_number': gstNumber.trim().toUpperCase(),
      'archived_at': archivedAt?.trim(),
      'workspace_relative_path': workspaceRelativePath.trim(),
      'active_financial_year_id': activeFinancialYearId?.trim(),
    };
  }

  factory Buyer.fromMap(Map<String, dynamic> map) {
    return Buyer(
      id: (map['id'] ?? '').toString().trim(),
      name: (map['name'] ?? '').toString().trim(),
      pan: (map['pan'] ?? '').toString().trim().toUpperCase(),
      gstNumber: (map['gst_number'] ?? '').toString().trim().toUpperCase(),
      archivedAt: (map['archived_at'] ?? '').toString().trim().isEmpty
          ? null
          : (map['archived_at'] ?? '').toString().trim(),
      workspaceRelativePath: (map['workspace_relative_path'] ?? '')
          .toString()
          .trim(),
      activeFinancialYearId:
          (map['active_financial_year_id'] ?? '').toString().trim().isEmpty
          ? null
          : (map['active_financial_year_id'] ?? '').toString().trim(),
    );
  }

  Buyer copyWith({
    String? id,
    String? name,
    String? pan,
    String? gstNumber,
    String? archivedAt,
    String? workspaceRelativePath,
    String? activeFinancialYearId,
    bool clearActiveFinancialYearId = false,
  }) {
    return Buyer(
      id: id ?? this.id,
      name: name ?? this.name,
      pan: pan ?? this.pan,
      gstNumber: gstNumber ?? this.gstNumber,
      archivedAt: archivedAt ?? this.archivedAt,
      workspaceRelativePath:
          workspaceRelativePath ?? this.workspaceRelativePath,
      activeFinancialYearId: clearActiveFinancialYearId
          ? null
          : activeFinancialYearId ?? this.activeFinancialYearId,
    );
  }
}
