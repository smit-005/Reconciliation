import 'package:flutter/material.dart';

import 'app_loading.dart';

class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedOnPressed = isLoading ? null : onPressed;

    if (isLoading) {
      return FilledButton.icon(
        onPressed: resolvedOnPressed,
        icon: const AppInlineLoadingIndicator(),
        label: Text(label),
      );
    }

    if (icon != null) {
      return FilledButton.icon(
        onPressed: resolvedOnPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    return FilledButton(onPressed: resolvedOnPressed, child: Text(label));
  }
}
