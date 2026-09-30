import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/document_email_links_cubit.dart';

final class DocumentEmailLinksPanel extends StatelessWidget {
  const DocumentEmailLinksPanel({
    super.key,
    required this.cubit,
    required this.onOpen,
  });
  final DocumentEmailLinksCubit cubit;
  final Future<void> Function(String) onOpen;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentEmailLinksCubit, DocumentEmailLinksState>(
    bloc: cubit,
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.stale)
          AppNotice(
            message: 'Links changed. Reload links.',
            action: TextButton(
              onPressed: state.loading ? null : cubit.reload,
              child: const Text('Reload links'),
            ),
          ),
        AppProgressSlot(active: state.loading),
        if (state.error case final error?)
          AppNotice(
            message: error,
            action: TextButton(
              onPressed: state.loading ? null : cubit.reload,
              child: const Text('Retry email links'),
            ),
          ),
        if (state.parents.isNotEmpty) ...[
          const AppStripedDivider(height: 32, thickness: 8),
          Text('Source emails', style: Theme.of(context).textTheme.titleMedium),
          for (final parent in state.parents)
            TextButton.icon(
              key: Key('email-parent-${parent.id}'),
              onPressed: state.stale ? null : () => onOpen(parent.id),
              icon: const Icon(Icons.mail_outline),
              label: Text(parent.title),
            ),
        ],
        if (state.parentCursor != null)
          TextButton(
            onPressed: state.loading || state.stale
                ? null
                : () => cubit.load(moreParents: true),
            child: const Text('More source emails'),
          ),
        if (state.attachments.isNotEmpty) ...[
          const AppStripedDivider(height: 32, thickness: 8),
          Text('Attachments', style: Theme.of(context).textTheme.titleMedium),
          for (final attachment in state.attachments)
            AppRecordRow(
              key: Key('email-attachment-${attachment.part}'),
              title: attachment.filename,
              leading: const Icon(Icons.attach_file),
              subtitle: Text(attachment.status),
              onTap: attachment.document == null || state.stale
                  ? null
                  : () => onOpen(attachment.document!.id),
              trailing: attachment.document == null
                  ? null
                  : const Icon(Icons.chevron_right),
            ),
        ],
        if (state.attachmentCursor != null)
          TextButton(
            onPressed: state.loading || state.stale
                ? null
                : () => cubit.load(moreAttachments: true),
            child: const Text('More attachments'),
          ),
      ],
    ),
  );
}
