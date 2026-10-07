import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/document/models/document_vocabulary.dart';
import '../../../domain/document/models/document_search.dart';
import '../cubits/documents_cubit.dart';

final class DocumentSearchControls extends StatelessWidget {
  const DocumentSearchControls({
    super.key,
    required this.term,
    required this.termFocus,
    required this.termError,
    required this.state,
    required this.filtersFocus,
    required this.onSubmit,
    required this.onFilters,
    required this.onClear,
    required this.onRemoveTag,
    required this.onClearAddress,
    required this.onKindsChanged,
    required this.onClearKinds,
    required this.onResetFilters,
    required this.onSort,
    required this.compactSort,
  });
  final TextEditingController term;
  final FocusNode termFocus;
  final String? termError;
  final DocumentsState state;
  final FocusNode filtersFocus;
  final VoidCallback onSubmit;
  final VoidCallback onFilters;
  final VoidCallback onClear;
  final Future<void> Function(String) onRemoveTag;
  final Future<void> Function(DocumentVocabularyField) onClearAddress;
  final Future<void> Function(Iterable<DocumentKind>) onKindsChanged;
  final Future<void> Function() onClearKinds;
  final Future<void> Function() onResetFilters;
  final Future<void> Function(DocumentSort) onSort;
  final bool compactSort;

  @override
  Widget build(BuildContext context) {
    final criteria = state.desiredCriteria;
    final filtersLabel = criteria.filterCount == 0
        ? 'Filters'
        : 'Filters (${criteria.filterCount})';
    final clear = state.desiredSearching || state.rawTerm.isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            double buttonWidth(String label) {
              final painter = TextPainter(
                text: TextSpan(
                  text: label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context),
              )..layout();
              final width = painter.width + 64;
              painter.dispose();
              return width;
            }

            final actionWidth =
                buttonWidth(filtersLabel) +
                buttonWidth('Search') +
                (clear ? buttonWidth('Clear search') : 0) +
                (clear ? 24 : 16);
            final wide =
                constraints.maxWidth >= 720 &&
                constraints.maxWidth - actionWidth >= 280;
            final fieldWidth = wide
                ? math.min(560.0, constraints.maxWidth - actionWidth)
                : math.min(560.0, constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: TextField(
                        key: const Key('documentSearchTerm'),
                        controller: term,
                        focusNode: termFocus,
                        onTapOutside: (_) => termFocus.unfocus(),
                        textInputAction: TextInputAction.search,
                        onEditingComplete: () {
                          final composing = term.value.composing;
                          if (!composing.isValid || composing.isCollapsed) {
                            termFocus.unfocus();
                          }
                        },
                        onSubmitted: (_) => onSubmit(),
                        decoration: InputDecoration(
                          labelText: 'Search documents',
                          prefixIcon: const Tooltip(
                            message:
                                'Search titles, metadata and extracted text',
                            child: Icon(Icons.search),
                          ),
                          suffixIcon: term.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search text',
                                  onPressed: term.clear,
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                    ),
                    if (wide)
                      OutlinedButton.icon(
                        key: const Key('documentFilters'),
                        focusNode: filtersFocus,
                        onPressed: onFilters,
                        icon: const Icon(Icons.tune),
                        label: Text(filtersLabel),
                      )
                    else
                      IconButton.filledTonal(
                        key: const Key('documentFilters'),
                        focusNode: filtersFocus,
                        tooltip: filtersLabel,
                        onPressed: onFilters,
                        icon: Badge(
                          isLabelVisible: criteria.filterCount > 0,
                          label: Text('${criteria.filterCount}'),
                          child: const Icon(Icons.tune),
                        ),
                      ),
                    TextFieldTapRegion(
                      child: wide
                          ? FilledButton.icon(
                              key: const Key('applyDocumentSearch'),
                              onPressed: onSubmit,
                              icon: const Icon(Icons.search),
                              label: const Text('Search'),
                            )
                          : IconButton.filled(
                              key: const Key('applyDocumentSearch'),
                              tooltip: 'Search',
                              onPressed: onSubmit,
                              icon: const Icon(Icons.search),
                            ),
                    ),
                    if (compactSort)
                      DocumentSortControl(
                        criteria: criteria,
                        onSort: onSort,
                        compact: true,
                      ),
                    if (clear)
                      if (wide)
                        TextButton(
                          key: const Key('clearDocumentSearch'),
                          onPressed: onClear,
                          child: const Text('Clear search'),
                        )
                      else
                        IconButton(
                          key: const Key('clearDocumentSearch'),
                          tooltip: 'Clear search',
                          onPressed: onClear,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        ),
                  ],
                ),
                if (termError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        termError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                DocumentKindFilters(
                  kinds: criteria.kinds,
                  onChanged: onKindsChanged,
                ),
                if (criteria.filterCount > 0) ...[
                  const SizedBox(height: 8),
                  DocumentActiveFilters(
                    criteria: criteria,
                    onRemoveTag: onRemoveTag,
                    onClearAddress: onClearAddress,
                    onClearKinds: onClearKinds,
                    onReset: onResetFilters,
                    resetLabel: 'Clear filters',
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

final class DocumentKindFilters extends StatelessWidget {
  const DocumentKindFilters({
    super.key,
    required this.kinds,
    required this.onChanged,
    this.keyPrefix = 'documentType',
  });

  final List<DocumentKind> kinds;
  final Future<void> Function(Iterable<DocumentKind>) onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          'Document type',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            key: Key('$keyPrefix-all'),
            label: const Text('All types'),
            selected: kinds.isEmpty,
            onSelected: (_) => unawaited(onChanged(const [])),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
          for (final kind in DocumentKind.values)
            FilterChip(
              key: Key('$keyPrefix-${kind.name}'),
              label: Text(kind.label),
              avatar: kinds.contains(kind)
                  ? null
                  : Icon(
                      switch (kind) {
                        DocumentKind.document => Icons.description_outlined,
                        DocumentKind.letter => Icons.markunread_mailbox_outlined,
                        DocumentKind.email => Icons.mail_outline,
                      },
                      size: 18,
                    ),
              selected: kinds.contains(kind),
              onSelected: (selected) => unawaited(
                onChanged([
                  ...kinds.where((value) => value != kind),
                  if (selected) kind,
                ]),
              ),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
    ],
  );
}

final class DocumentActiveFilters extends StatelessWidget {
  const DocumentActiveFilters({
    super.key,
    required this.criteria,
    required this.onRemoveTag,
    required this.onClearAddress,
    required this.onClearKinds,
    required this.onReset,
    this.resetLabel = 'Reset filters',
  });

  final DocumentSearchCriteria criteria;
  final Future<void> Function(String) onRemoveTag;
  final Future<void> Function(DocumentVocabularyField) onClearAddress;
  final Future<void> Function() onClearKinds;
  final Future<void> Function() onReset;
  final String resetLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Active filters',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: criteria.filterCount == 0
                ? null
                : () => unawaited(onReset()),
            child: Text(resetLabel),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (criteria.kinds.isNotEmpty)
            _DocumentFilterChip(
              label: 'Type: ${criteria.kinds.map((kind) => kind.label).join(', ')}',
              onRemove: () => unawaited(onClearKinds()),
            ),
          for (final tag in criteria.tags)
            _DocumentFilterChip(
              label: 'Tag: $tag',
              onRemove: () => unawaited(onRemoveTag(tag)),
            ),
          if (criteria.sender.isNotEmpty)
            _DocumentFilterChip(
              label:
                  '${criteria.senderMatch == DocumentAddressMatch.exact ? 'Sender' : 'Sender contains'}: ${criteria.sender}',
              onRemove: () => unawaited(
                onClearAddress(DocumentVocabularyField.sender),
              ),
            ),
          if (criteria.recipient.isNotEmpty)
            _DocumentFilterChip(
              label:
                  '${criteria.recipientMatch == DocumentAddressMatch.exact ? 'Recipient' : 'Recipient contains'}: ${criteria.recipient}',
              onRemove: () => unawaited(
                onClearAddress(DocumentVocabularyField.recipient),
              ),
            ),
        ],
      ),
    ],
  );
}

final class DocumentSortControl extends StatelessWidget {
  const DocumentSortControl({
    super.key,
    required this.criteria,
    required this.onSort,
    required this.compact,
  });
  final DocumentSearchCriteria criteria;
  final Future<void> Function(DocumentSort) onSort;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<DocumentSort>(
    key: const Key('sortDocuments'),
    tooltip: 'Sort documents: ${criteria.sort.label}',
    initialValue: criteria.sort,
    onSelected: (sort) => unawaited(onSort(sort)),
    itemBuilder: (_) => [
      for (final sort in DocumentSort.values)
        PopupMenuItem(
          value: sort,
          enabled: sort != DocumentSort.relevance || criteria.query.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sort.label),
                if (sort == DocumentSort.relevance && criteria.query.isEmpty)
                  const Text('Enter a search term to sort by relevance.'),
                if (sort == DocumentSort.dateNewest ||
                    sort == DocumentSort.dateOldest)
                  const Text('Documents without a date appear last.'),
              ],
            ),
          ),
        ),
    ],
    icon: compact ? const Icon(Icons.sort) : null,
    child: compact
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text('Sort: ${criteria.sort.label} ▾'),
          ),
  );
}

final class _DocumentFilterChip extends StatelessWidget {
  const _DocumentFilterChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove $label',
          onPressed: onRemove,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );
}
