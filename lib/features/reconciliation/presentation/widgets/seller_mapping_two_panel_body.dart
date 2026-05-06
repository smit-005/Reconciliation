import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_models.dart';
import 'package:reconciliation_app/features/reconciliation/presentation/widgets/seller_mapping_theme.dart';

typedef SellerMappingRowValueGetter = Object? Function(SellerMappingRowVm row);
typedef SellerMappingRowStringGetter = Object? Function(SellerMappingRowVm row);
typedef SellerMappingRowBoolGetter = Object? Function(SellerMappingRowVm row);
typedef SellerMappingRowListGetter = Object? Function(SellerMappingRowVm row);
typedef SellerMappingRowAction = void Function(SellerMappingRowVm row);
typedef SellerMappingTdsLinkAction =
    void Function(SellerMappingRowVm row, String? tdsParty);
typedef SellerMappingLedgerLinkAction =
    void Function(SellerMappingRowVm row, SellerMappingRowVm ledgerRow);

class SellerMappingTwoPanelBody extends StatefulWidget {
  final List<SellerMappingRowVm> visibleRows;
  final List<SellerMappingRowVm> ledgerCandidateRows;
  final String searchQuery;
  final bool showAllSellersMode;
  final List<String> tdsParties;
  final Map<String, List<String>> tdsPartyPans;
  final SellerMappingRowValueGetter selectedValueForRow;
  final SellerMappingRowStringGetter selectedPanForRow;
  final SellerMappingRowStringGetter statusForRow;
  final SellerMappingRowListGetter helperMessagesForRow;
  final SellerMappingRowBoolGetter canAcceptSuggestion;
  final SellerMappingRowAction onAcceptSuggestion;
  final SellerMappingTdsLinkAction onLinkToTds;
  final SellerMappingLedgerLinkAction onLinkToLedgerRow;
  final SellerMappingRowAction onKeepSeparate;
  final SellerMappingRowAction onClear;
  final SellerMappingRowAction onMarkTimingDifference;
  final SellerMappingRowAction onMarkMissingInBooks;

  const SellerMappingTwoPanelBody({
    super.key,
    required this.visibleRows,
    required this.ledgerCandidateRows,
    this.searchQuery = '',
    this.showAllSellersMode = false,
    required this.tdsParties,
    required this.tdsPartyPans,
    required this.selectedValueForRow,
    required this.selectedPanForRow,
    required this.statusForRow,
    required this.helperMessagesForRow,
    required this.canAcceptSuggestion,
    required this.onAcceptSuggestion,
    required this.onLinkToTds,
    required this.onLinkToLedgerRow,
    required this.onKeepSeparate,
    required this.onClear,
    required this.onMarkTimingDifference,
    required this.onMarkMissingInBooks,
  });

  @override
  State<SellerMappingTwoPanelBody> createState() =>
      _SellerMappingTwoPanelBodyState();
}

class _SellerMappingTwoPanelBodyState extends State<SellerMappingTwoPanelBody> {
  String? _selectedLeftKey;
  SellerMappingRowVm? _selectedLeftRowSnapshot;
  String? _selectedLedgerRowKey;
  String? _lastMissingSelectedRowLogKey;

  List<SellerMappingRowVm> get _leftReviewRows {
    // The parent screen already decides which rows belong in the current
    // list view. Do not filter this again by is26QUnmatched here.
    // A normal mapped 26Q audit row becomes pending immediately after Clear,
    // but it may not have is26QUnmatched=true. Filtering it here made the
    // row appear in Review View as Unmapped while staying hidden in Working
    // View / Needs Action.
    return widget.visibleRows;
  }

  List<SellerMappingRowVm> get _filteredLeftRows {
    final rows = _leftReviewRows;
    final query = _normalize(widget.searchQuery);
    if (query.isEmpty) return rows;
    return rows
        .where((row) => _rowMatchesSearch(row, query))
        .toList(growable: false);
  }

  String get _activeSearchQuery {
    return sellerMappingSafeText(widget.searchQuery);
  }

  bool get _hasLedgerForSection => widget.ledgerCandidateRows.isNotEmpty;

  @override
  void didUpdateWidget(covariant SellerMappingTwoPanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedRow = _selectedLeftRowFrom(widget.visibleRows);
    if (selectedRow == null) return;

    final oldSelectedRow = _selectedLeftRowFrom(oldWidget.visibleRows);
    final selectedRowChanged = oldSelectedRow?.rowKey != selectedRow.rowKey;
    if (selectedRowChanged) {
      _selectedLedgerRowKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredLeftRows = _filteredLeftRows;
    final selectedRow = _selectedLeftRowFrom(widget.visibleRows);
    final rightPanelKey = ValueKey<String?>(
      selectedRow == null ? null : 'right-panel:${selectedRow.rowKey}',
    );

    return Container(
      decoration: BoxDecoration(
        color: SellerMappingTheme.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SellerMappingTheme.borderColor),
      ),
      child: _leftReviewRows.isEmpty
          ? _buildEmptyState()
          : Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _SellerPanel(
                            title: 'Review Sellers',
                            subtitle: widget.showAllSellersMode
                                ? 'Inspect all visible sellers for this section.'
                                : 'Select the seller that needs mapping or exception review.',
                            child: _buildLeftList(
                              filteredLeftRows,
                              selectedRow,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 220,
                          child: _buildActionColumn(selectedRow),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 5,
                          child: _SellerPanel(
                            title: 'Matching Candidates',
                            subtitle: widget.showAllSellersMode
                                ? 'All section ledger sellers are visible; related sellers are shown first.'
                                : selectedRow == null
                                ? 'Select a 26Q seller to see ledger candidates.'
                                : 'Same-section ledger candidates for the selected 26Q seller.',
                            child: KeyedSubtree(
                              key: rightPanelKey,
                              child: _buildRightList(selectedRow),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: SellerMappingTheme.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.manage_search_rounded,
                size: 34,
                color: SellerMappingTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No 26Q sellers match the current filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: SellerMappingTheme.titleTextColor,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try changing the view, search, or status filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: SellerMappingTheme.mutedTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftList(
    List<SellerMappingRowVm> rows,
    SellerMappingRowVm? selectedRow,
  ) {
    if (rows.isEmpty) {
      return const _PanelEmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No review sellers found',
        message: 'Try another search term or filter.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        final selected = row.rowKey == selectedRow?.rowKey;
        final status = _safeStatusForRow(row);
        final selectedValue = _safeSelectedValueForRow(row);
        final leftTitle = resolveTdsSellerTitle(row);
        return _SellerCard(
          selected: selected,
          highlighted: false,
          title: leftTitle,
          badge: _friendlyStatusLabel(row, status),
          badgeColor: _statusColor(row, status),
          details: [
            'Section ${row.sectionCode}',
            if (row.tdsPan.isNotEmpty) '26Q PAN ${row.tdsPan}',
            if (row.tdsPan.isEmpty) '26Q PAN not available',
            '26Q rows ${row.tdsRowCount}',
            if (selectedValue != null && selectedValue.trim().isNotEmpty)
              row.is26QUnmatched
                  ? 'Linked ledger selected'
                  : 'Mapped ledger selected',
          ],
          onTap: () {
            setState(() {
              _selectedLeftKey = row.rowKey;
              _selectedLeftRowSnapshot = row;
              _selectedLedgerRowKey = null;
            });
          },
        );
      },
    );
  }

  Widget _buildRightList(SellerMappingRowVm? row) {
    if (!_hasLedgerForSection) {
      return const _PanelEmptyHint(
        icon: Icons.upload_file_outlined,
        title: 'No ledger uploaded for this section',
        message:
            'Upload source ledger data for this section, or review each 26Q seller as an exception.',
      );
    }

    if (widget.showAllSellersMode) {
      return _buildAllSellerLedgerList(row);
    }

    if (row == null) {
      if (_activeSearchQuery.trim().isNotEmpty) {
        return _buildSearchOnlyLedgerCandidateList();
      }
      return const _PanelEmptyHint(
        icon: Icons.touch_app_rounded,
        title: 'Select a 26Q seller',
        message:
            'Search can narrow the left list; select a 26Q seller to see same-section ledger candidates.',
      );
    }

    return _buildLedgerCandidateList(row);
  }

  Widget _buildAllSellerLedgerList(SellerMappingRowVm? selectedRow) {
    final candidates = _allSellerLedgerRows(selectedRow);

    if (candidates.isEmpty) {
      return const _PanelEmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No section sellers found',
        message: 'Try clearing search or changing the status filter.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: candidates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ledgerCandidateCard(selectedRow, candidates[index]),
    );
  }

  // ignore: unused_element
  Widget _buildSearchOnlyLedgerCandidateList() {
    final query = _normalize(_activeSearchQuery);
    final ledgerMatches = widget.ledgerCandidateRows
        .where((row) => _rowMatchesSearch(row, query))
        .take(30)
        .toList(growable: false);

    if (ledgerMatches.isEmpty) {
      return const _PanelEmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No ledger candidates found',
        message:
            'Try searching another ledger seller name, PAN, GST, or section.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: ledgerMatches.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ledgerCandidateCard(null, ledgerMatches[index]),
    );
  }

  Widget _buildLedgerCandidateList(SellerMappingRowVm row) {
    final candidates = _contextualLedgerRows(row);

    if (candidates.isEmpty) {
      return const _PanelEmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No ledger candidates found',
        message: 'Use search or mark this 26Q seller as Missing in Books.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: candidates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ledgerCandidateCard(row, candidates[index]),
    );
  }

  Widget _ledgerCandidateCard(
    SellerMappingRowVm? row,
    SellerMappingRowVm candidate,
  ) {
    final selectedRowUnmapped = row != null && _rowIsCurrentlyUnmapped(row);
    final similarityScore = row != null && row.is26QUnmatched
        ? _ledgerSimilarityScore(
            resolveTdsSellerTitle(row),
            resolveLedgerSellerTitle(candidate),
          )
        : 0.0;
    final selectedRowMapped =
        row != null && !selectedRowUnmapped && _rowHasMapping(row);
    final showMappedState =
        row != null &&
        selectedRowMapped &&
        _isMappedLedgerCandidate(row, candidate);
    final mappedElsewhere =
        row != null &&
        !selectedRowUnmapped &&
        !selectedRowMapped &&
        row.rowKey != candidate.rowKey &&
        _rowHasMapping(candidate);
    final explicitlySelected =
        row != null && candidate.rowKey == _selectedLedgerRowKey;
    final selected =
        explicitlySelected ||
        showMappedState ||
        (!selectedRowUnmapped && row == candidate);
    final possibleNameMatch =
        row != null &&
        !showMappedState &&
        !mappedElsewhere &&
        _looksRelated(
          resolveTdsSellerTitle(row),
          resolveLedgerSellerTitle(candidate),
        );
    final strongNameMatch =
        row != null &&
        row.is26QUnmatched &&
        !showMappedState &&
        !mappedElsewhere &&
        similarityScore > 0.75;
    final fuzzyPossibleMatch =
        row != null &&
        row.is26QUnmatched &&
        !showMappedState &&
        !mappedElsewhere &&
        similarityScore > 0.5;
    final applyMatchStyling = row != null;
    final badge = showMappedState
        ? 'Mapped'
        : mappedElsewhere
        ? 'Already Mapped Elsewhere'
        : applyMatchStyling && strongNameMatch
        ? 'Strong Match'
        : applyMatchStyling && (fuzzyPossibleMatch || possibleNameMatch)
        ? 'Possible Match'
        : 'Ledger Seller';
    final badgeColor = showMappedState
        ? SellerMappingTheme.successColor
        : mappedElsewhere
        ? SellerMappingTheme.warningColor
        : applyMatchStyling &&
              (strongNameMatch || fuzzyPossibleMatch || possibleNameMatch)
        ? SellerMappingTheme.primaryColor
        : SellerMappingTheme.mutedTextColor;

    return _SellerCard(
      selected: selected,
      highlighted: false,
      title: resolveLedgerSellerTitle(candidate),
      badge: badge,
      badgeColor: badgeColor,
      details: [
        'Section ${candidate.sectionCode}',
        if (candidate.purchasePan.isNotEmpty)
          'Ledger PAN ${candidate.purchasePan}',
        if (candidate.purchasePan.isEmpty) 'Ledger PAN not available',
        if (candidate.ledgerPanVariantsCount > 1)
          'Multiple PANs: ${candidate.ledgerPanVariantsCount}',
        if (candidate.purchaseGstNo.isNotEmpty)
          'GST ${candidate.purchaseGstNo}',
        'Ledger rows ${candidate.sourceRowCount}',
        if (showMappedState) 'Already linked',
        if (mappedElsewhere) 'Already mapped elsewhere',
      ],
      onTap: () {
        setState(() {
          if (row != null && !_hasSavedFinalDecision(row)) {
            _selectedLedgerRowKey = candidate.rowKey;
          }
        });
      },
    );
  }

  Widget _buildActionColumn(SellerMappingRowVm? row) {
    if (row == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SellerMappingTheme.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: SellerMappingTheme.titleTextColor,
              ),
            ),
            SizedBox(height: 10),
            FilledButton.icon(
              onPressed: null,
              icon: Icon(Icons.link_rounded, size: 18),
              label: Text('Link Seller'),
            ),
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('Accept Suggestion'),
            ),
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.call_split_rounded, size: 18),
              label: Text('Keep Separate'),
            ),
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: Icon(Icons.close_rounded, size: 18),
              label: Text('Clear'),
            ),
            Spacer(),
            Text(
              'Select a seller to enable actions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: SellerMappingTheme.mutedTextColor,
              ),
            ),
          ],
        ),
      );
    }

    final helperMessages = _safeHelperMessagesForRow(row);
    final selectedLedger = _selectedLedgerFor(row);
    final hasSavedDecision = _hasSavedFinalDecision(row);
    final noLedgerForSection = !_hasLedgerForSection;
    final hasPendingCandidate = selectedLedger != null;
    final canLink =
        !hasSavedDecision && !noLedgerForSection && hasPendingCandidate;
    final VoidCallback? linkSellerAction = canLink
        ? () {
            widget.onLinkToLedgerRow(row, selectedLedger);
            setState(() {
              _selectedLeftKey = row.rowKey;
            });
          }
        : null;
    final canAcceptSuggestion =
        !hasSavedDecision &&
        !noLedgerForSection &&
        _safeCanAcceptSuggestion(row);
    final canKeepSeparate =
        !hasSavedDecision && (!row.is26QUnmatched || noLedgerForSection);
    final selectedValue = _safeSelectedValueForRow(row)?.trim() ?? '';
    final status = _safeStatusForRow(row);
    final canShowExceptionActions =
        row.is26QUnmatched ||
        (selectedValue.isEmpty &&
            (status == 'Unmapped' || status == '26Q Unmatched'));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SellerMappingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Actions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: SellerMappingTheme.titleTextColor,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: linkSellerAction,
            icon: Icon(
              hasSavedDecision
                  ? Icons.check_circle_rounded
                  : Icons.link_rounded,
              size: 18,
            ),
            label: Text(hasSavedDecision ? 'Mapped / Linked' : 'Link Seller'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: canAcceptSuggestion
                ? () => widget.onAcceptSuggestion(row)
                : null,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Accept Suggestion'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: canKeepSeparate
                ? () {
                    widget.onKeepSeparate(row);
                    setState(_clearRightPanelSelection);
                  }
                : null,
            icon: const Icon(Icons.call_split_rounded, size: 18),
            label: const Text('Keep Separate'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              widget.onClear(row);
              setState(_clearRightPanelSelection);
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Clear'),
          ),
          if (canShowExceptionActions) ...[
            const Divider(height: 24),
            OutlinedButton.icon(
              onPressed: () => widget.onMarkTimingDifference(row),
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('Timing Difference'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onMarkMissingInBooks(row),
              icon: const Icon(Icons.bookmark_remove_rounded, size: 18),
              label: const Text('Missing in Books'),
            ),
          ],
          const Spacer(),
          if (helperMessages.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SellerMappingTheme.borderColor),
              ),
              child: Text(
                helperMessages.join(' '),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: SellerMappingTheme.mutedTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<SellerMappingRowVm> _allSellerLedgerRows(
    SellerMappingRowVm? selectedRow,
  ) {
    final query = _normalize(_activeSearchQuery);
    final ordered = <SellerMappingRowVm>[];

    void addCandidate(SellerMappingRowVm candidate) {
      if (ordered.any((item) => item.rowKey == candidate.rowKey)) return;
      if (query.isNotEmpty && !_rowMatchesSearch(candidate, query)) return;
      ordered.add(candidate);
    }

    if (selectedRow != null) {
      if (_rowHasMapping(selectedRow)) {
        final mappedRows = _mappedLedgerRowsFor(selectedRow);
        if (mappedRows.isNotEmpty) {
          for (final candidate in mappedRows) {
            addCandidate(candidate);
          }
          return ordered;
        }
        if (!selectedRow.is26QUnmatched) {
          addCandidate(selectedRow);
          return ordered;
        }
      }

      for (final candidate in _contextualLedgerRows(selectedRow)) {
        addCandidate(candidate);
      }

      for (final candidate in widget.ledgerCandidateRows) {
        if (candidate.sectionCode == selectedRow.sectionCode &&
            _looksRelated(
              resolveTdsSellerTitle(selectedRow),
              resolveLedgerSellerTitle(candidate),
            )) {
          addCandidate(candidate);
        }
      }
    }

    final mappedFirst = widget.ledgerCandidateRows
        .where(_rowHasMapping)
        .toList(growable: false);
    final rest = widget.ledgerCandidateRows
        .where((row) => !_rowHasMapping(row))
        .toList(growable: false);

    for (final candidate in mappedFirst) {
      addCandidate(candidate);
    }
    for (final candidate in rest) {
      addCandidate(candidate);
    }

    return ordered;
  }

  List<SellerMappingRowVm> _contextualLedgerRows(SellerMappingRowVm row) {
    final query = _normalize(_activeSearchQuery);
    final selectedValue = _safeSelectedValueForRow(row)?.trim() ?? '';
    final suggestion = _safeResolvedSuggestionName(row);
    final selected26QName = _normalize(resolveTdsSellerTitle(row));
    final candidates = widget.ledgerCandidateRows
        .where(
          (candidate) =>
              candidate.sectionCode == row.sectionCode &&
              candidate.sourceRowCount > 0,
        )
        .toList(growable: false);
    final ordered = <SellerMappingRowVm>[];

    void addCandidate(SellerMappingRowVm candidate) {
      if (ordered.any((item) => item.rowKey == candidate.rowKey)) return;
      ordered.add(candidate);
    }

    // If this 26Q seller already has a linked ledger row, show only that
    // mapped ledger seller on the right. This keeps mapped 26Q review focused.
    if (selectedValue.isNotEmpty) {
      for (final candidate in candidates) {
        if (selectedValue.contains(candidate.rowKey)) {
          addCandidate(candidate);
        }
      }
      if (ordered.isNotEmpty) return ordered;
    }

    // Also support the normal ledger -> 26Q mapping case only while the
    // selected left row is still mapped. After Clear, parent state can rebuild
    // the left row as Unmapped while ledgerCandidateRows may still contain the
    // previous candidate snapshot. Without this guard, the right panel keeps
    // showing the old candidate as Mapped.
    if (_rowHasMapping(row)) {
      for (final candidate in candidates) {
        final candidateMappedParty =
            _safeSelectedValueForRow(candidate)?.trim() ?? '';
        if (candidateMappedParty.isEmpty) continue;
        if (_normalize(candidateMappedParty) == selected26QName) {
          addCandidate(candidate);
        }
      }
      if (ordered.isNotEmpty) return ordered;
    }

    // Show the explicit suggestion first when it matches a ledger seller name.
    if (suggestion.isNotEmpty) {
      final normalizedSuggestion = _normalize(suggestion);
      for (final candidate in candidates) {
        if (_normalize(resolveLedgerSellerTitle(candidate)) ==
            normalizedSuggestion) {
          addCandidate(candidate);
        }
      }
    }

    final remainingCandidates =
        candidates
            .where(
              (candidate) =>
                  !ordered.any((item) => item.rowKey == candidate.rowKey) &&
                  (query.isEmpty || _rowMatchesSearch(candidate, query)),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final aRelated = _looksRelated(
              resolveTdsSellerTitle(row),
              resolveLedgerSellerTitle(a),
            );
            final bRelated = _looksRelated(
              resolveTdsSellerTitle(row),
              resolveLedgerSellerTitle(b),
            );
            if (aRelated != bRelated) {
              return bRelated ? 1 : -1;
            }

            final byScore =
                _ledgerSimilarityScore(
                  resolveTdsSellerTitle(row),
                  resolveLedgerSellerTitle(b),
                ).compareTo(
                  _ledgerSimilarityScore(
                    resolveTdsSellerTitle(row),
                    resolveLedgerSellerTitle(a),
                  ),
                );
            if (byScore != 0) return byScore;

            final byLedgerRows = b.sourceRowCount.compareTo(a.sourceRowCount);
            if (byLedgerRows != 0) return byLedgerRows;

            return resolveLedgerSellerTitle(
              a,
            ).compareTo(resolveLedgerSellerTitle(b));
          });

    for (final candidate in remainingCandidates) {
      addCandidate(candidate);
      if (ordered.length >= 40) break;
    }

    return ordered;
  }

  SellerMappingRowVm? _selectedLedgerFor(SellerMappingRowVm row) {
    if (_selectedLedgerRowKey == null) return null;
    for (final candidate in widget.ledgerCandidateRows) {
      if (candidate.rowKey == _selectedLedgerRowKey &&
          candidate.sectionCode == row.sectionCode) {
        return candidate;
      }
    }
    return null;
  }

  bool _rowHasMapping(SellerMappingRowVm row) {
    final status = _safeStatusForRow(row).toLowerCase();
    return status.contains('mapped') ||
        status.contains('accepted') ||
        status.contains('linked');
  }

  bool _hasSavedFinalDecision(SellerMappingRowVm row) {
    final status = _safeStatusForRow(row);
    return status == 'Mapped' ||
        status == 'Linked to Ledger' ||
        status == 'Mapped (PAN missing)' ||
        status == 'Timing Difference' ||
        status == 'Missing in Books' ||
        status == 'Marked Separate';
  }

  bool _rowIsCurrentlyUnmapped(SellerMappingRowVm row) {
    return _safeStatusForRow(row) == 'Unmapped';
  }

  List<SellerMappingRowVm> _mappedLedgerRowsFor(SellerMappingRowVm row) {
    if (!_rowHasMapping(row)) {
      return const <SellerMappingRowVm>[];
    }

    if (!row.is26QUnmatched) {
      return <SellerMappingRowVm>[row];
    }

    final selectedValue = _safeSelectedValueForRow(row)?.trim() ?? '';
    final rowName = _normalize(resolveTdsSellerTitle(row));
    final mappedRows = <SellerMappingRowVm>[];

    void addMapped(SellerMappingRowVm candidate) {
      if (mappedRows.any((item) => item.rowKey == candidate.rowKey)) return;
      mappedRows.add(candidate);
    }

    for (final candidate in widget.ledgerCandidateRows) {
      if (candidate.sectionCode != row.sectionCode) continue;
      if (selectedValue.isNotEmpty &&
          selectedValue.contains(candidate.rowKey)) {
        addMapped(candidate);
        continue;
      }
      final candidateMappedParty =
          _safeSelectedValueForRow(candidate)?.trim() ?? '';
      if (candidateMappedParty.isNotEmpty &&
          _normalize(candidateMappedParty) == rowName) {
        addMapped(candidate);
      }
    }

    return mappedRows;
  }

  bool _isMappedLedgerCandidate(
    SellerMappingRowVm row,
    SellerMappingRowVm candidate,
  ) {
    if (row.rowKey == candidate.rowKey) return _rowHasMapping(row);
    return _mappedLedgerRowsFor(
      row,
    ).any((item) => item.rowKey == candidate.rowKey);
  }

  SellerMappingRowVm? _selectedLeftRowFrom(List<SellerMappingRowVm> rows) {
    final selectedLeftKey = _selectedLeftKey;
    if (selectedLeftKey == null) return null;
    for (final row in rows) {
      if (row.rowKey == selectedLeftKey) {
        _selectedLeftRowSnapshot = row;
        _lastMissingSelectedRowLogKey = null;
        return row;
      }
    }
    final snapshot = _selectedLeftRowSnapshot;
    if (snapshot?.rowKey == selectedLeftKey) {
      return snapshot;
    }
    if (_lastMissingSelectedRowLogKey != selectedLeftKey) {
      _lastMissingSelectedRowLogKey = selectedLeftKey;
      debugPrint(
        'SELLER UI WARN => selected row not found after filtering '
        'rowKey=$selectedLeftKey',
      );
    }
    return null;
  }

  void _clearRightPanelSelection() {
    _selectedLedgerRowKey = null;
  }

  // ignore: unused_element
  void _clearLocalSelection() {
    _selectedLeftKey = null;
    _selectedLeftRowSnapshot = null;
    _clearRightPanelSelection();
  }

  bool _rowMatchesSearch(SellerMappingRowVm row, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final selected = _safeSelectedValueForRow(row) ?? '';
    final suggestion = _safeResolvedSuggestionName(row);
    final status = _safeStatusForRow(row);
    final haystack = _normalize(
      [
        resolveTdsSellerTitle(row),
        row.purchasePan,
        row.purchaseGstNo,
        row.sectionCode,
        selected,
        suggestion,
        status,
      ].join(' '),
    );
    return haystack.contains(normalizedQuery);
  }

  bool _looksRelated(Object? left, Object? right) {
    final leftNorm = _normalize(left);
    final rightNorm = _normalize(right);
    if (leftNorm.isEmpty || rightNorm.isEmpty) return false;
    if (leftNorm.contains(rightNorm) || rightNorm.contains(leftNorm)) {
      return true;
    }

    final leftTokens = _importantTokens(leftNorm);
    final rightTokens = _importantTokens(rightNorm);
    if (leftTokens.isEmpty || rightTokens.isEmpty) return false;

    var shared = 0;
    for (final token in leftTokens) {
      if (rightTokens.contains(token)) shared++;
    }
    return shared >= 2 || (shared == 1 && leftTokens.length == 1);
  }

  double _ledgerSimilarityScore(Object? a, Object? b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0.0;

    final tokensA = _importantTokens(na);
    final tokensB = _importantTokens(nb);

    final overlap = tokensA.intersection(tokensB).length.toDouble();
    final maxTokens = (tokensA.length + tokensB.length).clamp(1, 100);
    final tokenScore = overlap / maxTokens;

    final editScore = _levenshteinSimilarity(na, nb);

    return (tokenScore * 0.6) + (editScore * 0.4);
  }

  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }

    final maxLength = math.max(m, n);
    return maxLength == 0 ? 1.0 : 1.0 - (dp[m][n] / maxLength);
  }

  Set<String> _importantTokens(String value) {
    const stopWords = {
      'and',
      'the',
      'ltd',
      'limited',
      'pvt',
      'private',
      'co',
      'company',
      'corp',
      'corporation',
      'llp',
      'inc',
      'india',
    };
    return value
        .split(' ')
        .where((token) => token.length >= 3 && !stopWords.contains(token))
        .toSet();
  }

  String _normalize(Object? value) {
    return _safeString(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _safeString(Object? value) {
    return sellerMappingSafeText(value);
  }

  String _safeStatusForRow(SellerMappingRowVm row) {
    final dynamic getter = widget.statusForRow;
    return _safeString(getter(row));
  }

  String? _safeSelectedValueForRow(SellerMappingRowVm row) {
    final dynamic getter = widget.selectedValueForRow;
    final result = getter(row);
    if (result == null) {
      return null;
    }
    return result is String ? result : '$result';
  }

  String _safeResolvedSuggestionName(SellerMappingRowVm? row) {
    if (row == null) {
      return '';
    }
    return sellerMappingSafeText(row.resolvedSuggestion?.mappedName);
  }

  List<String> _safeHelperMessagesForRow(SellerMappingRowVm row) {
    final dynamic getter = widget.helperMessagesForRow;
    final result = getter(row);
    if (result is Iterable) {
      return result
          .map(sellerMappingSafeText)
          .where((message) => message.isNotEmpty)
          .toList(growable: false);
    }
    final message = sellerMappingSafeText(result);
    return message.isEmpty ? const <String>[] : <String>[message];
  }

  bool _safeCanAcceptSuggestion(SellerMappingRowVm row) {
    final dynamic getter = widget.canAcceptSuggestion;
    return getter(row) == true;
  }

  String _friendlyStatusLabel(SellerMappingRowVm row, Object? value) {
    final status = sellerMappingSafeText(value);
    if (row.is26QUnmatched && status == '26Q Unmatched') return 'Only in 26Q';
    if (status == 'No 26Q') return 'Only in Ledger';
    if (status == 'Review') return 'Needs Action';
    return status.isEmpty ? 'Unmapped' : status;
  }

  Color _statusColor(SellerMappingRowVm row, String status) {
    if (status.contains('Conflict') || status.contains('Unresolved')) {
      return SellerMappingTheme.dangerColor;
    }
    if (status.contains('Mapped') || status.contains('Accepted')) {
      return SellerMappingTheme.successColor;
    }
    if (status.contains('Linked')) {
      return SellerMappingTheme.successColor;
    }
    if (row.is26QUnmatched) return SellerMappingTheme.warningColor;
    if (status == 'No 26Q' || status == 'Review') {
      return SellerMappingTheme.warningColor;
    }
    return SellerMappingTheme.primaryColor;
  }
}

class _SellerPanel extends StatelessWidget {
  final Object? title;
  final Object? subtitle;
  final Widget child;

  const _SellerPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SellerMappingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sellerMappingSafeText(title),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: SellerMappingTheme.titleTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sellerMappingSafeText(subtitle),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: SellerMappingTheme.mutedTextColor,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: SellerMappingTheme.borderColor),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PanelEmptyHint extends StatelessWidget {
  final IconData icon;
  final Object? title;
  final Object? message;

  const _PanelEmptyHint({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: SellerMappingTheme.mutedTextColor),
            const SizedBox(height: 12),
            Text(
              sellerMappingSafeText(title),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: SellerMappingTheme.titleTextColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sellerMappingSafeText(message),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: SellerMappingTheme.mutedTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  final bool selected;
  final bool highlighted;
  final Object? title;
  final Object? badge;
  final Color badgeColor;
  final List<String> details;
  final VoidCallback onTap;

  const _SellerCard({
    required this.selected,
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.details,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final safeTitle = sellerMappingSafeText(title);
    final safeBadge = sellerMappingSafeText(badge);
    final borderColor = selected
        ? SellerMappingTheme.primaryColor
        : highlighted
        ? SellerMappingTheme.warningColor
        : SellerMappingTheme.borderColor;
    final bgColor = selected
        ? SellerMappingTheme.primarySoft
        : highlighted
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFF8FAFC);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: selected || highlighted ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      safeTitle.isEmpty ? 'Unnamed seller' : safeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: SellerMappingTheme.titleTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      safeBadge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: details
                    .where((detail) => sellerMappingSafeText(detail).isNotEmpty)
                    .map(
                      (detail) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: SellerMappingTheme.borderColor,
                          ),
                        ),
                        child: Text(
                          sellerMappingSafeText(detail),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: SellerMappingTheme.mutedTextColor,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
