import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:reconciliation_app/app/routes.dart';
import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';
import 'package:reconciliation_app/core/widgets/app_empty_state.dart';
import 'package:reconciliation_app/core/widgets/app_primary_button.dart';
import 'package:reconciliation_app/core/widgets/app_rect_snackbar.dart';
import 'package:reconciliation_app/core/widgets/app_search_field.dart';
import 'package:reconciliation_app/core/widgets/app_secondary_button.dart';
import 'package:reconciliation_app/core/widgets/app_section_card.dart';
import 'package:reconciliation_app/core/widgets/app_status_badge.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_financial_year_store.dart';
import 'package:reconciliation_app/features/buyers/data/buyer_store.dart';
import 'package:reconciliation_app/features/buyers/models/buyer.dart';
import 'package:reconciliation_app/features/buyers/models/buyer_financial_year.dart';
import 'package:reconciliation_app/features/upload/presentation/screens/excel_upload_screen.dart';
import 'package:reconciliation_app/features/workspace/services/workspace_service.dart';

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  static const Duration _snackBarDuration = Duration(seconds: 4);

  final nameController = TextEditingController();
  final panController = TextEditingController();
  final gstController = TextEditingController();
  final searchController = TextEditingController();
  final fyController = TextEditingController();
  final workspaceService = WorkspaceService();

  String? editingId;
  String? selectedBuyerId;
  String? selectedFinancialYearId;
  String? defaultFinancialYearLabel;
  final Map<String, String> temporarySelectedFinancialYearIdsByBuyer = {};
  List<BuyerFinancialYear> selectedFinancialYears = [];
  bool isLoading = true;
  bool isSaving = false;
  bool isLoadingFinancialYears = false;

  List<Buyer> get buyers => BuyerStore.getAll();

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
    final defaultFy = await workspaceService.loadDefaultFinancialYearLabel();

    if (!mounted) return;
    setState(() {
      defaultFinancialYearLabel = defaultFy;
      isLoading = false;
    });
  }

  Buyer? _selectedBuyerFrom(List<Buyer> source) {
    final id = selectedBuyerId;
    if (id == null) {
      return null;
    }

    for (final buyer in source) {
      if (buyer.id == id) {
        return buyer;
      }
    }

    return null;
  }

  bool _isValidPan(String pan) {
    final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
    return regex.hasMatch(pan);
  }

  void _showSnackBar(String message, {IconData icon = Icons.info_rounded}) {
    AppRectSnackBar.show(
      context,
      message,
      icon: icon,
      duration: _snackBarDuration,
    );
  }

  Future<bool> saveBuyer() async {
    final name = nameController.text.trim();
    final pan = panController.text.trim().toUpperCase();
    final gstNumber = gstController.text.trim().toUpperCase();
    final wasEditing = editingId != null;

    if (name.isEmpty) {
      _showSnackBar('Enter buyer name');
      return false;
    }

    if (pan.isNotEmpty && !_isValidPan(pan)) {
      _showSnackBar('Enter valid PAN format');
      return false;
    }

    setState(() {
      isSaving = true;
    });

    String? error;

    if (editingId == null) {
      error = await BuyerStore.add(name, pan, gstNumber);
    } else {
      error = await BuyerStore.update(editingId!, name, pan, gstNumber);
    }

    if (!mounted) return false;

    setState(() {
      isSaving = false;
    });

    if (error != null) {
      _showSnackBar(error);
      return false;
    }

    nameController.clear();
    panController.clear();
    gstController.clear();
    editingId = null;

    setState(() {});

    _showSnackBar(
      wasEditing ? 'Buyer updated successfully' : 'Buyer added successfully',
      icon: Icons.check_circle_rounded,
    );
    return true;
  }

  void editBuyer(Buyer buyer) {
    _openBuyerDialog(buyer: buyer);
  }

  Future<void> _openBuyerDialog({Buyer? buyer}) async {
    if (buyer == null) {
      nameController.clear();
      panController.clear();
      gstController.clear();
      editingId = null;
    } else {
      nameController.text = buyer.name;
      panController.text = buyer.pan;
      gstController.text = buyer.gstNumber;
      editingId = buyer.id;
      selectBuyer(buyer);
    }

    setState(() {});

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(buyer == null ? 'Add Buyer' : 'Rename Buyer'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Buyer Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: panController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'PAN',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: gstController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'GST Number',
                    hintText: 'GST Number',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                clearForm();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('add_buyer_button'),
              onPressed: isSaving
                  ? null
                  : () async {
                      final saved = await saveBuyer();
                      if (!context.mounted || !saved) return;
                      Navigator.of(context).pop();
                    },
              child: Text(buyer == null ? 'Add Buyer' : 'Update Buyer'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      clearForm();
    }
  }

  Future<void> selectBuyer(Buyer buyer) async {
    setState(() {
      selectedBuyerId = buyer.id;
      selectedFinancialYearId = null;
      isLoadingFinancialYears = true;
    });

    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    if (!mounted || selectedBuyerId != buyer.id) return;
    final effectiveFinancialYearId = _effectiveFinancialYearIdForBuyer(
      buyer.id,
      financialYears,
    );
    setState(() {
      selectedFinancialYears = financialYears;
      selectedFinancialYearId = effectiveFinancialYearId;
      isLoadingFinancialYears = false;
    });
  }

  String? _effectiveFinancialYearIdForBuyer(
    String buyerId,
    List<BuyerFinancialYear> financialYears,
  ) {
    final temporaryFinancialYearId =
        temporarySelectedFinancialYearIdsByBuyer[buyerId]?.trim();
    if (temporaryFinancialYearId != null &&
        temporaryFinancialYearId.isNotEmpty &&
        financialYears.any(
          (financialYear) => financialYear.id == temporaryFinancialYearId,
        )) {
      return temporaryFinancialYearId;
    }

    final defaultFy = defaultFinancialYearLabel?.trim();
    if (defaultFy != null && defaultFy.isNotEmpty) {
      for (final financialYear in financialYears) {
        if (financialYear.fyLabel.trim() == defaultFy) {
          return financialYear.id;
        }
      }
    }

    return null;
  }

  Future<void> archiveBuyer(String id) async {
    await BuyerStore.archive(id);
    if (!mounted) return;
    temporarySelectedFinancialYearIdsByBuyer.remove(id);
    if (selectedBuyerId == id) {
      selectedBuyerId = null;
      selectedFinancialYearId = null;
      selectedFinancialYears = [];
    }
    setState(() {});
  }

  Future<void> openBuyerFolder(Buyer buyer) async {
    if (buyer.workspaceRelativePath.trim().isEmpty) {
      _showSnackBar('No workspace folder is linked yet');
      return;
    }

    final opened = await workspaceService.openFolder(
      buyer.workspaceRelativePath,
    );
    if (!mounted || opened) return;

    _showSnackBar('Buyer folder was not found. Check workspace settings.');
  }

  Future<void> addFinancialYear(Buyer buyer) async {
    fyController.clear();

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Financial Year'),
          content: TextField(
            controller: fyController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Financial year',
              hintText: '2024-25',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (shouldCreate != true) {
      return;
    }

    final error = await BuyerFinancialYearStore.create(
      buyer: buyer,
      fyLabel: fyController.text,
    );
    if (!mounted) return;

    if (error != null) {
      _showSnackBar(error);
      return;
    }

    await selectBuyer(buyer);
    if (!mounted) return;
    _showSnackBar('Financial year added', icon: Icons.check_circle_rounded);
  }

  Future<void> _openSettingsAndRefresh() async {
    await Navigator.of(context).pushNamed(AppRoutes.settings);
    if (!mounted) return;
    temporarySelectedFinancialYearIdsByBuyer.clear();
    await _loadBuyers();
    final selectedBuyer = _selectedBuyerFrom(buyers);
    if (selectedBuyer != null) {
      await selectBuyer(selectedBuyer);
    }
  }

  Future<void> _openWorkspacePath(String path) async {
    final opened = await workspaceService.openPath(path);
    if (!mounted || opened) return;
    _showSnackBar('Unable to open workspace item');
  }

  Future<void> _copyWorkspacePath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    _showSnackBar('Path copied', icon: Icons.copy_rounded);
  }

  Future<void> _openFinancialYearPickerDialog(Buyer buyer) async {
    final financialYears = await BuyerFinancialYearStore.listActive(buyer.id);
    if (!mounted) return;

    setState(() {
      selectedFinancialYears = financialYears;
      if (selectedBuyerId == buyer.id) {
        selectedFinancialYearId = _effectiveFinancialYearIdForBuyer(
          buyer.id,
          financialYears,
        );
      }
    });

    final selected = await showDialog<BuyerFinancialYear>(
      context: context,
      builder: (context) {
        final effectiveId = _effectiveFinancialYearIdForBuyer(
          buyer.id,
          financialYears,
        );

        return AlertDialog(
          title: Text('Select FY - ${buyer.name}'),
          content: SizedBox(
            width: 420,
            child: financialYears.isEmpty
                ? const AppEmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'No FY found',
                    message: 'Add a financial year to continue.',
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: financialYears.length,
                    itemBuilder: (context, index) {
                      final financialYear = financialYears[index];
                      final isSelected = financialYear.id == effectiveId;
                      return ListTile(
                        selected: isSelected,
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(financialYear.fyLabel),
                        onTap: () => Navigator.of(context).pop(financialYear),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await addFinancialYear(buyer);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add FY'),
            ),
          ],
        );
      },
    );

    if (selected == null || !mounted) return;
    temporarySelectedFinancialYearIdsByBuyer[buyer.id] = selected.id;
    await selectBuyer(buyer);
  }

  void clearForm() {
    nameController.clear();
    panController.clear();
    gstController.clear();
    editingId = null;
    setState(() {});
  }

  BuyerFinancialYear? _selectedFinancialYearFrom(
    List<BuyerFinancialYear> source,
  ) {
    final id = selectedFinancialYearId;
    if (id == null) {
      return null;
    }

    for (final financialYear in source) {
      if (financialYear.id == id) {
        return financialYear;
      }
    }

    return null;
  }

  void _startReconciliation(Buyer buyer) {
    var financialYear = _selectedFinancialYearFrom(selectedFinancialYears);
    if (financialYear == null) {
      final effectiveFinancialYearId = _effectiveFinancialYearIdForBuyer(
        buyer.id,
        selectedFinancialYears,
      );
      if (effectiveFinancialYearId != null) {
        selectedFinancialYearId = effectiveFinancialYearId;
        financialYear = _selectedFinancialYearFrom(selectedFinancialYears);
      }
    }
    if (financialYear == null) {
      _showSnackBar('Select a financial year to continue');
      return;
    }
    final resolvedFinancialYear = financialYear;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelUploadScreen(
          selectedBuyerId: buyer.id,
          selectedBuyerName: buyer.name,
          selectedBuyerPan: buyer.pan,
          selectedFinancialYearId: resolvedFinancialYear.id,
          selectedFinancialYearLabel: resolvedFinancialYear.fyLabel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    panController.dispose();
    gstController.dispose();
    searchController.dispose();
    fyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    final filtered = buyers.where((b) {
      return b.name.toLowerCase().contains(query) ||
          b.pan.toLowerCase().contains(query) ||
          b.gstNumber.toLowerCase().contains(query);
    }).toList();
    final selectedBuyer = _selectedBuyerFrom(buyers);
    final selectedFinancialYear = _financialYearById(
      selectedFinancialYears,
      selectedFinancialYearId,
    );
    final effectiveFinancialYearLabel =
        selectedFinancialYear?.fyLabel ?? defaultFinancialYearLabel?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buyer Management'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettingsAndRefresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 304,
                    child: _BuyerListPanel(
                      buyers: filtered,
                      totalBuyerCount: buyers.length,
                      selectedBuyerId: selectedBuyerId,
                      searchController: searchController,
                      onSearchChanged: (_) => setState(() {}),
                      onAddBuyer: () => _openBuyerDialog(),
                      onSelectBuyer: selectBuyer,
                      onSelectFinancialYear: _openFinancialYearPickerDialog,
                      onEditBuyer: editBuyer,
                      onArchiveBuyer: (buyer) => archiveBuyer(buyer.id),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _BuyerWorkspacePreview(
                      buyer: selectedBuyer,
                      financialYears: selectedFinancialYears,
                      selectedFinancialYearId: selectedFinancialYearId,
                      effectiveFinancialYearLabel:
                          effectiveFinancialYearLabel?.isEmpty ?? true
                          ? null
                          : effectiveFinancialYearLabel,
                      isLoadingFinancialYears: isLoadingFinancialYears,
                      onAddFinancialYear: selectedBuyer == null
                          ? null
                          : () => addFinancialYear(selectedBuyer),
                      onSelectFinancialYear: (financialYear) {
                        final buyer = selectedBuyer;
                        if (buyer == null) return;
                        setState(() {
                          temporarySelectedFinancialYearIdsByBuyer[buyer.id] =
                              financialYear.id;
                          selectedFinancialYearId = financialYear.id;
                        });
                      },
                      onStartReconciliation: selectedBuyer == null
                          ? null
                          : () => _startReconciliation(selectedBuyer),
                      onOpenBuyerFolder: selectedBuyer == null
                          ? null
                          : () => openBuyerFolder(selectedBuyer),
                      workspaceService: workspaceService,
                      onOpenSettings: _openSettingsAndRefresh,
                      onOpenWorkspacePath: _openWorkspacePath,
                      onCopyWorkspacePath: _copyWorkspacePath,
                      isTemporarySelection: selectedBuyer == null
                          ? false
                          : temporarySelectedFinancialYearIdsByBuyer[selectedBuyer
                                        .id] ==
                                    selectedFinancialYearId &&
                                selectedFinancialYearId != null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

BuyerFinancialYear? _financialYearById(
  List<BuyerFinancialYear> financialYears,
  String? financialYearId,
) {
  if (financialYearId == null) {
    return null;
  }

  for (final financialYear in financialYears) {
    if (financialYear.id == financialYearId) {
      return financialYear;
    }
  }

  return null;
}

enum _BuyerRowAction { selectFinancialYear, edit, archive }

class _BuyerListPanel extends StatelessWidget {
  final List<Buyer> buyers;
  final int totalBuyerCount;
  final String? selectedBuyerId;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddBuyer;
  final ValueChanged<Buyer> onSelectBuyer;
  final ValueChanged<Buyer> onSelectFinancialYear;
  final ValueChanged<Buyer> onEditBuyer;
  final ValueChanged<Buyer> onArchiveBuyer;

  const _BuyerListPanel({
    required this.buyers,
    required this.totalBuyerCount,
    required this.selectedBuyerId,
    required this.searchController,
    required this.onSearchChanged,
    required this.onAddBuyer,
    required this.onSelectBuyer,
    required this.onSelectFinancialYear,
    required this.onEditBuyer,
    required this.onArchiveBuyer,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: AppColorScheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Buyers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$totalBuyerCount',
                style: const TextStyle(
                  color: AppColorScheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSearchField(
            controller: searchController,
            hintText: 'Search buyer',
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: AppPrimaryButton(
              key: const ValueKey('add_buyer_button'),
              label: 'Add Buyer',
              icon: Icons.add_rounded,
              onPressed: onAddBuyer,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: buyers.isEmpty
                ? const Center(
                    child: AppEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No buyers found',
                      message: 'No buyers match the current search.',
                    ),
                  )
                : ListView.separated(
                    itemCount: buyers.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final buyer = buyers[index];
                      return _BuyerListRow(
                        buyer: buyer,
                        isSelected: buyer.id == selectedBuyerId,
                        onTap: () => onSelectBuyer(buyer),
                        onSelectFinancialYear: () =>
                            onSelectFinancialYear(buyer),
                        onEdit: () => onEditBuyer(buyer),
                        onArchive: () => onArchiveBuyer(buyer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BuyerListRow extends StatelessWidget {
  final Buyer buyer;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onSelectFinancialYear;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const _BuyerListRow({
    required this.buyer,
    required this.isSelected,
    required this.onTap,
    required this.onSelectFinancialYear,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? colorScheme.primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : AppColorScheme.divider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        dense: true,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        selected: isSelected,
        onTap: onTap,
        title: Text(
          buyer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            _buyerSubtitle(buyer),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<_BuyerRowAction>(
          tooltip: 'Buyer actions',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            switch (action) {
              case _BuyerRowAction.selectFinancialYear:
                onSelectFinancialYear();
              case _BuyerRowAction.edit:
                onEdit();
              case _BuyerRowAction.archive:
                onArchive();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _BuyerRowAction.selectFinancialYear,
              child: Text('Select FY'),
            ),
            PopupMenuItem(
              value: _BuyerRowAction.edit,
              child: Text('Rename Buyer'),
            ),
            PopupMenuItem(
              value: _BuyerRowAction.archive,
              child: Text('Archive Buyer'),
            ),
          ],
        ),
      ),
    );
  }

  String _buyerSubtitle(Buyer buyer) {
    final parts = <String>[
      if (buyer.pan.trim().isNotEmpty) 'PAN: ${buyer.pan.trim()}',
      if (buyer.gstNumber.trim().isNotEmpty) 'GST: ${buyer.gstNumber.trim()}',
    ];

    return parts.isEmpty ? 'PAN/GST not available' : parts.join('  |  ');
  }
}

class _BuyerWorkspacePreview extends StatelessWidget {
  final Buyer? buyer;
  final List<BuyerFinancialYear> financialYears;
  final String? selectedFinancialYearId;
  final String? effectiveFinancialYearLabel;
  final bool isLoadingFinancialYears;
  final bool isTemporarySelection;
  final VoidCallback? onAddFinancialYear;
  final ValueChanged<BuyerFinancialYear> onSelectFinancialYear;
  final VoidCallback? onStartReconciliation;
  final VoidCallback? onOpenBuyerFolder;
  final WorkspaceService workspaceService;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onOpenWorkspacePath;
  final ValueChanged<String> onCopyWorkspacePath;

  const _BuyerWorkspacePreview({
    required this.buyer,
    required this.financialYears,
    required this.selectedFinancialYearId,
    required this.effectiveFinancialYearLabel,
    required this.isLoadingFinancialYears,
    required this.isTemporarySelection,
    required this.onAddFinancialYear,
    required this.onSelectFinancialYear,
    required this.onStartReconciliation,
    required this.onOpenBuyerFolder,
    required this.workspaceService,
    required this.onOpenSettings,
    required this.onOpenWorkspacePath,
    required this.onCopyWorkspacePath,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBuyer = buyer;
    if (selectedBuyer == null) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.business_center_outlined,
          title: 'Select a buyer to view workspace',
          message: 'Choose a buyer from the list to preview reconciliation.',
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            borderColor: AppColorScheme.border,
            title: Text(
              selectedBuyer.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            trailing: AppStatusBadge(
              label: financialYears.isEmpty ? 'Not started' : 'Workspace ready',
              tone: financialYears.isEmpty
                  ? AppStatusBadgeTone.neutral
                  : AppStatusBadgeTone.info,
              icon: financialYears.isEmpty
                  ? Icons.pending_outlined
                  : Icons.folder_copy_outlined,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _InfoPill(
                  label: 'PAN',
                  value: selectedBuyer.pan.trim().isEmpty
                      ? 'Not available'
                      : selectedBuyer.pan,
                ),
                _InfoPill(
                  label: 'GST',
                  value: selectedBuyer.gstNumber.trim().isEmpty
                      ? 'Not available'
                      : selectedBuyer.gstNumber,
                ),
                _InfoPill(
                  label: 'Folder',
                  value: selectedBuyer.workspaceRelativePath.trim().isEmpty
                      ? 'Not linked'
                      : selectedBuyer.workspaceRelativePath,
                ),
                if (selectedBuyer.workspaceRelativePath.trim().isNotEmpty)
                  AppSecondaryButton(
                    label: 'Open Folder',
                    icon: Icons.folder_open_rounded,
                    onPressed: onOpenBuyerFolder,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _FinancialYearContextCard(
            selectedFinancialYear: _financialYearById(
              financialYears,
              selectedFinancialYearId,
            ),
            selectedFinancialYearId: selectedFinancialYearId,
            effectiveFinancialYearLabel: effectiveFinancialYearLabel,
            isLoading: isLoadingFinancialYears,
            onAdd: onAddFinancialYear ?? () {},
            onSelect: onSelectFinancialYear,
            financialYears: financialYears,
            isTemporarySelection: isTemporarySelection,
          ),
          const SizedBox(height: AppSpacing.md),
          _WorkspaceFilesPanel(
            buyer: selectedBuyer,
            financialYears: financialYears,
            selectedFinancialYearId: selectedFinancialYearId,
            effectiveFinancialYearLabel: effectiveFinancialYearLabel,
            workspaceService: workspaceService,
            onStartReconciliation: onStartReconciliation ?? () {},
            onOpenSettings: onOpenSettings,
            onOpenWorkspacePath: onOpenWorkspacePath,
            onCopyWorkspacePath: onCopyWorkspacePath,
          ),
        ],
      ),
    );
  }
}

class _FinancialYearContextCard extends StatelessWidget {
  final BuyerFinancialYear? selectedFinancialYear;
  final String? selectedFinancialYearId;
  final String? effectiveFinancialYearLabel;
  final bool isLoading;
  final VoidCallback onAdd;
  final ValueChanged<BuyerFinancialYear> onSelect;
  final List<BuyerFinancialYear> financialYears;
  final bool isTemporarySelection;

  const _FinancialYearContextCard({
    required this.selectedFinancialYear,
    required this.selectedFinancialYearId,
    required this.effectiveFinancialYearLabel,
    required this.isLoading,
    required this.onAdd,
    required this.onSelect,
    required this.financialYears,
    required this.isTemporarySelection,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const LinearProgressIndicator();
    }

    final financialYear = selectedFinancialYear;
    final effectiveLabel =
        financialYear?.fyLabel ?? effectiveFinancialYearLabel;
    final label = effectiveLabel == null
        ? 'No FY selected'
        : 'FY $effectiveLabel';
    final subtitle = effectiveLabel == null
        ? 'Select or create an FY'
        : isTemporarySelection
        ? 'Temporary Selection'
        : 'Using Global Default FY';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Row(
        children: [
          Icon(
            effectiveLabel == null
                ? Icons.calendar_today_outlined
                : Icons.event_available_outlined,
            color: AppColorScheme.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColorScheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PopupMenuButton<BuyerFinancialYear>(
            tooltip: 'Select FY',
            enabled: financialYears.isNotEmpty,
            icon: const Icon(Icons.arrow_drop_down_circle_outlined),
            onSelected: onSelect,
            itemBuilder: (context) => [
              for (final financialYear in financialYears)
                PopupMenuItem(
                  value: financialYear,
                  child: Row(
                    children: [
                      Icon(
                        financialYear.id == selectedFinancialYearId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(financialYear.fyLabel),
                    ],
                  ),
                ),
            ],
          ),
          AppSecondaryButton(
            label: 'Add FY',
            icon: Icons.add_rounded,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              color: AppColorScheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceFilesPanel extends StatefulWidget {
  final Buyer buyer;
  final List<BuyerFinancialYear> financialYears;
  final String? selectedFinancialYearId;
  final String? effectiveFinancialYearLabel;
  final WorkspaceService workspaceService;
  final VoidCallback onStartReconciliation;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onOpenWorkspacePath;
  final ValueChanged<String> onCopyWorkspacePath;

  const _WorkspaceFilesPanel({
    required this.buyer,
    required this.financialYears,
    required this.selectedFinancialYearId,
    required this.effectiveFinancialYearLabel,
    required this.workspaceService,
    required this.onStartReconciliation,
    required this.onOpenSettings,
    required this.onOpenWorkspacePath,
    required this.onCopyWorkspacePath,
  });

  @override
  State<_WorkspaceFilesPanel> createState() => _WorkspaceFilesPanelState();
}

class _WorkspaceFilesPanelState extends State<_WorkspaceFilesPanel> {
  static const List<_WorkspaceFolderCandidate> _folderCandidates = [
    _WorkspaceFolderCandidate('Source Files', ['Source_Files']),
    _WorkspaceFolderCandidate('Working', ['Working']),
    _WorkspaceFolderCandidate('Exports', ['Exports', 'Final_Exports']),
    _WorkspaceFolderCandidate('Reports', ['Reports', 'Exception_Reports']),
    _WorkspaceFolderCandidate('Backups', ['Backups']),
    _WorkspaceFolderCandidate('Snapshots', ['Source_Snapshots']),
  ];

  WorkspaceStatus workspaceStatus = WorkspaceStatus.notConfigured;
  bool isLoading = true;
  String? buyerWorkspacePath;
  String? selectedWorkspacePath;
  List<_DetectedFinancialYearWorkspace> detectedWorkspaces = [];
  List<_WorkspaceFolderPreview> folderPreviews = [];

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceFilesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buyer.id != widget.buyer.id ||
        oldWidget.selectedFinancialYearId != widget.selectedFinancialYearId ||
        oldWidget.effectiveFinancialYearLabel !=
            widget.effectiveFinancialYearLabel ||
        oldWidget.financialYears.length != widget.financialYears.length) {
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    setState(() => isLoading = true);

    final status = await widget.workspaceService.getWorkspaceStatus();
    String? resolvedBuyerPath;
    final detected = <_DetectedFinancialYearWorkspace>[];
    var previews = <_WorkspaceFolderPreview>[];
    String? resolvedSelectedPath;

    if (status == WorkspaceStatus.valid) {
      resolvedBuyerPath = await _resolveBuyerWorkspacePath();
      if (resolvedBuyerPath != null &&
          await Directory(resolvedBuyerPath).exists()) {
        detected.addAll(
          await _detectFinancialYearWorkspaces(resolvedBuyerPath),
        );
        resolvedSelectedPath = _selectedWorkspacePath(detected);
        if (resolvedSelectedPath != null) {
          previews = await _loadFolderPreviews(resolvedSelectedPath);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      workspaceStatus = status;
      buyerWorkspacePath = resolvedBuyerPath;
      detectedWorkspaces = detected;
      selectedWorkspacePath = resolvedSelectedPath;
      folderPreviews = previews;
      isLoading = false;
    });
  }

  Future<String?> _resolveBuyerWorkspacePath() async {
    final storedPath = widget.buyer.workspaceRelativePath.trim();
    if (storedPath.isNotEmpty) {
      final resolvedStoredPath = await widget.workspaceService
          .resolveWorkspacePath(storedPath);
      if (resolvedStoredPath != null &&
          await Directory(resolvedStoredPath).exists()) {
        return resolvedStoredPath;
      }
    }

    final expectedFolderName = widget.workspaceService.buildBuyerFolderName(
      pan: widget.buyer.pan,
      name: widget.buyer.name,
      buyerCode: widget.buyer.id,
    );
    final expectedPath = await widget.workspaceService.resolveWorkspacePath(
      p.join('Buyers', expectedFolderName),
    );
    if (expectedPath != null && await Directory(expectedPath).exists()) {
      return expectedPath;
    }

    return null;
  }

  Future<List<_DetectedFinancialYearWorkspace>> _detectFinancialYearWorkspaces(
    String resolvedBuyerPath,
  ) async {
    final workspaces = <String, _DetectedFinancialYearWorkspace>{};

    for (final financialYear in widget.financialYears) {
      final relativePath = financialYear.workspaceRelativePath.trim();
      if (relativePath.isEmpty) {
        continue;
      }
      final resolvedPath = await widget.workspaceService.resolveWorkspacePath(
        relativePath,
      );
      if (resolvedPath == null || !await Directory(resolvedPath).exists()) {
        continue;
      }
      workspaces[p.normalize(resolvedPath)] = _DetectedFinancialYearWorkspace(
        label: financialYear.fyLabel,
        path: resolvedPath,
        financialYearId: financialYear.id,
      );
    }

    await for (final entity in Directory(
      resolvedBuyerPath,
    ).list(recursive: false, followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final folderName = p.basename(entity.path);
      if (!folderName.toUpperCase().startsWith('FY_')) {
        continue;
      }
      final normalizedPath = p.normalize(entity.path);
      workspaces.putIfAbsent(
        normalizedPath,
        () => _DetectedFinancialYearWorkspace(
          label: _fyLabelFromFolderName(folderName),
          path: entity.path,
        ),
      );
    }

    final sorted = workspaces.values.toList()
      ..sort((a, b) => b.label.compareTo(a.label));
    return sorted;
  }

  String? _selectedWorkspacePath(
    List<_DetectedFinancialYearWorkspace> workspaces,
  ) {
    if (workspaces.isEmpty) {
      return null;
    }

    final selectedFinancialYearId = widget.selectedFinancialYearId;
    if (selectedFinancialYearId != null) {
      for (final workspace in workspaces) {
        if (workspace.financialYearId == selectedFinancialYearId) {
          return workspace.path;
        }
      }
    }

    final effectiveLabel = widget.effectiveFinancialYearLabel?.trim();
    if (effectiveLabel != null && effectiveLabel.isNotEmpty) {
      for (final workspace in workspaces) {
        if (workspace.label.trim() == effectiveLabel) {
          return workspace.path;
        }
      }
    }

    return null;
  }

  Future<List<_WorkspaceFolderPreview>> _loadFolderPreviews(
    String selectedPath,
  ) async {
    final previews = <_WorkspaceFolderPreview>[];

    for (final candidate in _folderCandidates) {
      for (final folderName in candidate.folderNames) {
        final folderPath = p.join(selectedPath, folderName);
        if (!await Directory(folderPath).exists()) {
          continue;
        }
        previews.add(
          _WorkspaceFolderPreview(
            label: candidate.label,
            path: folderPath,
            entries: await _loadDirectChildren(folderPath),
          ),
        );
        break;
      }
    }

    return previews;
  }

  Future<List<_WorkspaceFileEntry>> _loadDirectChildren(
    String folderPath,
  ) async {
    final entries = <_WorkspaceFileEntry>[];

    await for (final entity in Directory(
      folderPath,
    ).list(recursive: false, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.file) {
        continue;
      }
      entries.add(
        _WorkspaceFileEntry(
          name: p.basename(entity.path),
          path: entity.path,
          isDirectory: type == FileSystemEntityType.directory,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries.length > 12 ? entries.sublist(0, 12) : entries;
  }

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: AppColorScheme.border,
      title: const Text(
        'Workspace Files',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      trailing: IconButton(
        tooltip: 'Refresh',
        onPressed: isLoading ? null : _loadPreview,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: LinearProgressIndicator(),
      );
    }

    if (workspaceStatus != WorkspaceStatus.valid) {
      return _WorkspaceWarning(
        message: workspaceStatus == WorkspaceStatus.notConfigured
            ? 'Workspace root is not configured.'
            : 'Workspace root is missing or has moved.',
        onOpenSettings: widget.onOpenSettings,
      );
    }

    if (buyerWorkspacePath == null ||
        detectedWorkspaces.isEmpty ||
        selectedWorkspacePath == null) {
      return _missingWorkspaceState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (folderPreviews.isEmpty)
          const AppEmptyState(
            icon: Icons.folder_open_outlined,
            title: 'Workspace folder is empty',
            message: 'No expected LedgerMatch folders were found here.',
          )
        else
          for (final preview in folderPreviews) ...[
            _WorkspaceFolderPreviewCard(
              preview: preview,
              onOpenWorkspacePath: widget.onOpenWorkspacePath,
              onCopyWorkspacePath: widget.onCopyWorkspacePath,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }

  Widget _missingWorkspaceState() {
    final effectiveLabel = widget.effectiveFinancialYearLabel?.trim();
    final hasEffectiveFinancialYear =
        effectiveLabel != null && effectiveLabel.isNotEmpty;

    return AppEmptyState(
      icon: hasEffectiveFinancialYear
          ? Icons.folder_off_outlined
          : Icons.calendar_today_outlined,
      title: hasEffectiveFinancialYear
          ? 'No reconciliation workspace found for FY $effectiveLabel'
          : 'No FY selected',
      message: hasEffectiveFinancialYear
          ? 'Start reconciliation to create this financial-year workspace.'
          : 'Select or create an FY to preview workspace files.',
      action: AppPrimaryButton(
        label: 'Start Reconciliation',
        icon: Icons.play_arrow_rounded,
        onPressed: widget.onStartReconciliation,
      ),
    );
  }

  String _fyLabelFromFolderName(String folderName) {
    final cleaned = folderName.replaceFirst(RegExp(r'^FY[_\s-]*'), '');
    return cleaned.replaceAll('_', '-');
  }
}

class _WorkspaceWarning extends StatelessWidget {
  final String message;
  final VoidCallback onOpenSettings;

  const _WorkspaceWarning({
    required this.message,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColorScheme.warningSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColorScheme.warning),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColorScheme.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColorScheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppSecondaryButton(
            label: 'Settings',
            icon: Icons.settings_outlined,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceFolderPreviewCard extends StatelessWidget {
  final _WorkspaceFolderPreview preview;
  final ValueChanged<String> onOpenWorkspacePath;
  final ValueChanged<String> onCopyWorkspacePath;

  const _WorkspaceFolderPreviewCard({
    required this.preview,
    required this.onOpenWorkspacePath,
    required this.onCopyWorkspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColorScheme.divider),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.folder_outlined,
              color: AppColorScheme.textMuted,
            ),
            title: Text(
              preview.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(preview.path),
            trailing: _WorkspaceItemMenu(
              path: preview.path,
              isDirectory: true,
              onOpenWorkspacePath: onOpenWorkspacePath,
              onCopyWorkspacePath: onCopyWorkspacePath,
            ),
          ),
          if (preview.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Empty folder',
                  style: TextStyle(
                    color: AppColorScheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            for (final entry in preview.entries)
              _WorkspaceFileRow(
                entry: entry,
                onOpenWorkspacePath: onOpenWorkspacePath,
                onCopyWorkspacePath: onCopyWorkspacePath,
              ),
        ],
      ),
    );
  }
}

class _WorkspaceFileRow extends StatelessWidget {
  final _WorkspaceFileEntry entry;
  final ValueChanged<String> onOpenWorkspacePath;
  final ValueChanged<String> onCopyWorkspacePath;

  const _WorkspaceFileRow({
    required this.entry,
    required this.onOpenWorkspacePath,
    required this.onCopyWorkspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 8),
      leading: Icon(
        entry.isDirectory
            ? Icons.folder_outlined
            : Icons.insert_drive_file_outlined,
        size: 20,
        color: AppColorScheme.textMuted,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _WorkspaceItemMenu(
        path: entry.path,
        isDirectory: entry.isDirectory,
        onOpenWorkspacePath: onOpenWorkspacePath,
        onCopyWorkspacePath: onCopyWorkspacePath,
      ),
    );
  }
}

enum _WorkspaceItemAction { open, copyPath }

class _WorkspaceItemMenu extends StatelessWidget {
  final String path;
  final bool isDirectory;
  final ValueChanged<String> onOpenWorkspacePath;
  final ValueChanged<String> onCopyWorkspacePath;

  const _WorkspaceItemMenu({
    required this.path,
    required this.isDirectory,
    required this.onOpenWorkspacePath,
    required this.onCopyWorkspacePath,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_WorkspaceItemAction>(
      tooltip: 'Workspace item actions',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _WorkspaceItemAction.open:
            onOpenWorkspacePath(path);
          case _WorkspaceItemAction.copyPath:
            onCopyWorkspacePath(path);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _WorkspaceItemAction.open,
          child: Text(isDirectory ? 'Open Folder' : 'Open File'),
        ),
        const PopupMenuItem(
          value: _WorkspaceItemAction.copyPath,
          child: Text('Copy Path'),
        ),
      ],
    );
  }
}

class _WorkspaceFolderCandidate {
  final String label;
  final List<String> folderNames;

  const _WorkspaceFolderCandidate(this.label, this.folderNames);
}

class _DetectedFinancialYearWorkspace {
  final String label;
  final String path;
  final String? financialYearId;

  const _DetectedFinancialYearWorkspace({
    required this.label,
    required this.path,
    this.financialYearId,
  });
}

class _WorkspaceFolderPreview {
  final String label;
  final String path;
  final List<_WorkspaceFileEntry> entries;

  const _WorkspaceFolderPreview({
    required this.label,
    required this.path,
    required this.entries,
  });
}

class _WorkspaceFileEntry {
  final String name;
  final String path;
  final bool isDirectory;

  const _WorkspaceFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });
}
