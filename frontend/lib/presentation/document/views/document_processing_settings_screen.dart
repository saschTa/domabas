import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/document_processing_settings_cubit.dart';
import '../widgets/document_scheduling_summary.dart';
import '../widgets/processing_widgets.dart';
import '../widgets/property_extraction_settings.dart';

final class DocumentProcessingSettingsScreen extends StatefulWidget {
  const DocumentProcessingSettingsScreen({super.key, required this.cubit});
  final DocumentProcessingSettingsCubit cubit;

  @override
  State<DocumentProcessingSettingsScreen> createState() =>
      _DocumentProcessingSettingsScreenState();
}

final class _DocumentProcessingSettingsScreenState
    extends State<DocumentProcessingSettingsScreen> {
  bool _editingExtraction = false;
  DocumentProcessingSettingsCubit get cubit => widget.cubit;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<
        DocumentProcessingSettingsCubit,
        DocumentProcessingSettingsState
      >(
        bloc: cubit,
        listenWhen: (previous, current) =>
            !_editingExtraction &&
            current.notice != null &&
            previous.notice != current.notice,
        listener: (context, state) => ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(state.notice!))),
        builder: (context, state) {
          final config = state.configuration;
          return AppPage(
            insetBody: false,
            eyebrow: 'ADMIN SETTINGS',
            title: 'Document processing',
            description: 'Configure OCR, optional AI property and invoice extraction, and indexing across all libraries.',
            onRefresh: state.loading || state.saving ? null : cubit.load,
            child: ListView(
              padding: AppLayout.cardListPadding(context),
              children: [
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
                if (state.browsingHistory) ...[
                  const AppNotice(
                    message: 'Older history stays in place while active outcomes update. Pull down to see the newest requests.',
                  ),
                  const SizedBox(height: 16),
                ],
                AppProgressSlot(active: state.loading || state.saving),
                const SizedBox(height: 16),
                if (config != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            Text(
                              'Installed pipeline',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            AppStatusBadge(
                              label: config.pipeline.ready
                                  ? 'Processor ready'
                                  : 'Processor unavailable',
                              tone: config.pipeline.ready
                                  ? AppTone.success
                                  : AppTone.warning,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const AppSectionHeader(
                          title: 'Document ingestion',
                          description: 'Original, OCR, embeddings and searchable publication.',
                        ),
                        const SizedBox(height: 16),
                        PipelineDiagram(
                          configuration: config.pipeline.configuration,
                          onEditExtraction: () => _editExtraction(context),
                        ),
                        const SizedBox(height: 24),
                        const AppSectionHeader(
                          title: 'AI processing',
                          description: 'Runs after ingestion. Optional failures leave the document searchable.',
                        ),
                        const SizedBox(height: 16),
                        DocumentAIPipelineDiagram(
                          configuration: config.pipeline.configuration,
                          onEditExtraction: () => _editExtraction(context),
                        ),
                        ProcessingConfigurationDetails(
                          configuration: config.pipeline.configuration,
                        ),
                        const SizedBox(height: 24),
                        const AppSectionHeader(
                          title: 'Thumbnail generation',
                          description: 'Creates collection previews automatically using worker capacity without OCR or AI.',
                        ),
                        const SizedBox(height: 16),
                        const DocumentThumbnailPipelineDiagram(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DocumentSchedulingSummary(
                    scheduling: config.pipeline.scheduling,
                    initiallyExpanded: true,
                  ),
                  const SizedBox(height: 20),
                  AppSurface(
                    key: const Key('propertyExtractionSettings'),
                    child: PropertyExtractionSettings(
                      cubit: cubit,
                      state: state,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          title: 'OCR settings',
                          description: 'A saved change automatically reprocesses stored originals in every library. Saved OCR corrections remain in use.',
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          key: ValueKey('ocrLanguage-${state.language}'),
                          initialValue: state.language,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'OCR language',
                          ),
                          items: [
                            for (final language in config.pipeline.languages)
                              DropdownMenuItem(
                                value: language,
                                child: Text(processingLabel(language)),
                              ),
                          ],
                          onChanged: state.saving || state.reconcileRequired
                              ? null
                              : (value) => cubit.edit(language: value),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'ocrSegmentation-${state.segmentation}',
                          ),
                          initialValue: state.segmentation,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Page layout',
                          ),
                          items: [
                            for (final segmentation
                                in config.pipeline.segmentations)
                              DropdownMenuItem(
                                value: segmentation,
                                child: Text(processingLabel(segmentation)),
                              ),
                          ],
                          onChanged: state.saving || state.reconcileRequired
                              ? null
                              : (value) => cubit.edit(segmentation: value),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              key: const Key('saveProcessingSettings'),
                              onPressed: cubit.canSave
                                  ? () => cubit.save()
                                  : null,
                              child: const Text('Save settings'),
                            ),
                            TextButton(
                              onPressed:
                                  state.saving ||
                                      state.reconcileRequired ||
                                      !state.dirty
                                  ? null
                                  : cubit.resetDraft,
                              child: const Text('Use saved settings'),
                            ),
                          ],
                        ),
                        if (state.draftRevision != null &&
                            state.draftRevision !=
                                config.pipeline.configuration.revision) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'The server configuration changed while you were editing. Review the saved settings before applying your draft.',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          title: 'Reindex originals',
                          description: 'Request another complete pass through the current pipeline for every library. Progress reflects completed document attempts.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('reindexSystem'),
                          onPressed: cubit.canRequest
                              ? () => _reindex(context)
                              : null,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reindex all library originals'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          title: 'Temporal dashboard',
                          description: 'Open the internal workflow dashboard in a separate browser window.',
                        ),
                        const SizedBox(height: 16),
                        if (config.dashboardUrl != null)
                          OutlinedButton.icon(
                            key: const Key('openTemporalDashboard'),
                            onPressed: cubit.openDashboard,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open Temporal dashboard'),
                          )
                        else
                          const Text(
                            'The internal dashboard link has not been configured for this installation.',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const AppSectionHeader(
                    title: 'Installation reindex requests',
                    description: 'All libraries · Manual requests and automatic pipeline changes. Requests for one library appear in Jobs & pipeline.',
                  ),
                  const SizedBox(height: 16),
                  if (state.batches.isEmpty)
                    const AppEmptyState(
                      icon: Icons.restart_alt,
                      title: 'No reindex requests yet',
                      message: 'Manual requests and automatic pipeline changes will appear here.',
                    ),
                  AppPagedList(
                    key: const PageStorageKey('system-reindex-pages'),
                    itemCount: state.batches.length,
                    hasMore: state.nextCursor != null,
                    loading: state.loading || state.saving,
                    onLoadMore: () => cubit.load(more: true),
                    loadMoreLabel: 'Load more requests',
                    itemBuilder: (context, index) {
                      final batch = state.batches[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ReindexBatchCard(
                          key: Key('system-batch-${batch.id}'),
                          batch: batch,
                        ),
                      );
                    },
                  ),
                ] else if (!state.loading && state.error == null)
                  const AppEmptyState(
                    icon: Icons.settings_outlined,
                    title: 'Processing settings are unavailable',
                    message: 'Pull down to load the installed pipeline.',
                  ),
              ],
            ),
          );
        },
      );
  Future<void> _editExtraction(BuildContext context) async {
    _editingExtraction = true;
    ScaffoldMessenger.of(context).clearSnackBars();
    String? savedNotice;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) =>
            BlocConsumer<
              DocumentProcessingSettingsCubit,
              DocumentProcessingSettingsState
            >(
              bloc: cubit,
              listenWhen: (previous, current) =>
                  current.notice != null &&
                  current.error == null &&
                  previous.notice != current.notice &&
                  ((previous.saving &&
                          previous.pendingRequest == null &&
                          !current.saving) ||
                      (previous.reconcileRequired &&
                          !current.reconcileRequired)),
              listener: (context, state) => savedNotice = state.notice,
              builder: (context, state) {
                return AppDialog(
                  title: 'Extraction settings',
                  onRefresh: state.loading || state.saving ? null : cubit.load,
                  actions: [
                    Visibility(
                      visible:
                          savedNotice != null && savedNotice == state.notice,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Semantics(
                        liveRegion: true,
                        child: const AppStatusBadge(
                          label: 'Settings saved',
                          tone: AppTone.success,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.error != null) ...[
                        AppNotice(
                          message: state.error!,
                          action: TextButton(
                            onPressed: state.saving ? null : () => cubit.load(),
                            child: const Text('Retry'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AppProgressSlot(active: state.saving),
                      if (state.configuration != null)
                        PropertyExtractionSettings(cubit: cubit, state: state),
                    ],
                  ),
                );
              },
            ),
      );
    } finally {
      _editingExtraction = false;
    }
  }

  Future<void> _reindex(BuildContext context) async {
    if (!cubit.canRequest) return;
    if (await confirmReindex(context, system: true) &&
        context.mounted &&
        cubit.canRequest) {
      await cubit.requestReindex();
    }
  }
}
