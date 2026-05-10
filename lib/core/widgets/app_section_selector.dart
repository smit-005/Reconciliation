import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/normalize_utils.dart';

String compactSectionDisplayLabel(String value) {
  switch (normalizeSection(value)) {
    case '194I_A':
      return '194I(a) Plant Rent';
    case '194I_B':
      return '194I(b) Property Rent';
    case '194J_A':
      return '194J(a) Technical';
    case '194J_B':
      return '194J(b) Professional';
    default:
      return value == 'All' ? 'All' : sectionDisplayLabel(value);
  }
}

class AppSectionSelectorItem {
  final String value;
  final String label;
  final String subtitle;
  final String metricLabel;
  final bool isSelected;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? width;

  const AppSectionSelectorItem({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.metricLabel,
    required this.isSelected,
    required this.onTap,
    this.isMuted = false,
    this.onLongPress,
    this.width,
  });
}

class AppSectionSelector extends StatelessWidget {
  final List<AppSectionSelectorItem> items;
  final bool showContainer;
  final double height;

  const AppSectionSelector({
    super.key,
    required this.items,
    this.showContainer = true,
    this.height = 66,
  });

  @override
  Widget build(BuildContext context) {
    final list = SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _AppSectionSelectorTile(item: items[index]),
      ),
    );

    if (!showContainer) {
      return list;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: list,
    );
  }
}

class _AppSectionSelectorTile extends StatelessWidget {
  final AppSectionSelectorItem item;

  const _AppSectionSelectorTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final fullLabel = item.value == 'All'
        ? 'All'
        : sectionDisplayLabel(item.value);
    final tooltip = fullLabel == item.label ? item.label : fullLabel;
    final foreground = item.isSelected
        ? Colors.white
        : item.isMuted
        ? AppColorScheme.textMuted
        : AppColorScheme.textPrimary;
    final secondary = item.isSelected
        ? Colors.white.withValues(alpha: 0.72)
        : AppColorScheme.textMuted;
    final width = item.width ?? (item.label.length > 17 ? 188.0 : 166.0);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: item.onTap,
          onLongPress: item.onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: width,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              gradient: item.isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: item.isSelected
                  ? null
                  : item.isMuted
                  ? AppColorScheme.surfaceVariant
                  : AppColorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: item.isSelected
                    ? AppColorScheme.infoSoft
                    : AppColorScheme.border,
                width: item.isSelected ? 1.4 : 1,
              ),
              boxShadow: item.isSelected
                  ? [
                      BoxShadow(
                        color: AppColorScheme.textPrimary.withValues(
                          alpha: 0.12,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _SectionMetricPill(
                  label: item.metricLabel,
                  isSelected: item.isSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionMetricPill extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _SectionMetricPill({required this.label, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected ? AppColorScheme.info : AppColorScheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.10)
              : AppColorScheme.divider,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColorScheme.info,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
    );
  }
}
