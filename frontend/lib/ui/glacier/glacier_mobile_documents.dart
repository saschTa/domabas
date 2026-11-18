import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glacier_controls.dart';
import 'glacier_documents.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';
import 'glacier_preview_placeholder.dart';

enum GlacierMobileCollectionState {
  ready,
  loading,
  empty,
  noMatch,
  error,
  stale,
  pageError,
  readOnly,
}

class GlacierMobileDocumentFilters extends StatelessWidget {
  const GlacierMobileDocumentFilters({
    super.key,
    this.selected = 'All',
    required this.onChanged,
  });
  final String selected;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in const ['All', 'PDF', 'Images', 'Email'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: selected == option,
                child: OutlinedButton(
                  onPressed: () => onChanged(option),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    backgroundColor: selected == option
                        ? GlacierTokens.of(context).selectedNavigation
                        : GlacierTokens.of(context).glass,
                    foregroundColor: selected == option
                        ? GlacierTokens.of(context).onSelectedNavigation
                        : Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(
                      color: selected == option
                          ? Colors.transparent
                          : GlacierTokens.of(context).border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    option,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class GlacierMobileDocumentCard extends StatelessWidget {
  const GlacierMobileDocumentCard({
    super.key,
    required this.document,
    required this.preview,
    this.previewHeight = 157,
    this.onOpen,
    this.onRetry,
    this.onRetryPreview,
    this.selected,
    this.onSelectionChanged,
    this.focusNode,
    this.semanticLabel,
    this.titleLines = 1,
  });

  final FocusNode? focusNode;
  final String? semanticLabel;
  final int titleLines;
  final GlacierDocumentValue document;
  final Widget preview;
  final double previewHeight;
  final VoidCallback? onOpen, onRetry, onRetryPreview;
  final bool? selected;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return GlacierMobileSurface(
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Semantics(
            button: true,
            value: [
              document.sender,
              document.date,
              document.tags.join(', '),
              document.status,
              document.snippet ?? '',
            ].where((value) => value.isNotEmpty).join('. '),
            label:
                semanticLabel ?? 'Open ${document.title}, ${document.sender}',
            onTap: onOpen,
            child: ExcludeSemantics(
              child: InkWell(
                focusNode: focusNode,
                onTap: onOpen,
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        height: previewHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: tokens.preview, child: preview),
                            Positioned(
                              left: 7,
                              top: 7,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xE8FFFFFF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    document.type,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF465B5D),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 12, 5, 0),
                      child: SizedBox(
                        height: titleLines > 1
                            ? MediaQuery.textScalerOf(context).scale(14) *
                                  (18 / 14) *
                                  titleLines
                            : null,
                        child: Text(
                          document.title,
                          maxLines: titleLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 18 / 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 3, 5, 0),
                      child: Text(
                        document.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: tokens.muted,
                        ),
                      ),
                    ),
                    if (document.snippet case final snippet?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(5, 6, 5, 0),
                        child: SizedBox(
                          height:
                              MediaQuery.textScalerOf(context).scale(12) * 2.6,
                          child: Text(
                            snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 12, 5, 5),
                      child: SizedBox(
                        height:
                            MediaQuery.textScalerOf(context).scale(11) *
                                (14 / 11) +
                            8,
                        child: Row(
                          children: [
                            Expanded(
                              child: document.tags.isEmpty
                                  ? const SizedBox.shrink()
                                  : Tooltip(
                                      message: document.tags.join(', '),
                                      child: DefaultTextStyle.merge(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        child: GlacierTag(
                                          label: document.tags.first,
                                        ),
                                      ),
                                    ),
                            ),
                            if (document.tags.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '+${document.tags.length - 1}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                document.date,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 14 / 11,
                                  color: tokens.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (document.failed)
            Positioned(
              right: -2,
              top: -2,
              child: SizedBox.square(
                dimension: 48,
                child: IconButton(
                  tooltip: 'Retry processing ${document.title}',
                  onPressed: onRetry,
                  padding: EdgeInsets.zero,
                  icon: Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: tokens.solid,
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (document.busy)
            Positioned(
              right: 8,
              top: 9,
              child: Semantics(
                label: 'Processing ${document.title}',
                liveRegion: true,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tokens.solid,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  ),
                ),
              ),
            ),
          if (onRetryPreview != null)
            Positioned(
              right: 0,
              top: 50,
              child: GlacierPreviewRetry(
                compact: MediaQuery.textScalerOf(context).scale(11) > 16,
                onPressed: onRetryPreview!,
                semanticLabel: 'Retry preview ${document.title}',
              ),
            ),
          if (selected != null)
            Positioned(
              top: 0,
              left: 0,
              child: Semantics(
                label: 'Select ${document.title}',
                checked: selected,
                child: SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    onPressed: onSelectionChanged == null
                        ? null
                        : () => onSelectionChanged!(!selected!),
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.solid,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _DocumentChoiceMark(selected: selected!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GlacierMobileDocumentSelectionBar extends StatelessWidget {
  const GlacierMobileDocumentSelectionBar({
    super.key,
    required this.count,
    this.onEditTags,
    this.onDelete,
    this.onDone,
  });
  final int count;
  final VoidCallback? onEditTags, onDelete, onDone;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    glass: true,
    radius: 12,
    padding: const EdgeInsets.all(12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$count selected',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        GlacierButton(label: 'Edit tags', onPressed: onEditTags),
        GlacierButton(
          label: 'Delete',
          kind: GlacierButtonKind.danger,
          onPressed: onDelete,
        ),
        GlacierButton(
          label: 'Done',
          kind: GlacierButtonKind.quiet,
          onPressed: onDone,
        ),
      ],
    ),
  );
}

class GlacierMobileDocumentCollection extends StatelessWidget {
  const GlacierMobileDocumentCollection({
    super.key,
    required this.documents,
    required this.previewBuilder,
    this.state = GlacierMobileCollectionState.ready,
    this.list = false,
    this.selectedIds,
    this.onOpen,
    this.onRetry,
    this.onSelectionChanged,
    this.onSelect,
    this.onToggleView,
    this.onRefresh,
    this.onScan,
    this.onUpload,
    this.onEditSearch,
    this.onClearSearch,
    this.selectionBar,
    this.leading,
    this.continuation,
    this.activity,
    this.caption = 'Recently added · Personal',
  });
  final List<GlacierDocumentValue> documents;
  final Widget Function(GlacierDocumentValue) previewBuilder;
  final GlacierMobileCollectionState state;
  final bool list;
  final Set<String>? selectedIds;
  final ValueChanged<GlacierDocumentValue>? onOpen, onRetry;
  final void Function(GlacierDocumentValue, bool)? onSelectionChanged;
  final VoidCallback? onSelect,
      onToggleView,
      onRefresh,
      onScan,
      onUpload,
      onEditSearch,
      onClearSearch;
  final Widget? selectionBar, leading, continuation, activity;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?leading,
      if (state == GlacierMobileCollectionState.stale)
        GlacierMobileNotice(
          title: 'Showing saved results',
          message:
              'Live updates are unavailable. You can still use these results.',
          action: GlacierButton(label: 'Refresh', onPressed: onRefresh),
        ),
      Row(
        children: [
          Expanded(
            child: Text(caption, style: Theme.of(context).textTheme.bodySmall),
          ),
          GlacierIconButton(
            label: 'Select documents',
            icon: Icons.done_rounded,
            onPressed: state == GlacierMobileCollectionState.readOnly
                ? null
                : onSelect,
          ),
          GlacierIconButton(
            label: list ? 'Grid view' : 'List view',
            icon: list
                ? Icons.grid_view_outlined
                : Icons.format_list_bulleted_rounded,
            onPressed: onToggleView,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (selectionBar != null) ...[selectionBar!, const SizedBox(height: 14)],
      if (state == GlacierMobileCollectionState.loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 16),
              Text('Loading documents…'),
            ],
          ),
        )
      else if ([
        GlacierMobileCollectionState.empty,
        GlacierMobileCollectionState.noMatch,
        GlacierMobileCollectionState.error,
      ].contains(state))
        _CollectionEmpty(
          state: state,
          onScan: onScan,
          onUpload: onUpload,
          onEditSearch: onEditSearch,
          onClearSearch: onClearSearch,
          onRefresh: onRefresh,
        )
      else ...[
        if (state == GlacierMobileCollectionState.readOnly)
          const GlacierMobileNotice(
            title: 'Read-only library',
            message: 'You can open documents. Upload and editing need additional access.',
            attention: false,
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = MediaQuery.sizeOf(context).width;
            final large = MediaQuery.textScalerOf(context).scale(14) >= 25;
            final columns = list || large
                ? 1
                : width >= 600
                ? 3
                : 2;
            final gap = width <= 350 ? 9.0 : 12.0;
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final document in documents)
                  SizedBox(
                    width: itemWidth,
                    child: list
                        ? GlacierMobileRecordRow(
                            title: document.title,
                            detail:
                                '${document.sender} · ${document.tags.join(', ')} · ${document.date}',
                            icon: Icons.description_outlined,
                            onTap: onOpen == null
                                ? null
                                : () => onOpen!(document),
                          )
                        : GlacierMobileDocumentCard(
                            document: document,
                            preview: previewBuilder(document),
                            previewHeight: width <= 350
                                ? 139
                                : width >= 600
                                ? 180
                                : 157,
                            onOpen: onOpen == null
                                ? null
                                : () => onOpen!(document),
                            onRetry: onRetry == null
                                ? null
                                : () => onRetry!(document),
                            selected: selectedIds?.contains(document.id),
                            onSelectionChanged: onSelectionChanged == null
                                ? null
                                : (selected) =>
                                      onSelectionChanged!(document, selected),
                          ),
                  ),
              ],
            );
          },
        ),
        ?continuation,
      ],
      if (activity != null) ...[const SizedBox(height: 20), activity!],
    ],
  );
}

class _CollectionEmpty extends StatelessWidget {
  const _CollectionEmpty({
    required this.state,
    this.onScan,
    this.onUpload,
    this.onEditSearch,
    this.onClearSearch,
    this.onRefresh,
  });
  final GlacierMobileCollectionState state;
  final VoidCallback? onScan, onUpload, onEditSearch, onClearSearch, onRefresh;
  @override
  Widget build(BuildContext context) {
    final empty = state == GlacierMobileCollectionState.empty;
    final error = state == GlacierMobileCollectionState.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          Icon(
            empty
                ? Icons.description_outlined
                : error
                ? Icons.error_outline
                : Icons.search,
            size: 36,
            color: GlacierTokens.of(context).accent,
          ),
          const SizedBox(height: 18),
          Text(
            empty
                ? 'Your library starts here'
                : error
                ? 'Documents are unavailable'
                : 'No matching documents',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            empty
                ? 'Scan a page or add an original file. You can find it here once it is accepted.'
                : error
                ? 'Check your connection and try again.'
                : 'Try fewer filters or a different search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GlacierTokens.of(context).muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              GlacierButton(
                label: empty
                    ? 'Scan a document'
                    : error
                    ? 'Try again'
                    : 'Edit search',
                kind: GlacierButtonKind.primary,
                onPressed: empty
                    ? onScan
                    : error
                    ? onRefresh
                    : onEditSearch,
              ),
              if (!error)
                GlacierButton(
                  label: empty ? 'Upload files' : 'Clear all',
                  kind: empty
                      ? GlacierButtonKind.secondary
                      : GlacierButtonKind.quiet,
                  onPressed: empty ? onUpload : onClearSearch,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

@immutable
class GlacierMobileSearchValue {
  const GlacierMobileSearchValue({
    this.query = '',
    this.types = const [],
    this.tags = const [],
    this.sender = '',
    this.recipient = '',
    this.from = '',
    this.through = '',
    this.match = 'Words',
    this.sort = 'Newest first',
  });
  final String query, sender, recipient, from, through, match, sort;
  final List<String> types, tags;
}

class GlacierMobileSearchFilters extends StatefulWidget {
  const GlacierMobileSearchFilters({
    super.key,
    this.value = const GlacierMobileSearchValue(),
    this.tags = const ['Home', 'Invoice', 'Insurance', 'Travel'],
    this.library = 'Personal',
    required this.onApply,
    required this.onCancel,
    this.onMoreTags,
    this.validationMessage,
  });
  final GlacierMobileSearchValue value;
  final List<String> tags;
  final String library;
  final String? validationMessage;
  final ValueChanged<GlacierMobileSearchValue> onApply;
  final VoidCallback onCancel;
  final VoidCallback? onMoreTags;
  @override
  State<GlacierMobileSearchFilters> createState() =>
      _GlacierMobileSearchFiltersState();
}

class _GlacierMobileSearchFiltersState
    extends State<GlacierMobileSearchFilters> {
  late final TextEditingController query, sender, recipient, from, through;
  late Set<String> types, tags;
  late String match, sort;
  String? error;
  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: widget.value.query);
    sender = TextEditingController(text: widget.value.sender);
    recipient = TextEditingController(text: widget.value.recipient);
    from = TextEditingController(text: widget.value.from);
    through = TextEditingController(text: widget.value.through);
    types = widget.value.types.toSet();
    tags = widget.value.tags.toSet();
    match = widget.value.match;
    sort = widget.value.sort;
    error = widget.validationMessage;
  }

  @override
  void dispose() {
    for (final controller in [query, sender, recipient, from, through]) {
      controller.dispose();
    }
    super.dispose();
  }

  void apply() {
    if (query.value.composing.isValid && !query.value.composing.isCollapsed) {
      return;
    }
    if (from.text.isNotEmpty &&
        through.text.isNotEmpty &&
        from.text.compareTo(through.text) > 0) {
      setState(
        () => error = 'The start date must be on or before the end date.',
      );
      return;
    }
    widget.onApply(
      GlacierMobileSearchValue(
        query: query.text,
        sender: sender.text,
        recipient: recipient.text,
        from: from.text,
        through: through.text,
        types: List.unmodifiable(types),
        tags: List.unmodifiable(tags),
        match: match,
        sort: sort,
      ),
    );
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if ([query, sender, recipient, from, through].any(
        (c) => c.value.composing.isValid && !c.value.composing.isCollapsed,
      )) {
        return KeyEventResult.ignored;
      }
      apply();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if ([
            query,
            sender,
            recipient,
            from,
            through,
          ].any((c) => c.text.isNotEmpty) ||
          types.isNotEmpty ||
          tags.isNotEmpty) {
        setState(() {
          for (final c in [query, sender, recipient, from, through]) {
            c.clear();
          }
          types.clear();
          tags.clear();
          error = null;
        });
      } else {
        widget.onCancel();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: key,
    child: GlacierMobileSheet(
      footer: GlacierMobileActionBar(
        expandLast: true,
        hint: 'Enter applies · Esc clears, then closes',
        children: [
          GlacierButton(
            label: 'Cancel',
            kind: GlacierButtonKind.quiet,
            onPressed: widget.onCancel,
          ),
          GlacierButton(
            label: 'Apply search',
            kind: GlacierButtonKind.primary,
            onPressed: apply,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: GlacierTokens.of(context).border),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 21),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: query,
                        autofocus: true,
                        style: const TextStyle(fontSize: 21),
                        decoration: const InputDecoration(
                          hintText: 'Find a document',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          semanticCounterText: 'Search documents',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Search in ${widget.library} library',
            style: TextStyle(color: GlacierTokens.of(context).muted),
          ),
          const SizedBox(height: 24),
          _SearchGroup(
            title: 'Match',
            options: const ['Words', 'Meaning'],
            selected: {match},
            onChanged: (value) => setState(() => match = value),
            showCheck: false,
            exclusive: true,
          ),
          _SearchGroup(
            title: 'Document type',
            options: const ['PDF', 'Image', 'Email'],
            selected: types,
            onChanged: (value) => setState(() {
              types.contains(value) ? types.remove(value) : types.add(value);
            }),
          ),
          _SearchGroup(
            title: 'Tags',
            options: widget.tags,
            selected: tags,
            onChanged: (value) => setState(() {
              tags.contains(value) ? tags.remove(value) : tags.add(value);
            }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: GlacierButton(
              label: 'More tags',
              kind: GlacierButtonKind.quiet,
              onPressed: widget.onMoreTags,
            ),
          ),
          GlacierMobileField(label: 'Sender contains', controller: sender),
          GlacierMobileField(
            label: 'Recipient contains',
            controller: recipient,
          ),
          GlacierMobileField(
            label: 'From date',
            controller: from,
            keyboardType: TextInputType.datetime,
            hintText: 'YYYY-MM-DD',
          ),
          GlacierMobileField(
            label: 'Through date',
            controller: through,
            keyboardType: TextInputType.datetime,
            hintText: 'YYYY-MM-DD',
          ),
          Text('Sort by', style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            initialValue: sort,
            isExpanded: true,
            items: [
              for (final value in const [
                'Newest first',
                'Oldest first',
                'Title',
                'Relevance',
              ])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => sort = value);
            },
          ),
          if (error != null)
            GlacierMobileNotice(title: 'Check the date range', message: error!),
        ],
      ),
    ),
  );
}

class _SearchGroup extends StatelessWidget {
  const _SearchGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.showCheck = true,
    this.exclusive = false,
  });
  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onChanged;
  final bool showCheck;
  final bool exclusive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              MergeSemantics(
                child: Semantics(
                  selected: selected.contains(option),
                  checked: selected.contains(option),
                  inMutuallyExclusiveGroup: exclusive,
                  container: true,
                  child: OutlinedButton(
                    onPressed: () => onChanged(option),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected.contains(option)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : GlacierTokens.of(context).surface,
                      foregroundColor: selected.contains(option)
                          ? GlacierTokens.of(context).accent
                          : Theme.of(context).colorScheme.onSurface,
                      side: BorderSide(
                        color: selected.contains(option)
                            ? GlacierTokens.of(context).accent
                            : GlacierTokens.of(context).border,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showCheck) ...[
                          _DocumentChoiceMark(
                            selected: selected.contains(option),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _DocumentChoiceMark extends StatelessWidget {
  const _DocumentChoiceMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: selected ? tokens.accent : Colors.transparent,
        border: Border.all(
          color: selected ? tokens.accent : tokens.muted,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: 13,
              color: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }
}
