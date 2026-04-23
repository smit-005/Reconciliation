import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppSectionCard extends StatelessWidget {
  final Widget child;
  final Widget? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  const AppSectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final content = title == null && trailing == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) Expanded(child: title!),
                  if (title != null && trailing != null)
                    const SizedBox(width: AppSpacing.md),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              child,
            ],
          );

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor ?? AppColorScheme.border),
      ),
      child: content,
    );
  }
}
