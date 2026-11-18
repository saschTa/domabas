import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'mobile_catalog.dart';

const mobileWorkflowStates = <String, List<String>>{
  'invoices': ['ready', 'filters', 'empty', 'error', 'page-error'],
  'invoice-detail': ['ready', 'unavailable'],
  'chat': [
    'ready',
    'empty',
    'disabled',
    'sending',
    'uncertain',
    'failed',
    'keyboard',
  ],
  'chat-history': ['ready', 'empty', 'page-error'],
  'jobs': ['ready', 'failed', 'unknown', 'stale', 'page-error'],
  'job-detail': [
    'ingestion',
    'ai',
    'thumbnail',
    'email',
    'paperless',
    'unknown',
    'failed',
  ],
  'reindex': ['ready', 'enumerating', 'partial', 'uncertain', 'system'],
};
const _titles = {
  'invoices': 'Invoices',
  'invoice-detail': 'Invoice details',
  'chat': 'Chat',
  'chat-history': 'Conversation history',
  'jobs': 'Jobs and activity',
  'job-detail': 'Processing details',
  'reindex': 'Reindex scope',
};
const _types = {
  'invoices': 'GlacierMobileInvoicesScreen',
  'invoice-detail': 'GlacierMobileInvoiceDetails',
  'chat': 'GlacierMobileChatScreen',
  'chat-history': 'GlacierMobileChatHistory',
  'jobs': 'GlacierMobileJobsScreen',
  'job-detail': 'GlacierMobileJobDetails',
  'reindex': 'GlacierMobileReindexScreen',
};

List<CatalogCase> mobileWorkflowCases() => [
  for (final family in mobileWorkflowStates.entries)
    for (final state in family.value)
      mobileScreenCase(
        screen: family.key,
        state: state,
        title: _titles[family.key]!,
        widgetType: family.key == 'invoices' && state == 'filters'
            ? 'GlacierMobileInvoiceFilters'
            : _types[family.key]!,
        domain: 'Mobile workflows',
        builder: (_) => MobileWorkflowExample(screen: family.key, state: state),
      ),
  for (final component in _components.entries)
    mobileComponentCase(
      id: component.key,
      title: component.value.$1,
      widgetType: component.value.$2,
      referenceComponent: component.value.$3,
      builder: (context) => mobileCatalogShell(
        context,
        title: component.value.$1,
        showNavigation: false,
        showLibrary: false,
        child: _component(context, component.key),
      ),
    ),
];

const _components = <String, (String, String, String)>{
  'invoice-row': ('Invoice row', 'GlacierMobileInvoiceRow', 'invoice-row'),
  'invoice-filters': (
    'Invoice filters',
    'GlacierMobileInvoiceFilters',
    'invoice-row',
  ),
  'invoice-section': (
    'Invoice disclosure',
    'GlacierMobileInvoiceSection',
    'invoice-sections',
  ),
  'chat-message': ('Chat message', 'GlacierMobileChatMessage', 'chat-message'),
  'chat-composer': (
    'Chat composer',
    'GlacierMobileChatComposer',
    'chat-composer',
  ),
  'chat-history-row': (
    'Conversation row',
    'GlacierMobileChatHistoryRow',
    'chat-history-row',
  ),
  'activity-summary': (
    'Activity summary',
    'GlacierMobileActivitySummary',
    'activity-summary',
  ),
  'job-row': ('Job row', 'GlacierMobileJobRow', 'job-row'),
  'pipeline-evidence': (
    'Pipeline evidence',
    'GlacierMobilePipelineEvidence',
    'pipeline-evidence',
  ),
  'reindex-form': (
    'Reindex scope',
    'GlacierMobileReindexScreen',
    'reindex-form',
  ),
};

const _forma = GlacierInvoiceValue(
  number: 'FS-2026-042',
  supplier: 'Forma Studio',
  amount: '€1,785.00',
  currency: 'EUR',
  issueDate: '12 November 2026',
  dueDate: '26 November 2026',
  provenance: 'E-invoice',
);
const _energy = GlacierInvoiceValue(
  number: 'SW-2026-1182',
  supplier: 'Stadtwerke Berlin',
  amount: '€142.80',
  currency: 'EUR',
  issueDate: '9 November 2026',
  dueDate: '23 November 2026',
  provenance: 'AI extracted · Review',
  aiExtracted: true,
);
const _sorts = [
  'Automatic',
  'Newest added',
  'Oldest added',
  'Earliest due date',
  'Latest due date',
  'Earliest issue date',
  'Latest issue date',
  'Invoice number A–Z',
  'Invoice number Z–A',
  'Supplier A–Z',
  'Supplier Z–A',
  'Customer A–Z',
  'Customer Z–A',
];
const _filterOptions = {
  'Currency': ['Any currency', 'EUR', 'GBP', 'USD'],
  'Invoice type': ['Any type', 'Invoice', 'Credit note', 'Corrected invoice'],
  'Format': ['Any format', 'Factur-X', 'XRechnung', 'PDF'],
  'Payment method': ['Any method', 'Credit transfer', 'Direct debit'],
};
const _question = 'What is covered by my home insurance?';
const _answer =
    'Your policy lists cover for fire, water damage and burglary. The contents limit is €75,000, with a €150 excess for each claim.\n\nThe policy excludes gradual damage. Check its wording and endorsements before relying on this summary.';

Widget _component(BuildContext context, String id) => switch (id) {
  'invoice-row' => GlacierMobileInvoiceRow(
    invoice: _forma,
    onOpen: () => mobileCatalogNavigate(context, 'invoice-detail'),
  ),
  'invoice-filters' => const _IsolatedFilters(),
  'invoice-section' => const GlacierMobileInvoiceSection(
    title: 'Amounts',
    initiallyExpanded: true,
    values: {
      'Net total': '€1,500.00',
      'Tax total': '€285.00',
      'Gross total': '€1,785.00',
    },
  ),
  'chat-message' => GlacierMobileChatMessage(
    text: _answer,
    sources: [
      GlacierChatSource(
        title: 'Home insurance · Policy 2026',
        onOpen: () =>
            mobileCatalogNavigate(context, 'reader', arguments: 'insurance'),
      ),
    ],
  ),
  'chat-composer' => const _IsolatedComposer(),
  'chat-history-row' => GlacierMobileChatHistoryRow(
    conversation: const GlacierConversation(
      id: 'insurance',
      title: 'Home insurance',
      updated: 'Today · Personal library',
    ),
    onOpen: () => mobileCatalogNavigate(context, 'chat'),
    onDelete: () {},
  ),
  'activity-summary' => GlacierMobileActivitySummary(
    label: '2 jobs running',
    detail: 'Originals are safe · Processing in background',
    running: true,
    onOpen: () => mobileCatalogNavigate(context, 'jobs'),
  ),
  'job-row' => GlacierMobileJobRow(
    title: 'Home insurance.pdf',
    status: 'Failed',
    stage: 'OCR · Could not read a page',
    onOpen: () => mobileCatalogNavigate(context, 'job-detail', state: 'failed'),
    onRetry: () {},
  ),
  'pipeline-evidence' => GlacierMobilePipelineEvidence(
    stages: _jobEvidence('ingestion').stages,
  ),
  'reindex-form' => const _IsolatedReindex(),
  _ => const SizedBox.shrink(),
};

class MobileWorkflowExample extends StatefulWidget {
  const MobileWorkflowExample({
    super.key,
    required this.screen,
    this.state = 'ready',
  });
  final String screen, state;
  @override
  State<MobileWorkflowExample> createState() => _MobileWorkflowExampleState();
}

class _MobileWorkflowExampleState extends State<MobileWorkflowExample> {
  late String screen = widget.screen, state = widget.state;
  final query = TextEditingController(), draft = TextEditingController();
  String invoiceSource = 'All invoices',
      invoiceSort = 'Automatic',
      committedQuery = '',
      conversation = 'insurance',
      question = _question;
  GlacierInvoiceValue invoice = _forma;
  Map<String, String> filters = {}, draftFilters = {}, drafts = {};
  String? filterError;
  bool invoiceEnd = false,
      historyEnd = false,
      earlier = false,
      jobsEnd = false,
      reindexEnd = false,
      retried = false;
  final deletedConversations = <String>{};
  late GlacierMobileReindexScope scope = widget.state == 'system'
      ? GlacierMobileReindexScope.installation
      : GlacierMobileReindexScope.library;
  late GlacierMobileReindexStatus libraryStatus = widget.screen == 'reindex'
      ? _reindexStatus(widget.state)
      : GlacierMobileReindexStatus.ready;
  GlacierMobileReindexStatus installationStatus =
      GlacierMobileReindexStatus.ready;

  @override
  void dispose() {
    query.dispose();
    draft.dispose();
    super.dispose();
  }

  void go(String next, [String nextState = 'ready']) {
    if (screen == 'chat') drafts[conversation] = draft.text;
    if (next == 'reader') {
      mobileCatalogNavigate(
        context,
        next,
        arguments: nextState == 'ready' ? 'forma' : nextState,
      );
    } else if (mobileWorkflowStates.containsKey(next)) {
      setState(() {
        screen = next;
        state = nextState;
      });
    } else {
      mobileCatalogNavigate(context, next, state: nextState);
    }
  }

  void back() {
    if (screen == 'invoice-detail' ||
        (screen == 'invoices' && state == 'filters')) {
      go('invoices');
    } else if (screen == 'chat-history') {
      go('chat');
    } else if (screen == 'job-detail' || screen == 'reindex') {
      go('jobs');
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      go('more');
    }
  }

  void preview(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Preview: $message')));

  @override
  Widget build(BuildContext context) {
    final forcedKeyboard =
        widget.screen == 'chat' && widget.state == 'keyboard';
    return MediaQuery(
      data: forcedKeyboard
          ? MediaQuery.of(context).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 280),
              padding: MediaQuery.paddingOf(context).copyWith(bottom: 0),
            )
          : MediaQuery.of(context),
      child: Builder(
        builder: (context) {
          final compactComposer =
              screen == 'chat' &&
              MediaQuery.sizeOf(context).height > 500 &&
              MediaQuery.textScalerOf(context).scale(15) <= 22;
          final body = switch (screen) {
            'invoices' => invoiceBody(),
            'invoice-detail' => invoiceDetails(),
            'chat' => chatBody(inlineComposer: !compactComposer),
            'chat-history' => chatHistory(),
            'jobs' => jobsBody(),
            'job-detail' => jobDetails(),
            'reindex' => reindexBody(),
            _ => const SizedBox.shrink(),
          };
          return mobileCatalogShell(
            context,
            title: _titles[screen]!,
            selectedId: screen.startsWith('invoice')
                ? 'invoices'
                : screen.startsWith('chat')
                ? 'chat'
                : 'more',
            showLibrary: screen == 'invoices' || screen == 'chat',
            onBack: screen == 'invoices' || screen == 'chat' ? null : back,
            actions: [
              if (screen == 'chat')
                GlacierIconButton(
                  label: 'Conversation history',
                  icon: Icons.history,
                  onPressed: () => go('chat-history'),
                ),
            ],
            scrollable: !compactComposer,
            footer: compactComposer ? composer() : null,
            child: compactComposer ? SingleChildScrollView(child: body) : body,
          );
        },
      ),
    );
  }

  Widget invoiceBody() {
    if (state == 'filters') {
      return GlacierMobileInvoiceFilters(
        values: draftFilters,
        options: _filterOptions,
        onChanged: (key, value) => draftFilters[key] = value,
        error: filterError,
        onCancel: () => go('invoices'),
        onApply: applyFilters,
      );
    }
    final visible = [_forma, _energy]
        .where(
          (entry) =>
              (invoiceSource == 'All invoices' ||
                  (invoiceSource == 'E-invoices'
                      ? !entry.aiExtracted
                      : entry.aiExtracted)) &&
              '${entry.supplier} ${entry.number}'.toLowerCase().contains(
                committedQuery.toLowerCase(),
              ) &&
              (filters['Supplier']?.isNotEmpty != true ||
                  entry.supplier.toLowerCase().contains(
                    filters['Supplier']!.toLowerCase(),
                  )) &&
              (filters['Currency'] == null ||
                  filters['Currency'] == 'Any currency' ||
                  filters['Currency'] == entry.currency),
        )
        .toList();
    if (invoiceSort.endsWith('Z–A') || invoiceSort == 'Oldest added') {
      visible.sort((a, b) => b.supplier.compareTo(a.supplier));
    }
    return GlacierMobileInvoicesScreen(
      queryController: query,
      invoices: visible,
      source: invoiceSource,
      sort: invoiceSort,
      sortOptions: _sorts,
      onOpen: (value) {
        invoice = value;
        go('invoice-detail');
      },
      onSearch: () => setState(() {
        committedQuery = query.text.trim();
        invoiceEnd = false;
      }),
      onSource: (value) => setState(() {
        invoiceSource = value;
        invoiceEnd = false;
      }),
      onSort: (value) => setState(() => invoiceSort = value),
      onFilters: () {
        draftFilters = Map.of(filters);
        filterError = null;
        go('invoices', 'filters');
      },
      onMore: invoiceEnd
          ? null
          : () => setState(() {
              invoiceEnd = true;
              if (state == 'page-error') state = 'ready';
            }),
      onOpenDocuments: () => go('documents'),
      onClear: () => setState(() {
        query.clear();
        committedQuery = '';
      }),
      empty: state == 'empty',
      notice: state == 'error'
          ? GlacierMobileNotice(
              title: 'Invoices could not load',
              message: 'Your filters are retained. Try the request again.',
              action: GlacierButton(
                label: 'Try again',
                onPressed: () => go('invoices'),
              ),
            )
          : null,
      continuationNotice: state == 'page-error'
          ? GlacierMobileNotice(
              title: 'Next page could not load',
              message: 'The invoices already shown remain available.',
              action: GlacierButton(
                label: 'Retry next page',
                onPressed: () => go('invoices'),
              ),
            )
          : null,
      appliedFilters: [
        for (final entry in filters.entries.where(
          (entry) => entry.value.isNotEmpty && !entry.value.startsWith('Any'),
        ))
          GlacierButton(
            label: '${entry.key}: ${entry.value}',
            icon: Icons.close,
            onPressed: () => setState(() {
              filters.remove(entry.key);
              if (entry.key == 'Currency') {
                filters.remove('Minimum total');
                filters.remove('Maximum total');
              }
            }),
          ),
      ],
    );
  }

  void applyFilters() {
    final errors = <String>[];
    if (((draftFilters['Minimum total'] ?? '').isNotEmpty ||
            (draftFilters['Maximum total'] ?? '').isNotEmpty) &&
        (draftFilters['Currency'] == null ||
            draftFilters['Currency'] == 'Any currency')) {
      errors.add('Choose a currency for the total range.');
    }
    for (final prefix in ['Added', 'Issued', 'Due']) {
      final from = draftFilters['$prefix from'] ?? '',
          to = draftFilters['$prefix to'] ?? '';
      if (from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0) {
        errors.add('$prefix start must be before its end.');
      }
    }
    for (final key in ['Minimum total', 'Maximum total']) {
      final value = draftFilters[key] ?? '';
      if (value.isNotEmpty &&
          !RegExp(r'^-?\d{1,24}(\.\d{1,12})?$').hasMatch(value)) {
        errors.add('$key must be a decimal amount.');
      }
    }
    if (errors.isNotEmpty) {
      setState(() => filterError = errors.join(' '));
      return;
    }
    filters = Map.of(draftFilters);
    invoiceEnd = false;
    go('invoices');
  }

  Widget invoiceDetails() {
    final energy = invoice.aiExtracted;
    final net = energy ? '€120.00' : '€1,500.00',
        tax = energy ? '€22.80' : '€285.00';
    Widget section(
      String title,
      Map<String, String> values, {
      bool open = false,
      Widget? child,
    }) => GlacierMobileInvoiceSection(
      title: title,
      values: values,
      initiallyExpanded: open,
      child: child,
    );
    return GlacierMobileInvoiceDetails(
      invoice: invoice,
      unavailable: state == 'unavailable',
      onBack: () => go('invoices'),
      onOpenOriginal: () => go('reader', energy ? 'energy' : 'forma'),
      sections: [
        GlacierMobileInvoiceSection(
          title: 'Supplier and customer',
          initiallyExpanded: true,
          records: [
            GlacierInvoiceDetailRecord(
              title: 'Supplier',
              values: {
                'Name': invoice.supplier,
                'Address': energy
                    ? 'Alexanderplatz 1, 10178 Berlin, Germany'
                    : 'Waldstraße 8, 10115 Berlin, Germany',
                'Tax identifier': energy ? 'Not recorded' : 'DE123456789',
                'Email': energy
                    ? 'service@stadtwerke.example'
                    : 'billing@forma.example',
              },
            ),
            const GlacierInvoiceDetailRecord(
              title: 'Customer',
              values: {
                'Name': 'Alex Morgan',
                'Address': 'Oak Street 12, Berlin, Germany',
                'Reference': 'Personal library',
              },
            ),
          ],
        ),
        section('Amounts', {
          'Net total': net,
          'Tax total': tax,
          'Gross total': invoice.amount,
          'Paid amount': '€0.00',
          'Amount due': invoice.amount,
          'Rounding': '€0.00',
          'Tax accounting currency': 'Not recorded',
        }, open: true),
        GlacierMobileInvoiceSection(
          title: 'Line items',
          records: [
            GlacierInvoiceDetailRecord(
              title: energy ? 'Electricity supply' : 'Design consultation',
              values: {
                'Line': '1',
                'Quantity': '1 C62',
                'Unit price': net,
                'Net amount': net,
                'Tax category': 'S · Standard rate',
                'Tax rate': '19%',
              },
            ),
          ],
          initiallyExpanded: true,
          child: const Text('1 line shown · All lines loaded.'),
        ),
        section('Tax breakdown', {
          'Rate': '19%',
          'Taxable amount': net,
          'Tax amount': tax,
          'Exemption reason': 'Not recorded',
        }),
        section(
          'Allowances and charges',
          {},
          child: const Text('No allowances or additional charges recorded.'),
        ),
        section('Payment details', {
          'Method': 'Credit transfer · Code 58',
          'Payment reference': invoice.number,
          'IBAN': 'DE00 0000 0000 0000 0000 00',
          'BIC': 'EXAMPLEXXX',
          'Terms': 'Pay within 14 days.',
        }),
        section(
          'References and notes',
          {'Reference': 'ORDER-2026-084', 'Linked invoice': 'Not recorded'},
          child: const Text(
            'No other linked invoice is recorded in this library.\n\nThank you for working with us. This is a fictional design example.',
          ),
        ),
        section(
          'Source and provenance',
          {
            'Document': '${invoice.supplier} invoice.pdf',
            'Format': energy ? 'PDF' : 'Factur-X',
            'Profile': energy ? 'Not recorded' : 'EN16931',
            'Extraction model': energy
                ? 'local-model'
                : 'Not applicable · Embedded XML',
            'Library': 'Personal library',
          },
          child: GlacierButton(
            label: 'Open source document',
            onPressed: () => go('reader', energy ? 'energy' : 'forma'),
          ),
        ),
      ],
    );
  }

  Widget composer() => GlacierMobileChatComposer(
    controller: draft,
    state: switch (state) {
      'sending' => GlacierMobileChatSubmitState.sending,
      'uncertain' => GlacierMobileChatSubmitState.uncertain,
      'disabled' => GlacierMobileChatSubmitState.disabled,
      _ => GlacierMobileChatSubmitState.ready,
    },
    onSend: () {
      if (draft.text.trim().isEmpty) return;
      setState(() {
        question = draft.text.trim();
        draft.clear();
        drafts[conversation] = '';
        state = 'sending';
      });
    },
    onStop: () => setState(() => state = 'failed'),
    onCheck: () {
      setState(() => state = 'ready');
      preview('the same request was checked; no new message was sent');
    },
  );

  void newChat() {
    drafts[conversation] = draft.text;
    conversation = 'new';
    draft.text = drafts[conversation] ?? '';
    go('chat', 'empty');
  }

  Widget chatBody({required bool inlineComposer}) {
    final pending = state == 'sending',
        uncertain = state == 'uncertain',
        failed = state == 'failed';
    final response = pending
        ? GlacierMobileNotice(
            title: 'Searching your library',
            message: 'The reply is running. No completion time is recorded.',
            action: GlacierButton(
              label: 'Stop reply',
              onPressed: () => setState(() => state = 'failed'),
            ),
          )
        : uncertain
        ? GlacierMobileNotice(
            title: 'Message outcome unknown',
            message: 'Your question is retained. Check the same message before sending anything else.',
            action: GlacierButton(
              label: 'Check sent message',
              onPressed: () => setState(() => state = 'ready'),
            ),
          )
        : failed
        ? GlacierMobileNotice(
            title: 'The reply did not finish',
            message: 'Your question is still in this conversation. Send again starts a new question.',
            action: GlacierButton(
              label: 'Use question again',
              onPressed: () => setState(() {
                draft.text = question;
                state = 'ready';
              }),
            ),
          )
        : GlacierMobileChatMessage(
            text: _answer,
            sources: [
              GlacierChatSource(
                title: 'Home insurance · Policy 2026',
                onOpen: () => go('reader', 'insurance'),
              ),
            ],
          );
    return GlacierMobileChatScreen(
      onHistory: () => go('chat-history'),
      onNew: newChat,
      onEarlier: earlier ? null : () => setState(() => earlier = true),
      onSuggestion: () => setState(() => draft.text = _question),
      empty: state == 'empty',
      notice: state == 'disabled'
          ? const GlacierMobileNotice(
              title: 'Chat is currently disabled',
              message: 'Your conversation history is still available. New messages cannot be sent.',
            )
          : null,
      composer: inlineComposer ? composer() : null,
      messages: [
        if (earlier)
          const GlacierMobileChatMessage(
            text: 'Which policy is the current one?',
            author: 'Earlier question',
          ),
        GlacierMobileChatMessage(text: question, fromUser: true),
        response,
      ],
    );
  }

  Widget chatHistory() => GlacierMobileChatHistory(
    conversations: state == 'empty'
        ? []
        : [
            for (final item in [
              const GlacierConversation(
                id: 'insurance',
                title: 'Home insurance',
                updated: 'Today · Personal library',
              ),
              const GlacierConversation(
                id: 'energy',
                title: 'Energy costs',
                updated: 'Yesterday · Personal library',
              ),
              if (historyEnd)
                const GlacierConversation(
                  id: 'tax',
                  title: 'Tax documents',
                  updated: '12 November · Personal library',
                ),
            ])
              if (!deletedConversations.contains(item.id)) item,
          ],
    onNew: newChat,
    onOpen: (id) {
      drafts[conversation] = draft.text;
      conversation = id;
      draft.text = drafts[id] ?? '';
      go('chat');
    },
    onDelete: (id) => confirmDeleteChat(id),
    onMore: historyEnd ? null : () => setState(() => historyEnd = true),
    pageError: state == 'page-error',
    onRetry: () => setState(() {
      state = 'ready';
      historyEnd = true;
    }),
  );

  Future<void> confirmDeleteChat(String id) async {
    final accepted = await showGlacierMobileSheet<bool>(
      context: context,
      builder: (context) => GlacierMobileSheet(
        footer: GlacierMobileActionBar(
          children: [
            GlacierButton(
              label: 'Keep conversation',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            GlacierButton(
              label: 'Delete conversation',
              onPressed: () => Navigator.of(context).pop(true),
              kind: GlacierButtonKind.danger,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete this conversation?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'Its messages will be removed from your history. Your documents are retained.',
            ),
          ],
        ),
      ),
    );
    if (mounted && accepted == true) {
      setState(() => deletedConversations.add(id));
    }
  }

  Widget job(
    String title,
    String status,
    String stage,
    String pipeline, {
    bool retry = false,
  }) => GlacierMobileJobRow(
    title: title,
    status: retry && retried ? 'Running' : status,
    stage: retry && retried
        ? 'Retry accepted for the retained original'
        : stage,
    running: status == 'Running' || (retry && retried),
    onOpen: () => go('job-detail', retry && retried ? 'ingestion' : pipeline),
    onRetry: retry && !retried ? () => setState(() => retried = true) : null,
  );

  Widget jobsBody() => GlacierMobileJobsScreen(
    onReindex: () => go('reindex'),
    onSettings: () => go('processing-settings'),
    onFilter: (label) =>
        go('jobs', label == 'Needs attention' ? 'failed' : 'ready'),
    notice: state == 'stale'
        ? GlacierMobileNotice(
            title: 'Showing saved results',
            message: 'Live updates are unavailable. You can still use these results.',
            action: GlacierButton(
              label: 'Refresh',
              onPressed: () => go('jobs'),
            ),
          )
        : null,
    activityNotice: state == 'unknown'
        ? GlacierMobileNotice(
            title: 'Progress is not recorded',
            message:
                'This job is running. A total and percentage are not supplied.',
            action: GlacierButton(
              label: 'View recorded evidence',
              onPressed: () => go('job-detail', 'unknown'),
            ),
          )
        : null,
    activeJobs: state == 'failed'
        ? [
            job(
              'Home insurance.pdf',
              'Failed',
              'OCR · Could not read a page',
              'failed',
              retry: true,
            ),
          ]
        : [
            job(
              'Home insurance.pdf',
              'Running',
              'Preparing searchable text',
              'ingestion',
            ),
            job(
              'Forma invoice.pdf',
              'Running',
              'Extracting invoice properties',
              'ai',
            ),
          ],
    recentJobs: [
      job(
        'Energy bill.pdf',
        'Completed',
        'Original indexed; AI check finished',
        'thumbnail',
      ),
      job(
        'Household inbox',
        'Completed',
        '18 messages checked; 3 originals accepted',
        'email',
      ),
      job(
        'Paperless archive',
        'Partially completed',
        '48 accepted; 2 files need attention',
        'paperless',
      ),
      if (jobsEnd)
        job('Tax records.pdf', 'Completed', 'Original indexed', 'ingestion'),
    ],
    onMore: jobsEnd ? null : () => setState(() => jobsEnd = true),
    pageError: state == 'page-error'
        ? 'The jobs already shown remain available.'
        : null,
    onRetryPage: () => setState(() {
      state = 'ready';
      jobsEnd = true;
    }),
  );

  Widget jobDetails() {
    final value = _jobEvidence(state);
    return GlacierMobileJobDetails(
      title: value.title,
      name: value.name,
      status: value.status,
      stage: value.stage,
      stages: value.stages,
      values: value.values,
      requestDetails: const {
        'Request': 'example-job-7f2a',
        'Started': '17 November 2026, 09:42',
        'Last update': '17 November 2026, 09:43',
      },
      onBack: () => go('jobs'),
      onOpenDocument: ['email', 'paperless'].contains(state)
          ? null
          : () => go(
              'reader',
              state == 'ai'
                  ? 'forma'
                  : state == 'thumbnail'
                  ? 'energy'
                  : 'insurance',
            ),
      notice: state == 'failed'
          ? GlacierMobileNotice(
              title: 'This original needs another attempt',
              message: 'The original is retained. Retry the failed processing job; this does not upload a second copy.',
              action: GlacierButton(
                label: 'Retry processing',
                onPressed: () {
                  retried = true;
                  go('job-detail', 'ingestion');
                },
                kind: GlacierButtonKind.primary,
              ),
            )
          : state == 'paperless'
          ? GlacierMobileNotice(
              title: 'Some files were not imported',
              message:
                  'Open individual outcomes before deciding what to retry.',
              action: GlacierButton(
                label: 'Review outcomes',
                onPressed: () => go('paperless-outcomes'),
              ),
            )
          : null,
      disclaimer: 'The status and steps above are fictional recorded examples; no job is running in this prototype.',
    );
  }

  Widget reindexBody() => GlacierMobileReindexScreen(
    scope: scope,
    libraryStatus: libraryStatus,
    installationStatus: installationStatus,
    onScopeChanged: (value) => setState(() => scope = value),
    onStart: () => setState(() {
      if (scope == GlacierMobileReindexScope.library) {
        libraryStatus = GlacierMobileReindexStatus.enumerating;
      } else {
        installationStatus = GlacierMobileReindexStatus.enumerating;
      }
    }),
    onCheck: () => setState(() {
      if (scope == GlacierMobileReindexScope.library) {
        libraryStatus = GlacierMobileReindexStatus.partial;
      } else {
        installationStatus = GlacierMobileReindexStatus.partial;
      }
    }),
    partialMessage: '12 requests accepted. 2 originals could not be scheduled. Accepted requests continue processing.',
    onReviewJobs: () => go('jobs', 'failed'),
    onMore: reindexEnd ? null : () => setState(() => reindexEnd = true),
    history: [
      GlacierMobileRecordRow(
        title: 'Personal library · Originals',
        detail: '12 November · Completed · 42 accepted',
        icon: Icons.sync,
        onTap: () => go('jobs'),
      ),
      if (reindexEnd)
        GlacierMobileRecordRow(
          title: 'Personal library · Originals',
          detail: '9 November · Completed · 16 accepted',
          icon: Icons.image_outlined,
          onTap: () => go('jobs'),
        ),
    ],
  );
}

GlacierMobileReindexStatus _reindexStatus(String value) => switch (value) {
  'enumerating' => GlacierMobileReindexStatus.enumerating,
  'partial' => GlacierMobileReindexStatus.partial,
  'uncertain' => GlacierMobileReindexStatus.uncertain,
  _ => GlacierMobileReindexStatus.ready,
};

typedef _JobEvidence = ({
  String title,
  String name,
  String status,
  String stage,
  List<GlacierPipelineStage> stages,
  Map<String, String> values,
});

_JobEvidence _jobEvidence(String state) {
  GlacierPipelineStage step(
    String label,
    String detail,
    GlacierStageState state,
  ) => GlacierPipelineStage(label: label, detail: detail, state: state);
  const done = GlacierStageState.complete,
      running = GlacierStageState.running,
      waiting = GlacierStageState.waiting,
      failed = GlacierStageState.failed;
  return switch (state) {
    'ai' => (
      title: 'AI processing',
      name: 'Forma invoice.pdf',
      status: 'Running',
      stage: 'Extracting invoice properties',
      stages: [
        step('Embedded invoice', 'Structured XML extracted.', done),
        step('Invoice AI', 'Running · local-model', running),
        step(
          'Property extraction',
          'Waiting · Enabled for this request.',
          waiting,
        ),
      ],
      values: {
        'Original': 'Searchable',
        'Model': 'local-model',
        'Property extraction': 'Enabled when request was accepted',
      },
    ),
    'thumbnail' => (
      title: 'Thumbnail generation',
      name: 'Energy bill.pdf',
      status: 'Completed',
      stage: 'Preview ready',
      stages: [
        step('Read original', 'Completed', done),
        step('Render first page', 'Completed', done),
        step('Save preview', 'Completed', done),
      ],
      values: {'Preview': 'Recorded', 'Original': 'Retained'},
    ),
    'email' => (
      title: 'Email import',
      name: 'Household inbox',
      status: 'Completed',
      stage: '18 messages checked',
      stages: [
        step('Connect', 'Completed · Saved account', done),
        step('Read mailbox', '18 messages checked', done),
        step('Accept originals', '3 accepted; 15 already known', done),
      ],
      values: {
        'Mailbox': 'INBOX',
        'Attachments': 'Continue through document processing',
      },
    ),
    'paperless' => (
      title: 'Paperless import',
      name: 'Personal library archive',
      status: 'Partially completed',
      stage: '48 accepted; 2 rejected',
      stages: [
        step('Discover documents', '50 listed', done),
        step(
          'Retrieve originals',
          '48 accepted; 2 source files unavailable',
          failed,
        ),
        step('Finish import', 'Partially completed', failed),
      ],
      values: {'Accepted': '48', 'Rejected': '2', 'Total': '50 recorded'},
    ),
    'unknown' => (
      title: 'Document ingestion',
      name: 'Archive scan.pdf',
      status: 'Running',
      stage: 'Stage not recorded',
      stages: [],
      values: {
        'Completed items': 'Not recorded',
        'Total': 'Not recorded',
        'Original': 'Retained',
      },
    ),
    'failed' => (
      title: 'Document ingestion',
      name: 'Home insurance.pdf',
      status: 'Failed',
      stage: 'OCR could not read a page',
      stages: [
        step('Read original', 'Completed', done),
        step('OCR', 'Failed · Page image unavailable', failed),
        step('Indexing', 'Not started', waiting),
      ],
      values: {
        'Failure': 'The processor could not read one page.',
        'Original': 'Retained',
      },
    ),
    _ => (
      title: 'Document ingestion',
      name: 'Home insurance.pdf',
      status: 'Running',
      stage: 'Preparing searchable text',
      stages: [
        step('Accepted', 'Original is saved in staging.', done),
        step('Text extraction', 'Recorded: 4 pages read.', done),
        step('OCR', 'Running · Recognizing page text.', running),
        step('Indexing', 'Waiting for text extraction.', waiting),
      ],
      values: {},
    ),
  };
}

class _IsolatedComposer extends StatefulWidget {
  const _IsolatedComposer();
  @override
  State<_IsolatedComposer> createState() => _IsolatedComposerState();
}

class _IsolatedComposerState extends State<_IsolatedComposer> {
  final controller = TextEditingController();
  var status = GlacierMobileChatSubmitState.ready;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlacierMobileChatComposer(
    controller: controller,
    state: status,
    onSend: () => setState(() => status = GlacierMobileChatSubmitState.sending),
    onStop: () => setState(() => status = GlacierMobileChatSubmitState.ready),
  );
}

class _IsolatedFilters extends StatefulWidget {
  const _IsolatedFilters();
  @override
  State<_IsolatedFilters> createState() => _IsolatedFiltersState();
}

class _IsolatedFiltersState extends State<_IsolatedFilters> {
  final values = <String, String>{};
  @override
  Widget build(BuildContext context) => GlacierMobileInvoiceFilters(
    values: values,
    options: _filterOptions,
    onChanged: (key, value) => values[key] = value,
    onApply: () {},
    onCancel: () {},
  );
}

class _IsolatedReindex extends StatefulWidget {
  const _IsolatedReindex();
  @override
  State<_IsolatedReindex> createState() => _IsolatedReindexState();
}

class _IsolatedReindexState extends State<_IsolatedReindex> {
  var scope = GlacierMobileReindexScope.library;
  var library = GlacierMobileReindexStatus.ready;
  var installation = GlacierMobileReindexStatus.ready;
  @override
  Widget build(BuildContext context) => GlacierMobileReindexScreen(
    scope: scope,
    libraryStatus: library,
    installationStatus: installation,
    onScopeChanged: (value) => setState(() => scope = value),
    onStart: () => setState(() {
      if (scope == GlacierMobileReindexScope.library) {
        library = GlacierMobileReindexStatus.enumerating;
      } else {
        installation = GlacierMobileReindexStatus.enumerating;
      }
    }),
    onCheck: () => setState(() {
      if (scope == GlacierMobileReindexScope.library) {
        library = GlacierMobileReindexStatus.partial;
      } else {
        installation = GlacierMobileReindexStatus.partial;
      }
    }),
  );
}
