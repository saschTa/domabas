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
  });
  final DocumentProcessingCubit documents;
  final EmailJobsCubit email;
  final PaperlessJobsCubit paperless;
  final void Function(EmailRun) onOpenEmailJob;

  @override
  State<ProcessingJobsList> createState() => _ProcessingJobsListState();
}

final class _ProcessingJobsListState extends State<ProcessingJobsList> {
  String _pipeline = 'all';
  String? _status;
  bool _restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final saved = PageStorage.maybeOf(context)
        ?.readState(context, identifier: 'jobFilters');
    if (saved is (String, String?)) {
      _pipeline = saved.$1;
      _status = saved.$2;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyStatus();
    });
  }

  void _applyStatus() {
    widget.documents.filter(
      _status == 'partial' ? null : _status,
      pipeline: switch (_pipeline) {
        'document' => 'ingestion',
        'ai' => 'ai',
        'thumbnail' => 'thumbnail',
        _ => null,
      },
    );
    widget.email.filter(_status == 'skipped' ? null : _status);
    widget.paperless.filter(
      {'superseded', 'skipped'}.contains(_status) ? null : _status,
    );
  }

  void _filter({String? pipeline, String? status, bool changeStatus = false}) {
    setState(() {
      if (pipeline != null) _pipeline = pipeline;
      if (changeStatus) _status = status;
    });
    PageStorage.maybeOf(context)
        ?.writeState(context, (_pipeline, _status), identifier: 'jobFilters');
    if (changeStatus || pipeline != null) _applyStatus();
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
          final countSources = <String, ProcessingJobCountSnapshot>{
            if (widget.documents.canReadJobs)
              for (final pipeline in ['ingestion', 'ai', 'thumbnail'])
                pipeline == 'ingestion'
                    ? 'document'
                    : pipeline: ProcessingJobCountSnapshot(
                  counts: documents.counts == null
                      ? null
                      : {
                          for (final entry in documents.counts!.entries)
                            if (entry.key.$1 == pipeline)
                              entry.key.$2: entry.value,
                        },
                  refreshing: documents.countsRefreshing,
                  error: documents.countsError,
                ),
            if (widget.email.allowed)
              'email': ProcessingJobCountSnapshot(
                counts: email.counts,
                refreshing: email.countsRefreshing,
                error: email.countsError,
              ),
            if (widget.paperless.allowed)
              'paperless': ProcessingJobCountSnapshot(
                counts: paperless.counts,
                refreshing: paperless.countsRefreshing,
                error: paperless.countsError,
              ),
          };
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, label) in [
                    ('all', 'All pipelines'),
                    if (widget.documents.canReadJobs)
                      ('document', 'Document ingestion'),
                    if (widget.documents.canReadJobs) ('ai', 'AI processing'),
                    if (widget.documents.canReadJobs)
                      ('thumbnail', 'Thumbnail generation'),
                    if (widget.email.allowed) ('email', 'Email import'),
                    if (widget.paperless.allowed)
                      ('paperless', 'Paperless import'),
                  ])
                    ChoiceChip(
                      key: Key('pipeline-filter-$id'),
                      label: _countLabel(
                        label,
                        processingJobCount(
                          countSources,
                          pipeline: id,
                          status: _status,
                        ),
                      ),
                      selected: _pipeline == id,
                      onSelected: (_) => _filter(pipeline: id),
                    ),
                  IconButton(
                    tooltip: 'Refresh jobs',
                    onPressed: loading
                        ? null
                        : () => unawaited(
                            Future.wait([
                              if (widget.documents.canReadJobs)
                                widget.documents.load(),
                              if (widget.email.allowed) widget.email.load(),
                              if (widget.paperless.allowed)
                                widget.paperless.load(),
                            ]),
                          ),
                    icon: const Icon(Icons.refresh),
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
                      key: Key('job-filter-${status ?? 'all'}'),
                      label: _countLabel(
                        status == null
                            ? 'All jobs'
                            : status == 'partial'
                            ? 'Partially completed'
                            : processingLabel(status),
                        processingJobCount(
                          countSources,
                          pipeline: _pipeline,
                          status: status,
                        ),
                      ),
                      selected: _status == status,
                      onSelected: (_) =>
                          _filter(status: status, changeStatus: true),
                    ),
                ],
              ),
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
              if (visible.isEmpty && !loading)
                AppEmptyState(
                  icon: Icons.work_history_outlined,
                  title: 'No jobs to show',
                  message: _status != null
                      ? 'No jobs match the selected filters.'
                      : 'Paperless imports, email imports and document processing attempts appear here.',
                ),
              AppPagedList(
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
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppSurface(
                      padding: EdgeInsets.zero,
                      child: AppRecordRow(
                        key: Key(
                          row.document != null
                              ? 'job-${row.id}'
                              : row.paperless != null
                              ? 'paperless-job-${row.id}'
                              : 'email-job-${row.id}',
                        ),
                        leading: Icon(
                          row.document != null
                              ? row.document!.isAI
                                    ? Icons.auto_awesome_outlined
                                    : row.document!.isThumbnail
                                    ? Icons.image_outlined
                                    : Icons.description_outlined
                              : row.paperless != null
                              ? Icons.file_download_outlined
                              : Icons.mail_outline,
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
                        subtitle: Text(
                          row.document != null
                              ? '${row.document!.pipelineLabel} · ${processingLabel(row.document!.reason)} · attempt ${row.document!.attemptNumber}\n${processingTime(row.createdAt)}'
                              : row.paperless != null
                              ? 'Paperless import · ${paperlessJobStage(row.paperless!)}\n${processingTime(row.createdAt)}'
                              : 'Email import · ${_reason(row.email!.reason)} · ${_stage(row.email!)}\n${processingTime(row.createdAt)}',
                        ),
                        metadata: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AppStatusBadge(
                              running: row.status == 'running',
                              label: row.status == 'partial'
                                  ? 'Partially completed'
                                  : processingLabel(row.status),
                              tone: row.status == 'partial'
                                  ? AppTone.warning
                                  : processingTone(row.status),
                            ),
                          ],
                        ),
                        trailing: TextButton(
                          onPressed:
                              row.document != null && documents.detailLoading
                              ? null
                              : () {
                                  if (row.document != null) {
                                    unawaited(
                                      widget.documents.selectJob(row.id),
                                    );
                                  } else if (row.paperless != null) {
                                    widget.paperless.selectJob(row.paperless!);
                                  } else {
                                    widget.onOpenEmailJob(row.email!);
                                  }
                                },
                          child: const Text('Details'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _countLabel(
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
