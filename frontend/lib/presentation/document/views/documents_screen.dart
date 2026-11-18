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
import '../widgets/documents_workspace_toolbar.dart';
import '../widgets/document_search_widgets.dart';
import '../cubits/documents_cubit.dart';
import '../cubits/document_preview_cubit.dart';

final class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.cubit,
    this.canCreate = true,
    this.vocabulary,
    this.appearanceAction,
    this.shellToolbar = false,
    this.preparingPreviewDocumentIds = const {},
  });
  final DocumentsCubit cubit;
  final bool canCreate;
  final DocumentVocabularyRepository? vocabulary;
  final Widget? appearanceAction;
  final bool shellToolbar;
  final Set<String> preparingPreviewDocumentIds;
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

final class _DocumentsScreenState extends State<DocumentsScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  int _scrollEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<DocumentsCubit, DocumentsState>(
    bloc: widget.cubit,
    listenWhen: (before, after) => before.scrollEpoch != after.scrollEpoch,
    listener: (_, state) {
      if (_scrollEpoch != state.scrollEpoch) {
        _scrollEpoch = state.scrollEpoch;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    },
    builder: (context, state) => AppPage(
      title: 'Documents',
      glacier: true,
      insetBody: false,
      onRefresh: state.isSaving || state.intentBlocked
          ? null
          : () => widget.cubit.load(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          final inset =
              AppLayout.pageInset(screenWidth) - (screenWidth < 600 ? 8 : 16);
          final width = constraints.maxWidth - inset * 2;
          final compact = screenWidth < 600;
          final columns = state.layout == DocumentLayout.list
              ? 1
              : compact
              ? (width >= 340 && MediaQuery.textScalerOf(context).scale(14) < 22
                    ? 2
                    : 1)
              : math.max(1, ((width + 16) / 281).floor());
          final items = state.searching
              ? state.results.map(DocumentCollectionItem.fromSearch).toList()
              : state.documents
                    .map(DocumentCollectionItem.fromDocument)
                    .toList();
          final rows = (items.length / columns).ceil();
          final reduced =
              MediaQuery.disableAnimationsOf(context) ||
              View.of(context)
                  .platformDispatcher
                  .accessibilityFeatures
                  .reduceMotion;
          final count = !state.hasSnapshot
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
          final bottomClearance = MediaQuery.paddingOf(context).bottom
              .clamp(0.0, constraints.maxHeight);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
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
                        padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!widget.shellToolbar) ...[
                                DocumentsWorkspaceToolbar(
                                  cubit: widget.cubit,
                                  vocabulary: widget.vocabulary,
                                  showSearchButton: true,
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (widget.cubit.capabilities.read &&
                                  widget.cubit.capabilities.search &&
                                  (state.desiredCriteria.filterCount > 0 ||
                                      state.rawTerm.isNotEmpty)) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (state.rawTerm.isNotEmpty)
                                      GlacierTag(
                                        label: 'Search: ${state.rawTerm}',
                                        onDeleted: () =>
                                            widget.cubit.applySearch(
                                              state.desiredCriteria.copyWith(
                                                query: '',
                                              ),
                                            ),
                                      ),
                                    DocumentActiveFilters(
                                      criteria: state.desiredCriteria,
                                      onRemoveTag: widget.cubit.removeTag,
                                      onClearAddress: widget.cubit.clearAddress,
                                      onClearKinds: widget.cubit.clearKinds,
                                      onReset: widget.cubit.resetFilters,
                                      compact: true,
                                      resetLabel: 'Clear filters',
                                    ),
                                  ],
                                ),
                              ],
                              SizedBox(
                                height: 2,
                                child: state.showLoading
                                    ? AppStripedProgressIndicator(
                                        animate: !reduced,
                                        minHeight: 2,
                                      )
                                    : null,
                              ),
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
                                      child:
                                          row * columns + column < items.length
                                          ? DocumentCollectionCard(
                                              preparingPreview: widget
                                                  .preparingPreviewDocumentIds
                                                  .contains(
                                                    items[row * columns +
                                                            column]
                                                        .id,
                                                  ),
                                              appearanceAction:
                                                  widget.appearanceAction,
                                              key: ValueKey(
                                                items[row * columns + column]
                                                    .id,
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
                          16 + (status.isEmpty ? bottomClearance : 0),
                        ),
                        sliver: SliverToBoxAdapter(
                          child: GlacierWorkspaceGeometry.measureEndActions(
                            context,
                            followingExtent:
                                16 + (status.isEmpty ? bottomClearance : 0),
                            child: Column(
                              key: const Key('documentCollectionFooter'),
                              children: [
                                Semantics(
                                  liveRegion: !state.isLoading,
                                  child: Text(
                                    count,
                                    key: const Key('documentCount'),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                if (state.searching ||
                                    state.total > DocumentsCubit.pageSize)
                                  const SizedBox(height: 8),
                                if (state.searching)
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
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
                                else if (state.total > DocumentsCubit.pageSize)
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    children: [
                                      IconButton(
                                        tooltip: 'Previous page',
                                        onPressed:
                                            state.page == 0 ||
                                                !state.canPaginate
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
                                            : () =>
                                                  widget.cubit.load(more: true),
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: GlacierWorkspaceGeometry.trailingOf(
                            context,
                            existingBottom: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (status.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: bottomClearance),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          (constraints.maxHeight - bottomClearance) * .35,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: EdgeInsets.fromLTRB(inset, 8, inset, 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          status,
                          key: const Key('documentCollectionStatus'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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
    await showGlacierDialog<void>(
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
    this.preparingPreview = false,
  });
  final DocumentCollectionItem document;
  final DocumentsCubit cubit;
  final Widget? appearanceAction;
  final bool list;
  final bool preparingPreview;
  @override
  State<DocumentCollectionCard> createState() => _DocumentCollectionCardState();
}

final class _DocumentCollectionCardState extends State<DocumentCollectionCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createPreview();
  }

  late DocumentPreviewCubit _preview;
  late int _previewEpoch;

  void _createPreview() {
    _preview = DocumentPreviewCubit(
      widget.cubit.previews,
      widget.document.thumbnail,
    );
    _previewEpoch = widget.cubit.state.previewEpoch;
    if (widget.document.thumbnail != null &&
        widget.cubit.capabilities.preview) {
      unawaited(_preview.load());
    }
  }

  @override
  void didUpdateWidget(DocumentCollectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit ||
        oldWidget.document.id != widget.document.id ||
        oldWidget.document.thumbnail?.identity !=
            widget.document.thumbnail?.identity) {
      unawaited(_preview.close());
      _createPreview();
    } else if (_previewEpoch != widget.cubit.state.previewEpoch) {
      _previewEpoch = widget.cubit.state.previewEpoch;
      unawaited(_preview.resume());
    }
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
    unawaited(_preview.close());
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
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentPreviewCubit, DocumentPreviewState>(
        bloc: _preview,
        builder: _buildCard,
      );

  Widget _buildCard(BuildContext context, DocumentPreviewState previewState) {
    final document = widget.document;
    final original = document.original?.original;
    final details = documentSupplementalDetails(context, document);
    final value = GlacierDocumentValue(
      id: document.id,
      title: document.title,
      type: switch (original?.mediaType) {
        'application/pdf' => 'PDF',
        'image/png' => 'PNG',
        'image/jpeg' => 'JPEG',
        'message/rfc822' => 'EML',
        _ =>
          document.kind == 'email'
              ? 'EML'
              : document.knownNoOriginal
              ? 'Metadata'
              : 'Document',
      },
      date: document.documentDate.isNotEmpty
          ? document.documentDate
          : MaterialLocalizations.of(context)
                .formatShortDate(document.createdAt.toLocal()),
      tags: document.tags,
      status: document.status,
      snippet: widget.cubit.state.searching ? document.snippet ?? '' : null,
      busy:
          widget.cubit.state.retryingIds.contains(document.id) ||
          {'queued', 'processing'}.contains(document.processingState),
      failed:
          document.processingState == 'failed' &&
          !widget.cubit.state.retryingIds.contains(document.id) &&
          !document.requiresPassword &&
          widget.cubit.capabilities.retry,
    );
    final preview = _DocumentPreview(
      key: ValueKey('${document.id}/${document.thumbnail?.identity}'),
      document: document,
      cubit: widget.cubit,
      state: previewState,
      preparing: widget.preparingPreview,
    );
    final onRetry =
        value.failed && !widget.cubit.state.retryingIds.contains(document.id)
        ? () => unawaited(widget.cubit.retryDocument(document.id))
        : null;
    final onRetryPreview =
        previewState.failed &&
            previewState.image == null &&
            !previewState.loading &&
            document.thumbnail != null &&
            widget.cubit.capabilities.preview &&
            document.kind != 'email' &&
            document.original?.original.isEmail != true
        ? _preview.load
        : null;
    final semanticLabel = 'Open document: ${document.title}';
    final Widget card;
    if (widget.list) {
      card = GlacierDocumentRow(
        key: Key('document-${document.id}'),
        document: value,
        preview: preview,
        focusNode: _focus,
        onOpen: _open,
        onRetry: onRetry,
        onRetryPreview: onRetryPreview,
      );
    } else if (MediaQuery.sizeOf(context).width < 600) {
      card = GlacierMobileDocumentCard(
        key: Key('document-${document.id}'),
        document: value,
        preview: preview,
        focusNode: _focus,
        semanticLabel: semanticLabel,
        titleLines: 2,
        onOpen: _open,
        onRetry: onRetry,
        onRetryPreview: onRetryPreview,
      );
    } else {
      card = GlacierDocumentCard(
        key: Key('document-${document.id}'),
        document: value,
        preview: preview,
        focusNode: _focus,
        semanticLabel: semanticLabel,
        titleLines: 2,
        previewOverlay: DocumentCardDetailsPill(
          pillKey: Key('document-hover-details-${document.id}'),
          details: details,
          visible: _hovered || _focused,
          reduceMotion:
              MediaQuery.disableAnimationsOf(context) ||
              View.of(context)
                  .platformDispatcher
                  .accessibilityFeatures
                  .reduceMotion,
        ),
        onOpen: _open,
        onRetry: onRetry,
        onRetryPreview: onRetryPreview,
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: KeyedSubtree(
          key: document.snippet == null
              ? null
              : Key('search-document-${document.id}'),
          child: card,
        ),
      ),
    );
  }
}

final class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    super.key,
    required this.document,
    required this.cubit,
    required this.state,
    required this.preparing,
  });
  final DocumentCollectionItem document;
  final DocumentsCubit cubit;
  final DocumentPreviewState state;
  final bool preparing;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    if (document.original?.original.isEmail == true ||
        document.kind == 'email') {
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
        duration:
            MediaQuery.disableAnimationsOf(context) ||
                View.of(context)
                    .platformDispatcher
                    .accessibilityFeatures
                    .reduceMotion
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
      return const GlacierPreviewPlaceholder(semanticLabel: 'Loading preview');
    }
    if (document.thumbnail == null &&
        preparing &&
        cubit.capabilities.preview &&
        const {
          'application/pdf',
          'image/png',
          'image/jpeg',
        }.contains(document.original?.original.mediaType)) {
      return const GlacierPreviewPlaceholder();
    }
    if (!state.failed ||
        document.thumbnail == null ||
        !cubit.capabilities.preview) {
      return Center(
        child: Icon(
          Icons.description_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        semanticLabel: 'Preview unavailable',
      ),
    );
  }
}
