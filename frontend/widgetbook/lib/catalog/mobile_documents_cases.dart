import 'dart:ui' show ImageFilter;

import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'mobile_catalog.dart';

const _screens = <String, (String, String, List<String>)>{
  'documents': (
    'Documents',
    'GlacierMobileDocumentCollection',
    [
      'ready',
      'loading',
      'empty',
      'no-match',
      'error',
      'stale',
      'page-error',
      'read-only',
      'selection',
    ],
  ),
  'search': (
    'Search and filters',
    'GlacierMobileSearchFilters',
    ['ready', 'keyboard', 'validation'],
  ),
  'reader': (
    'Original and text reader',
    'GlacierMobileReader',
    [
      'ready',
      'text',
      'find',
      'image',
      'email',
      'locked',
      'missing',
      'error',
      'deleted',
      'read-only',
    ],
  ),
  'properties': (
    'Document properties and links',
    'GlacierMobileDocumentProperties',
    ['ready', 'conflict', 'uncertain', 'deleted', 'saving'],
  ),
  'capture': (
    'Native scan handoff',
    'GlacierMobileScanHandoff',
    [
      'ready',
      'permission',
      'unavailable',
      'restored',
      'storage-error',
      'pending',
      'limit',
    ],
  ),
  'scan-review': (
    'Scan draft review',
    'GlacierMobileScanReview',
    ['ready', 'reorder', 'pending', 'recovery'],
  ),
  'upload': (
    'Upload and metadata',
    'GlacierMobileUploadForm',
    [
      'ready',
      'metadata',
      'sending',
      'accepted',
      'rejected',
      'duplicate',
      'uncertain',
    ],
  ),
  'upload-receipts': (
    'Upload receipts',
    'GlacierMobileUploadReceipts',
    ['ready', 'page-error'],
  ),
  'share-android': (
    'Android incoming sharing',
    'GlacierMobileIncomingShare',
    ['ready', 'auth', 'blocked', 'existing', 'uncertain'],
  ),
  'share-ios': (
    'iOS share extension',
    'GlacierMobileShareExtension',
    ['ready', 'setup', 'sending', 'accepted', 'uncertain'],
  ),
};

List<CatalogCase> mobileDocumentsCases() => [
  for (final screen in _screens.entries)
    for (final state in screen.value.$3)
      mobileScreenCase(
        screen: screen.key,
        state: state,
        title: screen.value.$1,
        widgetType:
            screen.key == 'upload' && !['ready', 'metadata'].contains(state)
            ? 'GlacierMobileUploadOutcome'
            : screen.value.$2,
        domain: 'Mobile documents',
        builder: (_) =>
            _MobileDocumentsExample(screen: screen.key, state: state),
      ),
  ..._componentCases(),
];

const _records = [
  GlacierDocumentValue(
    id: 'forma',
    title: 'Forma Studio',
    sender: 'Invoice · November',
    tags: ['Invoice'],
    date: '12 Nov',
    busy: true,
  ),
  GlacierDocumentValue(
    id: 'insurance',
    title: 'Home insurance',
    sender: 'Nord & Co.',
    tags: ['Insurance'],
    date: '10 Nov',
  ),
  GlacierDocumentValue(
    id: 'energy',
    title: 'Energy statement',
    sender: 'Stadtwerke Berlin',
    tags: ['Home'],
    date: '09 Nov',
    failed: true,
  ),
  GlacierDocumentValue(
    id: 'rental',
    title: 'Rental agreement',
    sender: 'Oak Street 12',
    tags: ['Home'],
    date: '02 Nov',
  ),
  GlacierDocumentValue(
    id: 'booking',
    title: 'Booking confirmation',
    sender: 'North Rail',
    tags: ['Travel'],
    date: '30 Oct',
    type: 'EML',
  ),
  GlacierDocumentValue(
    id: 'warranty',
    title: 'Kitchen warranty',
    sender: 'Atelier Home',
    tags: ['Warranty'],
    date: '24 Oct',
  ),
  GlacierDocumentValue(
    id: 'notes',
    title: 'Home project notes',
    sender: 'Scanned document',
    tags: ['Home'],
    date: '17 Nov',
  ),
];

class _MobileDocumentsExample extends StatefulWidget {
  const _MobileDocumentsExample({required this.screen, required this.state});
  final String screen, state;
  @override
  State<_MobileDocumentsExample> createState() =>
      _MobileDocumentsExampleState();
}

class _MobileDocumentsExampleState extends State<_MobileDocumentsExample> {
  late String screen = widget.screen, state = widget.state;
  String source = 'forma', type = 'All';
  bool list = false, selecting = false, nextLoaded = false, fileChosen = true;
  bool sourceInitialized = false;
  final selected = <String>{'forma', 'insurance'};
  final pages = <String>['page-1', 'page-2', 'page-3'];
  int nextPage = 4, readerPage = 1, match = 1;
  int? acceptedNotesPages;
  double zoom = 1;
  GlacierMobileSearchValue search = const GlacierMobileSearchValue();
  final find = TextEditingController(text: 'Forma');
  final scanTitle = TextEditingController(text: 'Home project notes');
  final scanDate = TextEditingController(text: '2026-11-17');
  final scanTags = TextEditingController(text: 'Home');
  final extracted = TextEditingController();
  final propertyDrafts = <String, Map<String, String>>{};
  final propertyTags = <String, List<String>>{};
  bool scanDetails = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!sourceInitialized) {
      final argument = ModalRoute.of(context)?.settings.arguments;
      if (argument is String && _records.any((r) => r.id == argument)) {
        source = argument;
      }
      sourceInitialized = true;
      extracted.text = _textFor(source);
      selecting = state == 'selection';
    }
  }

  @override
  void dispose() {
    for (final c in [find, scanTitle, scanDate, scanTags, extracted]) {
      c.dispose();
    }
    super.dispose();
  }

  GlacierDocumentValue get document =>
      _records.firstWhere((r) => r.id == source);
  void go(String next, [String nextState = 'ready']) {
    if (!_screens.containsKey(next)) {
      mobileCatalogNavigate(context, next, state: nextState);
      return;
    }
    setState(() {
      screen = next;
      state = nextState;
    });
  }

  void notify(String message) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(
        SnackBar(
          content: Text('Preview: $message'),
          duration: const Duration(seconds: 2),
        ),
      );
  void open(GlacierDocumentValue record) {
    setState(() {
      source = record.id;
      extracted.text = _textFor(source);
      readerPage = 1;
      screen = 'reader';
      state = record.id == 'booking' ? 'email' : 'ready';
    });
  }

  void back() {
    if (screen == 'scan-review') {
      confirmDiscard();
      return;
    }
    if (screen == 'properties') {
      go('reader');
      return;
    }
    if (widget.screen != 'documents' &&
        screen == widget.screen &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    go('documents');
  }

  Future<void> openSearch() async {
    final result = await showGlacierMobileSheet<GlacierMobileSearchValue>(
      context: context,
      builder: (sheetContext) => GlacierMobileSearchFilters(
        library: mobileCatalogLibrary(context),
        value: search,
        onApply: (value) => Navigator.of(sheetContext).pop(value),
        onCancel: () => Navigator.of(sheetContext).pop(),
        onMoreTags: () => notify('next vocabulary page loaded'),
      ),
    );
    if (mounted && result != null) {
      setState(() {
        search = result;
        state = 'ready';
        screen = 'documents';
      });
    }
  }

  void confirmDiscard() {
    showGlacierMobileSheet<void>(
      context: context,
      builder: (sheetContext) => GlacierMobileSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Discard this draft?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'The saved pages and unsent changes in Personal library will be removed.',
            ),
            const SizedBox(height: 16),
            GlacierMobileActionBar(
              children: [
                GlacierButton(
                  label: 'Keep draft',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
                GlacierButton(
                  label: 'Discard draft',
                  kind: GlacierButtonKind.danger,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    setState(() {
                      pages.clear();
                      screen = 'documents';
                      state = 'ready';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void confirmDelete() {
    showGlacierMobileSheet<void>(
      context: context,
      builder: (sheetContext) => GlacierMobileSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Delete ${document.title}?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'This removes the document from Personal library. This action cannot be undone.',
            ),
            const SizedBox(height: 16),
            GlacierMobileActionBar(
              children: [
                GlacierButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
                GlacierButton(
                  label: 'Delete document',
                  kind: GlacierButtonKind.danger,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    go('documents');
                    notify('document deletion confirmed');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSearch = screen == 'search';
    final isExtension = screen == 'share-ios';
    final primary = screen == 'documents' || isSearch;
    final title = switch (screen) {
      'reader' => document.title,
      'properties' => 'Properties & links',
      'capture' => 'Scan a document',
      'scan-review' => 'Review scan',
      'upload' => 'Upload documents',
      'share-android' => 'Shared files',
      'share-ios' => 'Save to Domabas',
      'search' => 'Documents',
      _ => _screens[screen]!.$1,
    };
    final shell = mobileCatalogShell(
      context,
      title: title,
      subtitle: isExtension ? 'iOS share extension' : 'Personal library',
      onBack: primary || isExtension ? null : back,
      showLibrary: primary,
      showNavigation: !isExtension,
      captureEnabled: state != 'read-only',
      actions: [
        if (primary)
          GlacierIconButton(
            label: 'Upload documents',
            icon: Icons.upload_outlined,
            onPressed: state == 'read-only' ? null : () => go('upload'),
          ),
        if (isExtension)
          GlacierIconButton(
            label: 'Close extension',
            icon: Icons.close,
            onPressed: () => notify('extension closes without uploading'),
          ),
      ],
      child: _body(context, isSearch ? 'documents' : screen),
    );
    if (!isSearch) return shell;
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: GlacierTokens.of(context).opaque ? 0 : 6,
            sigmaY: GlacierTokens.of(context).opaque ? 0 : 6,
          ),
          child: ExcludeFocus(child: ExcludeSemantics(child: shell)),
        ),
        Positioned.fill(child: const ColoredBox(color: Color(0x2409252B))),
        GlacierMobileSearchFilters(
          library: mobileCatalogLibrary(context),
          value: search,
          validationMessage: state == 'validation'
              ? 'The start date must be on or before the end date.'
              : null,
          onApply: (value) {
            setState(() => search = value);
            go('documents');
          },
          onCancel: () => go('documents'),
          onMoreTags: () => notify('next vocabulary page loaded'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, String route) => switch (route) {
    'documents' => _documents(),
    'reader' => _reader(),
    'properties' => _properties(),
    'capture' => _capture(),
    'scan-review' => _scanReview(),
    'upload' => _upload(),
    'upload-receipts' => _receipts(),
    'share-android' => _androidShare(),
    'share-ios' => _iosShare(),
    _ => const SizedBox.shrink(),
  };
  Widget _documents() {
    final query = search.query.toLowerCase();
    final filtered =
        query.isNotEmpty ||
        type != 'All' ||
        search.types.isNotEmpty ||
        search.tags.isNotEmpty ||
        search.sender.isNotEmpty ||
        search.recipient.isNotEmpty ||
        search.from.isNotEmpty ||
        search.through.isNotEmpty;
    final shown = _records.take(filtered || nextLoaded ? 7 : 6).where((record) {
      final terms = '${record.title} ${record.sender} ${record.tags.join(' ')}'
          .toLowerCase();
      final kind = record.type == 'EML' ? 'Email' : record.type;
      return (query.isEmpty || terms.contains(query)) &&
          (type == 'All' || type == kind) &&
          (search.types.isEmpty || search.types.contains(kind)) &&
          search.tags.every(record.tags.contains) &&
          (search.sender.isEmpty ||
              terms.contains(search.sender.toLowerCase())) &&
          (search.recipient.isEmpty ||
              'alex morgan'.contains(search.recipient.toLowerCase())) &&
          (search.from.isEmpty ||
              _dateFor(record.id).compareTo(search.from) >= 0) &&
          (search.through.isEmpty ||
              _dateFor(record.id).compareTo(search.through) <= 0);
    }).toList();
    if (search.sort == 'Title') {
      shown.sort((a, b) => a.title.compareTo(b.title));
    } else if (search.sort == 'Oldest first') {
      shown.sort((a, b) => _dateFor(a.id).compareTo(_dateFor(b.id)));
    }
    final status = switch (state) {
      'loading' => GlacierMobileCollectionState.loading,
      'empty' => GlacierMobileCollectionState.empty,
      'no-match' => GlacierMobileCollectionState.noMatch,
      'error' => GlacierMobileCollectionState.error,
      'stale' => GlacierMobileCollectionState.stale,
      'page-error' => GlacierMobileCollectionState.pageError,
      'read-only' => GlacierMobileCollectionState.readOnly,
      _ =>
        shown.isEmpty
            ? GlacierMobileCollectionState.noMatch
            : GlacierMobileCollectionState.ready,
    };
    return GlacierMobileDocumentCollection(
      documents: shown,
      state: status,
      list: list,
      selectedIds: selecting ? selected : null,
      previewBuilder: (record) => _Paper(record: record.id, miniature: true),
      onOpen: open,
      onRetry: (record) =>
          notify('retry requested for ${record.title}; original retained'),
      onSelectionChanged: (record, value) => setState(() {
        value ? selected.add(record.id) : selected.remove(record.id);
      }),
      onSelect: () => setState(() => selecting = !selecting),
      onToggleView: () => setState(() => list = !list),
      onRefresh: () => go('documents'),
      onScan: () => go('capture'),
      onUpload: () => go('upload'),
      onEditSearch: openSearch,
      onClearSearch: () => setState(() {
        search = const GlacierMobileSearchValue();
        type = 'All';
        state = 'ready';
      }),
      caption: !filtered
          ? 'Recently added · ${mobileCatalogLibrary(context)}'
          : '${shown.length} ${shown.length == 1 ? 'match' : 'matches'} · ${mobileCatalogLibrary(context)}',
      selectionBar: selecting
          ? GlacierMobileDocumentSelectionBar(
              count: selected.length,
              onEditTags: () => go('properties'),
              onDelete: confirmDelete,
              onDone: () => setState(() => selecting = false),
            )
          : null,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlacierMobileSearchEntry(
            label: search.query.isEmpty ? 'Find a document' : search.query,
            onPressed: openSearch,
          ),
          GlacierMobileDocumentFilters(
            selected: type,
            onChanged: (value) => setState(() => type = value),
          ),
          if (search.query.isNotEmpty ||
              search.tags.isNotEmpty ||
              search.types.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  '${mobileCatalogLibrary(context)} · ${[search.query, ...search.tags, ...search.types].where((v) => v.isNotEmpty).join(' · ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                GlacierButton(
                  label: 'Clear',
                  kind: GlacierButtonKind.quiet,
                  onPressed: () =>
                      setState(() => search = const GlacierMobileSearchValue()),
                ),
              ],
            ),
        ],
      ),
      continuation: GlacierMobileContinuation(
        label: filtered
            ? '${shown.length} matching ${shown.length == 1 ? 'document' : 'documents'} shown'
            : nextLoaded
            ? 'All example results loaded'
            : '6 of 248 documents',
        error: state == 'page-error'
            ? 'These documents remain available.'
            : null,
        onRetry: () => setState(() {
          state = 'ready';
          nextLoaded = true;
        }),
        onLoadMore: filtered || nextLoaded
            ? null
            : () => setState(() => nextLoaded = true),
      ),
      activity: GlacierMobileActivitySummary(
        label: '2 jobs in progress',
        detail: 'Indexing Forma Studio · 1 waiting',
        running: true,
        onOpen: () => go('jobs'),
      ),
    );
  }

  Widget _reader() {
    final view = GlacierMobileReaderState.values.firstWhere(
      (value) =>
          value.name == state ||
          (state == 'read-only' && value == GlacierMobileReaderState.readOnly),
      orElse: () => GlacierMobileReaderState.ready,
    );
    return GlacierMobileReader(
      state: view,
      original: Transform.scale(
        scale: zoom,
        alignment: Alignment.topCenter,
        child: _Paper(record: state == 'image' ? 'warranty' : source),
      ),
      textController: extracted,
      onOriginal: () => go('reader'),
      onText: () => go('reader', 'text'),
      onFind: () => go('reader', state == 'find' ? 'ready' : 'find'),
      onSaveText: () => notify('text changes retained in this example'),
      onRevisions: () => notify('2 retained revisions'),
      onProperties: () => go('properties'),
      onResync: () => go('job-detail', 'ingestion'),
      onDownload: () => notify('original download requested'),
      onDelete: confirmDelete,
      onRetry: () => go('reader'),
      onUnlock: () => go('reader'),
      onCopy: () => notify('retained text copied'),
      pageLabel:
          'Page $readerPage of ${source == 'notes' ? acceptedNotesPages ?? 3 : 3}',
      onPreviousPage: readerPage <= 1
          ? null
          : () => setState(() => readerPage--),
      onNextPage: readerPage >= (source == 'notes' ? pages.length : 3)
          ? null
          : () => setState(() => readerPage++),
      onFit: () => setState(() => zoom = 1),
      onZoomIn: () => setState(() => zoom = zoom >= 1.2 ? 1 : zoom + .1),
      findBar: GlacierMobileReaderFindBar(
        controller: find,
        matchLabel: '$match/2',
        onChanged: (_) => setState(() => match = 1),
        onPrevious: () => setState(() => match = match == 1 ? 2 : 1),
        onNext: () => setState(() => match = match == 1 ? 2 : 1),
      ),
      properties: GlacierMobileRecordRow(
        title: 'Properties & links',
        detail: '${document.tags.join(' · ')} · 2 related documents',
        icon: Icons.edit_outlined,
        onTap: () => go('properties'),
      ),
      processing: GlacierMobileRecordRow(
        title: 'Indexing in progress',
        detail: 'Original saved · text extracted',
        icon: Icons.show_chart,
        onTap: () => go('job-detail', 'ingestion'),
      ),
      email: GlacierMobileSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Booking confirmation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'From bookings@north-rail.example\nTo alex@example.test',
            ),
            const SizedBox(height: 12),
            const Text(
              'Your journey on 30 November is confirmed. Your original ticket is attached.',
            ),
            const SizedBox(height: 12),
            GlacierMobileRecordRow(
              title: 'Ticket.pdf',
              detail: 'Related attachment · 1 page',
              icon: Icons.link,
              onTap: () => go('reader'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _properties() => GlacierMobileDocumentProperties(
    key: ValueKey(source),
    values:
        propertyDrafts[source] ??
        {
          'Title': document.title,
          'Description': 'Design consultation for the home project',
          'Document type': document.tags.first,
          'Document date': source == 'energy' ? '2026-11-09' : '2026-11-12',
          'Sender': source == 'forma' ? 'Forma Studio' : document.sender,
          'Recipients': 'Alex Morgan',
        },
    tags:
        propertyTags[source] ??
        (source == 'forma' ? const ['Invoice', 'Home'] : document.tags),
    state: GlacierMobileEditState.values.firstWhere(
      (v) => v.name == state,
      orElse: () => GlacierMobileEditState.ready,
    ),
    onSave: (values) {
      propertyDrafts[source] = values;
      notify('properties saved for ${document.title}');
    },
    onDraftChanged: (values) => propertyDrafts[source] = values,
    onRecover: () => setState(() => state = 'ready'),
    onCopyDraft: () => notify('draft copied'),
    onAddTag: () => setState(() {
      final tags = propertyTags.putIfAbsent(
        source,
        () => List<String>.of(
          source == 'forma' ? ['Invoice', 'Home'] : document.tags,
        ),
      );
      if (!tags.contains('Reviewed')) tags.add('Reviewed');
    }),
    onRemoveTag: (tag) => setState(() {
      propertyTags
          .putIfAbsent(
            source,
            () => List<String>.of(
              source == 'forma' ? ['Invoice', 'Home'] : document.tags,
            ),
          )
          .remove(tag);
    }),
    links: Column(
      children: [
        GlacierMobileRecordRow(
          title: 'Project agreement',
          detail: 'Original · 2 November 2026',
          icon: Icons.link,
          onTap: () => open(_records[3]),
        ),
        const SizedBox(height: 8),
        GlacierMobileRecordRow(
          title: 'Confirmation email',
          detail: 'Email · 4 November 2026',
          icon: Icons.mail_outline,
          onTap: () => open(_records[4]),
        ),
        GlacierMobileContinuation(
          label: '2 related documents',
          onLoadMore: () => notify('next related page loaded'),
        ),
      ],
    ),
    revisions: GlacierMobileRecordRow(
      title: 'Current revision',
      detail: 'Updated 12 November · Alex Morgan',
      icon: Icons.schedule,
      onTap: () => notify('revision history opened'),
    ),
  );
  Widget _capture() => GlacierMobileScanHandoff(
    library: mobileCatalogLibrary(context),
    platform: Theme.of(context).platform,
    state: switch (state) {
      'storage-error' => GlacierMobileCaptureState.storageError,
      _ => GlacierMobileCaptureState.values.firstWhere(
        (v) => v.name == state,
        orElse: () => GlacierMobileCaptureState.ready,
      ),
    },
    savedPages: pages.length,
    onScan: () {
      if (state != 'restored') {
        pages.clear();
        pages.addAll(
          Theme.of(context).platform == TargetPlatform.iOS
              ? ['page-1', 'page-2', 'page-3']
              : ['page-1'],
        );
        nextPage = pages.length + 1;
      }
      go('scan-review');
    },
    onUpload: () => go('upload'),
    onSettings: () => notify('system settings handoff'),
    onCheckAvailability: () => notify('availability rechecked'),
    onKeepPage: () => go('scan-review'),
    onReview: () => go('scan-review'),
    onRetryPending: () => go('scan-review'),
    onDiscardPending: () => go('scan-review'),
    onDiscardDraft: confirmDiscard,
  );
  Widget _scanReview() => GlacierMobileScanReview(
    library: mobileCatalogLibrary(context),
    pages: [
      for (final id in pages)
        GlacierMobileScanPageValue(
          id: id,
          preview: const _Paper(record: 'forma', miniature: true),
        ),
    ],
    state: GlacierMobileScanState.values.firstWhere(
      (v) => v.name == state,
      orElse: () => GlacierMobileScanState.ready,
    ),
    onMove: (id, destination) => setState(() {
      pages.remove(id);
      pages.insert(destination, id);
    }),
    onRemove: (id) => setState(() => pages.remove(id)),
    onAddPage: () => setState(() => pages.add('page-${nextPage++}')),
    onDiscard: confirmDiscard,
    onUpload: () => go('upload', 'sending'),
    onRetryPending: () => setState(() => state = 'ready'),
    onDiscardPending: () => setState(() => state = 'ready'),
    onRecover: () => setState(() => state = 'ready'),
    details: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlacierMobileField(label: 'Title', controller: scanTitle),
        GlacierMobileField(label: 'Document date', controller: scanDate),
        GlacierMobileField(label: 'Tags', controller: scanTags),
        TextButton(
          onPressed: () => setState(() => scanDetails = !scanDetails),
          child: Row(
            children: [
              Icon(scanDetails ? Icons.arrow_drop_down : Icons.arrow_right),
              const Flexible(child: Text('More properties')),
            ],
          ),
        ),
        if (scanDetails)
          for (final field in const [
            'Description',
            'Kind',
            'Sender',
            'Recipients',
            'CC',
            'BCC',
            'Subject',
            'Message ID',
          ])
            GlacierMobileField(
              label: field,
              initialValue: field == 'Kind' ? 'Document' : '',
              maxLines: field == 'Description' ? 3 : 1,
            ),
      ],
    ),
  );
  Widget _upload() {
    if (['ready', 'metadata'].contains(state)) {
      return GlacierMobileUploadForm(
        library: mobileCatalogLibrary(context),
        key: ValueKey(state),
        metadataOnly: state == 'metadata',
        filename: fileChosen ? 'Home project notes.pdf' : '',
        fileDetail: '${pages.length} pages · 2.4 MB · example file',
        values: state == 'metadata'
            ? const {}
            : {
                'Title': scanTitle.text,
                'Tags': scanTags.text,
                'Document date': scanDate.text,
              },
        onChooseFiles: () => setState(() => fileChosen = true),
        onRemoveFile: () => setState(() => fileChosen = false),
        onLibrary: () => go('library'),
        onMetadataOnly: () => go('upload', 'metadata'),
        onSubmit: (values) {
          if (state == 'metadata') {
            notify('metadata record created');
            go('documents');
          } else {
            go('upload', 'sending');
          }
        },
      );
    }
    return GlacierMobileUploadOutcome(
      state: GlacierMobileUploadState.values.firstWhere(
        (v) => v.name == state,
        orElse: () => GlacierMobileUploadState.uncertain,
      ),
      filename: 'Home project notes.pdf',
      detail: '${pages.length} pages · ${mobileCatalogLibraryLabel(context)}',
      onCheck: () {
        acceptedNotesPages = pages.length;
        go('upload', 'accepted');
      },
      onOpen: () {
        acceptedNotesPages ??= pages.length;
        open(_records.last);
      },
      onProcessing: () => go('job-detail', 'ingestion'),
      onChooseAnother: () => go('upload'),
      onBack: () => go('documents'),
    );
  }

  Widget _receipts() => GlacierMobileUploadReceipts(
    receipts: [
      GlacierMobileReceiptValue(
        filename: 'Home project notes.pdf',
        detail: 'Accepted · processing continues',
        icon: Icons.check,
        onOpen: () => go('upload', 'accepted'),
      ),
      GlacierMobileReceiptValue(
        filename: 'Energy statement.pdf',
        detail: 'Receipt unknown · check before retry',
        icon: Icons.schedule,
        onOpen: () => go('upload', 'uncertain'),
      ),
      GlacierMobileReceiptValue(
        filename: 'Kitchen warranty.pdf',
        detail: 'Duplicate · existing original retained',
        onOpen: () => go('upload', 'duplicate'),
      ),
    ],
    continuation: GlacierMobileContinuation(
      label: '3 recent uploads',
      error: state == 'page-error'
          ? 'Existing receipts remain available.'
          : null,
      onRetry: () => setState(() => state = 'ready'),
      onLoadMore: nextLoaded ? null : () => setState(() => nextLoaded = true),
    ),
  );
  List<GlacierMobileReceiptValue> get sharedFiles => const [
    GlacierMobileReceiptValue(
      filename: 'Home project notes.pdf',
      detail: '2.4 MB · PDF',
    ),
    GlacierMobileReceiptValue(
      filename: 'Receipt.jpg',
      detail: '860 KB · JPEG',
      icon: Icons.image_outlined,
    ),
  ];
  GlacierMobileShareState get shareState =>
      GlacierMobileShareState.values.firstWhere(
        (v) => v.name == state,
        orElse: () => GlacierMobileShareState.ready,
      );
  Widget _androidShare() => GlacierMobileIncomingShare(
    files: sharedFiles,
    state: shareState,
    serverAndAccount: 'domabas.home · alex@example.test',
    onSignIn: () => go('signin'),
    onLibrary: () => go('library'),
    onReviewWaiting: () => go('share-android'),
    onDiscardWaiting: confirmDiscard,
    onCheck: () => go('share-android', 'accepted'),
    onUpload: () => go('share-android', 'sending'),
    onCancel: back,
  );
  Widget _iosShare() => GlacierMobileShareExtension(
    files: sharedFiles,
    state: shareState,
    serverAndAccount: 'domabas.home · alex@example.test',
    onCheck: () => go('share-ios', 'accepted'),
    onUpload: () => go('share-ios', 'sending'),
    onClose: () => notify('extension closed'),
  );
}

String _dateFor(String id) => switch (id) {
  'forma' => '2026-11-12',
  'insurance' => '2026-11-10',
  'energy' => '2026-11-09',
  'rental' => '2026-11-02',
  'booking' => '2026-10-30',
  'warranty' => '2026-10-24',
  _ => '2026-11-17',
};

String _textFor(String id) => switch (id) {
  'forma' => 'FORMA STUDIO\n\nInvoice FS-2026-042\n12 November 2026\n\nTo Alex Morgan\nOak Street 12, Berlin\n\nDesign consultation €1,500.00\nVAT 19% €285.00\nTotal EUR €1,785.00',
  'energy' => 'STADTWERKE BERLIN\n\nInvoice SW-2026-1182\n9 November 2026\n\nEnergy supply €120.00\nVAT 19% €22.80\nTotal EUR €142.80',
  _ =>
    '${_records.firstWhere((r) => r.id == id).title}\n\nAlex Morgan\nOak Street 12, Berlin\n\nDocument text retained from the original.',
};

class _Paper extends StatelessWidget {
  const _Paper({required this.record, this.miniature = false});
  final String record;
  final bool miniature;
  @override
  Widget build(BuildContext context) {
    final forma = record == 'forma', energy = record == 'energy';
    final name = switch (record) {
      'forma' => 'FORMA STUDIO',
      'energy' => 'STADTWERKE BERLIN',
      'insurance' => 'NORD & CO.',
      'rental' => 'OAK STREET 12',
      'booking' => 'NORTH RAIL',
      'warranty' => 'ATELIER HOME',
      _ => 'HOME PROJECT',
    };
    final title = forma
        ? 'Invoice'
        : _records
              .firstWhere((r) => r.id == record, orElse: () => _records.last)
              .title;
    final text = DefaultTextStyle(
      style: TextStyle(
        fontFamily: 'DMSans',
        fontSize: miniature ? 4 : 11,
        height: 1.6,
        color: const Color(0xFF293B3D),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: miniature ? 8 : 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: miniature ? 6 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (forma)
                  Text(
                    'FS',
                    style: TextStyle(
                      fontSize: miniature ? 6 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFDCE5E3)),
          SizedBox(height: miniature ? 11 : 30),
          Text(
            title,
            style: TextStyle(
              fontSize: miniature ? 8 : 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: miniature ? 6 : 16),
          Text(
            forma
                ? 'FS-2026-042 · 12 November 2026'
                : energy
                ? 'SW-2026-1182 · 9 November 2026'
                : 'Personal library original',
          ),
          SizedBox(height: miniature ? 3 : 4),
          const Text('To Alex Morgan\nOak Street 12, Berlin'),
          SizedBox(height: miniature ? 5 : 8),
          const Divider(height: 2, thickness: 2, color: Color(0xFFDCE5E3)),
          SizedBox(height: miniature ? 5 : 6),
          const FractionallySizedBox(
            widthFactor: .65,
            alignment: Alignment.centerLeft,
            child: Divider(height: 2, thickness: 2, color: Color(0xFFDCE5E3)),
          ),
          SizedBox(height: miniature ? 9 : 30),
          for (final line in <(String, String)>[
            if (forma)
              ('Design consultation', '€1,500.00')
            else if (energy)
              ('Energy supply', '€120.00')
            else
              ('Document details', ''),
            if (forma || energy) ('VAT · 19%', forma ? '€285.00' : '€22.80'),
          ]) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: miniature ? 3 : 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.$1,
                      style: TextStyle(fontSize: miniature ? 4 : 10),
                    ),
                  ),
                  Text(line.$2, style: TextStyle(fontSize: miniature ? 4 : 10)),
                ],
              ),
            ),
            const Divider(height: 1, thickness: .5, color: Color(0xFFE4EAE8)),
          ],
          if (forma || energy)
            Padding(
              padding: EdgeInsets.only(top: miniature ? 8 : 20),
              child: Text(
                forma ? '€1,785.00' : '€142.80',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: miniature ? 6 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SizedBox(height: miniature ? 3 : 6),
          Text(
            forma
                ? 'Thank you for working with us.'
                : 'Keep this original for your records.',
          ),
        ],
      ),
    );
    final page = MediaQuery.withNoTextScaling(
      child: ClipRect(
        child: Container(
          width: miniature ? 98 : double.infinity,
          height: miniature ? 137 : null,
          constraints: miniature ? null : const BoxConstraints(minHeight: 440),
          padding: miniature
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 13)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x1A1A3035),
                offset: Offset(0, 3),
                blurRadius: 8,
              ),
            ],
          ),
          child: miniature
              ? OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: text,
                )
              : text,
        ),
      ),
    );
    return miniature ? Center(child: page) : page;
  }
}

List<CatalogCase> _componentCases() {
  CatalogCase isolated(
    String id,
    String type,
    String reference,
    WidgetBuilder builder, {
    bool full = false,
  }) => mobileComponentCase(
    id: id,
    title: type.replaceFirst('GlacierMobile', ''),
    widgetType: type,
    referenceComponent: reference,
    domain: 'Mobile document components',
    builder: (context) => full
        ? builder(context)
        : mobileCatalogShell(
            context,
            title: type.replaceFirst('GlacierMobile', ''),
            showNavigation: false,
            showLibrary: false,
            child: builder(context),
          ),
  );
  return [
    isolated(
      'document-filters',
      'GlacierMobileDocumentFilters',
      'quick-filters',
      (_) => GlacierMobileDocumentFilters(onChanged: (_) {}),
    ),
    isolated(
      'document-card',
      'GlacierMobileDocumentCard',
      'document-card',
      (_) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 174,
          child: GlacierMobileDocumentCard(
            document: _records[2],
            preview: const _Paper(record: 'energy', miniature: true),
            onOpen: () {},
            onRetry: () {},
          ),
        ),
      ),
    ),
    isolated(
      'document-collection',
      'GlacierMobileDocumentCollection',
      'collection-state',
      (_) => const _MobileDocumentsExample(screen: 'documents', state: 'empty'),
      full: true,
    ),
    isolated(
      'document-selection',
      'GlacierMobileDocumentSelectionBar',
      'selection-bar',
      (_) => GlacierMobileDocumentSelectionBar(
        count: 2,
        onEditTags: () {},
        onDelete: () {},
        onDone: () {},
      ),
    ),
    isolated(
      'document-search-filters',
      'GlacierMobileSearchFilters',
      'search-filters',
      (_) => const _MobileDocumentsExample(screen: 'search', state: 'ready'),
      full: true,
    ),
    isolated(
      'reader-toolbar',
      'GlacierMobileReaderToolbar',
      'reader-toolbar',
      (_) => GlacierMobileReaderToolbar(
        onProperties: () {},
        onResync: () {},
        onDownload: () {},
        onDelete: () {},
      ),
    ),
    isolated(
      'original-canvas',
      'GlacierMobileOriginalCanvas',
      'original-canvas',
      (_) => const GlacierMobileOriginalCanvas(child: _Paper(record: 'forma')),
    ),
    isolated(
      'reader-find',
      'GlacierMobileReaderFindBar',
      'reader-find',
      (_) => const _FindExample(),
    ),
    isolated(
      'document-reader',
      'GlacierMobileReader',
      'reader-toolbar',
      (_) => const _MobileDocumentsExample(screen: 'reader', state: 'ready'),
      full: true,
    ),
    isolated(
      'document-properties',
      'GlacierMobileDocumentProperties',
      'properties-editor',
      (_) =>
          const _MobileDocumentsExample(screen: 'properties', state: 'ready'),
      full: true,
    ),
    isolated(
      'scan-handoff',
      'GlacierMobileScanHandoff',
      'scan-handoff',
      (_) => const _MobileDocumentsExample(screen: 'capture', state: 'ready'),
      full: true,
    ),
    isolated(
      'scan-page',
      'GlacierMobileScanPage',
      'scan-page',
      (_) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 174,
          child: GlacierMobileScanPage(
            number: 2,
            preview: const _Paper(record: 'forma', miniature: true),
            onEarlier: () {},
            onLater: () {},
            onRemove: () {},
          ),
        ),
      ),
    ),
    isolated(
      'scan-review',
      'GlacierMobileScanReview',
      'scan-draft',
      (_) =>
          const _MobileDocumentsExample(screen: 'scan-review', state: 'ready'),
      full: true,
    ),
    isolated(
      'upload-form',
      'GlacierMobileUploadForm',
      'upload-form',
      (_) => const _MobileDocumentsExample(screen: 'upload', state: 'ready'),
      full: true,
    ),
    isolated(
      'upload-outcome',
      'GlacierMobileUploadOutcome',
      'upload-outcome',
      (_) =>
          const _MobileDocumentsExample(screen: 'upload', state: 'uncertain'),
      full: true,
    ),
    isolated(
      'upload-receipts',
      'GlacierMobileUploadReceipts',
      'upload-outcome',
      (_) => const _MobileDocumentsExample(
        screen: 'upload-receipts',
        state: 'ready',
      ),
      full: true,
    ),
    isolated(
      'incoming-share',
      'GlacierMobileIncomingShare',
      'incoming-share',
      (_) => const _MobileDocumentsExample(
        screen: 'share-android',
        state: 'ready',
      ),
      full: true,
    ),
    isolated(
      'share-extension',
      'GlacierMobileShareExtension',
      'share-extension',
      (_) => const _MobileDocumentsExample(screen: 'share-ios', state: 'ready'),
      full: true,
    ),
  ];
}

class _FindExample extends StatefulWidget {
  const _FindExample();
  @override
  State<_FindExample> createState() => _FindExampleState();
}

class _FindExampleState extends State<_FindExample> {
  final controller = TextEditingController(text: 'Forma');
  int match = 1;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlacierMobileReaderFindBar(
    controller: controller,
    matchLabel: '$match/2',
    onPrevious: () => setState(() => match = match == 1 ? 2 : 1),
    onNext: () => setState(() => match = match == 1 ? 2 : 1),
  );
}
