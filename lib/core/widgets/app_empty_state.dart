import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasTightHeight = constraints.maxHeight.isFinite;
          final isCompact = hasTightHeight && constraints.maxHeight < 180;
          final isVeryCompact = hasTightHeight && constraints.maxHeight < 130;

          final content = Padding(
            padding: EdgeInsets.all(
              isVeryCompact
                  ? AppSpacing.xs
                  : isCompact
                  ? AppSpacing.md
                  : AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isVeryCompact
                      ? 22
                      : isCompact
                      ? 28
                      : 34,
                  color: AppColorScheme.textMuted,
                ),
                SizedBox(
                  height: isVeryCompact
                      ? AppSpacing.xxs
                      : isCompact
                      ? AppSpacing.xs
                      : AppSpacing.sm,
                ),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: isVeryCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColorScheme.textPrimary,
                    fontSize: isVeryCompact
                        ? 14
                        : isCompact
                        ? 16
                        : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: isVeryCompact ? 3 : 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: isVeryCompact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColorScheme.textSecondary,
                    fontSize: isVeryCompact
                        ? 11
                        : isCompact
                        ? 12
                        : 13,
                    height: isVeryCompact ? 1.25 : 1.45,
                  ),
                ),
                if (action != null) ...[
                  SizedBox(
                    height: isVeryCompact ? AppSpacing.xs : AppSpacing.md,
                  ),
                  action!,
                ],
              ],
            ),
          );

          if (!hasTightHeight) {
            return content;
          }

          return SingleChildScrollView(primary: false, child: content);
        },
      ),
    );
  }
}
