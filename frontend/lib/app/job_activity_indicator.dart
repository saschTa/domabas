import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/document/cubits/document_uploads_cubit.dart';
import '../presentation/document/widgets/processing_widgets.dart';
import '../ui/domabas_ui.dart';
import 'job_activity_cubit.dart';

final class JobActivityIndicator extends StatelessWidget {
  const JobActivityIndicator({
    super.key,
    required this.cubit,
    required this.uploads,
    required this.onOpen,
    this.onSelectFiles,
    this.glacier = false,
  });
  final JobActivityCubit cubit;
  final bool glacier;
  final DocumentUploadsCubit? uploads;
  final ValueChanged<JobActivityItem> onOpen;
  final VoidCallback? onSelectFiles;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<JobActivityCubit, JobActivityState>(
        bloc: cubit,
        builder: (context, jobs) {
          final owner = uploads;
          return owner == null
              ? _card(context, jobs, null)
              : BlocBuilder<DocumentUploadsCubit, DocumentUploadsState>(
                  bloc: owner,
                  builder: (context, state) => _card(context, jobs, state),
                );
        },
      );

  Widget _card(
    BuildContext context,
    JobActivityState jobs,
    DocumentUploadsState? uploadsState,
  ) {
    final pending = uploadsState?.pending ?? 0;
    final activeUpload = uploadsState?.rows
        .where(
          (row) =>
              row.phase == DocumentUploadPhase.reading ||
              row.phase == DocumentUploadPhase.uploading,
        )
        .firstOrNull;
    if (jobs.items.isEmpty &&
        jobs.runningCount == 0 &&
        jobs.queuedCount == 0 &&
        jobs.batchCount == 0 &&
        pending == 0 &&
        uploadsState?.showFeedback != true) {
      return const SizedBox.shrink();
    }
    if (glacier) {
      final totalsKnown =
          jobs.runningCount != null &&
          jobs.queuedCount != null &&
          jobs.batchCount != null;
      final count = totalsKnown
          ? jobs.runningCount! + jobs.queuedCount! + jobs.batchCount! + pending
          : null;
      final detail = [
        if (pending > 0) '$pending uploads',
        if (jobs.runningCount != null) '${jobs.runningCount} running',
        if (jobs.queuedCount != null) '${jobs.queuedCount} queued',
        if (jobs.batchCount != null && jobs.batchCount! > 0)
          '${jobs.batchCount} reindexes',
        if (!totalsKnown) 'Activity totals unavailable',
        if (jobs.discovering) 'Checking activity…',
        if (jobs.stale) 'Job updates paused',
        if (pending == 0 && uploadsState?.showFeedback == true)
          uploadsState!.feedback,
      ].join(' · ');
      final rows = [
        for (final row in uploadsState?.rows ?? const <DocumentUploadRow>[])
          GlacierActivityJob(
            id: 'upload-${row.candidate.id}',
            title: row.candidate.displayName,
            status: row.label,
            stage: row.message.isEmpty ? null : row.message,
            library: uploads?.libraryName,
            running:
                row.phase == DocumentUploadPhase.reading ||
                row.phase == DocumentUploadPhase.uploading,
            terminal:
                !row.pending && row.phase != DocumentUploadPhase.uncertain,
            failed: row.phase == DocumentUploadPhase.rejected,
          ),
        for (final item in jobs.items)
          GlacierActivityJob(
            id: '${item.kind.name}-${item.id}',
            title: item.title,
            status: processingLabel(item.status),
            stage: item.batch == null
                ? processingLabel(item.stage)
                : reindexProgressLabel(item.batch!),
            progress: item.batch?.progress,
            running: item.running && !jobs.stale,
            terminal: !item.active,
            failed: item.status == 'failed',
            onOpen: () => onOpen(item),
          ),
      ];
      return GlacierActivityDock(
        key: const Key('jobActivityIndicator'),
        jobs: rows.take(4).toList(growable: false),
        summary: GlacierActivitySummary(
          title: pending > 0
              ? '$pending uploads'
              : count == null
              ? 'Activity'
              : count > 0
              ? '$count active jobs'
              : 'Upload results',
          detail: detail,
          count: count,
          running:
              activeUpload != null ||
              (!jobs.stale &&
                  ((jobs.runningCount ?? 0) > 0 ||
                      (jobs.batchCount ?? 0) > 0 ||
                      jobs.items.any((item) => item.running))),
        ),
        compact:
            MediaQuery.sizeOf(context).width < 800 ||
            MediaQuery.viewInsetsOf(context).bottom > 0,
        truncated: jobs.hasMore || rows.length > 4,
        continuationLabel: 'This preview shows up to four entries. View all activity for the available history.',
        stale: jobs.stale && activeUpload == null,
        onRetryRefresh: jobs.loading ? null : cubit.refresh,
        onOpenActivity: () => showJobActivity(
          context,
          cubit: cubit,
          uploads: uploads,
          onOpen: onOpen,
          onSelectFiles: onSelectFiles,
        ),
      );
    }
    final running = jobs.runningCount ?? 0;
    final waiting = jobs.queuedCount ?? 0;
    final batchCount = jobs.batchCount ?? 0;
    final batches = jobs.items.where((item) => item.batch != null).toList();
    final batch = batches.firstOrNull?.batch;
    final summary = [
      if (pending > 0)
        '$pending upload${pending == 1 ? '' : 's'}${activeUpload == null ? ' queued' : ''}',
      if (running > 0) '$running jobs running',
      if (waiting > 0) '$waiting queued',
      if (batchCount > 0) '$batchCount reindex${batchCount == 1 ? '' : 'es'}',
      if (jobs.discovering) 'Checking activity…',
    ].join(' · ');
    final media = MediaQuery.of(context);
    final compact =
        media.size.height - media.viewInsets.bottom < 420 ||
        media.viewInsets.bottom > 0 ||
        media.textScaler.scale(14) > 24;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (media.size.width - 32).clamp(0, 280),
      ),
      child: AppJobActivityCard(
        key: const Key('jobActivityIndicator'),
        title: !compact
            ? 'Activity'
            : pending > 0
            ? '$pending uploads'
            : running > 0
            ? '$running running'
            : batchCount > 0
            ? 'Reindexing'
            : waiting > 0
            ? '$waiting queued'
            : 'Upload results',
        subtitle: jobs.stale
            ? '${summary.isEmpty ? 'Activity' : summary} · Job updates paused'
            : summary.isEmpty
            ? uploadsState?.feedback ?? 'No active background jobs.'
            : summary,
        running:
            activeUpload != null ||
            (!jobs.stale && (running > 0 || batchCount > 0)),
        stale: jobs.stale && (batch != null || activeUpload == null),
        compact: compact,
        progressLabel: batch != null
            ? '${batch.scope == 'system' ? 'All libraries' : 'Current library'} · ${reindexProgressLabel(batch)}'
            : activeUpload != null
            ? '${activeUpload.label} · ${activeUpload.candidate.displayName}'
            : null,
        progress: batch?.progress,
        onPressed: () => showJobActivity(
          context,
          cubit: cubit,
          uploads: uploads,
          onOpen: onOpen,
          onSelectFiles: onSelectFiles,
        ),
      ),
    );
  }
}

Future<void> showJobActivity(
  BuildContext context, {
  required JobActivityCubit cubit,
  required DocumentUploadsCubit? uploads,
  required ValueChanged<JobActivityItem> onOpen,
  VoidCallback? onSelectFiles,
}) => showGlacierDialog<void>(
  context: context,
  builder: (context) => BlocBuilder<JobActivityCubit, JobActivityState>(
    bloc: cubit,
    builder: (context, jobs) {
      Widget panel(DocumentUploadsState? state) {
        final rows = [...?state?.rows]
          ..sort((a, b) {
            int priority(DocumentUploadRow row) => !row.pending
                ? 2
                : row.phase == DocumentUploadPhase.waiting
                ? 1
                : 0;
            final order = priority(a).compareTo(priority(b));
            return order != 0
                ? order
                : state!.rows.indexOf(b).compareTo(state.rows.indexOf(a));
          });
        return AppDialog(
          glacier: true,
          title: 'Activity',
          onRefresh: jobs.loading ? null : cubit.refresh,
          description: 'Uploads, document processing and reindex progress',
          width: 560,
          actions: [
            if (uploads != null && state!.rows.any((row) => !row.pending))
              GlacierButton(
                kind: GlacierButtonKind.quiet,
                label: 'Clear finished uploads',
                onPressed: uploads.clearFinished,
              ),
            GlacierButton(
              kind: GlacierButtonKind.primary,
              label: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state != null &&
                  (state.rows.isNotEmpty || state.showFeedback)) ...[
                AppSectionHeader(
                  title: 'Uploads',
                  description: uploads!.libraryName,
                ),
                if (state.showFeedback)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Semantics(
                      key: const Key('uploadFeedback'),
                      liveRegion: true,
                      child: Text(state.feedback),
                    ),
                  ),
                AppPagedList(
                  glacier: true,
                  key: const PageStorageKey('upload-outcome-pages'),
                  itemCount: state.rows.length,
                  pageSize: 10,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppSurface(
                        glacier: true,
                        padding: EdgeInsets.zero,
                        child: AppRecordRow(
                          leading: const Icon(Icons.upload_file_outlined),
                          title: row.candidate.displayName,
                          subtitle: row.message.isEmpty
                              ? null
                              : Text(row.message),
                          metadata: AppStatusBadge(
                            label: row.label,
                            running:
                                row.phase == DocumentUploadPhase.reading ||
                                row.phase == DocumentUploadPhase.uploading,
                            tone: switch (row.phase) {
                              DocumentUploadPhase.accepted ||
                              DocumentUploadPhase.duplicate => AppTone.success,
                              DocumentUploadPhase.rejected => AppTone.danger,
                              DocumentUploadPhase.uncertain => AppTone.warning,
                              _ => AppTone.neutral,
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Text(
                  'Accepted originals continue processing. Upload acceptance does not mean processing is complete.',
                ),
                Text(
                  uploads.canRead
                      ? 'Check the library before selecting an unknown upload again.'
                      : 'Ask someone with library access before selecting an unknown upload again.',
                ),
                if (onSelectFiles != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GlacierButton(
                      kind: GlacierButtonKind.quiet,
                      label: 'Select files',
                      onPressed: state.usable
                          ? () {
                              Navigator.pop(context);
                              onSelectFiles();
                            }
                          : null,
                      icon: Icons.add,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
              const AppSectionHeader(title: 'Background jobs'),
              Text(
                [
                  if (jobs.runningCount != null) '${jobs.runningCount} running',
                  if (jobs.queuedCount != null) '${jobs.queuedCount} queued',
                  if (jobs.batchCount != null) '${jobs.batchCount} reindexes',
                  if (jobs.runningCount == null ||
                      jobs.queuedCount == null ||
                      jobs.batchCount == null)
                    'Activity totals unavailable',
                ].join(' · '),
              ),
              if (jobs.stale)
                AppNotice(
                  message: 'Updates paused. Showing last known progress.',
                  action: GlacierButton(
                    kind: GlacierButtonKind.quiet,
                    label: 'Retry',
                    onPressed: cubit.refresh,
                  ),
                ),
              if (jobs.discovering) const Text('Checking activity totals…'),
              if (jobs.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    jobs.stale
                        ? 'Activity could not be checked.'
                        : 'No active background jobs.',
                  ),
                ),
              AppPagedList(
                key: const PageStorageKey('active-job-pages'),
                itemCount: jobs.items.length,
                pageSize: 10,
                itemBuilder: (context, index) {
                  final item = jobs.items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppSurface(
                      padding: EdgeInsets.zero,
                      child: AppRecordRow(
                        leading: Icon(switch (item.kind) {
                          JobActivityKind.document =>
                            Icons.description_outlined,
                          JobActivityKind.ai => Icons.auto_awesome_outlined,
                          JobActivityKind.thumbnail => Icons.image_outlined,
                          JobActivityKind.email => Icons.mail_outline,
                          JobActivityKind.paperless =>
                            Icons.file_download_outlined,
                          JobActivityKind.reindex => Icons.restart_alt,
                        }),
                        title: item.title,
                        subtitle: item.batch != null
                            ? AppJobProgress(
                                label: reindexProgressLabel(item.batch!),
                                value: item.batch!.progress,
                                animate: !jobs.stale,
                              )
                            : Text(
                                '${item.kind == JobActivityKind.ai
                                    ? 'AI processing'
                                    : item.kind == JobActivityKind.thumbnail
                                    ? 'Thumbnail generation'
                                    : item.kind == JobActivityKind.document
                                    ? 'Document ingestion'
                                    : processingLabel(item.status)} · ${processingLabel(item.stage)}',
                              ),
                        metadata: AppStatusBadge(
                          label: processingLabel(item.status),
                          running: item.running && !jobs.stale,
                        ),
                        trailing: GlacierButton(
                          kind: GlacierButtonKind.quiet,
                          label: 'View',
                          onPressed: () {
                            Navigator.pop(context);
                            onOpen(item);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (jobs.hasMore)
                GlacierButton(
                  kind: GlacierButtonKind.quiet,
                  label: 'Load more active jobs',
                  onPressed: jobs.loading ? null : cubit.loadMore,
                ),
            ],
          ),
        );
      }

      return uploads == null
          ? panel(null)
          : BlocBuilder<DocumentUploadsCubit, DocumentUploadsState>(
              bloc: uploads,
              builder: (context, state) => panel(state),
            );
    },
  ),
);
