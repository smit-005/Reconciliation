import 'package:flutter/material.dart';
import 'package:reconciliation_app/core/theme/app_color_scheme.dart';

class UploadBottomActionButtons extends StatelessWidget {
  final bool hasWorkspaceContent;
  final bool has26QReady;
  final bool allRequiredMappingsConfirmed;
  final bool isLoadingSellerMapping;
  final bool isSellerMappingConfirmed;
  final bool canOpenReconciliation;
  final VoidCallback reviewWorkspaceStatus;
  final VoidCallback openSellerMappingScreen;
  final VoidCallback openReconciliationScreen;

  const UploadBottomActionButtons({
    super.key,
    required this.hasWorkspaceContent,
    required this.has26QReady,
    required this.allRequiredMappingsConfirmed,
    required this.isLoadingSellerMapping,
    required this.isSellerMappingConfirmed,
    required this.canOpenReconciliation,
    required this.reviewWorkspaceStatus,
    required this.openSellerMappingScreen,
    required this.openReconciliationScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          key: const ValueKey('review_mapping_button'),
          onPressed: hasWorkspaceContent ? reviewWorkspaceStatus : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColorScheme.textPrimary,
            disabledForegroundColor: AppColorScheme.textMuted,
            side: BorderSide(
              color: hasWorkspaceContent
                  ? AppColorScheme.border
                  : AppColorScheme.divider,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Review All Mappings'),
        ),
        const Spacer(),
        if (has26QReady && allRequiredMappingsConfirmed)
          OutlinedButton.icon(
            key: const ValueKey('review_seller_mappings_button'),
            onPressed: isLoadingSellerMapping ? null : openSellerMappingScreen,
            style: OutlinedButton.styleFrom(
              foregroundColor: isSellerMappingConfirmed
                  ? AppColorScheme.success
                  : AppColorScheme.textPrimary,
              disabledForegroundColor: AppColorScheme.textMuted,
              side: BorderSide(
                color: isSellerMappingConfirmed
                    ? AppColorScheme.success.withValues(alpha: 0.38)
                    : AppColorScheme.border,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: Icon(
              isSellerMappingConfirmed
                  ? Icons.check_circle_rounded
                  : Icons.person_search_rounded,
            ),
            label: Text(
              isLoadingSellerMapping
                  ? 'Loading...'
                  : (isSellerMappingConfirmed
                        ? 'Seller Mappings Confirmed'
                        : 'Review Seller Mappings'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const ValueKey('open_reconciliation_button'),
          onPressed: canOpenReconciliation ? openReconciliationScreen : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColorScheme.primary,
            disabledBackgroundColor: AppColorScheme.surfaceMuted,
            disabledForegroundColor: AppColorScheme.textMuted,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text(
            'Open Reconciliation',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
