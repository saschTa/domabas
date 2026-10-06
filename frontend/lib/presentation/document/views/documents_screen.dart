import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../models/document_collection_item.dart';
import '../widgets/document_card_metadata.dart';
import '../../../domain/document/interfaces/document_vocabulary_repository.dart';
import '../widgets/document_detail_dialog.dart';
import '../widgets/document_editor_dialog.dart';
import '../widgets/document_search_widgets.dart';
import '../widgets/document_filter_dialog.dart';
import '../cubits/documents_cubit.dart';
import '../cubits/document_preview_cubit.dart';

final class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.cubit,
    this.canCreate = true,
    this.vocabulary,
    this.appearanceAction,
  });
  final DocumentsCubit cubit;
  final bool canCreate;
  final DocumentVocabularyRepository? vocabulary;
  final Widget? appearanceAction;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

final class _DocumentsScreenState extends State<DocumentsScreen>
    with WidgetsBindingObserver {
  final _term = TextEditingController();
  final _termFocus = FocusNode();
  final _scroll = ScrollController();
  final _filtersFocus = FocusNode();
  RawDialogRoute<void>? _filterRoute;
  NavigatorState? _filterNavigator;
  int _filterGeneration = 0;
  int _scrollEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _term.text = widget.cubit.state.rawTerm;
    _term.addListener(_edited);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filterGeneration++;
    final route = _filterRoute;
    final navigator = _filterNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
    _term.dispose();
    _termFocus.dispose();
    _scroll.dispose();
    _filtersFocus.dispose();
    super.dispose();
  }

  void _edited() {
    final value = _term.value;
    widget.cubit.editTerm(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  void _submit() {
    final composing = _term.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    _termFocus.unfocus();
    unawaited(widget.cubit.submitSearch());
  }

  void _clear() {
    _term.clear();
    unawaited(widget.cubit.clearSearch());
  }

  Future<void> _filters() async {
    final repository = widget.vocabulary;
    if (_filterRoute != null || repository == null) return;
    final owner = widget.cubit;
    final generation = ++_filterGeneration;
    final navigator = _filterNavigator = Navigator.of(context);
    late final RawDialogRoute<void> route;
    bool owns() =>
        mounted &&
        identical(owner, widget.cubit) &&
        identical(repository, widget.vocabulary) &&
        !owner.isClosed &&
        generation == _filterGeneration &&
        _filterRoute == route &&
        navigator.mounted &&
        route.navigator == navigator &&
        route.isCurrent;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => DocumentFilterDialog(
        documents: owner,
        repository: repository,
        isCurrent: owns,
        onClose: () {
          if (owns()) navigator.pop();
        },
      ),
    );
    _filterRoute = route;
    await navigator.push(route);
    if (!mounted || generation != _filterGeneration || _filterRoute != route) {
      return;
    }
    _filterRoute = null;
    _filterNavigator = null;
    if (_filtersFocus.canRequestFocus) _filtersFocus.requestFocus();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<DocumentsCubit, DocumentsState>(
    bloc: widget.cubit,
    listenWhen: (before, after) =>
        before.scrollEpoch != after.scrollEpoch ||
        before.rawTerm != after.rawTerm,
    listener: (_, state) {
      if (_scrollEpoch != state.scrollEpoch) {
        _scrollEpoch = state.scrollEpoch;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
      if (_term.text != state.rawTerm) {
        _term.value = TextEditingValue(
          text: state.rawTerm,
          selection: TextSelection.collapsed(offset: state.rawTerm.length),
        );
      }
    },
    builder: (context, state) => LayoutBuilder(
      builder: (context, constraints) {
        final inset = AppLayout.pageInset(MediaQuery.sizeOf(context).width);
        final width = constraints.maxWidth - inset * 2;
        final columns = state.layout == DocumentLayout.list
            ? 1
            : math.max(1, ((width + 16) / 256).floor());
        final items = state.searching
            ? state.results.map(DocumentCollectionItem.fromSearch).toList()
            : state.documents.map(DocumentCollectionItem.fromDocument).toList();
        final rows = (items.length / columns).ceil();
        final reduced =
            MediaQuery.disableAnimationsOf(context) ||
            View.of(context)
                .platformDispatcher
                .accessibilityFeatures
                .reduceMotion;
        final heading = !state.hasSnapshot
            ? 'Documents'
            : state.searching
            ? state.totalKnown
                  ? '${state.total} ${state.total == 1 ? 'result' : 'results'}'
                  : 'Search results'
            : '${state.total} ${state.total == 1 ? 'document' : 'documents'}';
        final status =
            state.error ??
            state.notice ??
            (state.showLoading ||
                    state.debouncing ||
                    state.intentBlocked ||
                    state.confirmedMutation ||
                    !state.hasSnapshot
                ? state.status
                : '');
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            child: Semantics(
              container: true,
              label: 'Document collection',
              child: CustomScrollView(
                key: const Key('documentCollectionScroll'),
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 12, inset, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.cubit.capabilities.read &&
                              widget.cubit.capabilities.search) ...[
                            DocumentSearchControls(
                              term: _term,
                              termFocus: _termFocus,
                              termError: state.termError,
                              state: state,
                              filtersFocus: _filtersFocus,
                              onSubmit: _submit,
                              onFilters: _filters,
                              onClear: _clear,
                              onSort: widget.cubit.setSort,
                              compactSort: width < 560,
                              onRemoveTag: widget.cubit.removeTag,
                              onClearAddress: widget.cubit.clearAddress,
                              onKindsChanged: widget.cubit.setKinds,
                              onClearKinds: widget.cubit.clearKinds,
                              onResetFilters: widget.cubit.resetFilters,
                            ),
                            const SizedBox(height: 12),
                          ],
                          LayoutBuilder(
                            builder: (context, toolbar) {
                              final compact =
                                  toolbar.maxWidth < 720 ||
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      20;
                              return Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Tooltip(
                                    message: state.status,
                                    child: Semantics(
                                      liveRegion: !state.isLoading,
                                      child: Text(
                                        heading,
                                        key: const Key('documentCount'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (width >= 560 &&
                                          widget.cubit.capabilities.read &&
                                          widget.cubit.capabilities.search)
                                        DocumentSortControl(
                                          criteria: state.desiredCriteria,
                                          onSort: widget.cubit.setSort,
                                          compact: compact,
                                        ),
                                      ToggleButtons(
                                        borderRadius: BorderRadius.circular(24),
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          minHeight: 48,
                                        ),
                                        isSelected: [
                                          state.layout == DocumentLayout.grid,
                                          state.layout == DocumentLayout.list,
                                        ],
                                        onPressed: (index) =>
                                            widget.cubit.setLayout(
                                              DocumentLayout.values[index],
                                            ),
                                        children: [
                                          for (final (label, icon) in [
                                            ('Grid', Icons.grid_view_rounded),
                                            ('List', Icons.view_list_rounded),
                                          ])
                                            Tooltip(
                                              message: label,
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: compact ? 0 : 12,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(icon, size: 20),
                                                    if (!compact) ...[
                                                      const SizedBox(width: 8),
                                                      Text(label),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      IconButton(
                                        key: const Key('refreshDocuments'),
                                        tooltip: state.error == null
                                            ? 'Refresh documents'
                                            : 'Retry',
                                        onPressed:
                                            state.isSaving ||
                                                (state.error != null &&
                                                    (state.intentBlocked ||
                                                        state.showLoading))
                                            ? null
                                            : state.error != null
                                            ? widget.cubit.retryCollection
                                            : () => widget.cubit.load(),
                                        icon: const Icon(Icons.refresh_rounded),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Tooltip(
                                      message: status,
                                      child: Text(
                                        status.isEmpty ? ' ' : status,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 2,
                            child: state.showLoading
                                ? AppStripedProgressIndicator(
                                    animate: !reduced,
                                    minHeight: 2,
                                  )
                                : null,
                          ),
                          const AppStripedDivider(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (state.searching
                      ? state.results.isEmpty
                      : state.documents.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      sliver: SliverToBoxAdapter(
                        child: AppEmptyState(
                          icon: Icons.folder_open_rounded,
                          title: state.hasSnapshot
                              ? state.searching
                                    ? 'No matching documents'
                                    : 'No documents yet'
                              : state.isLoading
                              ? 'Opening your library…'
                              : state.error != null
                              ? (state.searching
                                    ? 'Search is unavailable'
                                    : 'Your library is unavailable')
                              : 'Your library has not loaded',
                          message: !state.hasSnapshot
                              ? 'Your documents will appear here.'
                              : state.searching
                              ? 'Try another term or adjust the filters.'
                              : widget.canCreate
                              ? 'Add your first document to start your collection.'
                              : 'Documents shared with this library will appear here.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      sliver: SliverList.builder(
                        itemCount: rows,
                        itemBuilder: (context, row) => Padding(
                          padding: EdgeInsets.only(
                            bottom: state.layout == DocumentLayout.list
                                ? 8
                                : 20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (
                                var column = 0;
                                column < columns;
                                column++
                              ) ...[
                                if (column > 0) const SizedBox(width: 16),
                                Expanded(
                                  child: row * columns + column < items.length
                                      ? DocumentCollectionCard(
                                          appearanceAction:
                                              widget.appearanceAction,
                                          key: ValueKey(
                                            items[row * columns + column].id,
                                          ),
                                          document:
                                              items[row * columns + column],
                                          cubit: widget.cubit,
                                          list:
                                              state.layout ==
                                              DocumentLayout.list,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      8,
                      inset,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: state.searching
                          ? Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (state.ordinal > 1)
                                  TextButton(
                                    onPressed: !state.canPaginate
                                        ? null
                                        : widget.cubit.firstSearchPage,
                                    child: const Text('First page'),
                                  ),
                                TextButton.icon(
                                  onPressed:
                                      !state.canPaginate ||
                                          (state
                                                  .searchRequest
                                                  ?.history
                                                  .isEmpty ??
                                              true)
                                      ? null
                                      : widget.cubit.previousSearchPage,
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Previous'),
                                ),
                                Text('Page ${state.ordinal}'),
                                TextButton.icon(
                                  onPressed:
                                      !state.canPaginate ||
                                          state.nextCursor == null
                                      ? null
                                      : widget.cubit.nextSearchPage,
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('Next'),
                                ),
                              ],
                            )
                          : state.total > DocumentsCubit.pageSize
                          ? Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                IconButton(
                                  tooltip: 'Previous page',
                                  onPressed:
                                      state.page == 0 || !state.canPaginate
                                      ? null
                                      : () => widget.cubit.load(
                                          page: state.page - 1,
                                        ),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text(
                                  'Page ${state.page + 1} of ${state.pages}',
                                ),
                                IconButton(
                                  key: const Key('loadMoreDocuments'),
                                  tooltip: 'Next page',
                                  onPressed:
                                      !widget.cubit.canLoadMore ||
                                          state.showLoading
                                      ? null
                                      : () => widget.cubit.load(more: true),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

final class DocumentCreateAction extends StatelessWidget {
  const DocumentCreateAction({super.key, required this.cubit});
  final DocumentsCubit cubit;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentsCubit, DocumentsState>(
        bloc: cubit,
        builder: (context, state) => OutlinedButton.icon(
          key: const Key('newDocument'),
          onPressed: state.isSaving || !cubit.capabilities.create
              ? null
              : () => _create(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create metadata'),
        ),
      );
  Future<void> _create(BuildContext context) => open(context, cubit);

  static Future<void> open(BuildContext context, DocumentsCubit cubit) async {
    cubit.clearSaveError();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentEditorDialog(cubit: cubit),
    );
  }
}

final class DocumentCollectionCard extends StatefulWidget {
  const DocumentCollectionCard({
    super.key,
    required this.document,
    required this.cubit,
    this.appearanceAction,
    required this.list,
  });
  final DocumentCollectionItem document;
  final DocumentsCubit cubit;
  final Widget? appearanceAction;
  final bool list;
  @override
  State<DocumentCollectionCard> createState() => _DocumentCollectionCardState();
}

final class _DocumentCollectionCardState extends State<DocumentCollectionCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  bool _hovered = false;
  bool _focused = false;
  final _focus = FocusNode();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await DocumentDetailDialog.open(
      context,
      documentId: widget.document.id,
      cubit: widget.cubit,
      appearanceAction: widget.appearanceAction,
    );
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final theme = Theme.of(context);
    final highlighted = _hovered || _focused;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    final metadata = DocumentCardMetadata(
      document: document,
      list: widget.list,
    );
    final preview = _DocumentPreview(
      key: ValueKey('${document.id}/${document.thumbnail?.identity}'),
      document: document,
      cubit: widget.cubit,
      resumeRevision: widget.cubit.state.previewEpoch,
    );
    final radius = BorderRadius.circular(24);
    final details = documentSupplementalDetails(context, document);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          key: document.snippet == null
              ? null
              : Key('search-document-${document.id}'),
          container: true,
          explicitChildNodes: true,
          label: 'Open document: ${document.title}',
          button: true,
          onTap: _open,
          child: InkWell(
            excludeFromSemantics: true,
            key: Key('document-${document.id}'),
            focusNode: _focus,
            onTap: _open,
            onFocusChange: (value) => setState(() => _focused = value),
            child: widget.list
                ? Tooltip(
                    message: details,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 56,
                              height: 72,
                              child: preview,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: metadata),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 1.45,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            preview,
                            DocumentCardDetailsPill(
                              pillKey: Key(
                                'document-hover-details-${document.id}',
                              ),
                              details: details,
                              visible: highlighted,
                              reduceMotion: reduced,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: metadata,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

final class _DocumentPreview extends StatefulWidget {
  const _DocumentPreview({
    super.key,
    required this.document,
    required this.cubit,
    required this.resumeRevision,
  });
  final DocumentCollectionItem document;
  final DocumentsCubit cubit;
  final int resumeRevision;
  @override
  State<_DocumentPreview> createState() => _DocumentPreviewState();
}

final class _DocumentPreviewState extends State<_DocumentPreview> {
  late final DocumentPreviewCubit _preview = DocumentPreviewCubit(
    widget.cubit.previews,
    widget.document.thumbnail,
  );
  @override
  void initState() {
    super.initState();
    if (widget.document.thumbnail != null &&
        widget.cubit.capabilities.preview) {
      unawaited(_preview.load());
    }
  }

  @override
  void didUpdateWidget(_DocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resumeRevision != widget.resumeRevision) {
      unawaited(_preview.resume());
    }
  }

  @override
  void dispose() {
    unawaited(_preview.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: BlocBuilder<DocumentPreviewCubit, DocumentPreviewState>(
      bloc: _preview,
      builder: (context, state) {
        if (widget.document.original?.original.isEmail == true ||
            widget.document.kind == 'email') {
          return Center(
            child: Icon(
              Icons.mail_outline,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              semanticLabel: 'Email',
            ),
          );
        }
        if (state.image != null) {
          return TweenAnimationBuilder<double>(
            key: ValueKey(state.image),
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            builder: (context, value, child) =>
                Opacity(opacity: value, child: child),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RawImage(image: state.image, fit: BoxFit.contain),
            ),
          );
        }
        if (state.loading) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (widget.document.thumbnail == null ||
            !widget.cubit.capabilities.preview) {
          return Center(
            child: Icon(
              Icons.description_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Center(
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 100
                ? IconButton(
                    tooltip: 'Preview unavailable. Retry preview',
                    onPressed: _preview.load,
                    icon: const Icon(Icons.refresh),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined),
                      const Text('Preview unavailable'),
                      TextButton(
                        onPressed: _preview.load,
                        child: const Text('Retry preview'),
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}
