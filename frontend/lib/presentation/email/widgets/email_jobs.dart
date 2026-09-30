import 'package:flutter/material.dart';

import '../../../domain/email/models/email.dart';
import '../../../ui/domabas_ui.dart';
import 'email_pipeline_diagram.dart';

final class EmailJobDetails extends StatelessWidget {
  const EmailJobDetails({
    super.key,
    required this.run,
    this.provider,
    this.error,
    required this.onOpenAccount,
  });
  final EmailRun run;
  final EmailProvider? provider;
  final String? error;
  final void Function(String) onOpenAccount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null) AppNotice(message: error!),
      EmailRunCard(run: run, provider: provider, onOpenAccount: onOpenAccount),
      const SizedBox(height: 20),
      AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(
              title: 'Pipeline for this attempt',
              description: 'Retrieval repeats for each message. The importing stage covers email and attachment acceptance.',
            ),
            const SizedBox(height: 20),
            EmailPipelineDiagram(run: run),
          ],
        ),
      ),
    ],
  );
}

final class EmailRunCard extends StatelessWidget {
  const EmailRunCard({
    super.key,
    required this.run,
    this.provider,
    required this.onOpenAccount,
  });
  final EmailRun run;
  final EmailProvider? provider;
  final void Function(String) onOpenAccount;

  @override
  Widget build(BuildContext context) => AppSurface(
    key: Key('email-job-${run.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.mail_outline),
            Text(
              provider?.label ?? 'Email import',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            AppStatusBadge(
              running: run.status == 'running',
              label: _label(run.status),
              tone: switch (run.status) {
                'succeeded' => AppTone.success,
                'failed' => AppTone.danger,
                'partial' => AppTone.warning,
                _ => AppTone.neutral,
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${_label(run.reason)} · ${formatLocalDateTime(run.createdAt)}'),
        if (run.startedAt != null)
          Text('Started ${formatLocalDateTime(run.startedAt!)}'),
        if (run.finishedAt != null)
          Text('Finished ${formatLocalDateTime(run.finishedAt!)}'),
        Text(
          'Stage: ${switch (run.stage) {
            'queued' => 'Waiting for retrieval',
            'connecting' => 'Connecting to mailbox',
            'discovering' => 'Discovering messages',
            'fetching' => 'Fetching email originals',
            'importing' => 'Importing emails and attachments',
            'complete' => 'Retrieval finished',
            _ => _label(run.stage),
          }}',
        ),
        Text('${run.messagesDiscovered} emails discovered'),
        Text(
          'Emails: ${run.messagesAccepted} accepted · ${run.messagesReused} reused · ${run.messagesSkipped} skipped · ${run.messagesFailed} failed',
        ),
        Text(
          'Attachments: ${run.attachmentsAccepted} accepted · ${run.attachmentsReused} reused · ${run.attachmentsSkipped} skipped · ${run.attachmentsFailed} failed',
        ),
        if (run.messagesWithContentFailures > 0)
          Text(
            '${run.messagesWithContentFailures} emails have content or attachment inspection failures.',
          ),
        if (run.failureCode != null)
          Text('Failure: ${_label(run.failureCode!)}'),
        if (run.hasMore)
          const Text('More mail remains for the next automatic check.'),
        const SizedBox(height: 8),
        const Text(
          'Accepted emails and attachments continue as separate document ingestion jobs.',
        ),
        if (provider != null)
          TextButton(
            onPressed: () => onOpenAccount(run.providerId),
            child: const Text('Open email account'),
          ),
      ],
    ),
  );

  static String _label(String value) => switch (value) {
    'scheduled' => 'Automatic check',
    'continuation' => 'Continuing mailbox import',
    'manual' => 'Import now',
    'partial' => 'Partially completed',
    _ =>
      value.isEmpty
          ? 'Unknown'
          : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}',
  };
}
