enum ReconciliationViewMode {
  summary,
  audit,
}

extension ReconciliationViewModeX on ReconciliationViewMode {
  String get label {
    switch (this) {
      case ReconciliationViewMode.summary:
        return 'Summary View';
      case ReconciliationViewMode.audit:
        return 'Audit View';
    }
  }

  String get shortLabel {
    switch (this) {
      case ReconciliationViewMode.summary:
        return 'Summary';
      case ReconciliationViewMode.audit:
        return 'Audit';
    }
  }
}
