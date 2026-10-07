import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/paperless_settings_cubit.dart';

final class PaperlessSettingsScreen extends StatelessWidget {
  const PaperlessSettingsScreen({super.key, required this.cubit});

  final PaperlessSettingsCubit cubit;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PaperlessSettingsCubit, PaperlessSettingsState>(
    bloc: cubit,
    builder: (context, state) => AppPage(
      insetBody: false,
      eyebrow: 'ADMIN SETTINGS',
      title: 'Paperless retrievals',
      description: 'Set how many documents Domabas retrieves from Paperless at the same time across all libraries and imports.',
      onRefresh: state.loading || state.saving ? null : cubit.load,
      child: ListView(
        padding: AppLayout.cardListPadding(context),
        key: const Key('paperlessSettingsScroll'),
        children: [
          if (state.error != null && state.settings == null) ...[
            AppNotice(message: state.error!),
            const SizedBox(height: 16),
          ],
          AppProgressSlot(active: state.loading || state.saving),
          if (state.settings case final settings?)
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionHeader(
                    title: 'Import speed',
                    description: 'Protect the Paperless server and network by limiting parallel retrievals. Shared worker capacity also limits active imports.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'paperlessConcurrency-${state.retrievalConcurrency}',
                    ),
                    initialValue: state.retrievalConcurrency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Parallel retrievals',
                    ),
                    items: [
                      for (
                        var value = settings.minimumRetrievalConcurrency;
                        value <= settings.maximumRetrievalConcurrency;
                        value++
                      )
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: state.loading || state.saving
                        ? null
                        : (value) {
                            if (value != null) cubit.edit(value);
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Currently saved: ${settings.retrievalConcurrency} parallel retrieval${settings.retrievalConcurrency == 1 ? '' : 's'}.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Changes apply to new retrievals. Lowering the limit lets documents already being retrieved finish.',
                  ),
                  const SizedBox(height: 20),
                  if (state.error != null) ...[
                    AppNotice(message: state.error!),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    key: const Key('savePaperlessSettings'),
                    onPressed: state.canSave ? cubit.save : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save retrieval settings'),
                  ),
                  if (state.notice != null) ...[
                    const SizedBox(height: 16),
                    AppNotice(message: state.notice!, tone: AppTone.success),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          const AppNotice(
            tone: AppTone.info,
            title: 'Shared worker capacity',
            message: 'Paperless retrievals use workers. Retrieved documents enter document ingestion separately, where they also need Ollama for embeddings. Manage shared capacity in Workload limits. Running AI jobs continue when imports arrive.',
          ),
        ],
      ),
    ),
  );
}
