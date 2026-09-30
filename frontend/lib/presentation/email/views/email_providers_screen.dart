import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/email/models/email.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/email_providers_cubit.dart';
import '../widgets/email_provider_editor.dart';

final class EmailProvidersScreen extends StatefulWidget {
  const EmailProvidersScreen({super.key, required this.cubit});
  final EmailProvidersCubit cubit;
  @override
  State<EmailProvidersScreen> createState() => _EmailProvidersScreenState();
}

final class _EmailProvidersScreenState extends State<EmailProvidersScreen> {
  DialogRoute<EmailProvider>? _editor;
  DialogRoute<bool>? _confirmation;
  @override
  void dispose() {
    for (final route in [_editor, _confirmation]) {
      if (route?.isActive ?? false) {
        route!.navigator?.removeRoute(route);
      }
    }
    super.dispose();
  }

  Future<void> _edit([EmailProvider? provider]) async {
    final capabilities = widget.cubit.state.capabilities;
    if (_editor != null || capabilities == null) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    late final DialogRoute<EmailProvider> route;
    route = DialogRoute(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmailProviderEditor(
        repository: widget.cubit.repository,
        capabilities: capabilities,
        provider: provider,
        canImport: widget.cubit.canImport,
        onClose: (result) {
          if (route.isActive) {
            navigator.removeRoute(route, result);
          }
        },
      ),
    );
    _editor = route;
    final result = await navigator.push(route);
    _editor = null;
    if (mounted && result != null) {
      await widget.cubit.saved(result);
    }
  }

  Future<void> _delete() async {
    if (_confirmation != null) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    late final DialogRoute<bool> route;
    route = DialogRoute(
      context: context,
      builder: (_) => AppDialog(
        title: 'Delete email account?',
        description: 'Future imports stop. Emails and attachments already accepted remain in this library.',
        actions: [
          TextButton(
            onPressed: () {
              if (route.isActive) {
                navigator.removeRoute(route, false);
              }
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('email-confirm-delete'),
            onPressed: () {
              if (route.isActive) {
                navigator.removeRoute(route, true);
              }
            },
            child: const Text('Delete account'),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    _confirmation = route;
    final confirmed = await navigator.push(route);
    _confirmation = null;
    if (mounted && confirmed == true) {
      await widget.cubit.deleteProvider();
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<EmailProvidersCubit, EmailProvidersState>(
    bloc: widget.cubit,
    builder: (context, state) => AppPage(
      insetBody: false,
      eyebrow: 'USER SETTINGS',
      title: 'Email accounts',
      description:
          'Your private account connections import into the current library.',
      child: ListView(
        padding: AppLayout.cardListPadding(context),
        children: [
          AppProgressSlot(active: state.loading || state.saving),
          if (state.error case final error?) AppNotice(message: error),
          if (state.notice case final notice?)
            AppNotice(message: notice, tone: AppTone.neutral),
          if (state.capabilities?.credentialsAvailable == false)
            const AppNotice(
              message: 'Email credentials are not configured on this server. Existing account details remain available.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state.selectedId != null)
                TextButton.icon(
                  onPressed:
                      state.saving || state.pendingRun || state.reconcileDelete
                      ? null
                      : widget.cubit.back,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('All email accounts'),
                ),
              OutlinedButton.icon(
                key: const Key('email-refresh'),
                onPressed: state.loading || state.saving
                    ? null
                    : () => widget.cubit.load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              if (state.selectedId == null)
                FilledButton.icon(
                  key: const Key('email-add'),
                  onPressed:
                      state.saving ||
                          state.capabilities?.credentialsAvailable != true
                      ? null
                      : _edit,
                  icon: const Icon(Icons.add),
                  label: const Text('Add email account'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.selectedId == null) ...[
            AppPagedList(
              key: const PageStorageKey('email-providers'),
              itemCount: state.providers.length,
              hasMore: state.providerCursor != null,
              loading: state.loading || state.saving,
              onLoadMore: () => widget.cubit.load(more: true),
              loadMoreLabel: 'Load more accounts',
              itemBuilder: (context, index) {
                final provider = state.providers[index];
                return AppRecordRow(
                  key: Key('email-provider-${provider.id}'),
                  leading: const Icon(Icons.mail_outline),
                  title: provider.label,
                  subtitle: Text(
                    '${provider.host}:${provider.port} · ${provider.enabled ? 'Enabled' : 'Disabled'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.cubit.select(provider.id),
                );
              },
            ),
            if (state.providers.isEmpty && !state.loading)
              const AppEmptyState(
                icon: Icons.mail_outline,
                title: 'No email accounts',
                message: 'Add an IMAP account to import messages and supported attachments.',
              ),
          ] else if (state.provider case final provider?) ...[
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${provider.host}:${provider.port} · ${provider.mailbox}',
                  ),
                  Text(
                    '${provider.enabled ? 'Enabled' : 'Disabled'} · Every ${provider.intervalMinutes} minutes · Last ${provider.maxAgeDays} days · ${provider.pageSize} messages per page',
                  ),
                  if (provider.consentState == 'renewal_required')
                    const AppNotice(
                      message: 'Import consent must be renewed. Edit this account to review and renew it.',
                    ),
                  if (provider.credentialState != 'ready')
                    const AppNotice(
                      message: 'Saved credentials are unavailable. Review this account with your administrator.',
                    ),
                  if (provider.nextDueAt case final due?)
                    Text('Next check: ${formatLocalDateTime(due)}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const Key('email-edit'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete
                            ? null
                            : () => _edit(provider),
                        child: const Text('Edit account'),
                      ),
                      FilledButton(
                        key: const Key('email-import'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete ||
                                !provider.canRun ||
                                !widget.cubit.canImport
                            ? null
                            : () => widget.cubit.importNow(),
                        child: const Text('Import now'),
                      ),
                      TextButton(
                        key: const Key('email-delete'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete
                            ? null
                            : _delete,
                        child: const Text('Delete account'),
                      ),
                      if (state.pendingRun)
                        OutlinedButton(
                          onPressed: state.saving
                              ? null
                              : () => widget.cubit.importNow(retry: true),
                          child: const Text('Check import request'),
                        ),
                      if (state.reconcileDelete)
                        OutlinedButton(
                          onPressed: state.saving
                              ? null
                              : widget.cubit.reconcileDelete,
                          child: const Text('Check deletion'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const AppSectionHeader(
              title: 'Import history',
              description: 'Accepted documents continue through document processing separately.',
            ),
            if (state.browsingHistory)
              const AppNotice(
                message: 'Older imports stay in place while active outcomes update. Refresh to see new imports.',
              ),
            AppPagedList(
              key: PageStorageKey('email-runs-${provider.id}'),
              itemCount: state.runs.length,
              hasMore: state.runCursor != null,
              loading: state.loading || state.saving,
              onLoadMore: () => widget.cubit.load(more: true),
              loadMoreLabel: 'Load older imports',
              itemBuilder: (context, index) {
                final run = state.runs[index];
                return AppRecordRow(
                  key: Key('email-run-${run.id}'),
                  leading: Icon(run.active ? Icons.sync : Icons.history),
                  title: '${run.status} · ${run.reason}',
                  subtitle: Text(
                    '${formatLocalDateTime(run.createdAt)}\n${run.messagesAccepted} emails accepted · ${run.messagesReused} reused · ${run.attachmentsAccepted} attachments accepted\n${run.messagesFailed} emails failed · ${run.messagesWithContentFailures} with content failures · ${run.attachmentsFailed} attachments failed${run.hasMore ? '\nMore mail remains for a later run.' : ''}',
                  ),
                );
              },
            ),
            if (state.runs.isEmpty && !state.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No imports yet.'),
              ),
          ],
        ],
      ),
    ),
  );
}
