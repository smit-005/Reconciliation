import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppInfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool compact;
  final bool showLabel;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? labelColor;
  final Color? valueColor;
  final double? fontSize;
  final double? maxWidth;
  final double? borderRadius;
  final FontWeight labelFontWeight;
  final FontWeight valueFontWeight;

  const AppInfoChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.compact = false,
    this.showLabel = true,
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.labelColor,
    this.valueColor,
    this.fontSize,
    this.maxWidth,
    this.borderRadius,
    this.labelFontWeight = FontWeight.w700,
    this.valueFontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedLabelColor = labelColor ?? AppColorScheme.textMuted;
    final resolvedValueColor = valueColor ?? AppColorScheme.textPrimary;
    final resolvedIconColor = iconColor ?? resolvedValueColor;
    final resolvedFontSize = fontSize ?? (compact ? 12.0 : 11.5);
    final text = RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(fontSize: resolvedFontSize, color: resolvedValueColor),
        children: [
          if (showLabel && label.trim().isNotEmpty)
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontWeight: labelFontWeight,
                color: resolvedLabelColor,
              ),
            ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: valueFontWeight,
              color: resolvedValueColor,
            ),
          ),
        ],
      ),
    );

    return Container(
      constraints: maxWidth == null
          ? null
          : BoxConstraints(maxWidth: maxWidth!),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : AppSpacing.sm,
        vertical: compact ? 6 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(borderRadius ?? AppRadius.pill),
        border: Border.all(color: borderColor ?? AppColorScheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 14 : 16, color: resolvedIconColor),
            const SizedBox(width: 6),
          ],
          if (maxWidth == null) text else Expanded(child: text),
        ],
      ),
    );
  }
}
