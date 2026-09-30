import 'package:flutter/material.dart';

import '../../../domain/email/models/email.dart';
import '../../../ui/domabas_ui.dart';

final class EmailPipelineDiagram extends StatelessWidget {
  const EmailPipelineDiagram({super.key, this.run});
  final EmailRun? run;

  @override
  Widget build(BuildContext context) {
    const stages = [
      (
        Icons.schedule,
        'Mailbox schedule',
        'Automatic checks at the account interval, or Import now.',
      ),
      (
        Icons.hourglass_empty,
        'Retrieval queue',
        'Saved import waits for an available worker.',
      ),
      (
        Icons.manage_search,
        'Message discovery',
        'Connect securely and find mail within the age limit using saved progress.',
      ),
      (
        Icons.mail_outline,
        'Email originals',
        'Keep the full EML including its body. Source messages stay unchanged.',
      ),
      (
        Icons.attach_file,
        'Attachments',
        'Import linked PDF, PNG and JPEG files. Record skipped and failed parts.',
      ),
      (
        Icons.account_tree_outlined,
        'Document ingestion',
        'Accepted email and attachments enter separate parsing, OCR and indexing jobs.',
      ),
    ];
    final value = run;
    final active = switch (value?.stage) {
      'queued' => 1,
      'discovering' => 2,
      'fetching' => 3,
      'importing' => 3,
      'complete' => 5,
      _ => -1,
    };
    AppPipelineStep step(int index) {
      if (value == null) {
        return AppPipelineStep(
          icon: stages[index].$1,
          title: stages[index].$2,
          description: stages[index].$3,
        );
      }
      final legacyFailure =
          value.stage == 'complete' &&
          (value.status == 'cancelled' ||
              (value.status == 'failed' && value.failureCode != null));
      final importing =
          value.stage == 'importing' && (index == 3 || index == 4);
      final current =
          value.status == 'running' && (index == active || importing);
      final itemFailures = index == 3
          ? value.messagesFailed
          : index == 4
          ? value.attachmentsFailed + value.messagesWithContentFailures
          : 0;
      final stopped =
          !value.active &&
          value.stage != 'complete' &&
          (index == active || importing);
      final failed = itemFailures > 0 || (stopped && value.status == 'failed');
      final accepted =
          value.messagesAccepted +
          value.messagesReused +
          value.attachmentsAccepted +
          value.attachmentsReused;
      final complete =
          index == 0 ||
          (index < active && !legacyFailure && index < 3) ||
          (value.stage == 'complete' &&
              !legacyFailure &&
              index < 5 &&
              itemFailures == 0);
      final status = index == 5
          ? accepted > 0
                ? 'Queued as document jobs'
                : value.active
                ? 'Waiting for accepted files'
                : 'No files accepted'
          : itemFailures > 0
          ? value.active
                ? 'Failures recorded'
                : 'Completed with failures'
          : stopped
          ? value.status == 'failed'
                ? 'Stopped here'
                : 'Cancelled here'
          : legacyFailure && index > 1
          ? 'Not recorded'
          : complete
          ? 'Complete'
          : current
          ? 'In progress'
          : value.active
          ? 'Waiting'
          : 'Not completed';
      return AppPipelineStep(
        icon: failed
            ? Icons.error_outline
            : complete
            ? Icons.check_circle_outline
            : stages[index].$1,
        title: stages[index].$2,
        description: index == 3
            ? '${value.messagesAccepted} accepted · ${value.messagesReused} reused · ${value.messagesSkipped} skipped · ${value.messagesFailed} failed'
            : index == 4
            ? '${value.attachmentsAccepted} accepted · ${value.attachmentsReused} reused · ${value.attachmentsSkipped} skipped · ${value.attachmentsFailed} failed'
            : stages[index].$3,
        status: status,
        current: current,
        failed: failed,
      );
    }

    return AppPipelineDiagram(
      stageKeyPrefix: 'email-pipeline-stage',
      steps: [for (var i = 0; i < stages.length; i++) step(i)],
    );
  }
}
