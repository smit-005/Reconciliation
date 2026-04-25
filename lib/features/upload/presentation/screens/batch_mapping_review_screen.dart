import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/utils/normalize_utils.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/core/widgets/app_sticky_action_bar.dart';
import 'package:reconciliation_app/features/upload/models/batch_mapping_review_item.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';
import 'package:reconciliation_app/features/upload/services/import_mapping_service.dart';

class BatchMappingReviewScreen extends StatefulWidget {
  final Future<List<BatchMappingReviewItem>> Function() loadItems;
  final Future<bool> Function(BatchMappingReviewItem item) onReviewItem;
  final Future<bool> Function(BatchMappingReviewItem item) onConfirmItem;
  final Future<int> Function() onConfirmAllSafe;

  const BatchMappingReviewScreen({
    super.key,
    required this.loadItems,
    required this.onReviewItem,
    required this.onConfirmItem,
    required this.onConfirmAllSafe,
  });

  @override
  State<BatchMappingReviewScreen> createState() => _BatchMappingReviewScreenState();
}

class _BatchMappingReviewScreenState extends State<BatchMappingReviewScreen> {
  List<BatchMappingReviewItem> _items = const [];
  bool _isLoading = true;
  bool _isConfirmingAll = false;

  @override
  void initState() {
    super.initState();
    _refreshItems();
  }

  Future<void> _refreshItems() async {
    final items = await widget.loadItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _handleReview(BatchMappingReviewItem item) async {
    final changed = await widget.onReviewItem(item);
    if (!mounted) return;
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.fileName} mapping updated')),
      );
    }
    await _refreshItems();
  }

  Future<void> _handleConfirm(BatchMappingReviewItem item) async {
    final changed = await widget.onConfirmItem(item);
    if (!mounted) return;
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.fileName} confirmed')),
      );
    }
    await _refreshItems();
  }

  Future<void> _handleConfirmAllSafe() async {
    setState(() {
      _isConfirmingAll = true;
    });
    final confirmedCount = await widget.onConfirmAllSafe();
    if (!mounted) return;
    setState(() {
      _isConfirmingAll = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          confirmedCount <= 0
              ? 'No safe mappings were ready to confirm.'
              : 'Confirmed $confirmedCount safe mapping${confirmedCount == 1 ? '' : 's'}.',
        ),
      ),
    );
    await _refreshItems();
  }

  int get _confirmedCount => _items.where((item) => item.isConfirmed).length;

  int get _safePendingCount => _items.where((item) => item.canConfirmSafely).length;

  int get _needsReviewCount => _items.where((item) => !item.isConfirmed).length;

  bool get _hasBlockingReview => _items.any((item) => !item.isConfirmed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      appBar: AppBar(title: const Text('Review All Mappings')),
      bottomNavigationBar: AppStickyActionBar(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 860;
            final summary = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hasBlockingReview
                      ? 'Complete mapping review here before Seller Mapping and Reconciliation unlock.'
                      : 'All uploaded files have confirmed mappings.',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColorScheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Confirmed $_confirmedCount of ${_items.length} files. $_needsReviewCount still need action.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColorScheme.textSecondary,
                  ),
                ),
              ],
            );

            final actions = Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to Upload'),
                ),
                FilledButton.icon(
                  onPressed: _safePendingCount <= 0 || _isConfirmingAll
                      ? null
                      : _handleConfirmAllSafe,
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(
                    _isConfirmingAll
                        ? 'Confirming...'
                        : 'Confirm All Safe Mappings',
                  ),
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: AppSpacing.sm),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: AppSpacing.md),
                actions,
              ],
            );
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildTableCard(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return AppSectionCard(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          _buildSummaryMetric(
            label: 'Uploaded Files',
            value: _items.length.toString(),
          ),
          _buildSummaryMetric(
            label: 'Confirmed',
            value: _confirmedCount.toString(),
          ),
          _buildSummaryMetric(
            label: 'Safe to Confirm',
            value: _safePendingCount.toString(),
          ),
          _buildSummaryMetric(
            label: 'Need Review',
            value: _needsReviewCount.toString(),
            emphasisColor: _needsReviewCount > 0
                ? AppColorScheme.warning
                : AppColorScheme.success,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required String value,
    Color? emphasisColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColorScheme.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: emphasisColor ?? AppColorScheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard() {
    if (_items.isEmpty) {
      return const AppSectionCard(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'No uploaded files are available for mapping review yet.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColorScheme.textSecondary,
            ),
          ),
        ),
      );
    }

    return AppSectionCard(
      title: const Text(
        'Mapping Review Queue',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColorScheme.textPrimary,
        ),
      ),
      trailing: AppStatusBadge(
        label: _hasBlockingReview ? 'Review Required' : 'All Confirmed',
        tone: _hasBlockingReview
            ? AppStatusBadgeTone.warning
            : AppStatusBadgeTone.success,
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          const Divider(height: 1, color: AppColorScheme.divider),
          ..._items.map(_buildTableRow),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'File',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Section',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Status',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Required',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Issues',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              'Action',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColorScheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(BatchMappingReviewItem item) {
    final needsReview = !item.isConfirmed;
    final rowColor = needsReview
        ? const Color(0xFFFFFBEB)
        : Colors.white;

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColorScheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    AppStatusBadge(
                      label: _fileTypeLabel(item.fileType),
                      tone: AppStatusBadgeTone.neutral,
                    ),
                    AppStatusBadge(
                      label: item.wasManuallyMapped ? 'Manual' : 'Auto',
                      tone: item.wasManuallyMapped
                          ? AppStatusBadgeTone.info
                          : AppStatusBadgeTone.neutral,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              item.type == BatchMappingReviewItemType.tds26q
                  ? '26Q'
                  : sectionDisplayLabel(item.sectionCode),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColorScheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: AppStatusBadge(
              label: item.mappingStatus.label,
              tone: _statusTone(item),
            ),
          ),
          Expanded(
            child: Text(
              '${item.mappedRequiredFieldsCount}/${item.requiredFieldsCount}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColorScheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: item.issues.isEmpty ? 'No blocking issues' : item.issues.join('\n'),
              child: Text(
                item.issuesCount.toString(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: item.issuesCount > 0
                      ? AppColorScheme.warning
                      : AppColorScheme.success,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: item.isConfirmed
                  ? OutlinedButton(
                      onPressed: () => _handleReview(item),
                      child: const Text('View'),
                    )
                  : item.canConfirmSafely
                  ? FilledButton(
                      onPressed: () => _handleConfirm(item),
                      child: const Text('Confirm'),
                    )
                  : OutlinedButton(
                      onPressed: () => _handleReview(item),
                      child: const Text('Review'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _fileTypeLabel(String fileType) {
    switch (fileType) {
      case ImportMappingService.tds26qFileType:
        return '26Q';
      case ImportMappingService.genericLedgerFileType:
        return 'Generic Ledger';
      default:
        return 'Purchase Parser';
    }
  }

  AppStatusBadgeTone _statusTone(BatchMappingReviewItem item) {
    if (item.isConfirmed) return AppStatusBadgeTone.success;
    if (item.canConfirmSafely) return AppStatusBadgeTone.info;
    if (item.hasBlockingIssues) return AppStatusBadgeTone.warning;
    return AppStatusBadgeTone.neutral;
  }
}
