import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final WorkspaceService workspaceService = WorkspaceService();

  String? workspaceRootPath;
  WorkspaceStatus workspaceStatus = WorkspaceStatus.notConfigured;
  bool isLoading = true;
  bool isBusy = false;
  bool isValidating = false;

  @override
  void initState() {
    super.initState();
    _loadWorkspaceRoot();
  }

  Future<void> _loadWorkspaceRoot() async {
    setState(() => isLoading = true);
    final path = await workspaceService.loadWorkspaceRootPath();
    final status = await workspaceService.getWorkspaceStatus();
    if (!mounted) return;
    setState(() {
      workspaceRootPath = path;
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

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: AppSectionCard(
                      title: Text(
                        'Workspace',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Current path',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
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
                                onPressed: _chooseWorkspace,
                              ),
                              AppSecondaryButton(
                                label: 'Open Folder',
                                icon: Icons.folder_open,
                                onPressed: canOpenWorkspace
                                    ? _openWorkspaceFolder
                                    : null,
                              ),
                              AppSecondaryButton(
                                label: validateLabel,
                                icon: Icons.verified_outlined,
                                onPressed: hasWorkspace && !isValidating
                                    ? _validateWorkspace
                                    : null,
                              ),
                            ],
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
