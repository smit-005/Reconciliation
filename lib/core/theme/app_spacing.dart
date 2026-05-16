import 'package:flutter/widgets.dart';

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppInsets {
  static const EdgeInsets page = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets section = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets sectionLarge = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets stickyActionBar = EdgeInsets.fromLTRB(
    AppSpacing.md,
    AppSpacing.sm,
    AppSpacing.md,
    AppSpacing.md,
  );
}

class AppGaps {
  static const SizedBox verticalXs = SizedBox(height: AppSpacing.xs);
  static const SizedBox verticalSm = SizedBox(height: AppSpacing.sm);
  static const SizedBox verticalMd = SizedBox(height: AppSpacing.md);
  static const SizedBox horizontalXs = SizedBox(width: AppSpacing.xs);
  static const SizedBox horizontalSm = SizedBox(width: AppSpacing.sm);
  static const SizedBox horizontalMd = SizedBox(width: AppSpacing.md);
}
