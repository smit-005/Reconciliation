import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_spacing.dart';

/// Shared page shell for desktop screens.
///
/// UI-only helper: no business logic, no parsing, no reconciliation work.
class AppPageScaffold extends StatelessWidget {
  final Widget body;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final bool safeArea;

  const AppPageScaffold({
    super.key,
    required this.body,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      0,
    ),
    this.safeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: body);

    return Scaffold(
      backgroundColor: AppColorScheme.background,
      bottomNavigationBar: bottomNavigationBar,
      body: safeArea ? SafeArea(child: content) : content,
    );
  }
}
