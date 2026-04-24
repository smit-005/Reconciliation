import 'package:flutter/material.dart';

import 'package:reconciliation_app/core/theme/app_color_scheme.dart';
import 'package:reconciliation_app/core/theme/app_radius.dart';
import 'package:reconciliation_app/core/theme/app_spacing.dart';

class AppSearchAutocompleteField extends StatefulWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSelected;
  final String hintText;
  final String? labelText;
  final bool allowFreeText;
  final Iterable<String> Function(String option)? searchableTermsBuilder;
  final String? Function(String option)? optionSubtitleBuilder;
  final int maxVisibleOptions;
  final double optionsMaxHeight;
  final InputDecoration? decoration;

  const AppSearchAutocompleteField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.onSelected,
    this.hintText = 'Search',
    this.labelText,
    this.allowFreeText = true,
    this.searchableTermsBuilder,
    this.optionSubtitleBuilder,
    this.maxVisibleOptions = 10,
    this.optionsMaxHeight = 320,
    this.decoration,
  });

  @override
  State<AppSearchAutocompleteField> createState() =>
      _AppSearchAutocompleteFieldState();
}

class _AppSearchAutocompleteFieldState extends State<AppSearchAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppSearchAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focusNode.hasFocus) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus || widget.allowFreeText) {
      return;
    }

    final currentValue = _controller.text.trim();
    if (currentValue.isEmpty || widget.options.contains(currentValue)) {
      return;
    }

    final fallback = widget.value;
    _controller.value = TextEditingValue(
      text: fallback,
      selection: TextSelection.collapsed(offset: fallback.length),
    );
  }

  Iterable<String> _searchableTerms(String option) {
    final customTerms = widget.searchableTermsBuilder?.call(option);
    if (customTerms == null) {
      return <String>[option];
    }
    return customTerms.where((term) => term.trim().isNotEmpty);
  }

  Iterable<String> _buildOptions(TextEditingValue textEditingValue) {
    final query = textEditingValue.text.trim().toUpperCase();
    final candidates = query.isEmpty
        ? widget.options
        : widget.options.where((option) {
            return _searchableTerms(option).any(
              (term) => term.toUpperCase().contains(query),
            );
          });

    return candidates.take(widget.maxVisibleOptions);
  }

  InputDecoration _decoration() {
    return widget.decoration ??
        InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          isDense: true,
          labelStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColorScheme.textMuted,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColorScheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(
              color: AppColorScheme.primary,
              width: 1.2,
            ),
          ),
          filled: true,
          fillColor: const Color(0xFFFDFEFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 11,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option,
      optionsBuilder: _buildOptions,
      onSelected: (option) {
        widget.onChanged(option);
        widget.onSelected?.call(option);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (value) {
            widget.onChanged(value);
            setState(() {});
          },
          decoration: _decoration(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final optionList = options.toList();
        if (optionList.isEmpty) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: widget.optionsMaxHeight,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColorScheme.border),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: optionList.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColorScheme.divider),
                  itemBuilder: (context, index) {
                    final option = optionList[index];
                    final subtitle = widget.optionSubtitleBuilder?.call(option);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              option,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColorScheme.textPrimary,
                              ),
                            ),
                            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColorScheme.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
