class MappingFieldOption {
  final String key;
  final String label;
  final String description;
  final bool requiredField;
  final bool importantField;

  const MappingFieldOption({
    required this.key,
    required this.label,
    required this.description,
    this.requiredField = false,
    this.importantField = false,
  });
}
