import 'package:flutter/material.dart';
import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_metric_card.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_search_field.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/presentation/screens/buyer_management_screen.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/excel_upload_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final searchController = TextEditingController();
  String? selectedBuyerId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBuyers();
  }

  Future<void> _loadBuyers() async {
    setState(() {
      isLoading = true;
    });

    await BuyerStore.load();

    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buyers = BuyerStore.getAll();
    final query = searchController.text.trim().toLowerCase();
    final filtered = buyers.where((b) {
      return b.name.toLowerCase().contains(query) ||
          b.pan.toLowerCase().contains(query);
    }).toList();
    final buyersWithGst =
        buyers.where((b) => b.gstNumber.trim().isNotEmpty).length;

    Buyer? selectedBuyer;
    if (selectedBuyerId != null) {
      try {
        selectedBuyer = buyers.firstWhere((b) => b.id == selectedBuyerId);
      } catch (_) {
        selectedBuyer = null;
      }
    }
    final selectedBuyerValue = selectedBuyer;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 1180;
                    final sidebar = isCompact
                        ? SizedBox(
                            height: 420,
                            child: _HomeBuyerSidebar(
                              searchController: searchController,
                              buyers: buyers,
                              filteredBuyers: filtered,
                              selectedBuyerId: selectedBuyerId,
                              onSearchChanged: (_) => setState(() {}),
                              onManageBuyers: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BuyerManagementScreen(),
                                  ),
                                ).then((_) => _loadBuyers());
                              },
                              onBuyerSelected: (buyerId) {
                                setState(() {
                                  selectedBuyerId = buyerId;
                                });
                              },
                            ),
                          )
                        : SizedBox(
                            width: 332,
                            child: _HomeBuyerSidebar(
                              searchController: searchController,
                              buyers: buyers,
                              filteredBuyers: filtered,
                              selectedBuyerId: selectedBuyerId,
                              onSearchChanged: (_) => setState(() {}),
                              onManageBuyers: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BuyerManagementScreen(),
                                  ),
                                ).then((_) => _loadBuyers());
                              },
                              onBuyerSelected: (buyerId) {
                                setState(() {
                                  selectedBuyerId = buyerId;
                                });
                              },
                            ),
                          );

                    final dashboard = _HomeDashboardContent(
                      buyers: buyers,
                      filteredBuyerCount: filtered.length,
                      buyersWithGst: buyersWithGst,
                      selectedBuyer: selectedBuyerValue,
                      onStartReconciliation: selectedBuyerValue == null
                          ? null
                          : () {
                              final buyer = selectedBuyerValue;
                              if (buyer == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExcelUploadScreen(
                                    selectedBuyerId: buyer.id,
                                    selectedBuyerName: buyer.name,
                                    selectedBuyerPan: buyer.pan,
                                  ),
                                ),
                              );
                            },
                    );

                    if (isCompact) {
                      return ListView(
                        children: [
                          sidebar,
                          const SizedBox(height: AppSpacing.md),
                          dashboard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sidebar,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: SingleChildScrollView(
                            child: dashboard,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _HomeBuyerSidebar extends StatelessWidget {
  final TextEditingController searchController;
  final List<Buyer> buyers;
  final List<Buyer> filteredBuyers;
  final String? selectedBuyerId;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onManageBuyers;
  final ValueChanged<String> onBuyerSelected;

  const _HomeBuyerSidebar({
    required this.searchController,
    required this.buyers,
    required this.filteredBuyers,
    required this.selectedBuyerId,
    required this.onSearchChanged,
    required this.onManageBuyers,
    required this.onBuyerSelected,
  });

  @override
  Widget build(BuildContext context) {
    final buyerList = filteredBuyers.isEmpty
        ? Center(
            child: Text(
              buyers.isEmpty
                  ? 'No buyers available'
                  : 'No buyers match the current search',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          )
        : ListView.separated(
            itemCount: filteredBuyers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final buyer = filteredBuyers[index];
              final isSelected = buyer.id == selectedBuyerId;

              return _HomeBuyerTile(
                buyer: buyer,
                isSelected: isSelected,
                onTap: () => onBuyerSelected(buyer.id),
              );
            },
          );

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.maxHeight.isFinite;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize:
                hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColorScheme.infoSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: AppColorScheme.info,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LedgerMatch',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Client database',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppSearchField(
                controller: searchController,
                hintText: 'Search buyer by name or PAN',
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    '${filteredBuyers.length} buyers',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (selectedBuyerId != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const AppStatusBadge(
                      label: 'Active buyer selected',
                      tone: AppStatusBadgeTone.success,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Buyers',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  AppSecondaryButton(
                    label: 'Manage',
                    icon: Icons.people_alt_outlined,
                    onPressed: onManageBuyers,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (hasBoundedHeight)
                Expanded(child: buyerList)
              else
                SizedBox(
                  height: 240,
                  child: buyerList,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeDashboardContent extends StatelessWidget {
  final List<Buyer> buyers;
  final int filteredBuyerCount;
  final int buyersWithGst;
  final Buyer? selectedBuyer;
  final VoidCallback? onStartReconciliation;

  const _HomeDashboardContent({
    required this.buyers,
    required this.filteredBuyerCount,
    required this.buyersWithGst,
    required this.selectedBuyer,
    required this.onStartReconciliation,
  });

  @override
  Widget build(BuildContext context) {
    final dashboardWidth = MediaQuery.sizeOf(context).width;
    final metricCardWidth = dashboardWidth >= 1500
        ? 208.0
        : dashboardWidth >= 1280
            ? 188.0
            : 176.0;
    final gstCoverage = buyers.isEmpty
        ? 0
        : ((buyersWithGst / buyers.length) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeHeader(selectedBuyer: selectedBuyer),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppMetricCard(
              label: 'Buyers',
              value: buyers.length.toString(),
              helper: 'Active buyer records',
              icon: Icons.groups_2_outlined,
              width: metricCardWidth,
            ),
            AppMetricCard(
              label: 'Search Results',
              value: filteredBuyerCount.toString(),
              helper: 'Visible from current search',
              icon: Icons.filter_list_rounded,
              width: metricCardWidth,
            ),
            AppMetricCard(
              label: 'GST Coverage',
              value: '$gstCoverage%',
              helper: '$buyersWithGst of ${buyers.length} buyers',
              icon: Icons.receipt_long_outlined,
              accentColor: AppColorScheme.secondary,
              width: metricCardWidth,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _BuyerOverviewCard(
          selectedBuyer: selectedBuyer,
        ),
        const SizedBox(height: AppSpacing.md),
        _CtaBanner(
          selectedBuyer: selectedBuyer,
          onStartReconciliation: onStartReconciliation,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _WorkflowSection(),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final Buyer? selectedBuyer;

  const _HomeHeader({
    required this.selectedBuyer,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reconciliation dashboard',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              selectedBuyer == null
                  ? 'Select a buyer from the sidebar to begin a reconciliation workspace.'
                  : 'Workspace ready for ${selectedBuyer!.name}. Review the buyer overview and launch a new reconciliation.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.textSecondary,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerOverviewCard extends StatelessWidget {
  final Buyer? selectedBuyer;

  const _BuyerOverviewCard({
    required this.selectedBuyer,
  });

  @override
  Widget build(BuildContext context) {
    final hasBuyer = selectedBuyer != null;

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      backgroundColor:
          hasBuyer ? const Color(0xFFF5F9FF) : AppColorScheme.surface,
      borderColor: hasBuyer
          ? AppColorScheme.info.withValues(alpha: 0.28)
          : AppColorScheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: hasBuyer
                      ? AppColorScheme.info
                      : AppColorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.domain_verification_rounded,
                  color: hasBuyer ? Colors.white : AppColorScheme.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasBuyer ? selectedBuyer!.name : 'Selected Buyer',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      hasBuyer
                          ? 'Buyer workspace is ready for upload and mapping review.'
                          : 'Choose a buyer from the left panel to unlock reconciliation actions.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColorScheme.textSecondary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppStatusBadge(
                label: hasBuyer ? 'Active' : 'Selection required',
                tone: hasBuyer
                    ? AppStatusBadgeTone.success
                    : AppStatusBadgeTone.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasBuyer)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _BuyerDetailPill(
                  label: 'Buyer Name',
                  value: selectedBuyer!.name,
                ),
                _BuyerDetailPill(
                  label: 'PAN',
                  value: selectedBuyer!.pan,
                  emphasizeValue: true,
                ),
                _BuyerDetailPill(
                  label: 'GSTIN',
                  value: selectedBuyer!.gstNumber.trim().isEmpty
                      ? 'Not available'
                      : selectedBuyer!.gstNumber,
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColorScheme.border),
              ),
              child: Text(
                'Buyer status and profile details will appear here once a buyer is selected.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColorScheme.textSecondary,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CtaBanner extends StatelessWidget {
  final Buyer? selectedBuyer;
  final VoidCallback? onStartReconciliation;

  const _CtaBanner({
    required this.selectedBuyer,
    required this.onStartReconciliation,
  });

  @override
  Widget build(BuildContext context) {
    final hasBuyer = selectedBuyer != null;

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to start?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasBuyer
                      ? 'Open a new reconciliation workspace for the selected buyer.'
                      : 'Choose a buyer first, then open a new reconciliation workspace.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(
                label: 'Start New Reconciliation',
                icon: Icons.play_arrow_rounded,
                onPressed: onStartReconciliation,
              ),
              const _DisabledWorkspaceButton(),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        icon: Icons.upload_file_outlined,
        title: 'Upload Files',
        detail: 'Import source files',
        isActive: true,
      ),
      (
        icon: Icons.tune_rounded,
        title: 'Review Mapping',
        detail: 'Validate columns',
        isActive: false,
      ),
      (
        icon: Icons.analytics_outlined,
        title: 'Reconcile Data',
        detail: 'Run matching checks',
        isActive: false,
      ),
      (
        icon: Icons.file_download_outlined,
        title: 'Export Report',
        detail: 'Download outputs',
        isActive: false,
      ),
    ];

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workflow',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  SizedBox(
                    width: 196,
                    child: _WorkflowStepTile(
                      stepNumber: i + 1,
                      icon: steps[i].icon,
                      title: steps[i].title,
                      detail: steps[i].detail,
                      isActive: steps[i].isActive,
                    ),
                  ),
                  if (i != steps.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(
                        width: 36,
                        height: 2,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? AppColorScheme.info.withValues(alpha: 0.35)
                              : AppColorScheme.divider,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColorScheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColorScheme.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "Select a buyer, then 'Start New Reconciliation' to begin the workflow.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorScheme.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBuyerTile extends StatelessWidget {
  final Buyer buyer;
  final bool isSelected;
  final VoidCallback onTap;

  const _HomeBuyerTile({
    required this.buyer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFF4F8FF) : AppColorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColorScheme.info.withValues(alpha: 0.42)
                  : AppColorScheme.border,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColorScheme.info.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isSelected
                    ? AppColorScheme.info
                    : AppColorScheme.surfaceVariant,
                foregroundColor: isSelected
                    ? Colors.white
                    : AppColorScheme.textSecondary,
                child: Text(
                  buyer.name.isEmpty ? '?' : buyer.name[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buyer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColorScheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      buyer.pan,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColorScheme.textSecondary,
                            letterSpacing: 0.2,
                          ),
                    ),
                    if (buyer.gstNumber.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'GST: ${buyer.gstNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColorScheme.textSecondary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isSelected)
                    const AppStatusBadge(
                      label: 'Selected',
                      tone: AppStatusBadgeTone.info,
                    ),
                  if (!isSelected)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColorScheme.textMuted.withValues(alpha: 0.85),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyerDetailPill extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasizeValue;

  const _BuyerDetailPill({
    required this.label,
    required this.value,
    this.emphasizeValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: emphasizeValue
                      ? AppColorScheme.textPrimary
                      : AppColorScheme.textSecondary,
                  letterSpacing: emphasizeValue ? 0.2 : 0,
                ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowStepTile extends StatelessWidget {
  final int stepNumber;
  final IconData icon;
  final String title;
  final String detail;
  final bool isActive;

  const _WorkflowStepTile({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.detail,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColorScheme.info
                    : AppColorScheme.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? AppColorScheme.info
                      : AppColorScheme.border,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : AppColorScheme.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Step $stepNumber',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive
                        ? AppColorScheme.info
                        : AppColorScheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isActive
                    ? AppColorScheme.textPrimary
                    : AppColorScheme.textSecondary,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorScheme.textMuted,
                height: 1.25,
              ),
        ),
      ],
    );
  }
}

class _DisabledWorkspaceButton extends StatelessWidget {
  const _DisabledWorkspaceButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Previous workspace browsing is not available in the current app flow.',
      child: const AppSecondaryButton(
        label: 'View Previous Workspaces',
        icon: Icons.workspaces_outline,
        onPressed: null,
      ),
    );
  }
}
