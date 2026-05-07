import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_spacing.dart';

class AppInlineLoadingIndicator extends StatelessWidget {
  final String? label;
  final double size;
  final double strokeWidth;
  final double spacing;
  final Color? color;
  final TextStyle? labelStyle;

  const AppInlineLoadingIndicator({
    super.key,
    this.label,
    this.size = 16,
    this.strokeWidth = 2,
    this.spacing = AppSpacing.xs,
    this.color,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final spinner = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );

    final safeLabel = label?.trim();
    if (safeLabel == null || safeLabel.isEmpty) {
      return spinner;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        spinner,
        SizedBox(width: spacing),
        Text(
          safeLabel,
          style:
              labelStyle ??
              Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorScheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class AppSectionLoadingView extends StatelessWidget {
  final String? label;
  final EdgeInsetsGeometry padding;
  final double spinnerSize;
  final double strokeWidth;
  final Color? color;

  const AppSectionLoadingView({
    super.key,
    this.label,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.spinnerSize = 36,
    this.strokeWidth = 4,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: AppInlineLoadingIndicator(
          label: label,
          size: spinnerSize,
          strokeWidth: strokeWidth,
          color: color,
        ),
      ),
    );
  }
}
