import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

enum AppInlineBannerTone { info, warning, success }

class AppInlineBanner extends StatelessWidget {
  final String message;
  final AppInlineBannerTone tone;
  final IconData? icon;
  final Widget? action;

  const AppInlineBanner({
    super.key,
    required this.message,
    this.tone = AppInlineBannerTone.info,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForTone(tone);
    final resolvedIcon = icon ?? _iconForTone(tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.$2.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(resolvedIcon, color: colors.$2),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.$2,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }

  (Color, Color) _colorsForTone(AppInlineBannerTone tone) {
    switch (tone) {
      case AppInlineBannerTone.warning:
        return (AppColorScheme.warningSoft, AppColorScheme.warning);
      case AppInlineBannerTone.success:
        return (AppColorScheme.successSoft, AppColorScheme.success);
      case AppInlineBannerTone.info:
        return (AppColorScheme.infoSoft, AppColorScheme.info);
    }
  }

  IconData _iconForTone(AppInlineBannerTone tone) {
    switch (tone) {
      case AppInlineBannerTone.warning:
        return Icons.warning_amber_rounded;
      case AppInlineBannerTone.success:
        return Icons.check_circle_outline;
      case AppInlineBannerTone.info:
        return Icons.info_outline;
    }
  }
}
