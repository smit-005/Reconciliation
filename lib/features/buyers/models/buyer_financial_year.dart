class BuyerFinancialYear {
  final String id;
  final String buyerId;
  final String fyLabel;
  final String workspaceRelativePath;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String? archivedAt;

  const BuyerFinancialYear({
    required this.id,
    required this.buyerId,
    required this.fyLabel,
    this.workspaceRelativePath = '',
    this.status = 'not_started',
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id.trim(),
      'buyer_id': buyerId.trim(),
      'fy_label': fyLabel.trim(),
      'workspace_relative_path': workspaceRelativePath.trim(),
      'status': status.trim().isEmpty ? 'not_started' : status.trim(),
      'created_at': createdAt.trim(),
      'updated_at': updatedAt.trim(),
      'archived_at': archivedAt?.trim(),
    };
  }

  factory BuyerFinancialYear.fromMap(Map<String, dynamic> map) {
    return BuyerFinancialYear(
      id: (map['id'] ?? '').toString().trim(),
      buyerId: (map['buyer_id'] ?? '').toString().trim(),
      fyLabel: (map['fy_label'] ?? '').toString().trim(),
      workspaceRelativePath: (map['workspace_relative_path'] ?? '')
          .toString()
          .trim(),
      status: (map['status'] ?? 'not_started').toString().trim(),
      createdAt: (map['created_at'] ?? '').toString().trim(),
      updatedAt: (map['updated_at'] ?? '').toString().trim(),
      archivedAt: (map['archived_at'] ?? '').toString().trim().isEmpty
          ? null
          : (map['archived_at'] ?? '').toString().trim(),
    );
  }
}
