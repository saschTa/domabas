import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      insetBody: false,
      eyebrow: 'ADMIN SETTINGS',
      title: 'Workload limits',
      description: 'Control how many background jobs share workers and AI providers across all libraries.',
      actions: [
        IconButton(
          key: const Key('refreshWorkloadSettings'),
          tooltip: 'Refresh workload limits',
          onPressed: state.loading || state.saving ? null : cubit.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        key: const Key('workloadSettingsScroll'),
        padding: AppLayout.cardListPadding(context),
        children: [
          const AppNotice(
            tone: AppTone.info,
            title: 'Jobs share resources',
            message: 'Jobs wait until every resource they need has room. Running jobs finish normally; new imports and lower limits do not interrupt them.',
          ),
          const SizedBox(height: 16),
          AppProgressSlot(active: state.loading || state.saving),
          if (state.error != null) ...[
            AppNotice(message: state.error!),
            const SizedBox(height: 16),
          ],
          if (state.settings case final settings?) ...[
            for (final resource in settings.resources) ...[
              AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeader(
                      title: resource.label,
                      description: switch (resource.id) {
                        'worker' => 'One slot per active background job across all pipelines.',
                        'ollama' => 'Shared by background embedding jobs and AI pipelines configured to use Ollama.',
                        _ => 'Shared by background jobs using this provider address, including different models and API paths.',
                      },
                    ),
                    const SizedBox(height: 16),
                    _WorkloadLimitField(
                      key: ValueKey('workloadLimit-${resource.id}'),
                      resourceId: resource.id,
                      value: state.drafts[resource.id] ?? '',
                      keyboardType: TextInputType.number,
                      enabled: !state.loading && !state.saving,
                      decoration: InputDecoration(
                        labelText: 'Maximum active background jobs',
                        helperText: 'Allowed: 1–${resource.maximumLimit}',
                        errorText: resource.validateLimit(
                          state.drafts[resource.id] ?? '',
                        ),
                      ),
                      onChanged: (value) => cubit.edit(resource.id, value),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Saved: ${resource.limit} · Active: ${resource.activeJobs}',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New jobs wait until active usage falls below the saved limit.',
                    ),
                    if (resource.id == 'ollama') ...[
                      const SizedBox(height: 8),
                      Text(
                        'Configured Ollama queue: ${settings.ollamaQueueSize}. At most ${resource.maximumLimit} active background jobs, capped at 50% of the queue.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The queue sets a safety ceiling. Ollama controls how many requests run inference at once.',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active counts include jobs starting or finishing. Changes apply to new admissions and do not reindex documents.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('saveWorkloadSettings'),
                        onPressed: state.canSave ? cubit.save : null,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save limits'),
                      ),
                      TextButton(
                        key: const Key('resetWorkloadSettings'),
                        onPressed:
                            state.dirty &&
                                !state.loading &&
                                !state.saving &&
                                !state.requiresRefresh
                            ? cubit.resetDraft
                            : null,
                        child: const Text('Use saved limits'),
                      ),
                    ],
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
                    title: 'What shares these limits',
                    description: 'These are the current pipeline requirements. Each new job reserves every listed resource. When one is full, new jobs that need it wait; other pipelines can continue.',
                  ),
                  for (final pipeline in settings.pipelines) ...[
                    const SizedBox(height: 20),
                    Text(
                      pipeline.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in pipeline.resourceIds)
                          AppStatusBadge(
                            label: settings.resources
                                .firstWhere((resource) => resource.id == id)
                                .label,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Accepted jobs keep their original resource requirements. Provider resources from earlier settings can remain in the list above.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Paperless and email retrievals use workers. Accepted documents enter document ingestion separately, where they also need Ollama for embeddings.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Paperless parallel retrievals also protect the source server. That setting does not increase shared worker capacity.',
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
