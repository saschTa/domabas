import 'package:flutter/material.dart';

import '../../../domain/paperless/models/paperless.dart';
import '../../../ui/domabas_ui.dart';

final class PaperlessPipeline extends StatelessWidget {
  const PaperlessPipeline({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: ExpansionTile(
      key: const PageStorageKey('paperlessPipeline'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Paperless import pipeline'),
      subtitle: const Text(
        'Discover documents → import originals → document ingestion',
      ),
      children: const [SizedBox(height: 16), PaperlessPipelineDiagram()],
    ),
  );
}

final class PaperlessPipelineDiagram extends StatelessWidget {
  const PaperlessPipelineDiagram({super.key, this.run});
  final PaperlessRun? run;

  @override
  Widget build(BuildContext context) {
    const stages = [
      (
        Icons.hourglass_empty,
        'Import queue',
        'Saved import waits for an available worker.',
      ),
      (
        Icons.manage_search,
        'Document discovery',
        'Read the source document list and save progress.',
      ),
      (
        Icons.file_download_outlined,
        'Import originals',
        'Download originals with metadata. Record imported, duplicate and failed files.',
      ),
      (
        Icons.account_tree_outlined,
        'Document ingestion',
        'Imported originals enter separate parsing, OCR and indexing jobs.',
      ),
    ];
    final value = run;
    final active = switch (value?.stage) {
      'queued' => 0,
      'discovering' => 1,
      'importing' => 2,
      'complete' => 3,
      _ => -1,
    };
    AppPipelineStep step(int index) {
      String? status;
      var current = false;
      var failed = false;
      if (value != null) {
        final finished = value.state == 'succeeded';
        final missingStage = !finished && !value.active && active == 3;
        final itemFailures = index == 2 && value.failed > 0;
        final stopped =
            !value.active && !finished && !missingStage && index == active;
        current = value.state == 'running' && index == active;
        failed = itemFailures || (stopped && value.state == 'failed');
        status = index == 3
            ? value.imported > 0
                  ? 'Queued as document jobs'
                  : value.active
                  ? 'Waiting for imported files'
                  : 'No new files imported'
            : itemFailures
            ? finished
                  ? 'Completed with failures'
                  : 'Failures recorded'
            : missingStage || active == -1
            ? 'Not recorded'
            : stopped
            ? value.state == 'failed'
                  ? 'Stopped here'
                  : 'Cancelled here'
            : finished || index < active
            ? 'Complete'
            : current
            ? 'In progress'
            : value.active
            ? 'Waiting'
            : 'Not completed';
      }
      return AppPipelineStep(
        icon: failed ? Icons.error_outline : stages[index].$1,
        title: stages[index].$2,
        description: value == null || index != 2
            ? stages[index].$3
            : '${value.imported} imported · ${value.duplicates} duplicates · ${value.failed} failed',
        status: status,
        current: current,
        failed: failed,
      );
    }

    return AppPipelineDiagram(
      stageKeyPrefix: 'paperless-pipeline-stage',
      steps: [for (var i = 0; i < stages.length; i++) step(i)],
    );
  }
}
