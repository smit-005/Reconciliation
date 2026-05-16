import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/features/upload/models/upload_mapping_status.dart';

class UploadFileActionCard extends StatelessWidget {
  final String fileName;
  final int rowCount;
  final UploadMappingStatus status;
  final String? statusLabel;
  final bool is26Q;
  final bool isBusy;
  final VoidCallback? onReview;
  final VoidCallback? onReplace;
  final VoidCallback? onDelete;

  const UploadFileActionCard({
    super.key,
    required this.fileName,
    required this.rowCount,
    required this.status,
    this.statusLabel,
    this.is26Q = false,
    this.isBusy = false,
    this.onReview,
    this.onReplace,
    this.onDelete,
  });

  AppStatusBadgeTone get _tone {
    switch (status) {
      case UploadMappingStatus.confirmed:
        return AppStatusBadgeTone.success;
      case UploadMappingStatus.autoMapped:
        return AppStatusBadgeTone.info;
      case UploadMappingStatus.needsReview:
        return AppStatusBadgeTone.warning;
      case UploadMappingStatus.notMapped:
        return AppStatusBadgeTone.danger;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case UploadMappingStatus.confirmed:
        return Icons.check_circle_rounded;
      case UploadMappingStatus.autoMapped:
        return Icons.auto_awesome_rounded;
      case UploadMappingStatus.needsReview:
        return Icons.warning_amber_rounded;
      case UploadMappingStatus.notMapped:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = isBusy;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColorScheme.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: isBusy ? 0.30 : 1,
                  child: Icon(
                    is26Q
                        ? Icons.fact_check_rounded
                        : Icons.description_rounded,
                    color: AppColorScheme.info,
                    size: 20,
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColorScheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MiniChip(label: '$rowCount rows'),
                    AppStatusBadge(
                      label: statusLabel ?? status.label,
                      icon: _statusIcon,
                      tone: _tone,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ActionButton(
                tooltip: 'Review Mapping',
                icon: Icons.tune_rounded,
                onPressed: disabled ? null : onReview,
              ),
              _ActionButton(
                tooltip: is26Q ? 'Replace 26Q' : 'Replace File',
                icon: Icons.refresh_rounded,
                onPressed: disabled ? null : onReplace,
              ),
              if (!is26Q)
                _ActionButton(
                  tooltip: 'Delete File',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
                  onPressed: disabled ? null : onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;

  const _MiniChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColorScheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool danger;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.tooltip,
    required this.icon,
    this.danger = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColorScheme.danger : AppColorScheme.textSecondary;

    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      color: color,
      style: IconButton.styleFrom(
        backgroundColor: AppColorScheme.surfaceVariant,
        disabledForegroundColor: AppColorScheme.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColorScheme.divider),
        ),
      ),
    );
  }
}
