import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/utils/financial_year_utils.dart';
import 'package:reconciliation_app/core/widgets/app_empty_state.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final WorkspaceService workspaceService = WorkspaceService();
  final defaultFyController = TextEditingController();

  String? workspaceRootPath;
  String? defaultFinancialYearLabel;
  List<Buyer> archivedBuyers = [];
  WorkspaceStatus workspaceStatus = WorkspaceStatus.notConfigured;
  bool isLoading = true;
  bool isBusy = false;
  bool isValidating = false;
  bool isSavingDefaultFinancialYear = false;
  String? restoringBuyerId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => isLoading = true);
    final path = await workspaceService.loadWorkspaceRootPath();
    final status = await workspaceService.getWorkspaceStatus();
    final defaultFinancialYear = await workspaceService
        .loadDefaultFinancialYearLabel();
    final archived = await BuyerStore.listArchived();
    if (!mounted) return;
    setState(() {
      workspaceRootPath = path;
      defaultFinancialYearLabel = defaultFinancialYear;
      defaultFyController.text = defaultFinancialYear ?? '';
      archivedBuyers = archived;
      workspaceStatus = status;
      isLoading = false;
    });
  }

  Future<void> _chooseWorkspace() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose LedgerMatch workspace folder',
      initialDirectory: workspaceRootPath,
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }

    setState(() => isBusy = true);
    try {
      await workspaceService.initWorkspace(selectedPath);
      await workspaceService.saveWorkspaceRootPath(selectedPath);
      final status = await workspaceService.getWorkspaceStatus();
      if (!mounted) return;
      setState(() {
        workspaceRootPath = selectedPath.trim();
        workspaceStatus = status;
        isBusy = false;
      });
      _showMessage(
        status == WorkspaceStatus.valid
            ? 'Workspace configured successfully'
            : 'Workspace not found or has been moved',
      );
    } catch (_) {
      final status = await workspaceService.getWorkspaceStatus();
      if (!mounted) return;
      setState(() {
        isBusy = false;
        workspaceStatus = status;
      });
      _showMessage('Failed to configure workspace');
    }
  }

  Future<void> _validateWorkspace() async {
    if (workspaceRootPath?.trim().isEmpty ?? true) {
      setState(() => workspaceStatus = WorkspaceStatus.notConfigured);
      _showMessage('No workspace selected');
      return;
    }

    setState(() => isValidating = true);
    final status = await workspaceService.getWorkspaceStatus();
    if (!mounted) return;
    setState(() {
      workspaceStatus = status;
      isValidating = false;
    });
    _showMessage(
      status == WorkspaceStatus.valid
          ? 'Workspace is valid'
          : 'Workspace not found or invalid',
    );
  }

  Future<void> _openWorkspaceFolder() async {
    final path = workspaceRootPath?.trim() ?? '';
    if (path.isEmpty) {
      setState(() => workspaceStatus = WorkspaceStatus.notConfigured);
      _showMessage('No workspace selected');
      return;
    }

    final opened = await workspaceService.openFolder(path);
    if (!mounted || opened) return;
    setState(() => workspaceStatus = WorkspaceStatus.invalid);
    _showMessage('Unable to open workspace folder');
  }

  Future<void> _saveDefaultFinancialYear() async {
    final rawValue = defaultFyController.text.trim();
    final normalized = rawValue.isEmpty
        ? null
        : normalizeFinancialYearLabel(rawValue);
    if (rawValue.isNotEmpty && normalized == null) {
      _showMessage('Enter FY in 2024-25 format');
      return;
    }

    setState(() => isSavingDefaultFinancialYear = true);
    await workspaceService.saveDefaultFinancialYearLabel(normalized);
    if (!mounted) return;
    setState(() {
      defaultFinancialYearLabel = normalized;
      defaultFyController.text = normalized ?? '';
      isSavingDefaultFinancialYear = false;
    });
    _showMessage(
      normalized == null
          ? 'Default FY cleared'
          : 'Default FY set to $normalized',
    );
  }

  Future<void> _clearDefaultFinancialYear() async {
    defaultFyController.clear();
    await _saveDefaultFinancialYear();
  }

  Future<void> _restoreBuyer(Buyer buyer) async {
    setState(() => restoringBuyerId = buyer.id);
    await BuyerStore.restore(buyer.id);
    final archived = await BuyerStore.listArchived();
    if (!mounted) return;
    setState(() {
      archivedBuyers = archived;
      restoringBuyerId = null;
    });
    _showMessage('${buyer.name} restored');
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    defaultFyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = workspaceRootPath?.trim() ?? '';
    final hasWorkspace = path.isNotEmpty;
    final canOpenWorkspace =
        hasWorkspace && workspaceStatus == WorkspaceStatus.valid;
    final validateLabel = _validateButtonLabel();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WorkspaceSettingsCard(
                            path: path,
                            hasWorkspace: hasWorkspace,
                            workspaceStatus: workspaceStatus,
                            canOpenWorkspace: canOpenWorkspace,
                            validateLabel: validateLabel,
                            isBusy: isBusy,
                            onChooseWorkspace: _chooseWorkspace,
                            onOpenWorkspaceFolder: _openWorkspaceFolder,
                            onValidateWorkspace: hasWorkspace && !isValidating
                                ? _validateWorkspace
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _DefaultFinancialYearCard(
                            controller: defaultFyController,
                            currentLabel: defaultFinancialYearLabel,
                            isSaving: isSavingDefaultFinancialYear,
                            onSave: _saveDefaultFinancialYear,
                            onClear: _clearDefaultFinancialYear,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ArchivedBuyersCard(
                            buyers: archivedBuyers,
                            restoringBuyerId: restoringBuyerId,
                            onRestore: _restoreBuyer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  String _validateButtonLabel() {
    if (isValidating) {
      return 'Validating...';
    }
    if (workspaceStatus == WorkspaceStatus.invalid) {
      return 'Validate Again';
    }
    return 'Validate';
  }
}

class _WorkspaceSettingsCard extends StatelessWidget {
  final String path;
  final bool hasWorkspace;
  final WorkspaceStatus workspaceStatus;
  final bool canOpenWorkspace;
  final String validateLabel;
  final bool isBusy;
  final VoidCallback onChooseWorkspace;
  final VoidCallback onOpenWorkspaceFolder;
  final VoidCallback? onValidateWorkspace;

  const _WorkspaceSettingsCard({
    required this.path,
    required this.hasWorkspace,
    required this.workspaceStatus,
    required this.canOpenWorkspace,
    required this.validateLabel,
    required this.isBusy,
    required this.onChooseWorkspace,
    required this.onOpenWorkspaceFolder,
    required this.onValidateWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: Text(
        'Workspace',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Current path',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColorScheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColorScheme.surfaceVariant,
              border: Border.all(color: AppColorScheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              hasWorkspace ? path : 'No workspace selected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: hasWorkspace
                    ? AppColorScheme.textPrimary
                    : AppColorScheme.textMuted,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _WorkspaceStatusBanner(status: workspaceStatus),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(
                label: 'Choose Workspace',
                icon: Icons.folder_outlined,
                isLoading: isBusy,
                onPressed: onChooseWorkspace,
              ),
              AppSecondaryButton(
                label: 'Open Folder',
                icon: Icons.folder_open,
                onPressed: canOpenWorkspace ? onOpenWorkspaceFolder : null,
              ),
              AppSecondaryButton(
                label: validateLabel,
                icon: Icons.verified_outlined,
                onPressed: onValidateWorkspace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DefaultFinancialYearCard extends StatelessWidget {
  final TextEditingController controller;
  final String? currentLabel;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _DefaultFinancialYearCard({
    required this.controller,
    required this.currentLabel,
    required this.isSaving,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final current = currentLabel?.trim();

    return AppSectionCard(
      title: Text(
        'Default Financial Year',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Used as the suggested FY when opening a buyer workspace.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColorScheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Default FY',
              hintText: '2024-25',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            current == null || current.isEmpty
                ? 'No default FY configured'
                : 'Current default: $current',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorScheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(
                label: 'Save Default FY',
                icon: Icons.save_outlined,
                isLoading: isSaving,
                onPressed: onSave,
              ),
              AppSecondaryButton(
                label: 'Clear',
                icon: Icons.clear_rounded,
                onPressed: isSaving ? null : onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchivedBuyersCard extends StatelessWidget {
  final List<Buyer> buyers;
  final String? restoringBuyerId;
  final ValueChanged<Buyer> onRestore;

  const _ArchivedBuyersCard({
    required this.buyers,
    required this.restoringBuyerId,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: Text(
        'Archived Buyers',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      child: buyers.isEmpty
          ? const AppEmptyState(
              icon: Icons.archive_outlined,
              title: 'No archived buyers',
              message: 'Archived buyers will appear here for restore.',
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: buyers.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final buyer = buyers[index];
                final isRestoring = restoringBuyerId == buyer.id;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    buyer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(_archivedBuyerSubtitle(buyer)),
                  trailing: AppSecondaryButton(
                    label: isRestoring ? 'Restoring...' : 'Restore',
                    icon: Icons.restore_rounded,
                    onPressed: restoringBuyerId == null
                        ? () => onRestore(buyer)
                        : null,
                  ),
                );
              },
            ),
    );
  }

  String _archivedBuyerSubtitle(Buyer buyer) {
    final parts = <String>[
      if (buyer.pan.trim().isNotEmpty) 'PAN: ${buyer.pan.trim()}',
      if (buyer.gstNumber.trim().isNotEmpty) 'GST: ${buyer.gstNumber.trim()}',
      if ((buyer.archivedAt ?? '').trim().isNotEmpty)
        'Archived: ${buyer.archivedAt!.trim()}',
    ];

    return parts.isEmpty ? 'No PAN/GST available' : parts.join('  |  ');
  }
}

class _WorkspaceStatusBanner extends StatelessWidget {
  final WorkspaceStatus status;

  const _WorkspaceStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final details = _detailsFor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: details.backgroundColor,
        border: Border.all(color: details.borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(details.icon, color: details.iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              details.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: details.textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _WorkspaceStatusDetails _detailsFor(WorkspaceStatus status) {
    switch (status) {
      case WorkspaceStatus.valid:
        return const _WorkspaceStatusDetails(
          message: 'Workspace is valid',
          icon: Icons.check_circle_outline,
          backgroundColor: AppColorScheme.successSoft,
          borderColor: AppColorScheme.success,
          iconColor: AppColorScheme.success,
          textColor: AppColorScheme.success,
        );
      case WorkspaceStatus.invalid:
        return const _WorkspaceStatusDetails(
          message: 'Workspace not found or has been moved',
          icon: Icons.error_outline,
          backgroundColor: AppColorScheme.warningSoft,
          borderColor: AppColorScheme.warning,
          iconColor: AppColorScheme.warning,
          textColor: AppColorScheme.warning,
        );
      case WorkspaceStatus.notConfigured:
        return const _WorkspaceStatusDetails(
          message: 'No workspace selected',
          icon: Icons.info_outline,
          backgroundColor: AppColorScheme.surfaceVariant,
          borderColor: AppColorScheme.border,
          iconColor: AppColorScheme.textMuted,
          textColor: AppColorScheme.textMuted,
        );
    }
  }
}

class _WorkspaceStatusDetails {
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;

  const _WorkspaceStatusDetails({
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
  });
}
