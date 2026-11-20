import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/chat_settings_cubit.dart';

final class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.cubit});
  final ChatSettingsCubit cubit;
  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

final class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late final _model = TextEditingController(
    text: widget.cubit.state.draft.model,
  );
  late final _url = TextEditingController(
    text: widget.cubit.state.draft.baseUrl,
  );
  late final _secret = TextEditingController(
    text: widget.cubit.state.draft.apiKey,
  );
  ChatSettingsCubit get cubit => widget.cubit;
  late String? _notice = widget.cubit.state.notice;
  @override
  void dispose() {
    _model.dispose();
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<ChatSettingsCubit, ChatSettingsState>(
    bloc: cubit,
    listener: (_, state) {
      if (state.notice != null && state.notice != _notice) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(state.notice!)));
      }
      _notice = state.notice;
      for (final entry in [
        (_model, state.draft.model),
        (_url, state.draft.baseUrl),
        (_secret, state.draft.apiKey),
      ]) {
        if (entry.$1.text != entry.$2) {
          entry.$1.value = TextEditingValue(
            text: entry.$2,
            selection: TextSelection.collapsed(offset: entry.$2.length),
          );
        }
      }
    },
    builder: (context, state) {
      final draft = state.draft;
      final editable = !state.saving;
      return AppPage(
        glacier: true,
        insetBody: false,

        title: 'AI chat',
        description: 'Choose the model people use to ask questions about their documents.',
        onRefresh: state.loading || state.saving ? null : cubit.load,
        child: ListView(
          key: const Key('chatSettingsScroll'),
          padding: GlacierSettingsPage.scrollPadding(context),
          children: [
            AppProgressSlot(active: state.loading || state.saving),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppNotice(
                  message: state.error!,
                  action: state.requiresRefresh
                      ? GlacierButton(
                          onPressed: state.loading ? null : cubit.load,
                          label: 'Refresh saved settings',
                          kind: GlacierButtonKind.quiet,
                        )
                      : null,
                ),
              ),
            if (state.saved != null)
              AppSurface(
                glacier: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.forum_outlined, size: 28),
                        Text(
                          'Chat model connection',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Visibility(
                          visible: state.dirty,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: const AppStatusBadge(
                            label: 'Unsaved changes',
                            tone: AppTone.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'These settings are independent of the document AI pipeline. Changes apply to new chat messages.',
                    ),
                    const SizedBox(height: 16),
                    GlacierSwitchRow(
                      key: const Key('chatEnabled'),
                      label: 'Enable AI chat',
                      description: 'Existing conversations remain available when new messages are paused.',
                      value: draft.enabled,
                      onChanged: editable
                          ? (value) => cubit.edit(enabled: value)
                          : null,
                    ),
                    GlacierSwitchRow(
                      key: const Key('chatThinkingEnabled'),
                      label: 'Enable thinking for chat',
                      description: 'Let supported models reason before answering. This can take longer.',
                      value: draft.thinkingEnabled,
                      onChanged: editable
                          ? (value) => cubit.edit(thinkingEnabled: value)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    GlacierModelConnection(
                      modelField: TextField(
                        key: const Key('chatModel'),
                        controller: _model,
                        enabled: editable,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          hintText: 'Your service model name',
                        ),
                        onChanged: (value) => cubit.edit(model: value),
                      ),
                      endpointField: TextField(
                        key: const Key('chatBaseUrl'),
                        controller: _url,
                        enabled: editable,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'API base URL',
                          hintText: 'https://example.com/v1',
                          helperText: 'Include the API prefix, such as /v1.',
                          helperMaxLines: 3,
                        ),
                        onChanged: (value) => cubit.edit(baseUrl: value),
                      ),
                      credentialField: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('chatApiKey'),
                            controller: _secret,
                            enabled: editable && !draft.clearApiKey,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: state.saved!.hasApiKey
                                  ? 'Replacement API key'
                                  : 'API key (optional)',
                              helperText: 'Stored encrypted on the server. Leave blank to keep the stored key for this address.',
                              helperMaxLines: 3,
                            ),
                            onChanged: (value) => cubit.edit(apiKey: value),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IndexedStack(
                                index: state.saved!.hasApiKey ? 1 : 0,
                                children: const [
                                  AppStatusBadge(label: 'No API key stored'),
                                  AppStatusBadge(label: 'API key stored'),
                                ],
                              ),
                              GlacierButton(
                                key: const Key('clearChatApiKey'),
                                onPressed: editable && state.saved!.hasApiKey
                                    ? () => cubit.edit(
                                        clearApiKey: !draft.clearApiKey,
                                      )
                                    : null,
                                icon: draft.clearApiKey
                                    ? Icons.undo
                                    : Icons.delete_outline,
                                label: 'Remove stored key',
                                alternateLabel: 'Keep stored key',
                                showAlternateLabel: draft.clearApiKey,
                                kind: GlacierButtonKind.quiet,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Removing a key or changing the service address clears the stored key when you save.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (draft.error != null && state.dirty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: AppNotice(message: draft.error!),
                      ),
                    const SizedBox(height: 24),
                    GlacierWorkspaceGeometry.measureEndActions(
                      context,
                      followingExtent: 24,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          GlacierButton(
                            key: const Key('saveChatSettings'),
                            onPressed: state.canSave ? cubit.save : null,
                            label: 'Save settings',
                            icon: Icons.save_outlined,
                            kind: GlacierButtonKind.primary,
                          ),
                          GlacierButton(
                            key: const Key('resetChatSettings'),
                            onPressed: editable && state.dirty
                                ? cubit.reset
                                : null,
                            label: 'Use saved settings',
                            kind: GlacierButtonKind.quiet,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            const AppNotice(
              tone: AppTone.info,
              title: 'Shared resource limits',
              message: 'Chat shares worker capacity and its selected AI provider with other background jobs. Replies wait for available resources before starting. New imports do not interrupt running replies. Manage shared capacity in Workload limits.',
            ),
          ],
        ),
      );
    },
  );
}
