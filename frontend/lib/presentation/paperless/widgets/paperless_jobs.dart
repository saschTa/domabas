import 'package:flutter/material.dart';

import '../../../domain/paperless/models/paperless.dart';
import '../../../ui/domabas_ui.dart';
import 'paperless_pipeline.dart';
import 'paperless_outcomes.dart';
import '../../../domain/paperless/interfaces/paperless_repository.dart';

String paperlessJobStatus(PaperlessRun run) => run.status;

String paperlessJobStage(PaperlessRun run) => switch (run.stage) {
  'queued' => 'Waiting for import',
  'discovering' => 'Discovering documents',
  'importing' => 'Importing originals',
  'complete' => 'Import finished',
  _ => run.stage,
};

final class PaperlessJobDetails extends StatelessWidget {
  const PaperlessJobDetails({
    super.key,
    required this.run,
    required this.repository,
    this.error,
    required this.onOpenImport,
    required this.onOpenDocument,
  });
  final PaperlessRun run;
  final PaperlessRepository repository;
  final String? error;
  final VoidCallback onOpenImport;
  final void Function(String) onOpenDocument;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null) AppNotice(message: error!),
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.file_download_outlined),
                Text(
                  'Paperless import',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                AppStatusBadge(
                  running: run.state == 'running',
                  label: switch (paperlessJobStatus(run)) {
                    'partial' => 'Partially completed',
                    'succeeded' => 'Succeeded',
                    'failed' => 'Failed',
                    'cancelled' => 'Cancelled',
                    'running' => 'Running',
                    _ => 'Queued',
                  },
                  tone: switch (paperlessJobStatus(run)) {
                    'partial' => AppTone.warning,
                    'succeeded' => AppTone.success,
                    'failed' => AppTone.danger,
                    _ => AppTone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(run.serverUrl),
            Text('Created ${formatLocalDateTime(run.createdAt)}'),
            Text('Updated ${formatLocalDateTime(run.updatedAt)}'),
            Text('Stage: ${paperlessJobStage(run)}'),
            Text(
              '${run.discovered} discovered · ${run.imported} imported · ${run.duplicates} duplicates · ${run.failed} failed',
            ),
            if (run.failureCode != null)
              Text(PaperlessFailure(run.failureCode!).message),
            if (run.cancelRequested && run.active)
              const Text('Cancellation requested'),
            const SizedBox(height: 8),
            const Text(
              'Imported originals continue as separate document ingestion jobs. Duplicate originals keep their existing processing history.',
            ),
            TextButton(
              onPressed: onOpenImport,
              child: const Text('Open Paperless import'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(
              title: 'Pipeline for this attempt',
              description: 'Originals are imported one at a time. File outcomes record duplicates and failures.',
            ),
            const SizedBox(height: 20),
            PaperlessPipelineDiagram(run: run),
          ],
        ),
      ),
      const SizedBox(height: 20),
      AppSurface(
        child: PaperlessOutcomes(
          key: ValueKey(run.id),
          repository: repository,
          run: run,
          onOpenDocument: onOpenDocument,
        ),
      ),
    ],
  );
}
