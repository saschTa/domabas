import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_job_progress.dart';

import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';

final class GlacierSearchDialog extends StatefulWidget {
  const GlacierSearchDialog({
    super.key,
    required this.controller,
    required this.filters,
    required this.onApply,
    required this.onClear,
    this.onCancel,
    this.onChanged,
    this.summary = '',
    this.contextLabel = '',
    this.placeholder = 'Search documents…',
    this.showKeyboardHint = true,
    this.error,
    this.fieldKey,
    this.applyKey,
  });
  final TextEditingController controller;
  final Widget filters;
  final VoidCallback? onApply, onClear, onCancel;
  final ValueChanged<String>? onChanged;
  final String summary;
  final String contextLabel, placeholder;
  final bool showKeyboardHint;
  final String? error;
  final Key? fieldKey, applyKey;
  @override
  State<GlacierSearchDialog> createState() => _GlacierSearchDialogState();

  Widget _build(
    BuildContext context,
    GlobalKey bodyKey,
    GlobalKey filtersKey,
  ) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (controller.text.isNotEmpty || summary.isNotEmpty) {
          onClear?.call();
        } else {
          onCancel?.call();
        }
      },
      const SingleActivator(LogicalKeyboardKey.enter): () {
        if (!controller.value.composing.isValid ||
            controller.value.composing.isCollapsed) {
          onApply?.call();
        }
      },
    },
    child: Semantics(
      namesRoute: true,
      label: 'Search and filters',
      child: GlacierSurface(
        padding: EdgeInsets.zero,
        radius: 20,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 520 ||
                MediaQuery.textScalerOf(context).scale(14) > 22;
            return SingleChildScrollView(
              physics: compact ? null : const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: compact ? double.infinity : constraints.maxHeight,
                ),
                child: _body(context, !compact, bodyKey, filtersKey),
              ),
            );
          },
        ),
      ),
    ),
  );
  Widget _body(
    BuildContext context,
    bool bounded,
    GlobalKey bodyKey,
    GlobalKey filtersKey,
  ) => Column(
    key: bodyKey,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
        child: TextField(
          key: fieldKey,
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onEditingComplete: () {},
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w400,
            letterSpacing: -.48,
          ),
          decoration: InputDecoration(
            filled: false,
            hintText: placeholder,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.only(bottom: 16, top: 4),
          ),
          onChanged: onChanged,
          onSubmitted: (_) {
            if (!controller.value.composing.isValid ||
                controller.value.composing.isCollapsed) {
              onApply?.call();
            }
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: LayoutBuilder(
          builder: (context, width) {
            final clear = TextButton(
              onPressed: onClear,
              child: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Clear all'),
                  _SearchKeycap('Esc', color: GlacierTokens.of(context).muted),
                ],
              ),
            );
            final label = Text(
              contextLabel.isNotEmpty ? contextLabel : summary,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            );
            return width.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 22
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [label, clear],
                  )
                : Row(
                    children: [
                      Expanded(child: label),
                      clear,
                    ],
                  );
          },
        ),
      ),
      if (bounded)
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
            child: KeyedSubtree(key: filtersKey, child: filters),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
          child: KeyedSubtree(key: filtersKey, child: filters),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showKeyboardHint)
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Enter applies search and filters. Esc clears them; press again to close.',
                    style: TextStyle(
                      fontSize: 12,
                      color: GlacierTokens.of(context).muted,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(summary, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            if (showKeyboardHint) const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                GlacierButton(label: 'Cancel', onPressed: onCancel),
                FilledButton(
                  key: applyKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                  ),
                  onPressed: onApply,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Apply search'),
                      _SearchKeycap(
                        'Enter',
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

final class _GlacierSearchDialogState extends State<GlacierSearchDialog> {
  final _bodyKey = GlobalKey();
  final _filtersKey = GlobalKey();
  @override
  Widget build(BuildContext context) =>
      widget._build(context, _bodyKey, _filtersKey);
}

final class _SearchKeycap extends StatelessWidget {
  const _SearchKeycap(this.label, {required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: color,
      ),
    ),
  );
}

final class GlacierSearchFilterGroup extends StatelessWidget {
  const GlacierSearchFilterGroup({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.explanation,
    this.onMore,
  });
  final String label;
  final List<String> options, selected;
  final void Function(String, bool) onChanged;
  final String? explanation;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13),
        ),
        if (explanation != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              explanation!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (option) => GlacierChoice(
                  label: option,
                  compact: true,
                  selected: selected.contains(option),
                  onChanged: (value) => onChanged(option, value == true),
                ),
              )
              .toList(),
        ),
        if (onMore != null)
          TextButton(
            onPressed: onMore,
            child: const Text('More library values'),
          ),
      ],
    ),
  );
}

final class GlacierActiveFilters extends StatelessWidget {
  const GlacierActiveFilters({
    super.key,
    required this.filters,
    this.onRemove,
    this.onClear,
  });
  final List<String> filters;
  final ValueChanged<String>? onRemove;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final filter in filters)
        InputChip(
          label: Text(filter),
          onDeleted: onRemove == null ? null : () => onRemove!(filter),
          deleteButtonTooltipMessage: 'Remove $filter',
        ),
      if (filters.isNotEmpty)
        TextButton(onPressed: onClear, child: const Text('Clear all')),
    ],
  );
}

final class GlacierVocabularyPicker extends StatelessWidget {
  const GlacierVocabularyPicker({
    super.key,
    required this.label,
    required this.controller,
    required this.values,
    required this.pageLabel,
    this.selected,
    this.onSearch,
    this.onSelect,
    this.onPrevious,
    this.onNext,
    this.onFirst,
    this.feedback,
    this.loading = false,
  });
  final String label, pageLabel;
  final TextEditingController controller;
  final List<String> values;
  final String? selected;
  final ValueChanged<String>? onSearch, onSelect;
  final VoidCallback? onPrevious, onNext, onFirst;
  final Widget? feedback;
  final bool loading;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierField(
        label: 'Find $label',
        controller: controller,
        onChanged: onSearch,
      ),
      const SizedBox(height: 12),
      if (loading) const AppJobProgress(label: 'Loading library values'),
      ?feedback,
      if (values.isEmpty && !loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No matching library values. Try another search.'),
        ),
      RadioGroup<String>(
        groupValue: selected,
        onChanged: (value) {
          if (value != null) {
            onSelect?.call(value);
          }
        },
        child: Column(
          children: values
              .map(
                (value) => RadioListTile<String>(
                  title: Text(value),
                  value: value,
                  enabled: onSelect != null,
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GlacierButton(label: 'First', onPressed: loading ? null : onFirst),
          GlacierButton(
            label: 'Previous',
            onPressed: loading ? null : onPrevious,
          ),
          Text(pageLabel),
          GlacierButton(label: 'Next', onPressed: loading ? null : onNext),
        ],
      ),
    ],
  );
}
