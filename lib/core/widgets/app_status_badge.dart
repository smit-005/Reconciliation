import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

enum AppStatusBadgeTone {
  neutral,
  info,
  success,
  warning,
  danger,
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppStatusBadgeTone tone;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppStatusBadgeTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForTone(tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.$2.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.$2),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.$2,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colorsForTone(AppStatusBadgeTone tone) {
    switch (tone) {
      case AppStatusBadgeTone.info:
        return (AppColorScheme.infoSoft, AppColorScheme.info);
      case AppStatusBadgeTone.success:
        return (AppColorScheme.successSoft, AppColorScheme.success);
      case AppStatusBadgeTone.warning:
        return (AppColorScheme.warningSoft, AppColorScheme.warning);
      case AppStatusBadgeTone.danger:
        return (AppColorScheme.dangerSoft, AppColorScheme.danger);
      case AppStatusBadgeTone.neutral:
        return (AppColorScheme.surfaceVariant, AppColorScheme.textSecondary);
    }
  }
}
