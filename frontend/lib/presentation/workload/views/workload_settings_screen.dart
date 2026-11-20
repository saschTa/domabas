import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/workload/models/workload_settings.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/workload_settings_cubit.dart';

final class WorkloadSettingsScreen extends StatelessWidget {
  const WorkloadSettingsScreen({super.key, required this.cubit});

  final WorkloadSettingsCubit cubit;

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<WorkloadSettingsCubit, WorkloadSettingsState>(
    bloc: cubit,
    listenWhen: (previous, current) =>
        current.notice != null && previous.notice != current.notice,
    listener: (context, state) => ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(state.notice!))),
    builder: (context, state) => AppPage(
      glacier: true,
      insetBody: false,

      title: 'Workload limits',
      description: 'Monitor active work across libraries and set how much can run at once.',
      onRefresh: state.loading || state.saving ? null : cubit.load,
      child: ListView(
        key: const Key('workloadSettingsScroll'),
        padding: GlacierSettingsPage.scrollPadding(context),
        children: [
          AppProgressSlot(active: state.loading || state.saving),
          if (state.error != null) ...[
            AppNotice(message: state.error!),
            const SizedBox(height: 16),
          ],
          if (state.settings case final settings?) ...[
            if (settings.pipelines.isNotEmpty) ...[
              AppSurface(
                glacier: true,
                child: GlacierWorkloadFlow(pipelines: _flowPipelines(settings)),
              ),
              const SizedBox(height: 24),
            ],
            for (final pipelines in [true, false]) ...[
              if (settings.resources.any(
                (r) => r.id.startsWith('pipeline:') == pipelines,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppSectionHeader(
                    title: pipelines ? 'Pipelines' : 'Shared resources',
                    description: pipelines
                        ? 'Maximum concurrent runs for each type of work.'
                        : 'Stages acquire these slots while they use the resource.',
                  ),
                ),
              for (final resource in settings.resources.where(
                (r) => r.id.startsWith('pipeline:') == pipelines,
              )) ...[
                GlacierWorkloadResource(
                  label: _resourceLabel(resource),
                  active: resource.activeJobs,
                  savedLimit: resource.limit,
                  maximumLimit: resource.maximumLimit,
                  description: switch (resource.id) {
                    'worker' => 'One slot per active background job across all pipelines.',
                    'pipeline:document_ingestion' => 'Generate a thumbnail, extract text, then embed the document.',
                    'pipeline:paperless' => 'Import runs across all libraries. Each run can download several files.',
                    'pipeline:invoice' => 'Extract structured invoice fields from XML or recognized text.',
                    'pipeline:tags' => 'Extract document tags and properties from recognized text.',
                    'stage:paperless' => 'Simultaneous downloads from Paperless before document ingestion.',
                    _ when pipelines => 'Concurrent runs across all libraries.',
                    _ when resource.id.startsWith('stage:') =>
                      'Shared across all pipelines that use this stage.',
                    'embedding-runtime' =>
                      'Used by document indexing and semantic search.',
                    _ => 'Shared by background jobs using this provider address, including different models and API paths.',
                  },
                  limitField: _WorkloadLimitField(
                    key: ValueKey('workloadLimit-${resource.id}'),
                    resourceId: resource.id,
                    value: state.drafts[resource.id] ?? '',
                    keyboardType: TextInputType.number,
                    enabled: !state.loading && !state.saving,
                    decoration: InputDecoration(
                      labelText: 'Maximum parallel',
                      errorText: resource.validateLimit(
                        state.drafts[resource.id] ?? '',
                      ),
                    ),
                    onChanged: (value) => cubit.edit(resource.id, value),
                  ),
                  notice: resource.id == 'embedding-runtime'
                      ? 'Embedding runtime queue size ${settings.embeddingQueueSize}. The maximum is half the configured queue.'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
            ],
            AppSurface(
              glacier: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lowering a limit lets active work finish. New work waits until a slot opens.',
                  ),
                  const SizedBox(height: 16),
                  GlacierWorkspaceGeometry.measureEndActions(
                    context,
                    followingExtent: 24,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        GlacierButton(
                          key: const Key('saveWorkloadSettings'),
                          onPressed: state.canSave ? cubit.save : null,
                          label: 'Save limits',
                          icon: Icons.save_outlined,
                          kind: GlacierButtonKind.primary,
                        ),
                        GlacierButton(
                          key: const Key('resetWorkloadSettings'),
                          onPressed:
                              state.dirty &&
                                  !state.loading &&
                                  !state.saving &&
                                  !state.requiresRefresh
                              ? cubit.resetDraft
                              : null,
                          label: 'Use saved limits',
                          kind: GlacierButtonKind.quiet,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

String _resourceLabel(WorkloadResource resource) =>
    resource.id.startsWith('external:')
    ? '${resource.label} (external API provider)'
    : resource.label;

List<GlacierFlowPipeline> _flowPipelines(WorkloadSettings settings) {
  final resources = {
    for (final resource in settings.resources) resource.id: resource,
  };
  return [
    for (final pipeline in settings.pipelines)
      (
        id: pipeline.id,
        label: pipeline.label,
        active: resources['pipeline:${pipeline.id}']?.activeJobs,
        limit: resources['pipeline:${pipeline.id}']?.limit,
        resources: [
          for (final id in pipeline.resourceIds)
            if (resources[id] case final resource?)
              (
                id: id,
                label: _resourceLabel(resource),
                active: resource.activeJobs,
                limit: resource.limit,
                fromPipeline: pipeline.activeSlots[id],
              ),
        ],
      ),
  ];
}

final class _WorkloadLimitField extends StatefulWidget {
  const _WorkloadLimitField({
    super.key,
    required this.resourceId,
    required this.value,
    required this.keyboardType,
    required this.enabled,
    required this.decoration,
    required this.onChanged,
  });

  final String resourceId, value;
  final TextInputType keyboardType;
  final bool enabled;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<_WorkloadLimitField> createState() => _WorkloadLimitFieldState();
}

final class _WorkloadLimitFieldState extends State<_WorkloadLimitField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_WorkloadLimitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('workloadLimit-${widget.resourceId}-input'),
    controller: _controller,
    keyboardType: widget.keyboardType,
    enabled: widget.enabled,
    decoration: widget.decoration,
    onChanged: widget.onChanged,
  );
}
