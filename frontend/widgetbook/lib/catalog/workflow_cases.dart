import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';

import 'catalog_case.dart';
import 'catalog_frame.dart';
import 'documents_cases.dart';

List<CatalogCase> workflowCases() => [
  CatalogCase(
    id: 'jobs-history',
    domain: 'Jobs and activity',
    component: 'History',
    name: 'Interactive history',
    widgetType: 'GlacierJobsScreen',
    builder: (_) => const _JobsExample(),
  ),
  CatalogCase(
    id: 'jobs-empty',
    domain: 'Jobs and activity',
    component: 'History',
    name: 'No matches',
    widgetType: 'GlacierJobsScreen',
    builder: (_) => const _JobsExample(empty: true),
  ),
  CatalogCase(
    id: 'jobs-stale',
    domain: 'Jobs and activity',
    component: 'History',
    name: 'Stale retained results',
    widgetType: 'GlacierJobsScreen',
    builder: (_) => const _JobsExample(stale: true),
  ),
  CatalogCase(
    id: 'jobs-loading',
    domain: 'Jobs and activity',
    component: 'History',
    name: 'Loading',
    widgetType: 'GlacierJobsScreen',
    builder: (_) => const _JobsExample(loading: true),
  ),
  CatalogCase(
    id: 'jobs-record-states',
    domain: 'Jobs and activity',
    component: 'Job row',
    name: 'Recorded outcomes',
    widgetType: 'GlacierJobRow',
    builder: (_) => CatalogFrame(
      child: Column(
        children: [
          for (final status in [
            'Waiting to start',
            'Running',
            'Failed',
            'Partial',
            'Completed',
            'Cancelled',
            'Not recorded',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlacierJobRow(
                title: 'Household record',
                pipeline: 'Document ingestion',
                timestamp: 'Today, 09:41',
                status: status,
                onOpen: () {},
                running: status == 'Running',
                tone: status == 'Failed' ? AppTone.danger : AppTone.neutral,
                detail: status == 'Not recorded'
                    ? 'This older attempt has no retained stage evidence.'
                    : null,
              ),
            ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'jobs-pipeline-states',
    domain: 'Jobs and activity',
    component: 'Pipeline',
    name: 'All evidence states',
    widgetType: 'GlacierPipelineTimeline',
    builder: (_) => CatalogFrame(
      child: GlacierPipelineTimeline(
        stages: [
          for (final state in GlacierStageState.values)
            GlacierPipelineStage(
              label:
                  '${state.name[0].toUpperCase()}${state.name.substring(1)} stage',
              state: state,
              detail: state == GlacierStageState.unknown
                  ? 'Earlier history did not retain this evidence.'
                  : null,
            ),
        ],
      ),
    ),
  ),
  for (final pipeline in _pipelines.keys)
    CatalogCase(
      id: 'jobs-detail-${_pipelineId(pipeline)}',
      domain: 'Jobs and activity',
      component: 'Attempt details',
      name: pipeline,
      widgetType: 'GlacierJobDetails',
      builder: (_) => _JobDetailExample(pipeline: pipeline),
    ),
  CatalogCase(
    id: 'jobs-item-outcomes',
    domain: 'Jobs and activity',
    component: 'Item outcomes',
    name: 'Accepted duplicate and failed',
    widgetType: 'GlacierJobOutcome',
    builder: (_) => CatalogFrame(
      child: Column(
        children: [
          GlacierJobOutcome(
            title: 'Electricity.pdf',
            outcome: 'Queued',
            detail: 'Accepted for separate document ingestion. Processing is not complete.',
            onOpen: () {},
          ),
          GlacierJobOutcome(
            title: 'Insurance.pdf',
            outcome: 'Duplicate',
            detail: 'An identical original already exists in this library.',
            onOpen: () {},
          ),
          GlacierJobOutcome(
            title: 'Receipt.pdf',
            outcome: 'Failed',
            failed: true,
            detail: 'The source did not return the original.',
            onRetry: () {},
          ),
        ],
      ),
    ),
  ),
  CatalogCase(
    id: 'activity-active',
    domain: 'Jobs and activity',
    component: 'Activity',
    name: 'Active work and receipts',
    widgetType: 'GlacierActivityPanel',
    builder: (_) => const _ActivityExample(),
  ),
  CatalogCase(
    id: 'activity-stale',
    domain: 'Jobs and activity',
    component: 'Activity',
    name: 'Connection interrupted',
    widgetType: 'GlacierActivityPanel',
    builder: (_) => const _ActivityExample(stale: true),
  ),
  CatalogCase(
    id: 'reindex-enumerating',
    domain: 'Jobs and activity',
    component: 'Reindex',
    name: 'Finding originals',
    widgetType: 'GlacierReindexProgress',
    builder: (_) => CatalogFrame(
      child: GlacierReindexProgress(
        scope: 'Current library · Personal',
        status: 'Finding originals',
        summary:
            'Accepted. The total is not known until enumeration completes.',
        enumerating: true,
        onDetails: () {},
      ),
    ),
  ),
  CatalogCase(
    id: 'reindex-outcomes',
    domain: 'Jobs and activity',
    component: 'Reindex',
    name: 'Completed with failures',
    widgetType: 'GlacierReindexProgress',
    builder: (_) => CatalogFrame(
      child: GlacierReindexProgress(
        scope: 'All libraries',
        status: 'Completed with failures',
        summary: 'Review the failed originals before retrying. A finished request is not necessarily a successful request.',
        total: 42,
        succeeded: 37,
        failed: 2,
        skipped: 2,
        superseded: 1,
        onDetails: () {},
      ),
    ),
  ),
  CatalogCase(
    id: 'chat-new',
    domain: 'Chat',
    component: 'Workspace',
    name: 'New conversation',
    widgetType: 'GlacierChatScreen',
    builder: (_) => const _ChatExample(empty: true),
  ),
  CatalogCase(
    id: 'chat-conversation',
    domain: 'Chat',
    component: 'Workspace',
    name: 'Conversation and sources',
    widgetType: 'GlacierChatScreen',
    builder: (_) => const _ChatExample(),
  ),
  CatalogCase(
    id: 'chat-disabled',
    domain: 'Chat',
    component: 'Workspace',
    name: 'Disabled with readable history',
    widgetType: 'GlacierChatScreen',
    builder: (_) => const _ChatExample(disabled: true),
  ),
  CatalogCase(
    id: 'chat-uncertain',
    domain: 'Chat',
    component: 'Workspace',
    name: 'Uncertain acceptance',
    widgetType: 'GlacierChatScreen',
    builder: (_) => const _ChatExample(uncertain: true),
  ),
  CatalogCase(
    id: 'chat-history',
    domain: 'Chat',
    component: 'Conversation history',
    name: 'Selection deletion and continuation',
    widgetType: 'GlacierConversationHistory',
    builder: (_) => const _HistoryExample(),
  ),
  CatalogCase(
    id: 'chat-composer',
    domain: 'Chat',
    component: 'Composer',
    name: 'Draft and keyboard send',
    widgetType: 'GlacierChatComposer',
    builder: (_) => const _ChatExample(composerOnly: true),
  ),
  CatalogCase(
    id: 'chat-message',
    domain: 'Chat',
    component: 'Message',
    name: 'Selectable answer and sources',
    widgetType: 'GlacierChatMessage',
    builder: (context) => CatalogFrame(
      child: GlacierChatMessage(
        text: 'Your lease says that ordinary notice must be received in writing three months before the end of the tenancy period.',
        sources: [
          GlacierChatSource(
            title: 'Studio lease · 2026',
            excerpt: 'Notice must be received in writing.',
            onOpen: () => _feedback(
              context,
              'The source callback opened the fictional original.',
            ),
          ),
        ],
      ),
    ),
  ),
  for (final status in [
    'Waiting to start',
    'Preparing',
    'Thinking',
    'Searching your library',
    'Reading documents',
    'Stop requested',
    'Cancelled',
    'Failed',
  ])
    CatalogCase(
      id: 'chat-message-${status.toLowerCase().replaceAll(' ', '-')}',
      domain: 'Chat',
      component: 'Reply progress',
      name: status,
      widgetType: 'GlacierChatMessage',
      builder: (_) => CatalogFrame(
        child: GlacierChatMessage(
          text: '',
          status: status,
          statusDescription: switch (status) {
            'Waiting to start' => 'Accepted and waiting for shared capacity. No completion estimate is available.',
            'Stop requested' =>
              'Waiting for confirmation that this reply has stopped.',
            'Cancelled' => 'This reply was stopped. Your question remains in the conversation.',
            'Failed' =>
              'The reply could not finish. Your question is still available.',
            _ => 'The recorded reply stage is shown here.',
          },
          active: !['Cancelled', 'Failed'].contains(status),
          failed: status == 'Failed',
          onSendAgain: ['Cancelled', 'Failed'].contains(status) ? () {} : null,
        ),
      ),
    ),
];

const _pipelines = <String, List<String>>{
  'Document ingestion': [
    'Original',
    'Text extraction',
    'Embeddings',
    'Publish index',
  ],
  'Document AI': ['Invoice extraction', 'Property extraction'],
  'Thumbnails': ['Original', 'Render thumbnail', 'Thumbnail ready'],
  'Email retrieval': [
    'Mailbox schedule',
    'Retrieval queue',
    'Message discovery',
    'Email originals',
    'Attachments',
    'Document ingestion',
  ],
  'Paperless import': [
    'Import queue',
    'Document discovery',
    'Import originals',
    'Document ingestion',
  ],
};

String _pipelineId(String pipeline) =>
    pipeline.toLowerCase().replaceAll(' ', '-');

void _feedback(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class _JobsExample extends StatefulWidget {
  const _JobsExample({
    this.empty = false,
    this.stale = false,
    this.loading = false,
  });
  final bool empty, stale, loading;
  @override
  State<_JobsExample> createState() => _JobsExampleState();
}

class _JobsExampleState extends State<_JobsExample> {
  String pipeline = 'All pipelines';
  String status = 'All statuses';
  bool older = false;
  String outcome(String family) => switch (family) {
    'Document ingestion' => 'Running',
    'Document AI' => 'Waiting to start',
    'Paperless import' => 'Partially completed',
    _ => 'Completed',
  };
  void reindex(String scope) => showGlacierDialog<void>(
    context: context,
    builder: (context) => GlacierDialog(
      title: 'Reindex $scope?',
      actions: [
        GlacierButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GlacierButton(
          label: 'Create sample request',
          kind: GlacierButtonKind.primary,
          onPressed: () {
            Navigator.pop(context);
            _feedback(
              this.context,
              'Sample request accepted. No backend jobs were created.',
            );
          },
        ),
      ],
      child: Text(
        'Repeat extraction and indexing for $scope. Originals are retained. This local example does not create backend jobs.',
      ),
    ),
  );
  void openJob(String pipeline) => showGlacierDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: GlacierSurface(
        radius: 20,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 620,
          height: (MediaQuery.sizeOf(context).height * .84).clamp(
            0,
            pipeline == 'Email retrieval' || pipeline == 'Paperless import'
                ? 756
                : 620,
          ),
          child: _JobDetailExample(
            pipeline: pipeline,
            recordTitle: switch (pipeline) {
              'Document ingestion' => 'Studio lease · 2026',
              'Document AI' => 'November electricity',
              'Paperless import' => 'Paperless archive',
              'Email retrieval' => 'Personal inbox',
              _ => 'Health insurance',
            },
            recordedStatus: outcome(pipeline),
            onBack: () => Navigator.pop(context),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: GlacierJobsScreen(
      toolbarActions: [
        const Text(
          'Newest first · recorded outcomes',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(width: 12),
        GlacierButton(
          label: 'Resource rules',
          icon: Icons.info_outline,
          onPressed: () => showGlacierDialog<void>(
            context: context,
            builder: (context) => const GlacierDialog(
              title: 'Resource rules',
              child: Text(
                'Retrieval and thumbnails need worker capacity. Ingestion also needs Ollama; document AI needs its accepted provider. Waiting does not identify which resource is unavailable unless recorded. An accepted original continues processing after this screen closes.',
              ),
            ),
          ),
        ),
      ],
      introduction: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Text(
            '2 active sample jobs · Personal library',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              GlacierButton(
                label: 'Your activity',
                onPressed: () => showGlacierDialog<void>(
                  context: context,
                  builder: (context) => GlacierDialog(
                    title: 'Your activity',
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * .55,
                      child: const _ActivityExample(),
                    ),
                  ),
                ),
              ),
              GlacierButton(
                label: 'Reindex library',
                onPressed: () => reindex('this library'),
              ),
              GlacierButton(
                label: 'Reindex all libraries',
                onPressed: () => reindex('all libraries'),
              ),
            ],
          ),
        ],
      ),
      loading: widget.loading,
      notice: widget.stale
          ? const AppNotice(
              message:
                  'Updates are paused. These are the last recorded results.',
              tone: AppTone.warning,
            )
          : null,
      filters: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _WorkflowFilter(
            label: 'Status',
            value: status,
            options: const [
              'All statuses',
              'Running',
              'Waiting to start',
              'Completed',
              'Partially completed',
            ],
            onChanged: (value) => setState(() => status = value),
          ),
          _WorkflowFilter(
            label: 'Pipeline',
            value: pipeline,
            options: ['All pipelines', ..._pipelines.keys],
            onChanged: (value) => setState(() => pipeline = value),
          ),
          if (pipeline != 'All pipelines')
            GlacierButton(
              label: 'Clear filters',
              onPressed: () => setState(() => pipeline = 'All pipelines'),
              kind: GlacierButtonKind.quiet,
            ),
        ],
      ),
      jobs: widget.empty || widget.loading
          ? []
          : [
              for (final family in _pipelines.keys.where(
                (value) =>
                    (pipeline == 'All pipelines' || pipeline == value) &&
                    (status == 'All statuses' || outcome(value) == status),
              ))
                GlacierJobRow(
                  title: switch (family) {
                    'Document ingestion' => 'Studio lease · 2026',
                    'Document AI' => 'November electricity',
                    'Paperless import' => 'Paperless archive',
                    'Email retrieval' => 'Personal inbox',
                    _ => 'Health insurance',
                  },
                  pipeline: family == 'Thumbnails'
                      ? 'Thumbnail generation'
                      : family,
                  timestamp: 'Today, 10:42',
                  duration: switch (family) {
                    'Document ingestion' => '32 seconds',
                    'Document AI' => '—',
                    'Paperless import' => '2 min 14 sec',
                    _ => '8 seconds',
                  },
                  status: outcome(family),
                  tone: family == 'Paperless import'
                      ? AppTone.warning
                      : AppTone.info,
                  running: family == 'Document ingestion',
                  onOpen: () => openJob(family),
                ),
              if ((pipeline == 'All pipelines' ||
                      pipeline == 'Document ingestion') &&
                  (status == 'All statuses' || status == 'Completed'))
                GlacierJobRow(
                  title: 'Design services · October',
                  pipeline: 'Document ingestion',
                  timestamp: 'Today, 10:32',
                  duration: '28 seconds',
                  status: 'Completed',
                  tone: AppTone.info,
                  onOpen: () => openJob('Document ingestion'),
                ),
              if (older)
                GlacierJobRow(
                  title: 'Older electricity statement',
                  pipeline: 'Document ingestion',
                  timestamp: 'Yesterday, 16:23',
                  status: 'Completed',
                  tone: AppTone.success,
                  onOpen: () => openJob('Document ingestion'),
                ),
            ],
      continuation: widget.empty || widget.loading
          ? null
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Text(
                  older ? '7 sample jobs loaded' : '6 sample jobs loaded',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    GlacierButton(
                      label: 'Previous',
                      onPressed: older
                          ? () => setState(() => older = false)
                          : null,
                    ),
                    GlacierButton(
                      label: 'Next',
                      onPressed: older
                          ? null
                          : () => setState(() => older = true),
                    ),
                  ],
                ),
              ],
            ),
      configuration: const ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          'Pipeline setup & resource rules',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Jobs wait for shared worker and provider capacity. Email and Paperless retrievals use workers; document ingestion also requires Ollama. Current visible jobs cannot identify a specific blocked resource.',
            ),
          ),
        ],
      ),
    ),
  );
}

class _JobDetailExample extends StatelessWidget {
  const _JobDetailExample({
    required this.pipeline,
    this.onBack,
    this.recordTitle,
    this.recordedStatus,
  });
  final String pipeline;
  final String? recordTitle, recordedStatus;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final imported =
        pipeline == 'Paperless import' || pipeline == 'Email retrieval';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlacierJobDetails(
        title: recordTitle ?? pipeline,
        scope: recordTitle != null
            ? 'Personal library · $pipeline'
            : imported
            ? 'Your source · Personal library'
            : 'Personal library · Home insurance',
        status:
            recordedStatus ??
            (imported ? 'Completed with item failures' : 'Failed'),
        tone: recordedStatus != null && recordedStatus != 'Partially completed'
            ? AppTone.info
            : AppTone.warning,
        summary: recordedStatus == 'Running'
            ? 'A recorded embedding step is running. Its remaining time is unknown.'
            : recordedStatus == 'Waiting to start'
            ? 'Accepted and waiting to start. The particular resource blocking this job was not recorded.'
            : recordedStatus == 'Completed'
            ? 'The recorded pipeline completed. Related document jobs have their own outcomes.'
            : imported
            ? 'Two originals were accepted into separate document jobs. One original could not be fetched. Accepted files are not yet processed.'
            : 'This attempt stopped before completing. The original and earlier successful work remain available.',
        timing: 'Accepted today at 09:41 · Last recorded update at 09:43',
        stages: [
          for (var i = 0; i < _pipelines[pipeline]!.length; i++)
            GlacierPipelineStage(
              label: _pipelines[pipeline]![i],
              state: recordedStatus == 'Completed'
                  ? GlacierStageState.complete
                  : recordedStatus == 'Waiting to start'
                  ? GlacierStageState.waiting
                  : recordedStatus == 'Running'
                  ? (i < 2
                        ? GlacierStageState.complete
                        : i == 2
                        ? GlacierStageState.running
                        : GlacierStageState.waiting)
                  : imported
                  ? i == _pipelines[pipeline]!.length - 1
                        ? GlacierStageState.waiting
                        : i == _pipelines[pipeline]!.length - 2
                        ? GlacierStageState.failed
                        : GlacierStageState.complete
                  : i == 0
                  ? GlacierStageState.complete
                  : i == 1
                  ? GlacierStageState.failed
                  : GlacierStageState.unknown,
              detail:
                  recordedStatus != null &&
                      recordedStatus != 'Partially completed'
                  ? null
                  : imported
                  ? i == _pipelines[pipeline]!.length - 1
                        ? 'Accepted originals are queued as separate document jobs.'
                        : i == _pipelines[pipeline]!.length - 2
                        ? 'Completed with a recorded item failure; other originals were accepted.'
                        : null
                  : i == 1
                  ? 'The service did not return a usable result.'
                  : i > 1
                  ? 'No completed work was recorded for this stage.'
                  : null,
            ),
        ],
        actions: [
          if (onBack != null)
            GlacierButton(
              label: 'Close',
              onPressed: onBack,
              kind: GlacierButtonKind.quiet,
            ),
          if (recordedStatus == null || recordedStatus == 'Partially completed')
            GlacierButton(
              label: 'Retry attempt',
              icon: Icons.replay,
              onPressed: () => _feedback(
                context,
                'A fictional retry was requested. Previous history remains available.',
              ),
            ),
        ],
        outcomes: imported
            ? Column(
                children: [
                  GlacierJobOutcome(
                    title: 'Electricity.pdf',
                    outcome: 'Queued',
                    detail: 'Accepted for separate ingestion.',
                    onOpen: () => _feedback(context, 'Open document callback'),
                  ),
                  GlacierJobOutcome(
                    title: 'Receipt.pdf',
                    outcome: 'Failed',
                    failed: true,
                    detail: 'The original could not be fetched.',
                    onRetry: () => _feedback(context, 'Retry item callback'),
                  ),
                ],
              )
            : null,
        continuation: imported
            ? GlacierButton(
                label: 'Load more outcomes',
                onPressed: () =>
                    _feedback(context, 'The next outcome page was requested.'),
              )
            : null,
      ),
    );
  }
}

class _ActivityExample extends StatelessWidget {
  const _ActivityExample({this.stale = false});
  final bool stale;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: GlacierActivityPanel(
      library: 'Personal library',
      running: stale ? null : 2,
      waiting: stale ? null : 4,
      notice: stale
          ? AppNotice(
              message: 'Connection interrupted. Counts cannot be refreshed; retained jobs remain below.',
              tone: AppTone.warning,
              action: GlacierButton(
                label: 'Retry connection',
                onPressed: () =>
                    _feedback(context, 'Retry connection callback'),
              ),
            )
          : null,
      jobs: [
        GlacierJobRow(
          title: 'Apartment lease',
          pipeline: 'Document ingestion',
          timestamp: 'Today, 10:02',
          status: 'Extracting text',
          running: true,
          activity: true,
          onOpen: () => _feedback(context, 'Open job callback'),
        ),
      ],
      reindex: GlacierReindexProgress(
        scope: 'Current library',
        status: 'Processing',
        summary: 'A request remains active while its document attempts finish.',
        total: 30,
        succeeded: 12,
        failed: 1,
        onDetails: () => _feedback(context, 'Open reindex request callback'),
      ),
      onMore: () => _feedback(context, 'Load next active page callback'),
      onUploads: () =>
          _feedback(context, 'Open retained upload receipts callback'),
    ),
  );
}

const _conversations = [
  GlacierConversation(
    id: 'lease',
    title: 'Studio lease questions',
    updated: '2 messages',
  ),
  GlacierConversation(
    id: 'energy',
    title: 'Electricity costs across the last year and the final household settlement',
    updated: 'Yesterday',
  ),
  GlacierConversation(
    id: 'insurance',
    title: 'Insurance documents',
    updated: '2 messages',
  ),
  GlacierConversation(
    id: 'receipts',
    title: 'November receipts',
    updated: '2 messages',
  ),
];

class _HistoryExample extends StatefulWidget {
  const _HistoryExample();
  @override
  State<_HistoryExample> createState() => _HistoryExampleState();
}

class _HistoryExampleState extends State<_HistoryExample> {
  String? selected = 'lease';
  final entries = [..._conversations];
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: GlacierConversationHistory(
      conversations: entries,
      selectedId: selected,
      onSelect: (id) => setState(() => selected = id),
      onNew: () => setState(() => selected = null),
      onDelete: (id) async {
        final confirmed = await showGlacierDialog<bool>(
          context: context,
          builder: (context) => GlacierDialog(
            title: 'Delete this conversation?',
            actions: [
              GlacierButton(
                label: 'Keep conversation',
                onPressed: () => Navigator.pop(context, false),
              ),
              GlacierButton(
                label: 'Delete conversation',
                kind: GlacierButtonKind.danger,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
            child: const Text(
              'This removes its messages and stops any active reply. This is a fictional local example.',
            ),
          ),
        );
        if (confirmed == true && mounted) {
          setState(() {
            entries.removeWhere((entry) => entry.id == id);
            if (selected == id) selected = null;
          });
        }
      },
      onMore: () => setState(() {
        if (!entries.any((entry) => entry.id == 'older')) {
          entries.add(
            const GlacierConversation(
              id: 'older',
              title: 'Household insurance',
              updated: 'Last month',
            ),
          );
        }
      }),
    ),
  );
}

class _ChatExample extends StatefulWidget {
  const _ChatExample({
    this.empty = false,
    this.disabled = false,
    this.uncertain = false,
    this.composerOnly = false,
  });
  final bool empty, disabled, uncertain, composerOnly;
  @override
  State<_ChatExample> createState() => _ChatExampleState();
}

class _ChatExampleState extends State<_ChatExample> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final entries = [..._conversations];
  String? selected = 'lease';
  String? question;
  bool busy = false, stopped = false, checked = false, earlier = false;
  Future<void> deleteConversation(String id) async {
    final confirmed = await showGlacierDialog<bool>(
      context: context,
      builder: (context) => GlacierDialog(
        title: 'Delete this conversation?',
        actions: [
          GlacierButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          GlacierButton(
            label: 'Delete conversation',
            kind: GlacierButtonKind.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
        child: const Text(
          'Remove this conversation and its draft from your local history? Other conversations stay available.',
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        entries.removeWhere((entry) => entry.id == id);
        selected = entries.firstOrNull?.id;
        question = null;
        controller.clear();
        busy = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.empty) selected = null;
    if (widget.uncertain) controller.text = 'When does our lease end?';
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composer = GlacierChatComposer(
      controller: controller,
      enabled: !widget.disabled,
      busy: busy,
      notice: widget.uncertain && !checked
          ? const AppNotice(
              message: 'The connection ended before acceptance was confirmed. Check the original request before sending another.',
              tone: AppTone.warning,
            )
          : null,
      onCheck: widget.uncertain && !checked
          ? () => setState(() {
              checked = true;
              question = controller.text;
              controller.clear();
            })
          : null,
      onSend: () => setState(() {
        question = controller.text;
        controller.clear();
        busy = true;
        stopped = false;
      }),
      onStop: () => setState(() {
        busy = false;
        stopped = true;
      }),
    );
    if (widget.composerOnly) return CatalogFrame(child: composer);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlacierToolbar(
            trailing: [
              GlacierButton(
                label: 'New conversation',
                icon: Icons.add,
                onPressed: () => setState(() {
                  selected = null;
                  question = null;
                  controller.clear();
                  busy = false;
                }),
              ),
            ],
            children: [
              const Text(
                'Conversations',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                'Sources stay linked to their originals.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 690),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlacierChatScreen(
                    title: selected == 'energy'
                        ? 'Electricity costs'
                        : selected == null
                        ? 'New conversation'
                        : 'Studio lease questions',
                    scrollController: scroll,
                    history: GlacierConversationHistory(
                      showNew: false,
                      conversations: entries,
                      selectedId: selected,
                      onSelect: (id) => setState(() {
                        selected = id;
                        question = null;
                        busy = false;
                      }),
                      onNew: () => setState(() {
                        selected = null;
                        question = null;
                        controller.clear();
                        busy = false;
                      }),
                      onMore: () =>
                          _feedback(context, 'Older conversations requested'),
                    ),
                    actions: [
                      if (selected != null)
                        GlacierButton(
                          label: 'Delete conversation',
                          onPressed: () => deleteConversation(selected!),
                        ),
                    ],
                    notice: widget.disabled
                        ? const AppNotice(
                            message: 'Chat is disabled for this installation. Your saved conversations are still readable.',
                            tone: AppTone.warning,
                          )
                        : null,
                    messages: [
                      if (earlier)
                        const GlacierChatMessage(
                          text: 'Please use the signed version of our lease.',
                          fromUser: true,
                        ),
                      if (selected != null) ...[
                        GlacierChatMessage(
                          text: selected == 'energy'
                              ? 'What was our November electricity bill?'
                              : 'Where should I check the notice terms in my studio lease?',
                          fromUser: true,
                        ),
                        GlacierChatMessage(
                          text: selected == 'energy'
                              ? 'The November energy statement records a total of €86.40.'
                              : 'This fictional response demonstrates a completed answer. Open the consulted document and check its wording before relying on any summary.',
                          sources: [
                            GlacierChatSource(
                              title: selected == 'energy'
                                  ? 'November electricity'
                                  : 'Apartment lease · page 6',
                              onOpen: () => showGlacierDialog<void>(
                                context: context,
                                builder: (_) => documentReaderDialog(),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (question != null)
                        GlacierChatMessage(text: question!, fromUser: true),
                      if (busy)
                        const GlacierChatMessage(
                          text: '',
                          status: 'Searching your library',
                          statusDescription: 'Looking for relevant documents in this conversation’s library.',
                          active: true,
                        ),
                      if (stopped)
                        GlacierChatMessage(
                          text: '',
                          status: 'Cancelled',
                          statusDescription: 'The reply was stopped. Your question remains above.',
                          onSendAgain: () {
                            controller.text = question ?? '';
                            setState(() => stopped = false);
                          },
                        ),
                      if (checked)
                        const GlacierChatMessage(
                          text: '',
                          status: 'Waiting to start',
                          statusDescription: 'The original request was found. No duplicate question was sent.',
                        ),
                    ],
                    composer: composer,
                    onEarlier: selected == null || earlier || !widget.uncertain
                        ? null
                        : () => setState(() => earlier = true),
                    onLatest: () {
                      if (scroll.hasClients) {
                        scroll.jumpTo(scroll.position.maxScrollExtent);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowFilter extends StatelessWidget {
  const _WorkflowFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    width: (236 * MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      236,
      360,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: GlacierTokens.of(context).surface,
      border: Border.all(color: GlacierTokens.of(context).border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            padding: const EdgeInsets.symmetric(vertical: 10),
            value: value,
            underline: const SizedBox.shrink(),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 12),
            items: options
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ],
    ),
  );
}
