import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AppFilterBar extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const AppFilterBar({
    super.key,
    required this.children,
    this.spacing = AppSpacing.sm,
    this.runSpacing = AppSpacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}
