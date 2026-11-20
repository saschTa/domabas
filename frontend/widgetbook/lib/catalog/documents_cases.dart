import 'dart:convert';
import 'dart:typed_data';

import 'package:domabas/presentation/document/widgets/document_canvas.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';

import 'catalog_frame.dart';

CatalogCase _case(
  String id,
  String component,
  String name,
  String widget,
  WidgetBuilder builder, {
  String domain = 'Documents',
  String description = '',
}) => CatalogCase(
  id: id,
  domain: domain,
  component: component,
  name: name,
  widgetType: widget,
  builder: builder,
  description: description,
);

List<CatalogCase> documentsCases() => [
  _case(
    'document-row',
    'Document row',
    'Compact record',
    'GlacierDocumentRow',
    (_) => CatalogFrame(
      child: GlacierDocumentRow(document: _document(), onOpen: () {}),
    ),
  ),
  _case(
    'document-property-grid',
    'Properties',
    'Missing and long values',
    'GlacierPropertyGrid',
    (_) => const CatalogFrame(
      child: GlacierPropertyGrid(
        values: {
          'Sender': 'Lumen Energy',
          'Recipients': 'Alex Morgan and household',
          'Document date': '',
          'Message ID': 'A-long-source-message-identifier@example.test',
        },
      ),
    ),
  ),
  _case(
    'document-related-links',
    'Related documents',
    'Email and attachments',
    'GlacierRelatedDocuments',
    (_) => CatalogFrame(
      child: GlacierRelatedDocuments(
        documents: [
          GlacierRelatedDocument(
            title: 'Your order has arrived',
            relationship: 'Source email',
            onOpen: () {},
          ),
          const GlacierRelatedDocument(
            title: 'Restricted attachment',
            relationship: 'Access unavailable',
          ),
        ],
      ),
    ),
  ),
  _case(
    'document-pdf-toolbar',
    'PDF controls',
    'Page and zoom',
    'GlacierPdfToolbar',
    (_) => CatalogFrame(
      child: GlacierPdfToolbar(
        page: 1,
        pageCount: 6,
        zoomLabel: '100%',
        onNext: () {},
        onZoomIn: () {},
        onZoomOut: () {},
        onFit: () {},
        onFind: () {},
      ),
    ),
  ),
  _case(
    'document-original-state',
    'Original fallback',
    'Unavailable',
    'GlacierOriginalState',
    (_) => Scaffold(
      backgroundColor: Colors.transparent,
      body: GlacierOriginalState(
        title: 'The original could not be opened',
        message: 'Saved properties and text remain available.',
        action: GlacierButton(label: 'Try again', onPressed: () {}),
      ),
    ),
  ),
  _case(
    'document-extracted-text',
    'Extracted text',
    'Revision and edit',
    'GlacierExtractedText',
    (_) => Scaffold(
      backgroundColor: Colors.transparent,
      body: GlacierExtractedText(
        text: 'Lumen Energy\nNovember electricity\nTotal EUR 86.40',
        revisionLabel: 'Revision 3',
        onEdit: () {},
      ),
    ),
  ),
  _case(
    'search-filter-group',
    'Filter group',
    'Rich multiple selection',
    'GlacierSearchFilterGroup',
    (_) => CatalogFrame(
      child: GlacierSearchFilterGroup(
        label: 'Document types',
        options: const ['PDF', 'Image', 'Email'],
        selected: const ['PDF'],
        onChanged: (_, _) {},
      ),
    ),
    domain: 'Search',
  ),
  _case(
    'invoice-section',
    'Labeled fields',
    'Exact amounts',
    'GlacierInvoiceSection',
    (_) => const CatalogFrame(
      child: GlacierInvoiceSection(
        title: 'Amounts',
        values: {
          'Net total': '72.61 EUR',
          'Tax total': '13.79 EUR',
          'Total': '86.40 EUR',
          'Amount due': '86.40 EUR',
        },
      ),
    ),
    domain: 'Invoices',
  ),
  _case(
    'invoice-records',
    'Embedded records',
    'Paginated line items',
    'GlacierInvoiceRecords',
    (_) => CatalogFrame(
      child: GlacierInvoiceRecords(
        title: 'Line items',
        pageSize: 2,
        records: List.generate(
          6,
          (i) => GlacierInvoiceDetailRecord(
            title: 'Household service ${i + 1}',
            values: const {
              'Quantity': '1 month',
              'Net amount': '72.61 EUR',
              'Tax rate': '19%',
            },
          ),
        ),
      ),
    ),
    domain: 'Invoices',
  ),

  _case(
    'document-preview-placeholder',
    'Preview preparation',
    'Shimmer at grid and row sizes',
    'GlacierPreviewPlaceholder',
    (_) => const CatalogFrame(
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        children: [
          SizedBox(width: 260, height: 180, child: GlacierPreviewPlaceholder()),
          SizedBox(width: 64, height: 64, child: GlacierPreviewPlaceholder()),
        ],
      ),
    ),
  ),
  _case(
    'document-preview-lifecycle',
    'Preview preparation',
    'Pending, ready, failed and absent preview',
    'GlacierDocumentCard',
    (_) => const _PreviewPreparationStory(),
  ),
  _case(
    'document-preview-mobile',
    'Preview preparation',
    'Mobile card while PNG is prepared',
    'GlacierMobileDocumentCard',
    (_) => const _PreviewPreparationStory(mobile: true),
  ),
  _case(
    'document-preview-retry',
    'Preview preparation',
    'Compact in-item preview retry',
    'GlacierPreviewRetry',
    (_) => CatalogFrame(
      child: Wrap(
        spacing: 20,
        children: [
          GlacierPreviewRetry(onPressed: () {}),
          GlacierPreviewRetry(compact: true, onPressed: () {}),
        ],
      ),
    ),
  ),
  _case(
    'document-preview-row',
    'Preview preparation',
    'List thumbnail retry',
    'GlacierDocumentRow',
    (_) => const _PreviewPreparationStory(list: true),
  ),
  _case(
    'document-preview-both-failed',
    'Preview preparation',
    'Independent preview and processing retry',
    'GlacierDocumentCard',
    (_) => const _PreviewPreparationStory(bothFailures: true),
  ),
  _case(
    'document-preview-mobile-both-failed',
    'Preview preparation',
    'Mobile independent preview and processing retry',
    'GlacierMobileDocumentCard',
    (_) => const _PreviewPreparationStory(mobile: true, bothFailures: true),
  ),
  for (final state in [
    'grid',
    'list',
    'empty',
    'no-results',
    'loading',
    'stale',
    'error',
    'denied',
  ])
    _case(
      'documents-$state',
      'Collection',
      state,
      'GlacierDocumentCollection',
      (_) => _CollectionStory(state: state),
    ),
  for (final state in ['ready', 'running', 'failed', 'locked', 'long-title'])
    _case(
      'document-card-$state',
      'Document card',
      state,
      'GlacierDocumentCard',
      (_) => CatalogFrame(
        maxWidth: 280,
        child: GlacierDocumentCard(
          document: _document(state: state),
          preview: const _DocumentArtwork(),
          onOpen: () {},
          onRetry: () {},
        ),
      ),
    ),
  for (final state in [
    'standard',
    'read-only',
    'locked',
    'missing',
    'error',
    'email',
    'text',
    'deleted',
  ])
    _case(
      'reader-$state',
      'Reader workspace',
      state,
      'GlacierReader',
      (_) => _ReaderStory(state: state),
    ),
  _case(
    'reader-pdf-engine',
    'Original canvas',
    'Real PDF engine',
    'DocumentPdfCanvas',
    (_) => const _PdfStory(),
    description: 'The existing production pdfrx canvas renders an in-memory fictional PDF. No document service is contacted.',
  ),
  _case(
    'document-find',
    'Find',
    'Two results',
    'GlacierFindBar',
    (_) => const _FindStory(),
  ),
  for (final state in ['metadata', 'conflict', 'uncertain', 'deleted'])
    _case(
      'document-editor-$state',
      'Metadata editor',
      state,
      'GlacierDocumentPropertiesForm',
      (_) => _PropertiesStory(state: state),
    ),
  _case(
    'document-upload-receipts',
    'Uploads',
    'Every receipt state',
    'GlacierUploadQueue',
    (_) => CatalogFrame(
      child: GlacierUploadQueue(
        library: 'Personal library',
        receipts: [
          for (final status in [
            'Waiting',
            'Reading file',
            'Uploading',
            'Accepted — processing continues',
            'Not uploaded',
            'Already in this library',
            'Outcome unknown',
          ])
            GlacierUploadReceipt(
              filename: 'Household record.pdf',
              status: status,
              busy: ['Waiting', 'Reading file', 'Uploading'].contains(status),
              tone: status == 'Not uploaded'
                  ? AppTone.danger
                  : status == 'Outcome unknown'
                  ? AppTone.warning
                  : AppTone.neutral,
              detail: status == 'Outcome unknown'
                  ? 'Check the library before trying again. No automatic retry will duplicate this upload.'
                  : '',
            ),
        ],
      ),
    ),
  ),
  for (final kind in ['documents', 'invoices'])
    _case(
      'search-$kind',
      'Search dialog',
      kind,
      'GlacierSearchDialog',
      (_) => _SearchStory(invoice: kind == 'invoices'),
      domain: 'Search',
    ),
  for (final state in ['results', 'empty', 'error'])
    _case(
      'search-vocabulary-$state',
      'Vocabulary chooser',
      state,
      'GlacierVocabularyPicker',
      (_) => _VocabularyStory(state: state),
      domain: 'Search',
    ),
  _case(
    'search-active-filters',
    'Applied criteria',
    'Wrapped filters',
    'GlacierActiveFilters',
    (_) => CatalogFrame(
      child: GlacierActiveFilters(
        filters: const [
          'Type: PDF or email',
          'Tag: Home',
          'Tag: Utilities',
          'Sender contains Lumen',
          'Recipient: Alex Morgan',
        ],
        onRemove: (_) {},
        onClear: () {},
      ),
    ),
    domain: 'Search',
  ),
  for (final state in ['structured', 'ai', 'credit', 'missing'])
    _case(
      'invoice-row-$state',
      'Invoice row',
      state,
      'GlacierInvoiceRow',
      (_) => CatalogFrame(
        child: GlacierInvoiceRow(
          invoice: GlacierInvoiceValue(
            number: state == 'missing' ? '' : 'LE-2026-1104',
            supplier: state == 'missing' ? '' : 'Lumen Energy',
            amount: state == 'missing'
                ? ''
                : state == 'credit'
                ? '-86.40'
                : '86.40',
            currency: 'EUR',
            issueDate: '15 Nov 2026',
            dueDate: '30 Nov 2026',
            aiExtracted: state == 'ai',
            provenance: state == 'ai' ? 'AI extracted · Review' : 'E-invoice',
            type: state == 'credit' ? 'Credit note' : 'Invoice',
          ),
          onOpen: () {},
        ),
      ),
      domain: 'Invoices',
    ),
  _case(
    'invoice-collection',
    'Collection',
    'Invoices',
    'GlacierInvoiceRow',
    (_) => const _InvoiceCollectionStory(),
    domain: 'Invoices',
  ),
  for (final state in ['structured', 'ai', 'error', 'loading'])
    _case(
      'invoice-details-$state',
      'Invoice details',
      state,
      'GlacierInvoiceDetails',
      (_) => _InvoiceStory(state: state),
      domain: 'Invoices',
    ),
];

GlacierDocumentValue _document({String state = 'ready', int index = 0}) =>
    GlacierDocumentValue(
      id: '$index',
      title: state == 'long-title'
          ? 'A very long household insurance renewal and supporting contractual correspondence for the coming year'
          : [
              'Studio lease · 2026',
              'November electricity',
              'Health insurance',
              'Design services · October',
              'Home insurance · 2027',
              'Your order has arrived',
              'Internet · November',
              'Annual tax statement',
              'Office supplies',
              'Welcome to Nordline',
              'Bicycle service',
              'Library invitation',
            ][index % 12],
      sender: [
        'Nordhaus Immobilien',
        'Lumen Energy',
        'Aster Versicherung',
        'Forma Studio',
        'Aster Versicherung',
        'hello@atelier-goods.example',
        'Nordline',
        'Stadtbank Berlin',
        'Papier & Co.',
        'service@nordline.example',
        'Velo Werkstatt',
        'sam@example.test',
      ][index % 12],
      date: [
        '16 Nov',
        '15 Nov',
        '14 Nov',
        '13 Nov',
        '12 Nov',
        '12 Nov',
        '11 Nov',
        '10 Nov',
        '09 Nov',
        '08 Nov',
        '07 Nov',
        '06 Nov',
      ][index % 12],
      type: [5, 9, 11].contains(index) ? 'EML' : 'PDF',
      pages: [8, 2, 3, 2, 12, 1, 2, 5, 1, 1, 1, 1][index % 12],
      tags: [
        ['Home'],
        ['Utilities'],
        ['Insurance'],
        ['Work'],
        ['Insurance'],
        ['Receipts'],
        ['Utilities'],
        ['Finance'],
        ['Work'],
        ['Utilities'],
        ['Receipts'],
        ['Work'],
      ][index % 12],
      busy: state == 'running',
      failed: state == 'failed',
      statusIcon: state == 'locked'
          ? Icons.lock_outline
          : state == 'waiting'
          ? Icons.schedule
          : Icons.info_outline,
      status: state == 'waiting'
          ? 'Waiting to start'
          : state == 'locked'
          ? 'Password required'
          : state == 'running'
          ? 'Processing'
          : '',
    );

final class _DocumentArtwork extends StatelessWidget {
  const _DocumentArtwork({this.index = 0});
  final int index;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GlacierTokens.of(context).preview,
    child: Center(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          width: 119,
          height: 162,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            color: index == 4 ? const Color(0xfff6f2e8) : Colors.white,
            boxShadow: const [
              BoxShadow(
                color: Color(0x1c1f3435),
                blurRadius: 7,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 4,
              height: 1.7,
              color: Color(0xff283536),
            ),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          [
                            'NORDHAUS',
                            'LUMEN',
                            'ASTER',
                            'FORMA',
                            'ASTER',
                            'ATELIER GOODS',
                            'NORDLINE',
                            'STADTBANK',
                            'PAPIER & CO.',
                            'NORDLINE',
                            'VELO',
                            'DOMABAS',
                          ][index % 12],
                          style: const TextStyle(
                            fontSize: 5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8,
                          ),
                        ),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: const Color(0xff395b4c),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Divider(height: 1, color: Color(0xffd4dddd)),
                    ),
                    Text(
                      [
                        'Commercial lease',
                        'Your energy statement',
                        'Your coverage, continued.',
                        'Invoice',
                        'Room for peace of mind.',
                        'A little more everyday.',
                        'Monthly statement',
                        'Annual tax statement',
                        'Invoice',
                        'You are connected.',
                        'Ready for the road.',
                        'A space to work together.',
                      ][index % 12],
                      style: TextStyle(
                        fontSize: index == 4 ? 13 : 7,
                        height: 1.35,
                        fontWeight: index == 4
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Alex Morgan\nLindenstraße 18 · 10969 Berlin\nThank you for your trust.',
                    ),
                    const SizedBox(height: 10),
                    if (index == 1 ||
                        index == 3 ||
                        index == 5 ||
                        index == 6) ...[
                      const Text(
                        'Description                         Amount',
                        style: TextStyle(fontSize: 3.5),
                      ),
                      const Divider(height: 9, color: Color(0xffd4dddd)),
                      const Text('Services for November            €86.40'),
                      const Divider(height: 9, color: Color(0xffd4dddd)),
                      const Text(
                        'Tax included                               19%',
                      ),
                      const Divider(height: 9, color: Color(0xffd4dddd)),
                      const Text(
                        'Total                               €86.40',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 5,
                        ),
                      ),
                    ] else if (index != 4) ...[
                      const Text(
                        'IMPORTANT INFORMATION',
                        style: TextStyle(
                          fontSize: 3.5,
                          color: Color(0xff768583),
                        ),
                      ),
                      for (final width in [1.0, .84, 1.0, .62])
                        Container(
                          height: 2,
                          width: 95 * width,
                          margin: const EdgeInsets.only(top: 4),
                          color: const Color(0xffdce1e0),
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'FOR YOUR RECORDS',
                        style: TextStyle(
                          fontSize: 3.5,
                          color: Color(0xff768583),
                        ),
                      ),
                      for (final width in [.84, 1.0])
                        Container(
                          height: 2,
                          width: 95 * width,
                          margin: const EdgeInsets.only(top: 4),
                          color: const Color(0xffdce1e0),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _CatalogInlineSelect extends StatelessWidget {
  const _CatalogInlineSelect({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.transparent = false,
  });
  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final bool transparent;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: transparent
          ? Colors.transparent
          : GlacierTokens.of(context).surface,
      border: Border.all(
        color: transparent
            ? Colors.transparent
            : GlacierTokens.of(context).border,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelStyle = Theme.of(context).textTheme.bodySmall;
            final valueStyle = Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 13);
            double widthOf(String text, TextStyle? style) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final width = painter.width;
              painter.dispose();
              return width;
            }

            var valueWidth = 0.0;
            for (final option in values) {
              final width = widthOf(option, valueStyle);
              if (width > valueWidth) valueWidth = width;
            }
            final bounded =
                constraints.maxWidth <
                widthOf(label, labelStyle) + 7 + valueWidth + 24;
            final selector = DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                isExpanded: bounded,
                borderRadius: BorderRadius.circular(8),
                style: valueStyle,
                items: values
                    .map(
                      (text) => DropdownMenuItem(
                        value: text,
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 7),
                if (bounded) Flexible(child: selector) else selector,
              ],
            );
          },
        ),
      ),
    ),
  );
}

final class _CollectionStory extends StatefulWidget {
  const _CollectionStory({required this.state});
  final String state;
  @override
  State<_CollectionStory> createState() => _CollectionStoryState();
}

final class _CollectionStoryState extends State<_CollectionStory> {
  late bool list = widget.state == 'list';
  String filter = 'All types';
  String tag = 'All tags', sort = 'Newest added';
  int page = 1;
  Widget _sortControl() => _CatalogInlineSelect(
    label: 'Sort',
    value: sort,
    values: const ['Newest added', 'Oldest added', 'Title'],
    transparent: true,
    onChanged: (value) => setState(() => sort = value),
  );
  List<Widget> _actionGroup(BuildContext context, List<Widget> actions) =>
      GlacierNativePresentationScope.maybeOf(context) == null
      ? actions
      : [
          Wrap(
            spacing: 0,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ];
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: GlacierDocumentCollection(
      documents:
          ['empty', 'no-results', 'loading', 'denied'].contains(widget.state)
          ? []
          : List.generate(
              page == 1 ? 8 : 4,
              (i) => _document(
                index: (page - 1) * 8 + i,
                state: i == 0
                    ? 'running'
                    : i == 1
                    ? 'waiting'
                    : i == 4
                    ? 'failed'
                    : 'ready',
              ),
            ),
      previewBuilder: (document) =>
          _DocumentArtwork(index: int.tryParse(document.id) ?? 0),
      list: list,
      toolbar: GlacierToolbar(
        trailing: [
          if (GlacierNativePresentationScope.maybeOf(context)?.compact != true)
            _sortControl(),
          ..._actionGroup(context, [
            DecoratedBox(
              decoration: BoxDecoration(
                color: GlacierTokens.of(context).surface,
                border: Border.all(color: GlacierTokens.of(context).border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final value in [false, true])
                      IconButton(
                        tooltip: value ? 'List view' : 'Grid view',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          maximumSize: const Size(36, 36),
                          padding: const EdgeInsets.all(8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: list == value
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => setState(() => list = value),
                        icon: Icon(
                          value
                              ? Icons.format_list_bulleted
                              : Icons.grid_view_outlined,
                          size: 17,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            GlacierButton(
              label: 'Upload',
              icon: Icons.file_upload_outlined,
              kind: GlacierButtonKind.primary,
              onPressed: () => showGlacierDialog<void>(
                context: context,
                builder: (_) => GlacierDialog(
                  title: 'Upload documents',
                  actions: [
                    GlacierButton(
                      label: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Choose files to add to Personal library.'),
                      const SizedBox(height: 20),
                      GlacierButton(
                        label: 'Choose files',
                        icon: Icons.upload_file_outlined,
                        onPressed: () {},
                      ),
                      const SizedBox(height: 20),
                      const GlacierUploadQueue(
                        library: 'Personal library',
                        receipts: [],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More document actions',
              icon: const Icon(Icons.more_horiz, size: 20),
              onSelected: (_) => showGlacierDialog<void>(
                context: context,
                builder: (_) => const _PropertiesStory(state: 'metadata'),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'create',
                  child: Text('Create document'),
                ),
              ],
            ),
          ]),
          if (GlacierNativePresentationScope.maybeOf(context)?.compact == true)
            _sortControl(),
        ],
        children: [
          Wrap(
            spacing: 2,
            runSpacing: 4,
            children: ['All types', 'Documents', 'Letters', 'Emails']
                .map(
                  (value) => TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      backgroundColor: filter == value
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      foregroundColor: filter == value
                          ? GlacierTokens.of(context).accent
                          : GlacierTokens.of(context).muted,
                      textStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: filter == value
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    onPressed: () => setState(() => filter = value),
                    child: Text(value),
                  ),
                )
                .toList(),
          ),
          _CatalogInlineSelect(
            label: 'Tag',
            value: tag,
            values: const [
              'All tags',
              'Home',
              'Utilities',
              'Insurance',
              'Work',
            ],
            onChanged: (value) => setState(() => tag = value),
          ),
        ],
      ),
      feedback: ['stale', 'error'].contains(widget.state)
          ? AppNotice(
              message: widget.state == 'stale'
                  ? 'Showing previous results while this library refreshes.'
                  : 'The update failed. Your previous results remain available.',
              tone: AppTone.warning,
              action: TextButton(onPressed: () {}, child: const Text('Retry')),
            )
          : null,
      empty: widget.state == 'loading'
          ? const AppJobSpinner(label: 'Loading documents')
          : AppEmptyState(
              icon: widget.state == 'denied'
                  ? Icons.lock_outline
                  : Icons.search,
              title: widget.state == 'denied'
                  ? 'Document access is unavailable'
                  : widget.state == 'no-results'
                  ? 'No matching documents'
                  : 'Your library starts here',
              message: widget.state == 'denied'
                  ? 'Ask a library owner for document access.'
                  : 'Upload a file or adjust your search criteria.',
            ),
      onOpen: (id) => showGlacierDialog<void>(
        context: context,
        builder: (_) => documentReaderDialog(index: int.tryParse(id) ?? 0),
      ),
      onRetry: (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fictional retry requested')),
      ),
      pagination: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '12 sample documents · ${page == 1 ? '1–8' : '9–12'} shown',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GlacierButton(
                  label: 'Previous',
                  onPressed: page == 1 ? null : () => setState(() => page--),
                ),
                Text('$page / 2', style: Theme.of(context).textTheme.bodySmall),
                GlacierButton(
                  label: 'Next',
                  onPressed: page == 2 ? null : () => setState(() => page++),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget documentReaderDialog({String state = 'standard', int index = 1}) =>
    Builder(
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: GlacierNativePresentationScope.maybeOf(context) == null
            ? const EdgeInsets.all(24)
            : const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1440,
            maxHeight:
                MediaQuery.sizeOf(context).height -
                (GlacierNativePresentationScope.maybeOf(context) == null
                    ? 48
                    : 24),
          ),
          child: _ReaderStory(
            state: index == 5 && state == 'standard' ? 'email' : state,
            index: index,
          ),
        ),
      ),
    );

final class _ReaderStory extends StatefulWidget {
  const _ReaderStory({required this.state, this.index = 1});
  final String state;
  final int index;
  @override
  State<_ReaderStory> createState() => _ReaderStoryState();
}

final class _ReaderStoryState extends State<_ReaderStory> {
  final find = TextEditingController();
  late bool text = widget.state == 'text';
  bool finding = false;
  int page = 1, match = 0, zoom = 100;
  String query = '';
  @override
  void dispose() {
    find.dispose();
    super.dispose();
  }

  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  @override
  Widget build(BuildContext context) {
    final editable = widget.state != 'read-only';
    final document = _document(index: widget.index);
    final documentDate =
        '2026-11-${[16, 15, 14, 13, 12, 12, 11, 10][widget.index % 8]}';
    final original = switch (widget.state) {
      'locked' => GlacierOriginalState(
        title: 'Password required',
        message: 'Unlock this PDF to continue processing.',
        icon: Icons.lock_outline,
        action: GlacierButton(
          label: 'Unlock PDF',
          onPressed: () => _notice('Fictional password rejected. Try again.'),
        ),
        child: const TextField(
          obscureText: true,
          decoration: InputDecoration(labelText: 'PDF password'),
        ),
      ),
      'missing' => const GlacierOriginalState(
        title: 'No original file',
        message: 'This record contains metadata only. Its properties and text remain available.',
      ),
      'error' => GlacierOriginalState(
        title: 'The original could not be opened',
        message: 'Saved properties and extracted text remain available.',
        action: GlacierButton(
          label: 'Try again',
          onPressed: () => _notice('Retry requested'),
        ),
      ),
      'deleted' => const GlacierOriginalState(
        title: 'This document was deleted',
        message: 'Copy any unsaved text before leaving. This preview cannot restore the record.',
      ),
      'email' => const SingleChildScrollView(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlacierPropertyGrid(
              values: {
                'From': 'orders@atelier.example',
                'To': 'Alex Morgan',
                'Subject': 'Your order has arrived',
                'Sent': '15 November 2026',
              },
            ),
            SizedBox(height: 24),
            SelectableText(
              'Hello Alex,\n\nYour order has arrived. The receipt is attached.\n\nThank you,\nAtelier Goods',
            ),
            SizedBox(height: 24),
            Text(
              'Plain-text email. Remote images and active content are blocked.',
            ),
          ],
        ),
      ),
      _ => _ReaderPaper(
        document: document,
        index: widget.index,
        page: page,
        zoom: zoom,
        query: query,
      ),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.zero,
        child: GlacierReader(
          title: document.title,
          contextLabel:
              'Personal library · ${document.type} · ${document.pages} pages',
          original: original,
          text: GlacierExtractedText(
            text: _documentExtractedText(widget.index),
            revisionLabel: 'Extracted text · Revision 3',
            onEdit: editable ? () => _notice('Edit text requested') : null,
          ),
          textSelected: text,
          onViewChanged: (value) => setState(() => text = value),
          onEdit: editable
              ? () => showGlacierDialog<void>(
                  context: context,
                  builder: (_) =>
                      _PropertiesStory(state: 'metadata', index: widget.index),
                )
              : null,
          onResync: editable
              ? () => showGlacierDialog<void>(
                  context: context,
                  builder: (dialog) => GlacierDialog(
                    title: 'Resync ${document.title}',
                    actions: [
                      GlacierButton(
                        label: 'Back to document',
                        onPressed: () => Navigator.pop(dialog),
                      ),
                    ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Personal library · Previous attempts remain in history.',
                        ),
                        const SizedBox(height: 20),
                        GlacierButton(
                          label: 'Rebuild search index',
                          onPressed: () {
                            Navigator.pop(dialog);
                            _notice('Fictional ingestion attempt waiting');
                          },
                        ),
                        const SizedBox(height: 12),
                        GlacierButton(
                          label: 'Rerun AI extraction',
                          onPressed: () {
                            Navigator.pop(dialog);
                            _notice('Fictional AI attempt waiting');
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          onDownload: () => _notice('Download requested in local example'),
          onDelete: editable
              ? () => showGlacierDialog<void>(
                  context: context,
                  builder: (dialog) => GlacierDialog(
                    title: 'Delete ${document.title}?',
                    actions: [
                      GlacierButton(
                        label: 'Keep document',
                        onPressed: () => Navigator.pop(dialog),
                      ),
                      GlacierButton(
                        label: 'Delete document',
                        kind: GlacierButtonKind.danger,
                        onPressed: () {
                          Navigator.pop(dialog);
                          _notice('Deleted from local example');
                        },
                      ),
                    ],
                    child: const Text(
                      'Removes the original, properties and extracted text from Personal library.',
                    ),
                  ),
                )
              : null,
          onClose: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              _notice('Close document requested');
            }
          },
          onFind: () => setState(() => finding = true),
          onCloseFind: () => setState(() => finding = false),
          find: finding
              ? GlacierFindBar(
                  controller: find,
                  resultLabel: query.isEmpty
                      ? ''
                      : query == '86.40'
                      ? '${match + 1} / 2'
                      : 'No matches',
                  onSubmitted: (value) => setState(() {
                    query = value;
                    match = 0;
                  }),
                  onPrevious: query == '86.40'
                      ? () => setState(() => match = (match + 1) % 2)
                      : null,
                  onNext: query == '86.40'
                      ? () => setState(() => match = (match + 1) % 2)
                      : null,
                  onClose: () => setState(() => finding = false),
                )
              : null,
          toolbar: GlacierPdfToolbar(
            page: page,
            pageCount: document.pages,
            zoomLabel: '$zoom%',
            onPrevious: () => setState(() => page--),
            onNext: () => setState(() => page++),
            onPageChanged: (value) => setState(() => page = value),
            onZoomOut: () => setState(() => zoom = (zoom - 25).clamp(50, 200)),
            onZoomIn: () => setState(() => zoom = (zoom + 25).clamp(50, 200)),
            onFit: () => setState(() => zoom = 100),
            onFind: () => setState(() => finding = !finding),
          ),
          inspector: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlacierSection(
                title: editable ? 'Properties' : 'Properties · Read only',
                child: GlacierPropertyGrid(
                  values: {
                    'Sender': document.sender,
                    'Recipients': 'Alex Morgan',
                    'Document date': documentDate,
                    'Type': 'Documents',
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Text('Kept for household records'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: document.tags
                    .map((tag) => GlacierTag(label: tag))
                    .toList(),
              ),
              const SizedBox(height: 16),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                minTileHeight: 32,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'File and processing evidence',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  GlacierPropertyGrid(
                    values: {
                      'Filename': 'november-electricity.pdf',
                      'Media type': 'application/pdf',
                      'Size': '42,815 bytes',
                      'SHA-256': 'Fictional example digest',
                      'Uploader': 'Alex Morgan',
                      'Created / ingested': '15 November 2026',
                      'Generation / configuration': '3 / 2',
                      'Extraction': 'OCR · Tesseract',
                      'Language / segmentation': 'eng+deu / auto',
                      'Embedding model': 'nomic-embed-text:v1.5',
                      'Embedding dimensions': '768',
                    },
                  ),
                ],
              ),
              const Divider(height: 40),
              GlacierRelatedDocuments(
                documents: [
                  GlacierRelatedDocument(
                    title: 'Your order has arrived',
                    relationship: 'Source email',
                    onOpen: () => showGlacierDialog<void>(
                      context: context,
                      builder: (_) => documentReaderDialog(index: 5),
                    ),
                  ),
                  GlacierRelatedDocument(
                    title: 'Office supplies',
                    relationship: 'Attachment',
                    onOpen: () => showGlacierDialog<void>(
                      context: context,
                      builder: (_) => documentReaderDialog(index: 1),
                    ),
                  ),
                ],
              ),
              const Divider(height: 40),
              GlacierSection(
                title: 'Processing',
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(left: 16),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  dense: true,
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.schedule, size: 17),
                  ),
                  title: const Text(
                    'Document AI',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Waiting to start',
                    style: TextStyle(fontSize: 11),
                  ),
                  children: [
                    const GlacierPipelineTimeline(
                      compact: true,
                      stages: [
                        GlacierPipelineStage(
                          label: 'Invoice extraction',
                          state: GlacierStageState.waiting,
                        ),
                        GlacierPipelineStage(
                          label: 'Property extraction',
                          state: GlacierStageState.waiting,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Accepted and waiting to start. No completed stage is inferred.',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => _notice('Attempt details requested'),
                      child: const Text('View attempt details'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

GlacierInvoiceValue? _invoiceForDocument(int documentIndex) {
  final index = const [1, 3, 5, 6, 2, 4].indexOf(documentIndex);
  return index < 0 ? null : _invoiceValue(index);
}

String _documentExtractedText(int index) {
  final document = _document(index: index);
  final invoice = _invoiceForDocument(index);
  return invoice == null
      ? '${document.sender}\n${document.title}\nRetain a copy for your records.'
      : '${invoice.supplier}\nInvoice ${invoice.number}\n${document.title}\nTotal €${invoice.amount}';
}

final class _ReaderPaper extends StatelessWidget {
  const _ReaderPaper({
    required this.document,
    required this.index,
    required this.page,
    required this.zoom,
    required this.query,
  });
  final GlacierDocumentValue document;
  final int index, page, zoom;
  final String query;
  @override
  Widget build(BuildContext context) {
    final invoice = _invoiceForDocument(index);
    final amount = invoice == null ? '' : '€${invoice.amount}';
    final description = index == 1
        ? 'Services for November'
        : 'Services from ${document.sender.split(' ').first}';
    final paper = Container(
      width: 370,
      height: 505,
      padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 42),
      color: Colors.white,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'DMSans',
          fontSize: 11,
          height: 1.7,
          color: Color(0xff213632),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  document.sender.split(' ').first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xff395b4c),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
            const Divider(height: 25, color: Color(0xffd4dddd)),
            const SizedBox(height: 22),
            Text(
              index == 0
                  ? 'Commercial lease'
                  : index == 1
                  ? 'Your energy statement'
                  : document.title,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              index == 0
                  ? 'Studio 04 · Lindenstraße 18\nDear Alex Morgan,\nRetain a copy of this agreement for your records.'
                  : 'Invoice ${invoice?.number ?? document.title} · Page $page\nAlex Morgan\n$description',
            ),
            const SizedBox(height: 18),
            if (index == 0) ...[
              const Text(
                '01 / YOUR AGREEMENT',
                style: TextStyle(fontSize: 9, color: Color(0xff768583)),
              ),
              for (final width in [1.0, 1.0, .84, .62])
                Container(
                  width: 300 * width,
                  height: 3,
                  margin: const EdgeInsets.only(top: 7),
                  color: const Color(0xffdce1e0),
                ),
              const SizedBox(height: 20),
              const Text(
                '02 / TERMS AND CONDITIONS',
                style: TextStyle(fontSize: 9, color: Color(0xff768583)),
              ),
              for (final width in [1.0, .84, .62])
                Container(
                  width: 300 * width,
                  height: 3,
                  margin: const EdgeInsets.only(top: 7),
                  color: const Color(0xffdce1e0),
                ),
              const Spacer(),
              const Text(
                'Nordhaus',
                style: TextStyle(fontSize: 30, height: 1.2),
              ),
            ] else ...[
              const Divider(height: 24, color: Color(0xffd4dddd)),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Description'), Text('Amount')],
              ),
              const Divider(height: 24, color: Color(0xffd4dddd)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(description, maxLines: 1)),
                  const SizedBox(width: 8),
                  Text(amount),
                ],
              ),
              const Divider(height: 24, color: Color(0xffd4dddd)),
              Container(
                color: query.isNotEmpty && query == invoice?.amount
                    ? const Color(0xffffe5a0)
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      amount,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'Illustrative original for layout review.',
                style: TextStyle(fontSize: 9, color: Color(0xff768583)),
              ),
            ],
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (370 * zoom / 100).clamp(0.0, constraints.maxWidth - 56);
        final scale = width / 370;
        return ColoredBox(
          color: GlacierTokens.of(context).preview,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: SizedBox(
                width: width,
                height: 505 * scale,
                child: RepaintBoundary(
                  child: MediaQuery.withNoTextScaling(
                    child: scale == 1
                        ? paper
                        : OverflowBox(
                            minWidth: 370,
                            maxWidth: 370,
                            minHeight: 505,
                            maxHeight: 505,
                            child: Transform.scale(scale: scale, child: paper),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _FindStory extends StatefulWidget {
  const _FindStory();
  @override
  State<_FindStory> createState() => _FindStoryState();
}

final class _FindStoryState extends State<_FindStory> {
  final controller = TextEditingController(text: '86.40');
  int result = 1;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CatalogFrame(
    maxWidth: 480,
    child: GlacierFindBar(
      controller: controller,
      resultLabel: '$result / 2',
      onSubmitted: (_) => setState(() => result = 1),
      onNext: () => setState(() => result = result == 1 ? 2 : 1),
      onPrevious: () => setState(() => result = result == 1 ? 2 : 1),
      onClose: () {},
    ),
  );
}

final class _PropertiesStory extends StatefulWidget {
  const _PropertiesStory({required this.state, this.index = 1});
  final String state;
  final int index;
  @override
  State<_PropertiesStory> createState() => _PropertiesStoryState();
}

final class _PropertiesStoryState extends State<_PropertiesStory> {
  late final controllers = {
    for (final entry in {
      'Title': _document(index: widget.index).title,
      'Description': 'Kept for household records',
      'Document date': '2026-11-15',
      'Type': 'Documents',
      'Sender': _document(index: widget.index).sender,
      'Recipients': 'Alex Morgan',
      'CC': '',
      'BCC': '',
      'Subject': '',
      'Message ID': '',
    }.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  late final tags = [..._document(index: widget.index).tags];
  bool saved = false;
  bool recovered = false;
  bool get needsRecovery =>
      !recovered && ['conflict', 'uncertain'].contains(widget.state);
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlacierDialog(
    title: 'Edit document properties',
    actions: [
      GlacierButton(
        label: 'Cancel',
        onPressed: () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        },
      ),
      GlacierButton(
        label: saved ? 'Saved' : 'Save changes',
        kind: GlacierButtonKind.primary,
        onPressed: widget.state == 'deleted' || needsRecovery
            ? null
            : () => setState(() => saved = true),
      ),
    ],
    child: GlacierDocumentPropertiesForm(
      controllers: controllers,
      tags: tags,
      onRemoveTag: (tag) => setState(() => tags.remove(tag)),
      onAddTag: () => setState(() {
        if (!tags.contains('Archive')) tags.add('Archive');
      }),
      feedback: widget.state == 'metadata'
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNotice(
                  tone: AppTone.warning,
                  message: recovered
                      ? 'Sample saved record checked: ${_document(index: widget.index).title}. Your draft is preserved. Review it before saving.'
                      : switch (widget.state) {
                          'conflict' => 'This document changed elsewhere. Your draft is preserved. Reload before saving again.',
                          'uncertain' => 'The save result is unknown. Check the saved value before submitting again.',
                          _ => 'This document was deleted. Copy your unsaved properties before leaving.',
                        },
                ),
                if (needsRecovery)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GlacierButton(
                      label: widget.state == 'conflict'
                          ? 'Reload saved record'
                          : 'Check saved value',
                      onPressed: () => setState(() => recovered = true),
                    ),
                  ),
              ],
            ),
    ),
  );
}

Widget documentSearchDialog({bool invoice = false, VoidCallback? onApplied}) =>
    _SearchStory(invoice: invoice, dialog: true, onApplied: onApplied);

final class _SearchStory extends StatefulWidget {
  const _SearchStory({
    required this.invoice,
    this.dialog = false,
    this.onApplied,
  });
  final bool invoice, dialog;
  final VoidCallback? onApplied;
  @override
  State<_SearchStory> createState() => _SearchStoryState();
}

final class _SearchStoryState extends State<_SearchStory> {
  final query = TextEditingController();
  final selected = <String>{};
  final tags = <String>{};
  late final fields = {
    for (final name
        in widget.invoice
            ? [
                'Invoice number',
                'Supplier',
                'Customer',
                'Currency',
                'Invoice type',
                'Format',
                'Payment method',
                'Added from',
                'Added to',
                'Issued from',
                'Issued to',
                'Due from',
                'Due to',
                'Minimum total',
                'Maximum total',
              ]
            : ['Sender', 'Recipient'])
      name: TextEditingController(),
  };
  bool exact = false;
  String? error;
  String applied = '';
  @override
  void dispose() {
    query.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void clear() => setState(() {
    query.clear();
    selected.clear();
    tags.clear();
    for (final field in fields.values) {
      field.clear();
    }
    error = null;
  });
  void apply() => setState(() {
    error =
        widget.invoice &&
            (fields['Minimum total']!.text.isNotEmpty ||
                fields['Maximum total']!.text.isNotEmpty) &&
            fields['Currency']!.text.isEmpty
        ? 'Choose a currency for the total range.'
        : null;
    if (error == null) {
      applied = 'Applied ${query.text.isEmpty ? 'filters' : query.text}';
    }
  });
  @override
  Widget build(BuildContext context) => widget.dialog
      ? Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: _content(context),
        )
      : Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: _content(context)),
        );

  Widget _content(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820),
        child: Padding(
          padding: EdgeInsets.zero,
          child: GlacierSearchDialog(
            controller: query,
            contextLabel: widget.invoice
                ? 'Personal library · Invoices'
                : 'Personal library · Documents',
            placeholder: widget.invoice
                ? 'Search invoices…'
                : 'Search documents…',
            showKeyboardHint: false,
            summary: selected.isNotEmpty || tags.isNotEmpty
                ? '${selected.length + tags.length} selected'
                : '',
            error: error,
            onApply: () {
              apply();
              if (error == null && widget.dialog) {
                Navigator.pop(context);
                widget.onApplied?.call();
              }
            },
            onClear: clear,
            onCancel: () {
              if (widget.dialog) {
                Navigator.pop(context);
              } else {
                clear();
              }
            },
            filters: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlacierSearchFilterGroup(
                  label: widget.invoice
                      ? 'Source'
                      : 'Document types · match any',
                  options: widget.invoice
                      ? const ['E-invoice', 'AI extracted']
                      : const ['Documents', 'Letters', 'Emails'],
                  selected: selected.toList(),

                  onChanged: (value, checked) => setState(
                    () =>
                        checked ? selected.add(value) : selected.remove(value),
                  ),
                ),
                if (!widget.invoice)
                  GlacierSearchFilterGroup(
                    label: 'Tags · match all',
                    options: const ['Home', 'Utilities', 'Insurance', 'Work'],
                    selected: tags.toList(),

                    onChanged: (value, checked) => setState(
                      () => checked ? tags.add(value) : tags.remove(value),
                    ),
                    onMore: () {},
                  ),
                ExpansionTile(
                  title: Text(
                    widget.invoice
                        ? 'Invoice properties and dates'
                        : 'Sender and recipient',
                    style: const TextStyle(fontSize: 13),
                  ),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    ...fields.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GlacierField(
                          label: entry.key,
                          controller: entry.value,
                          hint:
                              entry.key.contains('from') ||
                                  entry.key.contains('to') &&
                                      entry.key != 'Customer'
                              ? 'YYYY-MM-DD'
                              : null,
                        ),
                      ),
                    ),
                    if (!widget.invoice)
                      GlacierChoice(
                        label: 'Match addresses exactly',
                        selected: exact,
                        onChanged: (value) =>
                            setState(() => exact = value == true),
                        description: 'Otherwise, match addresses containing the entered text.',
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Enter applies search and filters. Esc clears them; press again to close.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Browse values in this library',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    TextButton(
                      onPressed: () => showGlacierDialog<void>(
                        context: context,
                        builder: (_) => const GlacierDialog(
                          title: 'Library values',
                          child: _VocabularyStory(state: 'ready'),
                        ),
                      ),
                      child: const Text('Find a library value'),
                    ),
                  ],
                ),
                if (widget.invoice)
                  const Text(
                    'Inclusive dates. Totals stay exact decimal strings and require a currency. Negative credit-note amounts are supported.',
                  ),
                if (applied.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AppNotice(message: applied),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _VocabularyStory extends StatefulWidget {
  const _VocabularyStory({required this.state});
  final String state;
  @override
  State<_VocabularyStory> createState() => _VocabularyStoryState();
}

final class _VocabularyStoryState extends State<_VocabularyStory> {
  final query = TextEditingController();
  int page = 1;
  String? selected;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CatalogFrame(
    maxWidth: 520,
    child: GlacierVocabularyPicker(
      label: 'library suppliers',
      controller: query,
      values: widget.state == 'empty'
          ? []
          : [
                  'Lumen Energy',
                  'North Insurance',
                  'A long supplier name retained in full for exact selection',
                ]
                .where(
                  (s) => s.toLowerCase().contains(query.text.toLowerCase()),
                )
                .toList(),
      pageLabel: 'Page $page',
      selected: selected,
      onSearch: (_) => setState(() => page = 1),
      onSelect: (value) => setState(() => selected = value),
      onFirst: page > 1 ? () => setState(() => page = 1) : null,
      onPrevious: page > 1 ? () => setState(() => page--) : null,
      onNext: () => setState(() => page++),
      feedback: widget.state == 'error'
          ? AppNotice(
              message:
                  'The next page could not load. Current values are retained.',
              tone: AppTone.warning,
              action: TextButton(onPressed: () {}, child: const Text('Retry')),
            )
          : null,
    ),
  );
}

GlacierInvoiceValue _invoiceValue(int index) => GlacierInvoiceValue(
  number: [
    'LE-2026-1104',
    'FS-2026-042',
    'AG-3910',
    'NL-26-11789',
    'CS-2026-1012',
    'MI-2026-1010',
  ][index],
  supplier: [
    'Lumen Energy',
    'Forma Studio',
    'Atelier Goods',
    'Nordline',
    'City Services',
    'Mountain Insurance',
  ][index],
  amount: ['86.40', '1,785.00', '129.00', '39.90', '48.00', '120.00'][index],
  currency: 'EUR',
  issueDate: [
    '15 Nov 2026',
    '13 Nov 2026',
    '12 Nov 2026',
    '11 Nov 2026',
    '12 Oct 2026',
    '10 Oct 2026',
  ][index],
  dueDate: [
    '29 Nov 2026',
    '27 Nov 2026',
    '26 Nov 2026',
    '25 Nov 2026',
    '26 Oct 2026',
    '24 Oct 2026',
  ][index],
  provenance: index < 2 ? 'E-invoice' : 'AI extracted',
  aiExtracted: index >= 2,
);

final class _InvoiceCollectionStory extends StatefulWidget {
  const _InvoiceCollectionStory();
  @override
  State<_InvoiceCollectionStory> createState() =>
      _InvoiceCollectionStoryState();
}

final class _InvoiceCollectionStoryState
    extends State<_InvoiceCollectionStory> {
  String source = 'All sources', sort = 'Newest added';
  int page = 1;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlacierToolbar(
          trailing: [
            _CatalogInlineSelect(
              label: 'Sort',
              value: sort,
              values: const ['Newest added', 'Oldest added', 'Supplier'],
              transparent: true,
              onChanged: (value) => setState(() => sort = value),
            ),
            GlacierIconButton(
              label: 'About invoice extraction',
              icon: Icons.info_outline,
              onPressed: () => showGlacierDialog<void>(
                context: context,
                builder: (_) => GlacierDialog(
                  title: 'Invoice extraction',
                  actions: [
                    GlacierButton(
                      label: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                  child: const Text(
                    'Structured and AI-extracted values are kept separate. Review AI-extracted amounts against the original.',
                  ),
                ),
              ),
            ),
          ],
          children: [
            _CatalogInlineSelect(
              label: 'Source',
              value: source,
              values: const ['All sources', 'E-invoice', 'AI extracted'],
              onChanged: (value) => setState(() => source = value),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlacierSurface(
                  surface: true,
                  blur: false,
                  padding: EdgeInsets.zero,
                  radius: 15,
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 650
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: .8,
                                    color: GlacierTokens.of(context).muted,
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text('SUPPLIER / INVOICE'),
                                      ),
                                      Expanded(child: Text('ISSUED')),
                                      SizedBox(width: 12),
                                      Expanded(child: Text('DUE')),
                                      SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: Text('EXTRACTION'),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'GROSS TOTAL',
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                      SizedBox(width: 44),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const Divider(),
                      for (var i = 0; i < (page == 1 ? 4 : 2); i++)
                        GlacierInvoiceRow(
                          invoice: _invoiceValue((page - 1) * 4 + i),
                          onOpen: () => showGlacierDialog<void>(
                            context: context,
                            builder: (_) => _InvoiceStory(
                              state: (page - 1) * 4 + i < 2
                                  ? 'structured'
                                  : 'ai',
                              index: (page - 1) * 4 + i,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                GlacierWorkspaceGeometry.measureEndActions(
                  context,
                  followingExtent: 20,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        '6 matching sample invoices · currencies kept separate',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          GlacierButton(
                            label: 'Previous',
                            onPressed: page == 1
                                ? null
                                : () => setState(() => page--),
                          ),
                          Text(
                            '$page / 2',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          GlacierButton(
                            label: 'Next',
                            onPressed: page == 2
                                ? null
                                : () => setState(() => page++),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: GlacierWorkspaceGeometry.trailingOf(
                    context,
                    existingBottom: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class _InvoiceStory extends StatelessWidget {
  const _InvoiceStory({required this.state, this.index = 0});
  final String state;
  final int index;
  @override
  Widget build(BuildContext context) {
    final invoice = _invoiceValue(index);
    final total = '${invoice.amount} ${invoice.currency}';
    final net =
        '${['72.61', '1,500.00', '108.40', '33.53', '40.34', '100.84'][index]} EUR';
    final tax =
        '${['13.79', '285.00', '20.60', '6.37', '7.66', '19.16'][index]} EUR';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlacierInvoiceDetails(
        title: 'Invoice ${invoice.number}',
        sourceLabel: state == 'ai' ? 'AI extracted' : 'E-invoice · CII',
        aiExtracted: state == 'ai',
        onClose: () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        },
        onOpenOriginal: () => showGlacierDialog<void>(
          context: context,
          builder: (_) =>
              documentReaderDialog(index: [1, 3, 5, 6, 2, 4][index]),
        ),
        feedback: state == 'error'
            ? AppNotice(
                message: 'Invoice details could not be refreshed.',
                tone: AppTone.warning,
                action: TextButton(
                  onPressed: () {},
                  child: const Text('Retry'),
                ),
              )
            : state == 'loading'
            ? const AppJobProgress(label: 'Loading invoice details')
            : null,
        sections: state == 'loading'
            ? []
            : [
                GlacierInvoiceSection(
                  title: 'Amounts and dates',
                  values: {
                    'Total including tax': total,
                    'Amount due': total,
                    'Invoice date': invoice.issueDate,
                    'Due date': invoice.dueDate,
                  },
                ),
                GlacierInvoiceSection(
                  title: 'Supplier',
                  values: {
                    'Name': invoice.supplier,
                    'Address': 'Example Street 12\n10115 Berlin\nGermany',
                    'VAT identifier': 'DE000000000',
                    'Email':
                        'billing@${invoice.supplier.toLowerCase().split(' ').first}.example',
                  },
                ),
                const GlacierInvoiceSection(
                  title: 'Customer',
                  values: {
                    'Name': 'Alex Morgan',
                    'Address': 'Lindenstraße 18\n10969 Berlin',
                    'Customer identifier': 'Household 142',
                  },
                ),
                GlacierInvoiceSection(
                  title: 'Amounts',
                  values: {
                    'Net total': net,
                    'Tax total': tax,
                    'Paid amount': '0.00 EUR',
                    'Rounding': '0.00 EUR',
                    'Tax in accounting currency': tax,
                  },
                ),
                GlacierInvoiceRecords(
                  title: 'Line items',
                  pageSize: 3,
                  records: List.generate(
                    index == 0 ? 7 : 1,
                    (i) => GlacierInvoiceDetailRecord(
                      title: i == 0
                          ? 'Services from ${invoice.supplier}'
                          : 'Metered household service ${i + 1}',
                      values: {
                        'Line': '${i + 1}',
                        'Quantity': '1 month',
                        'Unit price': net,
                        'Net amount': net,
                        'Tax category': 'Standard',
                        'Tax rate': '19%',
                      },
                    ),
                  ),
                ),
                GlacierInvoiceRecords(
                  title: 'Tax breakdown',
                  records: [
                    GlacierInvoiceDetailRecord(
                      title: 'Standard rate',
                      values: {
                        'Rate': '19%',
                        'Taxable amount': net,
                        'Tax amount': tax,
                        'Exemption reason': '',
                      },
                    ),
                  ],
                ),
                const GlacierInvoiceRecords(
                  title: 'Allowances and charges',
                  records: [
                    GlacierInvoiceDetailRecord(
                      title: 'Allowance',
                      values: {
                        'Reason': 'Annual billing credit',
                        'Amount': '-5.00 EUR',
                        'Tax category': 'Standard',
                        'Tax rate': '19%',
                      },
                    ),
                  ],
                ),
                GlacierInvoiceSection(
                  title: 'Payment details',
                  values: {
                    'Payment means code': '58 · SEPA transfer',
                    'Payment reference': invoice.number,
                    'IBAN': 'Fictional account',
                    'BIC': 'Fictional bank',
                    'Terms': 'Pay within 15 days',
                  },
                ),
                GlacierInvoiceRecords(
                  title: 'Referenced invoices',
                  records: [
                    GlacierInvoiceDetailRecord(
                      title: 'LE-2026-1004',
                      values: const {
                        'Date': '15 Oct 2026',
                        'Relationship': 'Earlier invoice',
                      },
                      action: GlacierButton(
                        label: 'Open referenced invoice',
                        onPressed: () {},
                      ),
                    ),
                    const GlacierInvoiceDetailRecord(
                      title: 'LE-2025-1104',
                      values: {
                        'Relationship': 'No linked invoice in this library',
                      },
                    ),
                  ],
                ),
                const GlacierInvoiceRecords(
                  title: 'Notes',
                  records: [
                    GlacierInvoiceDetailRecord(
                      title: 'Billing note',
                      values: {
                        'Text': 'Keep this invoice with the original meter statement.',
                      },
                    ),
                  ],
                ),
                GlacierInvoiceSection(
                  title: 'Source',
                  values: {
                    'Document': _document(index: [1, 3, 5, 6, 2, 4][index])
                        .title,
                    'Format': state == 'ai' ? 'AI extracted' : 'CII',
                    'Profile': 'EN 16931',
                    'Extraction model': state == 'ai' ? 'example-model' : '',
                  },
                ),
              ],
      ),
    );
  }
}

Uint8List _fictionalPdf() {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  const content =
      'BT /F1 24 Tf 50 760 Td (LUMEN - Fictional invoice) Tj 0 -60 Td /F1 14 Tf (Services for November: EUR 86.40) Tj 0 -35 Td (Total: EUR 86.40) Tj 0 -70 Td (Sample PDF for component review only.) Tj ET';
  objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  var result = '%PDF-1.4\n';
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(result.length);
    result += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = result.length;
  result += 'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n';
  for (final offset in offsets) {
    result += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  result +=
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(ascii.encode(result));
}

final class _PdfStory extends StatefulWidget {
  const _PdfStory();
  @override
  State<_PdfStory> createState() => _PdfStoryState();
}

final class _PdfStoryState extends State<_PdfStory> {
  final bytes = _fictionalPdf();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: DocumentPdfCanvas(
      bytes: bytes,
      sourceName: 'Fictional Lumen invoice',
      onExtractedText: () {},
      onRetry: () => setState(() {}),
    ),
  );
}

class _PreviewPreparationStory extends StatefulWidget {
  const _PreviewPreparationStory({
    this.mobile = false,
    this.list = false,
    this.bothFailures = false,
  });
  final bool mobile, list, bothFailures;
  @override
  State<_PreviewPreparationStory> createState() =>
      _PreviewPreparationStoryState();
}

class _PreviewPreparationStoryState extends State<_PreviewPreparationStory> {
  late String state = widget.bothFailures
      ? 'Preview unavailable'
      : 'Preparing preview';
  late bool processingFailed = widget.bothFailures;
  @override
  Widget build(BuildContext context) {
    final preview = switch (state) {
      'Preview ready' => const _DocumentArtwork(),
      'Preview unavailable' => ColoredBox(
        color: GlacierTokens.of(context).preview,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            semanticLabel: 'Preview unavailable',
          ),
        ),
      ),
      'No preview' => ColoredBox(
        color: GlacierTokens.of(context).preview,
        child: const Center(
          child: Icon(
            Icons.description_outlined,
            semanticLabel: 'No preview available',
          ),
        ),
      ),
      _ => const GlacierPreviewPlaceholder(),
    };
    final document = GlacierDocumentValue(
      id: 'preview-sample',
      title: 'Household insurance.pdf',
      sender: 'Northstar Insurance',
      date: '12 Nov 2026',
      tags: ['Insurance', 'Home'],
      failed: processingFailed,
    );
    final VoidCallback? retryPreview = state == 'Preview unavailable'
        ? () => setState(() => state = 'Preparing preview')
        : null;
    void retryProcessing() => setState(() => processingFailed = false);
    return CatalogFrame(
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in [
                'Preparing preview',
                'Preview ready',
                'Preview unavailable',
                'No preview',
              ])
                GlacierButton(
                  label: value,
                  onPressed: () => setState(() => state = value),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: widget.list
                ? 520
                : widget.mobile
                ? 186
                : 280,
            child: widget.list
                ? GlacierDocumentRow(
                    document: document,
                    preview: preview,
                    onOpen: () {},
                    onRetry: retryProcessing,
                    onRetryPreview: retryPreview,
                  )
                : widget.mobile
                ? GlacierMobileDocumentCard(
                    document: document,
                    preview: preview,
                    onOpen: () {},
                    onRetry: retryProcessing,
                    onRetryPreview: retryPreview,
                  )
                : GlacierDocumentCard(
                    document: document,
                    preview: preview,
                    onOpen: () {},
                    onRetry: retryProcessing,
                    onRetryPreview: retryPreview,
                  ),
          ),
        ],
      ),
    );
  }
}
