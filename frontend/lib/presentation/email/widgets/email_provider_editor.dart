import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/email/interfaces/email_repository.dart';
import '../../../domain/email/models/email.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/email_provider_editor_cubit.dart';

final class EmailProviderEditor extends StatefulWidget {
  const EmailProviderEditor({
    super.key,
    required this.repository,
    required this.capabilities,
    required this.canImport,
    required this.onClose,
    this.provider,
  });
  final EmailRepository repository;
  final EmailCapabilities capabilities;
  final EmailProvider? provider;
  final bool canImport;
  final void Function(EmailProvider?) onClose;
  @override
  State<EmailProviderEditor> createState() => _EmailProviderEditorState();
}

final class _EmailProviderEditorState extends State<EmailProviderEditor> {
  late final EmailProviderEditorCubit _cubit = EmailProviderEditorCubit(
    widget.repository,
    capabilities: widget.capabilities,
    canImport: widget.canImport,
    provider: widget.provider,
  );
  final _feedbackKey = GlobalKey();
  late final Map<String, TextEditingController> _fields = {
    'label': TextEditingController(text: _cubit.state.draft.label),
    'endpoint': TextEditingController(text: _cubit.state.draft.endpoint),
    'port': TextEditingController(text: '${_cubit.state.draft.port}'),
    'username': TextEditingController(text: _cubit.state.draft.username),
    'password': TextEditingController(),
    'mailbox': TextEditingController(text: _cubit.state.draft.mailbox),
    'interval': TextEditingController(
      text: '${_cubit.state.draft.intervalMinutes}',
    ),
    'age': TextEditingController(text: '${_cubit.state.draft.maxAgeDays}'),
    'page': TextEditingController(text: '${_cubit.state.draft.pageSize}'),
  };
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    unawaited(_cubit.close());
    super.dispose();
  }

  void _changed() => _cubit.edit(
    _cubit.state.draft.copyWith(
      label: _fields['label']!.text,
      endpoint: _fields['endpoint']!.text,
      port: int.tryParse(_fields['port']!.text) ?? 0,
      username: _fields['username']!.text,
      password: _fields['password']!.text,
      mailbox: _fields['mailbox']!.text,
      intervalMinutes: int.tryParse(_fields['interval']!.text) ?? 0,
      maxAgeDays: int.tryParse(_fields['age']!.text) ?? 0,
      pageSize: int.tryParse(_fields['page']!.text) ?? 0,
    ),
  );
  Widget _field(
    String name,
    String label,
    EmailProviderEditorState state, {
    String? helper,
    bool number = false,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: Key('email-$name'),
      controller: _fields[name],
      enabled: !state.busy && !state.uncertain,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      keyboardType: number
          ? TextInputType.number
          : secret
          ? TextInputType.visiblePassword
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 5,
      ),
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<EmailProviderEditorCubit, EmailProviderEditorState>(
    bloc: _cubit,
    listener: (context, state) {
      if (state.draft.password.isEmpty &&
          _fields['password']!.text.isNotEmpty) {
        _fields['password']!.clear();
      }
      if (state.saved) {
        widget.onClose(state.provider);
      } else if (state.testResult != null ||
          state.error != null ||
          state.notice != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final feedback = _feedbackKey.currentContext;
          if (feedback != null) {
            unawaited(
              Scrollable.ensureVisible(
                feedback,
                alignment: 1,
                duration: const Duration(milliseconds: 200),
              ),
            );
          }
        });
      }
    },
    builder: (context, state) => PopScope(
      canPop: !state.busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.provider == null
                      ? 'Add email account'
                      : 'Edit email account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect using IMAP with implicit TLS. Imported email and supported attachments are kept in this library.',
                ),
                const SizedBox(height: 20),
                _field('label', 'Account label', state),
                _field('endpoint', 'IMAP host or imaps:// URL', state),
                _field('port', 'Port', state, number: true),
                _field('username', 'Username', state),
                _field(
                  'password',
                  'Password or app password',
                  state,
                  secret: true,
                  helper: widget.provider == null
                      ? null
                      : 'Leave empty to keep the saved password.',
                ),
                _field('mailbox', 'Mailbox', state),
                _field(
                  'interval',
                  'Check every (minutes)',
                  state,
                  number: true,
                  helper:
                      '${widget.capabilities.minIntervalMinutes}–${widget.capabilities.maxIntervalMinutes} minutes',
                ),
                _field(
                  'age',
                  'Maximum email age (days)',
                  state,
                  number: true,
                  helper: 'Increasing this value also looks for older mail.',
                ),
                _field(
                  'page',
                  'Messages per page',
                  state,
                  number: true,
                  helper:
                      '${widget.capabilities.minPageSize}–${widget.capabilities.maxPageSize} messages',
                ),
                SwitchListTile.adaptive(
                  key: const Key('email-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable automatic import'),
                  value: state.draft.enabled,
                  subtitle: Text(
                    widget.canImport
                        ? 'Continues after sign-out. Disable or delete the account to stop future imports.'
                        : 'Document read and upload permissions are required.',
                  ),
                  onChanged: !state.busy && !state.uncertain && widget.canImport
                      ? (value) =>
                            _cubit.edit(state.draft.copyWith(enabled: value))
                      : null,
                ),
                if (!widget.capabilities.credentialsAvailable)
                  const AppNotice(
                    message: 'Email credentials are not configured on this server. Ask your administrator.',
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('email-editor-close'),
                      onPressed: state.busy ? null : () => widget.onClose(null),
                      child: const Text('Close'),
                    ),
                    if (state.uncertain)
                      OutlinedButton(
                        key: const Key('email-reconcile'),
                        onPressed: state.busy ? null : _cubit.reconcile,
                        child: const Text('Check saved account'),
                      ),
                    if (state.secretUncertain && !state.uncertain)
                      OutlinedButton(
                        onPressed: state.busy || state.testing
                            ? null
                            : () =>
                                  _cubit.testConnection(savedCredentials: true),
                        child: const Text('Test saved credentials'),
                      ),
                    OutlinedButton(
                      key: const Key('email-test'),
                      onPressed:
                          state.busy ||
                              state.testing ||
                              state.uncertain ||
                              !widget.capabilities.credentialsAvailable
                          ? null
                          : () => _cubit.testConnection(),
                      child: const Text('Test connection'),
                    ),
                    if (state.provider?.consentState == 'renewal_required' &&
                        state.draft.enabled)
                      FilledButton(
                        key: const Key('email-renew-consent'),
                        onPressed:
                            state.busy ||
                                state.uncertain ||
                                state.secretUncertain ||
                                !widget.canImport ||
                                !widget.capabilities.credentialsAvailable
                            ? null
                            : () => _cubit.save(renewConsent: true),
                        child: const Text('Renew consent and save'),
                      ),
                    FilledButton(
                      key: const Key('email-save'),
                      onPressed:
                          state.busy ||
                              state.uncertain ||
                              state.secretUncertain ||
                              !widget.capabilities.credentialsAvailable
                          ? null
                          : _cubit.save,
                      child: const Text('Save account'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  key: _feedbackKey,
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.busy || state.testing)
                        const AppStripedProgressIndicator(),
                      if (state.error case final error?)
                        AppNotice(message: error),
                      if (state.notice case final notice?)
                        AppNotice(message: notice, tone: AppTone.neutral),
                      if (state.testResult case final result?)
                        AppNotice(
                          key: const Key('email-test-result'),
                          message: result.success ? 'Connection successful.' : 'Connection failed. Check the server and credentials.',
                          tone: result.success
                              ? AppTone.success
                              : AppTone.danger,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
