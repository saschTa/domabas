import 'dart:async';

import 'processing_job_counts.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/document/models/document_processing.dart';
import '../domain/email/models/email.dart';
import '../domain/paperless/models/paperless.dart';
import '../presentation/document/cubits/document_processing_cubit.dart';
import '../presentation/document/widgets/processing_widgets.dart';
import '../presentation/email/cubits/email_jobs_cubit.dart';
import '../presentation/paperless/cubits/paperless_jobs_cubit.dart';
import '../presentation/paperless/widgets/paperless_jobs.dart';
import '../ui/domabas_ui.dart';

final class ProcessingJobsList extends StatefulWidget {
  const ProcessingJobsList({
    super.key,
    required this.documents,
    required this.email,
    required this.paperless,
    required this.onOpenEmailJob,
    this.filters,
    this.shellToolbar = false,
  });
  final ProcessingJobsFiltersCubit? filters;
  final bool shellToolbar;
  final DocumentProcessingCubit documents;
  final EmailJobsCubit email;
  final PaperlessJobsCubit paperless;
  final void Function(EmailRun) onOpenEmailJob;

  @override
  State<ProcessingJobsList> createState() => _ProcessingJobsListState();
}

final class _ProcessingJobsListState extends State<ProcessingJobsList> {
  late final ProcessingJobsFiltersCubit _filters;
  late final StreamSubscription<ProcessingJobsFiltersState>
  _filtersSubscription;
  String get _pipeline => _filters.pipeline;
  String? get _status => _filters.status;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _filters =
        widget.filters ??
        ProcessingJobsFiltersCubit(
          documents: widget.documents,
          email: widget.email,
          paperless: widget.paperless,
        );
    _filtersSubscription = _filters.stream.listen((_) => _changed());
  }

  void _changed() {
    PageStorage.maybeOf(context)
        ?.writeState(context, (_pipeline, _status), identifier: 'jobFilters');
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored || widget.filters != null) return;
    _restored = true;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: 'jobFilters');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (saved is (String, String?)) {
        _filters.filter(
          pipeline: saved.$1,
          status: saved.$2,
          changeStatus: true,
        );
      }
    });
  }

  @override
  void dispose() {
    unawaited(_filtersSubscription.cancel());
    if (widget.filters == null) unawaited(_filters.close());
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentProcessingCubit, DocumentProcessingState>(
    bloc: widget.documents,
    builder: (context, documents) => BlocBuilder<EmailJobsCubit, EmailJobsState>(
      bloc: widget.email,
      builder: (context, email) => BlocBuilder<PaperlessJobsCubit, PaperlessJobsState>(
        bloc: widget.paperless,
        builder: (context, paperless) {
          final countSources = processingJobsCountSources(_filters);
          final totals = processingJobCount(countSources);
          final showDocuments =
              widget.documents.canReadJobs &&
              _status != 'partial' &&
              (_pipeline == 'all' ||
                  _pipeline == 'document' ||
                  _pipeline == 'ai' ||
                  _pipeline == 'thumbnail');
          final showEmail =
              widget.email.allowed &&
              _status != 'skipped' &&
              (_pipeline == 'all' || _pipeline == 'email');
          final showPaperless =
              widget.paperless.allowed &&
              _status != 'superseded' &&
              _status != 'skipped' &&
              (_pipeline == 'all' || _pipeline == 'paperless');
          final rows = <_WorkspaceJobRow>[
            if (showDocuments)
              for (final job in documents.jobs) _WorkspaceJobRow.document(job),
            if (showEmail)
              for (final run in email.runs) _WorkspaceJobRow.email(run),
            if (showPaperless)
              for (final run in paperless.runs) _WorkspaceJobRow.paperless(run),
          ]..sort(_WorkspaceJobRow.compare);
          final boundaries = <_WorkspaceJobRow>[
            if (showDocuments &&
                documents.nextCursor != null &&
                documents.jobs.isNotEmpty)
              _WorkspaceJobRow.document(documents.jobs.last),
            if (showEmail && email.cursor != null && email.runs.isNotEmpty)
              _WorkspaceJobRow.email(email.runs.last),
            if (showPaperless &&
                paperless.cursor != null &&
                paperless.runs.isNotEmpty)
              _WorkspaceJobRow.paperless(paperless.runs.last),
          ]..sort(_WorkspaceJobRow.compare);
          final available = boundaries.isEmpty
              ? rows
              : rows
                    .where(
                      (row) =>
                          _WorkspaceJobRow.compare(row, boundaries.first) <= 0,
                    )
                    .toList();
          final visible = available
              .where((row) => _status == null || row.status == _status)
              .toList();
          final moreDocuments = showDocuments && documents.nextCursor != null;
          final moreEmail = showEmail && email.cursor != null;
          final morePaperless = showPaperless && paperless.cursor != null;
          final loading =
              (showDocuments && documents.loading) ||
              (showEmail && email.loading) ||
              (showPaperless && paperless.loading);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.shellToolbar)
                ProcessingJobsFilterFields(filters: _filters),
              if (totals.error)
                const AppNotice(
                  message: 'Job totals could not be refreshed. Numbers marked * are from the last successful update; — means unavailable.',
                ),
              AppProgressSlot(active: totals.refreshing),
              if (!totals.error && !totals.refreshing && totals.count == null)
                const AppNotice(
                  message: 'Some job totals are unavailable. Refresh jobs to try again.',
                ),
              if (showEmail && email.error != null)
                AppNotice(message: email.error!),
              if (showEmail && email.browsingHistory)
                const AppNotice(
                  message: 'Older email history stays in place while active outcomes update. Refresh to see new jobs.',
                ),
              if (showEmail) AppProgressSlot(active: email.loading),
              if (showPaperless && paperless.error != null)
                AppNotice(message: paperless.error!),
              if (showPaperless) ...[
                AppProgressSlot(active: paperless.loading),
                if (paperless.browsingHistory)
                  const AppNotice(
                    message: 'Older Paperless history stays in place while active outcomes update. Refresh to see new jobs.',
                  ),
              ],
              const SizedBox(height: 16),
              if (visible.isEmpty &&
                  (!loading ||
                      documents.pipeline != null ||
                      totals.count != null))
                AppEmptyState(
                  icon: Icons.work_history_outlined,
                  title: 'No jobs to show',
                  message: _status != null
                      ? 'No jobs match the selected filters.'
                      : 'Paperless imports, email imports and document processing attempts appear here.',
                ),
              AppPagedList(
                glacier: true,
                key: PageStorageKey(
                  'pipeline-jobs-$_pipeline-${_status ?? 'all'}',
                ),
                itemCount: visible.length,
                hasMore: moreDocuments || moreEmail || morePaperless,
                loading: loading,
                loadMoreKey: const Key('loadMorePipelineJobs'),
                loadMoreLabel: 'Load more jobs',
                onLoadMore: () => unawaited(
                  Future.wait([
                    if (moreDocuments) widget.documents.load(moreJobs: true),
                    if (moreEmail) widget.email.load(more: true),
                    if (morePaperless) widget.paperless.load(more: true),
                  ]),
                ),
                itemBuilder: (context, index) {
                  final row = visible[index];
                  return GlacierJobRow(
                    key: Key(
                      row.document != null
                          ? 'job-${row.id}'
                          : row.paperless != null
                          ? 'paperless-job-${row.id}'
                          : 'email-job-${row.id}',
                    ),
                    title:
                        row.document?.label ??
                        row.paperless?.serverUrl ??
                        email.providers
                            .where(
                              (provider) =>
                                  provider.id == row.email!.providerId,
                            )
                            .firstOrNull
                            ?.label ??
                        'Email import',
                    pipeline:
                        row.document?.pipelineLabel ??
                        (row.paperless != null
                            ? 'Paperless import'
                            : 'Email import'),
                    timestamp: processingTime(row.createdAt),
                    status: row.status == 'partial'
                        ? 'Partially completed'
                        : processingLabel(row.status),
                    tone: row.status == 'partial'
                        ? AppTone.warning
                        : processingTone(row.status),
                    running: row.status == 'running',
                    detail: row.document != null
                        ? '${processingLabel(row.document!.reason)} · attempt ${row.document!.attemptNumber}'
                        : row.paperless != null
                        ? paperlessJobStage(row.paperless!)
                        : '${_reason(row.email!.reason)} · ${_stage(row.email!)}',
                    onOpen: row.document != null && documents.detailLoading
                        ? null
                        : () {
                            if (row.document != null) {
                              unawaited(widget.documents.selectJob(row.id));
                            } else if (row.paperless != null) {
                              widget.paperless.selectJob(row.paperless!);
                            } else {
                              widget.onOpenEmailJob(row.email!);
                            }
                          },
                  );
                },
              ),
            ],
          );
        },
      ),
    ),
  );

  static String _reason(String value) => switch (value) {
    'scheduled' => 'Automatic check',
    'manual' => 'Import now',
    'continuation' => 'Continuation',
    _ => value,
  };
  static String _stage(EmailRun run) => switch (run.stage) {
    'queued' => 'Waiting for retrieval',
    'discovering' => 'Discovering messages',
    'fetching' => 'Fetching emails',
    'importing' => 'Importing emails and attachments',
    'complete' => 'Retrieval finished',
    _ => run.stage,
  };
}

final class _WorkspaceJobRow {
  _WorkspaceJobRow.document(DocumentProcessingJob job)
    : document = job,
      email = null,
      paperless = null;
  _WorkspaceJobRow.email(EmailRun run)
    : email = run,
      document = null,
      paperless = null;
  _WorkspaceJobRow.paperless(PaperlessRun run)
    : paperless = run,
      document = null,
      email = null;
  final DocumentProcessingJob? document;
  final EmailRun? email;
  final PaperlessRun? paperless;
  String get id => document?.id ?? email?.id ?? paperless!.id;
  DateTime get createdAt =>
      document?.createdAt ?? email?.createdAt ?? paperless!.createdAt;
  String get status =>
      document?.status ?? email?.status ?? paperlessJobStatus(paperless!);
  static int compare(_WorkspaceJobRow a, _WorkspaceJobRow b) {
    final date = b.createdAt.compareTo(a.createdAt);
    return date == 0 ? b.id.compareTo(a.id) : date;
  }
}

@immutable
final class ProcessingJobsFiltersState {
  const ProcessingJobsFiltersState({this.pipeline = 'all', this.status});
  final String pipeline;
  final String? status;
}

final class ProcessingJobsFiltersCubit
    extends Cubit<ProcessingJobsFiltersState> {
  ProcessingJobsFiltersCubit({
    required this.documents,
    required this.email,
    required this.paperless,
  }) : super(const ProcessingJobsFiltersState());
  final DocumentProcessingCubit documents;
  final EmailJobsCubit email;
  final PaperlessJobsCubit paperless;
  String get pipeline => state.pipeline;
  String? get status => state.status;
  int get count => (pipeline == 'all' ? 0 : 1) + (status == null ? 0 : 1);
  void filter({String? pipeline, String? status, bool changeStatus = false}) {
    if (isClosed) return;
    emit(
      ProcessingJobsFiltersState(
        pipeline: pipeline ?? state.pipeline,
        status: changeStatus ? status : state.status,
      ),
    );
    _applyStatus();
  }

  void _applyStatus() {
    documents.filter(
      status == 'partial' ? null : status,
      pipeline: switch (pipeline) {
        'document' => 'ingestion',
        'ai' => 'ai',
        'thumbnail' => 'thumbnail',
        _ => null,
      },
    );
    email.filter(status == 'skipped' ? null : status);
    paperless.filter(
      {'superseded', 'skipped'}.contains(status) ? null : status,
    );
  }
}

Map<String, ProcessingJobCountSnapshot> processingJobsCountSources(
  ProcessingJobsFiltersCubit filters,
) {
  final documents = filters.documents.state;
  final email = filters.email.state;
  final paperless = filters.paperless.state;
  return <String, ProcessingJobCountSnapshot>{
    if (filters.documents.canReadJobs)
      for (final pipeline in ['ingestion', 'ai', 'thumbnail'])
        pipeline == 'ingestion'
            ? 'document'
            : pipeline: ProcessingJobCountSnapshot(
          counts: documents.counts == null
              ? null
              : {
                  for (final entry in documents.counts!.entries)
                    if (entry.key.$1 == pipeline) entry.key.$2: entry.value,
                },
          refreshing: documents.countsRefreshing,
          error: documents.countsError,
        ),
    if (filters.email.allowed)
      'email': ProcessingJobCountSnapshot(
        counts: email.counts,
        refreshing: email.countsRefreshing,
        error: email.countsError,
      ),
    if (filters.paperless.allowed)
      'paperless': ProcessingJobCountSnapshot(
        counts: paperless.counts,
        refreshing: paperless.countsRefreshing,
        error: paperless.countsError,
      ),
  };
}

final class ProcessingJobsFilterFields extends StatelessWidget {
  const ProcessingJobsFilterFields({
    super.key,
    required this.filters,
    this.quick = false,
    this.actions = const [],
  });
  final ProcessingJobsFiltersCubit filters;
  final bool quick;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProcessingJobsFiltersCubit, ProcessingJobsFiltersState>(
        bloc: filters,
        builder: (context, _) =>
            BlocBuilder<DocumentProcessingCubit, DocumentProcessingState>(
              bloc: filters.documents,
              builder: (context, documents) =>
                  BlocBuilder<EmailJobsCubit, EmailJobsState>(
                    bloc: filters.email,
                    builder: (context, email) =>
                        BlocBuilder<PaperlessJobsCubit, PaperlessJobsState>(
                          bloc: filters.paperless,
                          builder: (context, paperless) {
                            final countSources = processingJobsCountSources(
                              filters,
                            );
                            if (quick) {
                              Widget selector({
                                required String label,
                                required String value,
                                required List<(String, String)> options,
                                required ValueChanged<String?> onChanged,
                                required bool pipeline,
                              }) => SizedBox(
                                width: 184,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('$label-$value'),
                                  initialValue: value,
                                  isExpanded: true,
                                  decoration: InputDecoration(labelText: label),
                                  items: [
                                    for (final (id, text) in options)
                                      DropdownMenuItem(
                                        value: id,
                                        child: _countLabel(
                                          context,
                                          text,
                                          processingJobCount(
                                            countSources,
                                            pipeline: pipeline
                                                ? id
                                                : filters.pipeline,
                                            status: pipeline
                                                ? filters.status
                                                : id == 'all'
                                                ? null
                                                : id,
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged: onChanged,
                                ),
                              );
                              return GlacierToolbar(
                                trailing: actions,
                                children: [
                                  selector(
                                    label: 'Pipeline',
                                    value: filters.pipeline,
                                    pipeline: true,
                                    onChanged: (value) {
                                      if (value != null) {
                                        filters.filter(pipeline: value);
                                      }
                                    },
                                    options: [
                                      ('all', 'All pipelines'),
                                      if (filters.documents.canReadJobs) ...[
                                        ('document', 'Document ingestion'),
                                        ('ai', 'AI processing'),
                                        ('thumbnail', 'Thumbnail generation'),
                                      ],
                                      if (filters.email.allowed)
                                        ('email', 'Email import'),
                                      if (filters.paperless.allowed)
                                        ('paperless', 'Paperless import'),
                                    ],
                                  ),
                                  selector(
                                    label: 'Status',
                                    value: filters.status ?? 'all',
                                    pipeline: false,
                                    onChanged: (value) => filters.filter(
                                      status: value == 'all' ? null : value,
                                      changeStatus: true,
                                    ),
                                    options: [
                                      ('all', 'All jobs'),
                                      for (final status in [
                                        'queued',
                                        'running',
                                        'succeeded',
                                        'partial',
                                        'failed',
                                        'superseded',
                                        'cancelled',
                                        'skipped',
                                      ])
                                        (
                                          status,
                                          status == 'partial'
                                              ? 'Partially completed'
                                              : processingLabel(status),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final (id, label) in [
                                      ('all', 'All pipelines'),
                                      if (filters.documents.canReadJobs)
                                        ('document', 'Document ingestion'),
                                      if (filters.documents.canReadJobs)
                                        ('ai', 'AI processing'),
                                      if (filters.documents.canReadJobs)
                                        ('thumbnail', 'Thumbnail generation'),
                                      if (filters.email.allowed)
                                        ('email', 'Email import'),
                                      if (filters.paperless.allowed)
                                        ('paperless', 'Paperless import'),
                                    ])
                                      ChoiceChip(
                                        key: Key('pipeline-filter-$id'),
                                        label: _countLabel(
                                          context,
                                          label,
                                          processingJobCount(
                                            countSources,
                                            pipeline: id,
                                            status: filters.status,
                                          ),
                                        ),
                                        selected: filters.pipeline == id,
                                        onSelected: (_) =>
                                            filters.filter(pipeline: id),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final status in <String?>[
                                      null,
                                      'queued',
                                      'running',
                                      'succeeded',
                                      'partial',
                                      'failed',
                                      'superseded',
                                      'cancelled',
                                      'skipped',
                                    ])
                                      ChoiceChip(
                                        key: Key(
                                          'job-filter-${status ?? 'all'}',
                                        ),
                                        label: _countLabel(
                                          context,
                                          status == null
                                              ? 'All jobs'
                                              : status == 'partial'
                                              ? 'Partially completed'
                                              : processingLabel(status),
                                          processingJobCount(
                                            countSources,
                                            pipeline: filters.pipeline,
                                            status: status,
                                          ),
                                        ),
                                        selected: filters.status == status,
                                        onSelected: (_) => filters.filter(
                                          status: status,
                                          changeStatus: true,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                  ),
            ),
      );
  Widget _countLabel(
    BuildContext context,
    String label,
    ({int? count, bool refreshing, bool error}) total,
  ) {
    final number = total.count?.toString() ?? '—';
    final suffix = total.error && total.count != null ? '*' : '';
    final description = total.count == null
        ? 'Count unavailable'
        : '${total.count} jobs${total.error
              ? ', last successful update'
              : total.refreshing
              ? ', updating'
              : ''}';
    return Semantics(
      label: '$label, $description',
      excludeSemantics: true,
      child: Tooltip(
        message:
            '$description. Counts include all history matching the other filter.',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$number$suffix',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class ProcessingJobsToolbar extends StatefulWidget {
  const ProcessingJobsToolbar({
    super.key,
    required this.filters,
    this.libraryPicker,
    this.workspaceActions,
  });
  final ProcessingJobsFiltersCubit filters;
  final Widget? libraryPicker, workspaceActions;
  @override
  State<ProcessingJobsToolbar> createState() => _ProcessingJobsToolbarState();
}

final class _ProcessingJobsToolbarState extends State<ProcessingJobsToolbar> {
  RawDialogRoute<void>? _route;
  @override
  void dispose() {
    final route = _route;
    final navigator = route?.navigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.navigator == navigator) {
          navigator.removeRoute(route);
        }
      });
    }
    super.dispose();
  }

  Future<void> _open() async {
    if (_route != null) return;
    final filters = widget.filters;
    final navigator = Navigator.of(context);
    late final RawDialogRoute<void> route;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: .22),
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => glacierDialogBackdrop(
        context,
        (context) => AppDialog(
          glacier: true,
          title: 'Filter jobs',
          description: 'Choose a pipeline and recorded status.',
          actions: [
            GlacierButton(
              onPressed: () {
                if (route.isCurrent) navigator.pop();
              },
              label: 'Done',
            ),
          ],
          child: ProcessingJobsFilterFields(filters: filters),
        ),
      ),
    );
    _route = route;
    await navigator.push(route);
    if (mounted && _route == route) setState(() => _route = null);
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProcessingJobsFiltersCubit, ProcessingJobsFiltersState>(
        bloc: widget.filters,
        builder: (context, _) => ProcessingJobsFilterFields(
          filters: widget.filters,
          quick: true,
          actions: [
            GlacierButton(
              key: const Key('jobFilters'),
              label: 'All filters',
              icon: Icons.tune,
              kind: GlacierButtonKind.quiet,
              onPressed: _open,
            ),
            if (widget.filters.count > 0)
              GlacierButton(
                label: 'Clear filters',
                kind: GlacierButtonKind.quiet,
                onPressed: () => widget.filters.filter(
                  pipeline: 'all',
                  status: null,
                  changeStatus: true,
                ),
              ),
            if (widget.workspaceActions != null) widget.workspaceActions!,
          ],
        ),
      );
}
