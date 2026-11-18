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
    route = createGlacierDialogRoute(
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
    route = createGlacierDialogRoute(
      context: context,
      builder: (_) => AppDialog(
        glacier: true,
        title: 'Delete email account?',
        description: 'Future imports stop. Emails and attachments already accepted remain in this library.',
        actions: [
          GlacierButton(
            onPressed: () {
              if (route.isActive) {
                navigator.removeRoute(route, false);
              }
            },
            label: 'Cancel',
            kind: GlacierButtonKind.quiet,
          ),
          GlacierButton(
            key: const Key('email-confirm-delete'),
            onPressed: () {
              if (route.isActive) {
                navigator.removeRoute(route, true);
              }
            },
            label: 'Delete account',
            kind: GlacierButtonKind.primary,
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
      glacier: true,
      insetBody: false,

      title: 'Email accounts',
      description:
          'Your private account connections import into the current library.',
      onRefresh: state.loading || state.saving
          ? null
          : () => widget.cubit.load(),
      child: ListView(
        padding: GlacierSettingsPage.scrollPadding(context),
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
                GlacierButton(
                  onPressed:
                      state.saving || state.pendingRun || state.reconcileDelete
                      ? null
                      : widget.cubit.back,
                  label: 'All email accounts',
                  icon: Icons.arrow_back,
                  kind: GlacierButtonKind.quiet,
                ),
              if (state.selectedId == null)
                GlacierButton(
                  key: const Key('email-add'),
                  onPressed:
                      state.saving ||
                          state.capabilities?.credentialsAvailable != true
                      ? null
                      : _edit,
                  label: 'Add email account',
                  icon: Icons.add,
                  kind: GlacierButtonKind.primary,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.selectedId == null) ...[
            AppPagedList(
              glacier: true,
              key: const PageStorageKey('email-providers'),
              itemCount: state.providers.length,
              hasMore: state.providerCursor != null,
              loading: state.loading || state.saving,
              onLoadMore: () => widget.cubit.load(more: true),
              loadMoreLabel: 'Load more accounts',
              itemBuilder: (context, index) {
                final provider = state.providers[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlacierSettingsRecord(
                    card: true,
                    key: Key('email-provider-${provider.id}'),
                    title: provider.label,
                    detail:
                        '${provider.host}:${provider.port} · ${provider.enabled ? 'Enabled' : 'Disabled'}',
                    icon: Icons.mail_outline,
                    onTap: () => widget.cubit.select(provider.id),
                    status: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
            if (state.providers.isEmpty && !state.loading)
              const GlacierSettingsSection(
                child: AppEmptyState(
                  icon: Icons.mail_outline,
                  title: 'No email accounts',
                  message: 'Add an IMAP account to import messages and supported attachments.',
                ),
              ),
          ] else if (state.provider case final provider?) ...[
            AppSurface(
              glacier: true,
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
                      GlacierButton(
                        key: const Key('email-edit'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete
                            ? null
                            : () => _edit(provider),
                        label: 'Edit account',
                        kind: GlacierButtonKind.secondary,
                      ),
                      GlacierButton(
                        key: const Key('email-import'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete ||
                                !provider.canRun ||
                                !widget.cubit.canImport
                            ? null
                            : () => widget.cubit.importNow(),
                        label: 'Import now',
                        kind: GlacierButtonKind.primary,
                      ),
                      GlacierButton(
                        key: const Key('email-delete'),
                        onPressed:
                            state.saving ||
                                state.pendingRun ||
                                state.reconcileDelete
                            ? null
                            : _delete,
                        label: 'Delete account',
                        kind: GlacierButtonKind.quiet,
                      ),
                      if (state.pendingRun)
                        GlacierButton(
                          onPressed: state.saving
                              ? null
                              : () => widget.cubit.importNow(retry: true),
                          label: 'Check import request',
                          kind: GlacierButtonKind.secondary,
                        ),
                      if (state.reconcileDelete)
                        GlacierButton(
                          onPressed: state.saving
                              ? null
                              : widget.cubit.reconcileDelete,
                          label: 'Check deletion',
                          kind: GlacierButtonKind.secondary,
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
                message: 'Older imports stay in place while active outcomes update. Pull down to see new imports.',
              ),
            AppPagedList(
              glacier: true,
              key: PageStorageKey('email-runs-${provider.id}'),
              itemCount: state.runs.length,
              hasMore: state.runCursor != null,
              loading: state.loading || state.saving,
              onLoadMore: () => widget.cubit.load(more: true),
              loadMoreLabel: 'Load older imports',
              itemBuilder: (context, index) {
                final run = state.runs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlacierSettingsRecord(
                    card: true,
                    key: Key('email-run-${run.id}'),
                    title: '${run.status} · ${run.reason}',
                    detail:
                        '${formatLocalDateTime(run.createdAt)}\n${run.messagesAccepted} emails accepted · ${run.messagesReused} reused · ${run.attachmentsAccepted} attachments accepted\n${run.messagesFailed} emails failed · ${run.messagesWithContentFailures} with content failures · ${run.attachmentsFailed} attachments failed${run.hasMore ? '\nMore mail remains for a later run.' : ''}',
                    icon: run.active ? Icons.sync : Icons.history,
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
