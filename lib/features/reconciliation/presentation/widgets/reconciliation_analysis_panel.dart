import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';

import 'reconciliation_reason_chip.dart';
import 'reconciliation_summary_header.dart';

class ReconciliationAnalysisPanel extends StatelessWidget {
  final String activeSectionTab;
  final int sourceFileCount;
  final int sourceRowCount;
  final int totalSellers;
  final int totalSections;
  final int manualMappingsCount;
  final int matchedSellersCount;
  final int mismatchSellersCount;
  final int only26QSellersCount;
  final int belowThresholdOnlySellersCount;
  final Map<String, int> mismatchReasonCounts;
  final List<String> unsupportedSections;
  final int skippedSellerCount;
  final int skippedRowsCount;
  final int applicableButNo26QSellerCount;
  final int applicableButNo26QRowCount;
  final bool isSkippedRowsFilterActive;
  final bool isMissing26QFilterActive;
  final VoidCallback? onSkippedRowsTap;
  final VoidCallback? onMissing26QTap;

  const ReconciliationAnalysisPanel({
    super.key,
    required this.activeSectionTab,
    required this.sourceFileCount,
    required this.sourceRowCount,
    required this.totalSellers,
    required this.totalSections,
    required this.manualMappingsCount,
    required this.matchedSellersCount,
    required this.mismatchSellersCount,
    required this.only26QSellersCount,
    required this.belowThresholdOnlySellersCount,
    required this.mismatchReasonCounts,
    required this.unsupportedSections,
    required this.skippedSellerCount,
    required this.skippedRowsCount,
    required this.applicableButNo26QSellerCount,
    required this.applicableButNo26QRowCount,
    this.isSkippedRowsFilterActive = false,
    this.isMissing26QFilterActive = false,
    this.onSkippedRowsTap,
    this.onMissing26QTap,
  });

  @override
  Widget build(BuildContext context) {
    final sellerExceptions = _buildSellerExceptions();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColorScheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF9FBFD), Color(0xFFF3F7FB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReconciliationSummaryHeader(
                    title: 'Exception Summary',
                    subtitle:
                        '${activeSectionTab == 'All' ? 'Combined' : activeSectionTab} scope | $sourceFileCount file(s) | $sourceRowCount row(s)',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _topMetricTile(
                          icon: Icons.apartment_rounded,
                          value: totalSellers.toString(),
                          label: 'Sellers',
                          emphasize: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _topMetricTile(
                          icon: Icons.link_rounded,
                          value: manualMappingsCount.toString(),
                          label: 'Mappings',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: _topMetricTile(
                          icon: Icons.grid_view_rounded,
                          value: totalSections.toString(),
                          label: 'Sections',
                        ),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Mismatch Reasons'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        ReconciliationReasonChip(
                          label: 'No 26Q entry',
                          count: mismatchReasonCounts['No 26Q entry'] ?? 0,
                          color: const Color(0xFFB45309),
                        ),
                        ReconciliationReasonChip(
                          label: 'Amount mismatch',
                          count: mismatchReasonCounts['Amount mismatch'] ?? 0,
                          color: const Color(0xFFDC2626),
                        ),
                        ReconciliationReasonChip(
                          label: 'TDS mismatch',
                          count: mismatchReasonCounts['TDS mismatch'] ?? 0,
                          color: const Color(0xFF7C3AED),
                        ),
                        ReconciliationReasonChip(
                          label: 'Timing difference',
                          count: mismatchReasonCounts['Timing difference'] ?? 0,
                          color: const Color(0xFF0F766E),
                        ),
                        ReconciliationReasonChip(
                          label: 'PAN/name mismatch',
                          count: mismatchReasonCounts['PAN/name mismatch'] ?? 0,
                          color: const Color(0xFF1D4ED8),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),
                    _sectionTitle('Seller Exceptions'),
                    const SizedBox(height: AppSpacing.xxs),
                    const Text(
                      'Click controls to filter sellers',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColorScheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (sellerExceptions.isEmpty)
                      const Text(
                        'No active seller exceptions in the current scope.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColorScheme.textMuted,
                        ),
                      )
                    else
                      Column(
                        children: sellerExceptions
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                child: _SellerExceptionActionCard(item: item),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.md),
                    _sectionTitle('Seller Outcomes'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        ReconciliationReasonChip(
                          label: 'Matched sellers',
                          count: matchedSellersCount,
                          color: const Color(0xFF15803D),
                        ),
                        ReconciliationReasonChip(
                          label: 'Mismatch sellers',
                          count: mismatchSellersCount,
                          color: const Color(0xFFDC2626),
                        ),
                        ReconciliationReasonChip(
                          label: 'Only 26Q sellers',
                          count: only26QSellersCount,
                          color: const Color(0xFF6D28D9),
                        ),
                        ReconciliationReasonChip(
                          label: 'Below-threshold only',
                          count: belowThresholdOnlySellersCount,
                          color: const Color(0xFF475467),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppColorScheme.textPrimary,
      ),
    );
  }

  Widget _topMetricTile({
    required IconData icon,
    required String value,
    required String label,
    bool emphasize = false,
  }) {
    final toneColor = emphasize
        ? const Color(0xFF1D4ED8)
        : AppColorScheme.textPrimary;
    final softColor = emphasize
        ? const Color(0xFFEFF6FF)
        : const Color(0xFFF8FAFC);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: softColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: toneColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: toneColor),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColorScheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColorScheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_SellerExceptionItem> _buildSellerExceptions() {
    final items = <_SellerExceptionItem>[];

    if (unsupportedSections.isNotEmpty) {
      items.add(
        _SellerExceptionItem(
          icon: Icons.warning_amber_rounded,
          toneColor: const Color(0xFFB45309),
          label: 'Unsupported sections',
          count: unsupportedSections.length,
          detail:
              'Unsupported or unknown 26Q sections in current scope: ${unsupportedSections.join(', ')}',
        ),
      );
    }

    if (skippedSellerCount > 0) {
      final detail = skippedRowsCount > 0
          ? '$skippedSellerCount seller(s) affected | $skippedRowsCount row(s) excluded.'
          : '$skippedSellerCount seller(s) affected.';

      items.add(
        _SellerExceptionItem(
          icon: Icons.rule_rounded,
          toneColor: const Color(0xFF9A3412),
          label: 'Skipped rows',
          count: skippedSellerCount,
          detail: detail,
          onTap: onSkippedRowsTap,
          isActive: isSkippedRowsFilterActive,
        ),
      );
    }

    if (applicableButNo26QSellerCount > 0) {
      final detail = applicableButNo26QRowCount > 0
          ? '$applicableButNo26QSellerCount seller(s) affected | $applicableButNo26QRowCount row(s) missing in 26Q.'
          : '$applicableButNo26QSellerCount seller(s) affected.';

      items.add(
        _SellerExceptionItem(
          icon: Icons.error_outline_rounded,
          toneColor: const Color(0xFFB91C1C),
          label: 'Missing 26Q deductions',
          count: applicableButNo26QSellerCount,
          detail: detail,
          onTap: onMissing26QTap,
          isActive: isMissing26QFilterActive,
        ),
      );
    }

    return items;
  }
}

class _SellerExceptionItem {
  final IconData icon;
  final Color toneColor;
  final String label;
  final int count;
  final String detail;
  final VoidCallback? onTap;
  final bool isActive;

  const _SellerExceptionItem({
    required this.icon,
    required this.toneColor,
    required this.label,
    required this.count,
    required this.detail,
    this.onTap,
    this.isActive = false,
  });
}

class _SellerExceptionActionCard extends StatefulWidget {
  final _SellerExceptionItem item;

  const _SellerExceptionActionCard({required this.item});

  @override
  State<_SellerExceptionActionCard> createState() =>
      _SellerExceptionActionCardState();
}

class _SellerExceptionActionCardState
    extends State<_SellerExceptionActionCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final backgroundColor = item.isActive
        ? item.toneColor.withValues(alpha: 0.12)
        : _isPressed
        ? item.toneColor.withValues(alpha: 0.1)
        : _isHovered
        ? item.toneColor.withValues(alpha: 0.07)
        : const Color(0xFFFCFCFD);
    final borderColor = item.isActive
        ? item.toneColor.withValues(alpha: 0.58)
        : _isPressed
        ? item.toneColor.withValues(alpha: 0.46)
        : _isHovered
        ? item.toneColor.withValues(alpha: 0.34)
        : AppColorScheme.border;

    final control = MouseRegion(
      cursor: item.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: item.isActive
                    ? 0.06
                    : _isHovered
                    ? 0.05
                    : 0.025,
              ),
              blurRadius: _isHovered ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            onHighlightChanged: (isPressed) {
              setState(() => _isPressed = isPressed);
            },
            borderRadius: BorderRadius.circular(AppRadius.md),
            splashColor: item.toneColor.withValues(alpha: 0.12),
            highlightColor: item.toneColor.withValues(alpha: 0.08),
            hoverColor: item.toneColor.withValues(alpha: 0.04),
            child: Ink(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: borderColor, width: 1.15),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: item.toneColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.filter_alt_rounded,
                      size: 14,
                      color: item.toneColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(item.icon, size: 15, color: item.toneColor),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.isActive
                            ? item.toneColor
                            : AppColorScheme.textPrimary,
                        height: 1.05,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.toneColor.withValues(
                        alpha: item.isActive ? 0.16 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: item.toneColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '${item.count}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: item.toneColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: item.isActive
                          ? item.toneColor
                          : item.toneColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.isActive
                          ? Icons.check_rounded
                          : Icons.chevron_right_rounded,
                      size: 14,
                      color: item.isActive ? Colors.white : item.toneColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: item.detail,
      waitDuration: const Duration(milliseconds: 300),
      child: control,
    );
  }
}
