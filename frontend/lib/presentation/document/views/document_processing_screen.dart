import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/document/models/document_processing.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/document_processing_cubit.dart';
import '../widgets/document_scheduling_summary.dart';
import '../widgets/processing_widgets.dart';

final class DocumentProcessingScreen extends StatefulWidget {
  const DocumentProcessingScreen({
    super.key,
    required this.cubit,
    required this.canReadDocuments,
    required this.onOpenDocument,
    this.sourcePipeline,
    this.jobsList,
    this.selectedSourceId,
    this.selectedSourceTitle,
    this.selectedSourceDetails,
    this.onClearSourceSelection,
    this.onRefresh,
    this.refreshing = false,
    this.onEditExtraction,
    this.initialBatches = false,
  });
  final DocumentProcessingCubit cubit;
  final bool initialBatches;
  final bool canReadDocuments;
  final void Function(String) onOpenDocument;
  final Widget? sourcePipeline, jobsList, selectedSourceDetails;
  final String? selectedSourceId, selectedSourceTitle;
  final VoidCallback? onClearSourceSelection;
  final Future<void> Function()? onRefresh;
  final bool refreshing;
  final VoidCallback? onEditExtraction;
  @override
  State<DocumentProcessingScreen> createState() =>
      _DocumentProcessingScreenState();
}

final class _DocumentProcessingScreenState
    extends State<DocumentProcessingScreen> {
  late bool _batches = widget.initialBatches;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentProcessingCubit, DocumentProcessingState>(
    bloc: widget.cubit,
    builder: (context, state) {
      final cubit = widget.cubit;
      final selected = state.selected;
      final details = selected != null || widget.selectedSourceDetails != null;
      return AppPage(
        insetBody: false,
        showHeading: details,
        eyebrow: 'CURRENT LIBRARY',
        title: !details ? 'Jobs & pipeline' : 'Job details',
        description: !details
            ? 'Track imports, document processing and reindexing.'
            : selected?.label ?? widget.selectedSourceTitle,
        onRefresh:
            widget.refreshing ||
                state.loading ||
                state.saving ||
                state.countsRefreshing ||
                state.detailLoading
            ? null
            : widget.onRefresh ??
                  (cubit.canReadJobs || cubit.canReindex ? cubit.load : null),
        actions: [
          if (details)
            TextButton.icon(
              onPressed: selected != null
                  ? cubit.clearSelection
                  : widget.onClearSourceSelection,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to jobs'),
            ),
        ],
        child: ListView(
          padding: AppLayout.cardListPadding(context),
          key: PageStorageKey(
            !details
                ? 'processingPage'
                : 'processingJob-${selected?.id ?? widget.selectedSourceId}',
          ),
          children: [
            if (cubit.canReindex && !details) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('reindexLibrary'),
                  onPressed: cubit.canRequest ? () => _reindex(context) : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reindex library originals'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (state.error != null) ...[
              AppNotice(
                message: state.error!,
                action: state.pendingRequest != null
                    ? TextButton(
                        onPressed: state.loading || state.saving
                            ? null
                            : () => cubit.requestReindex(retry: true),
                        child: const Text('Retry same request'),
                      )
                    : TextButton(
                        onPressed: state.loading || state.saving
                            ? null
                            : () => cubit.load(),
                        child: const Text('Retry'),
                      ),
              ),
              const SizedBox(height: 16),
            ],
            if (state.notice != null) ...[
              AppNotice(message: state.notice!, tone: AppTone.success),
              const SizedBox(height: 16),
            ],
            if (state.browsingHistory && !details) ...[
              const AppNotice(
                message: 'Older history stays in place while active outcomes update. Pull down to see the newest records.',
              ),
              const SizedBox(height: 16),
            ],
            AppProgressSlot(
              active: state.loading || state.saving || state.detailLoading,
            ),
            const SizedBox(height: 16),
            if (selected != null)
              ..._details(context, selected)
            else if (widget.selectedSourceDetails case final sourceDetails?)
              sourceDetails
            else ...[
              if (cubit.canReadJobs ||
                  (cubit.canReindex && widget.sourcePipeline != null)) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Jobs'),
                      selected: !_batches,
                      onSelected: (_) => setState(() => _batches = false),
                    ),
                    ChoiceChip(
                      key: const Key('showReindexRequests'),
                      label: const Text('Reindex requests'),
                      selected: _batches,
                      onSelected: (_) => setState(() => _batches = true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_batches ||
                  (!cubit.canReadJobs &&
                      cubit.canReindex &&
                      widget.sourcePipeline == null)) ...[
                const AppSectionHeader(
                  title: 'Current library reindex requests',
                  description: 'Requests started for this library. All-library requests and automatic pipeline changes appear in Admin document processing. Their individual document attempts appear in Jobs.',
                ),
                const SizedBox(height: 16),
                if (state.batches.isEmpty &&
                    (!state.loading || state.pipeline != null))
                  const AppEmptyState(
                    icon: Icons.restart_alt,
                    title: 'No reindex requests yet',
                    message: 'Accepted requests and their outcomes will appear here.',
                  ),
                AppPagedList(
                  key: const PageStorageKey('namespace-reindex-pages'),
                  itemCount: state.batches.length,
                  hasMore: state.batchCursor != null,
                  loading: state.loading || state.saving,
                  onLoadMore: () => cubit.load(moreBatches: true),
                  loadMoreLabel: 'Load more requests',
                  itemBuilder: (context, index) {
                    final batch = state.batches[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ReindexBatchCard(
                        key: Key('batch-${batch.id}'),
                        batch: batch,
                      ),
                    );
                  },
                ),
              ] else if (widget.jobsList case final jobs?) ...[
                jobs,
              ] else if (cubit.canReadJobs) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (id, label) in <(String?, String)>[
                      (null, 'All pipelines'),
                      ('ingestion', 'Document ingestion'),
                      ('ai', 'AI processing'),
                    ])
                      ChoiceChip(
                        key: Key('pipeline-filter-${id ?? 'all'}'),
                        label: Text(label),
                        selected: state.jobPipeline == id,
                        onSelected: (_) =>
                            cubit.filter(state.status, pipeline: id),
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
                      'failed',
                      'superseded',
                      'cancelled',
                      'skipped',
                    ])
                      ChoiceChip(
                        key: Key('job-filter-${status ?? 'all'}'),
                        label: Text(
                          status == null ? 'All jobs' : processingLabel(status),
                        ),
                        selected: state.status == status,
                        onSelected: (_) =>
                            cubit.filter(status, pipeline: state.jobPipeline),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (state.jobs.isEmpty &&
                    (!state.loading || state.pipeline != null))
                  const AppEmptyState(
                    icon: Icons.work_history_outlined,
                    title: 'No jobs to show',
                    message: 'Processing attempts appear here when originals are uploaded, corrected, retried or reindexed.',
                  ),
                AppPagedList(
                  key: PageStorageKey('document-jobs-${state.status ?? 'all'}'),
                  itemCount: state.jobs.length,
                  hasMore: state.nextCursor != null,
                  loading: state.loading || state.saving,
                  onLoadMore: () => cubit.load(moreJobs: true),
                  loadMoreLabel: 'Load more jobs',
                  itemBuilder: (context, index) {
                    final job = state.jobs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppSurface(
                        padding: EdgeInsets.zero,
                        child: AppRecordRow(
                          key: Key('job-${job.id}'),
                          leading: Icon(
                            job.status == 'failed'
                                ? Icons.error_outline
                                : Icons.work_history_outlined,
                          ),
                          title: job.label,
                          subtitle: Text(
                            '${job.pipelineLabel} · ${processingLabel(job.reason)} · attempt ${job.attemptNumber}\n${processingTime(job.createdAt)}',
                          ),
                          metadata: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppStatusBadge(
                                running: job.status == 'running',
                                label: processingLabel(job.status),
                                tone: processingTone(job.status),
                              ),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: state.detailLoading
                                ? null
                                : () => cubit.selectJob(job.id),
                            child: const Text('Details'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 20),
              _pipelineSetup(state),
            ],
          ],
        ),
      );
    },
  );
  Widget _pipelineSetup(DocumentProcessingState state) => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      key: const PageStorageKey('pipelineSetup'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      title: const Text('Pipeline setup'),
      children: [
        DocumentSchedulingSummary(scheduling: state.pipeline?.scheduling),
        const SizedBox(height: 20),
        if (widget.sourcePipeline case final pipeline?) ...[
          pipeline,
          const SizedBox(height: 20),
        ],
        if (state.pipeline case final DocumentProcessingPipeline pipeline) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ExpansionTile(
              key: const PageStorageKey('namespacePipeline'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Document ingestion pipeline'),
              subtitle: Text(
                '${pipeline.configuration.embeddingModel} · ${processingLabel(pipeline.configuration.language)}',
              ),
              children: [
                const SizedBox(height: 16),
                PipelineDiagram(
                  configuration: pipeline.configuration,
                  onEditExtraction: widget.onEditExtraction,
                ),
                ProcessingConfigurationDetails(
                  configuration: pipeline.configuration,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ExpansionTile(
              key: const PageStorageKey('namespaceAIPipeline'),
              tilePadding: EdgeInsets.zero,
              title: const Text('AI processing pipeline'),
              subtitle: const Text(
                'Runs after ingestion. Documents stay searchable if optional processing fails.',
              ),
              children: [
                const SizedBox(height: 16),
                DocumentAIPipelineDiagram(
                  configuration: pipeline.configuration,
                  onEditExtraction: widget.onEditExtraction,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (widget.cubit.canReadJobs) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ExpansionTile(
              key: const PageStorageKey('namespaceThumbnailPipeline'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Thumbnail generation pipeline'),
              subtitle: const Text(
                'Creates collection previews automatically. Uses worker capacity without OCR or AI.',
              ),
              children: const [
                SizedBox(height: 16),
                DocumentThumbnailPipelineDiagram(),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    ),
  );

  List<Widget> _details(BuildContext context, DocumentProcessingJob job) => [
    AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              AppStatusBadge(
                running: job.status == 'running',
                label: processingLabel(job.status),
                tone: processingTone(job.status),
              ),
              Text(
                '${job.pipelineLabel} · ${processingLabel(job.reason)} · attempt ${job.attemptNumber}',
              ),
              Text(job.isCurrent ? 'Current attempt' : 'Earlier attempt'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Created ${processingTime(job.createdAt)}'),
          if (job.startedAt != null)
            Text('Started ${processingTime(job.startedAt!)}'),
          if (job.finishedAt != null)
            Text('Finished ${processingTime(job.finishedAt!)}'),
          Text('Updated ${processingTime(job.updatedAt)}'),
          if (job.invoiceClassification case final classification?) ...[
            const SizedBox(height: 12),
            Text(invoiceClassificationLabel(classification)),
          ],
          if (job.failureCode != null) ...[
            const SizedBox(height: 16),
            AppNotice(
              message: processingFailure(job.failureCode),
              tone: processingTone(job.status),
            ),
          ],
          if (job.documentDeleted) ...[
            const SizedBox(height: 12),
            const Text(
              'The document was deleted. This record preserves the processing outcome.',
            ),
          ],
          if (widget.canReadDocuments && !job.documentDeleted) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('openJobDocument'),
              onPressed: () => widget.onOpenDocument(job.documentId),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open document'),
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 20),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'Pipeline for this attempt'),
          const SizedBox(height: 20),
          if (job.reason == 'legacy') ...[
            const AppNotice(
              message: 'This retained run predates detailed job history. Its overall outcome is known, but stage completion was not recorded.',
            ),
            const SizedBox(height: 16),
          ],
          if (job.isThumbnail) ...[
            const AppNotice(
              message: 'Thumbnail generation runs independently of document ingestion and AI processing.',
            ),
            const SizedBox(height: 16),
            DocumentThumbnailPipelineDiagram(job: job),
            if (job.rendererRevision case final revision?) ...[
              const SizedBox(height: 16),
              Text('Thumbnail renderer revision $revision'),
            ],
          ] else if (job.isAI) ...[
            const AppNotice(
              message: 'This processing runs after ingestion. Its outcome does not change the document’s ingestion result.',
            ),
            const SizedBox(height: 16),
            DocumentAIPipelineDiagram(
              configuration: job.configuration!,
              job: job,
            ),
          ] else ...[
            if (job.pipelineVersion == 1 && job.reason != 'legacy') ...[
              const AppNotice(
                message: 'This earlier attempt used the combined ingestion and AI pipeline.',
              ),
              const SizedBox(height: 16),
            ],
            PipelineDiagram(configuration: job.configuration!, job: job),
          ],
          if (!job.isThumbnail)
            ProcessingConfigurationDetails(configuration: job.configuration!),
        ],
      ),
    ),
  ];
  Future<void> _reindex(BuildContext context) async {
    if (!widget.cubit.canRequest) return;
    if (await confirmReindex(context, system: false) &&
        mounted &&
        widget.cubit.canRequest) {
      setState(() => _batches = true);
      await widget.cubit.requestReindex();
    }
  }
}
