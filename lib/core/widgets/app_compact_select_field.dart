import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';

class AppCompactSelectField extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? labelText;
  final String? hintText;
  final String Function(String value)? valueLabelBuilder;

  const AppCompactSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.valueLabelBuilder,
  });

  String _displayLabel(String rawValue) {
    return valueLabelBuilder?.call(rawValue) ?? rawValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInteractive = options.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final triggerWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;

        return PopupMenuButton<String>(
          enabled: isInteractive,
          tooltip: labelText ?? hintText ?? 'Select',
          initialValue: value,
          color: Colors.white,
          elevation: 8,
          constraints: BoxConstraints(
            minWidth: triggerWidth,
            maxWidth: triggerWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColorScheme.border),
          ),
          position: PopupMenuPosition.under,
          onSelected: onChanged,
          itemBuilder: (context) {
            return options.map((option) {
              final isSelected = option == value;
              return PopupMenuItem<String>(
                value: option,
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayLabel(option),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w700,
                          color: AppColorScheme.textPrimary,
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColorScheme.primary,
                      ),
                    ],
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFEFF),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColorScheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (labelText != null && labelText!.trim().isNotEmpty) ...[
                        Text(
                          labelText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColorScheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 1),
                      ],
                      Text(
                        value.trim().isEmpty
                            ? (hintText ?? 'Select')
                            : _displayLabel(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: value.trim().isEmpty
                              ? AppColorScheme.textMuted
                              : AppColorScheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: isInteractive
                      ? AppColorScheme.textMuted
                      : AppColorScheme.divider,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
