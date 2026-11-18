import 'package:flutter/material.dart';

import '../../../domain/document/models/document_processing.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/document_processing_settings_cubit.dart';

final class PropertyExtractionSettings extends StatefulWidget {
  const PropertyExtractionSettings({
    super.key,
    required this.cubit,
    required this.state,
  });
  final DocumentProcessingSettingsCubit cubit;
  final DocumentProcessingSettingsState state;

  @override
  State<PropertyExtractionSettings> createState() =>
      _DocumentPropertyExtractionSettingsState();
}

final class _DocumentPropertyExtractionSettingsState
    extends State<PropertyExtractionSettings> {
  late final _model = TextEditingController(text: widget.state.llm.model);
  late final _url = TextEditingController(text: widget.state.llm.baseUrl);
  late final _key = TextEditingController(text: widget.state.llm.apiKey);
  late final _contextLength = TextEditingController(
    text: widget.state.llm.contextLength,
  );

  @override
  void didUpdateWidget(PropertyExtractionSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in [
      (_model, widget.state.llm.model),
      (_url, widget.state.llm.baseUrl),
      (_key, widget.state.llm.apiKey),
      (_contextLength, widget.state.llm.contextLength),
    ]) {
      if (entry.$1.text != entry.$2) entry.$1.text = entry.$2;
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _url.dispose();
    _key.dispose();
    _contextLength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final draft = state.llm;
    final saved = state.configuration!.llm;
    final editable =
        widget.cubit.active && !state.saving && !state.reconcileRequired;
    final external = draft.provider == 'openai';
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            Text('AI extraction', style: theme.textTheme.titleLarge),
            Visibility(
              visible: draft.changed(saved),
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
          'Choose which AI steps run after documents are searchable. Both steps use the model connection below and apply to every library. Optional failures do not undo ingestion.',
        ),
        const SizedBox(height: 16),
        GlacierSwitchRow(
          key: const Key('invoiceLLMEnabled'),
          label: 'Enable AI invoice extraction',
          description: 'Recognize invoices and extract amounts from PDF and email text. Embedded e-invoice XML is always read without AI.',
          value: draft.invoiceEnabled,
          onChanged: editable
              ? (value) => widget.cubit.editLLM(invoiceEnabled: value)
              : null,
        ),
        GlacierSwitchRow(
          key: const Key('invoiceThinkingEnabled'),
          label: 'Enable thinking for invoices',
          description: 'Let supported models reason before extracting information. This can take longer.',
          value: draft.invoiceThinkingEnabled,
          onChanged: editable
              ? (value) => widget.cubit.editLLM(invoiceThinkingEnabled: value)
              : null,
        ),
        const AppStripedDivider(height: 24),
        GlacierSwitchRow(
          key: const Key('llmEnabled'),
          label: 'Enable AI property extraction',
          description: 'Fill missing descriptions, tags, sender and dates. Existing properties stay unchanged. Runs independently of invoice extraction.',
          value: draft.enabled,
          onChanged: editable
              ? (value) => widget.cubit.editLLM(enabled: value)
              : null,
        ),
        GlacierSwitchRow(
          key: const Key('propertyThinkingEnabled'),
          label: 'Enable thinking for properties',
          description: 'Let supported models reason before extracting information. This can take longer.',
          value: draft.propertyThinkingEnabled,
          onChanged: editable
              ? (value) => widget.cubit.editLLM(propertyThinkingEnabled: value)
              : null,
        ),
        const SizedBox(height: 20),
        Text('Shared model connection', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        GlacierModelConnection(
          provider: external ? 'external' : 'local',
          enabled: editable,
          providerField: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  GlacierChoice(
                    key: const Key('llmProviderOllama'),
                    label: 'Internal Ollama',
                    compact: true,
                    selected: !external,
                    onChanged: editable
                        ? (_) => widget.cubit.editLLM(provider: 'ollama')
                        : null,
                  ),
                  GlacierChoice(
                    key: const Key('llmProviderOpenAI'),
                    label: 'External service',
                    compact: true,
                    selected: external,
                    onChanged: editable
                        ? (_) => widget.cubit.editLLM(provider: 'openai')
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                external
                    ? 'Sends extracted document text to your OpenAI-compatible service.'
                    : 'Runs on this installation. The model is downloaded when first needed; the first run can take longer.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          modelField: Semantics(
            container: true,
            child: TextField(
              key: const Key('llmModel'),
              controller: _model,
              enabled: editable,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: external
                    ? 'Your service model name'
                    : const DocumentLLMSettingsDraft().model,
                errorText: draft.modelError,
                errorMaxLines: 3,
              ),
              onChanged: (value) => widget.cubit.editLLM(model: value),
            ),
          ),
          endpointField: Semantics(
            container: true,
            child: TextField(
              key: const Key('llmBaseUrl'),
              controller: _url,
              enabled: editable,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API base URL',
                hintText: 'https://example.com/v1',
                helperText: 'Include the API prefix, such as /v1.',
                helperMaxLines: 3,
                errorText: draft.baseUrl.isEmpty ? null : draft.baseUrlError,
                errorMaxLines: 4,
              ),
              onChanged: (value) => widget.cubit.editLLM(baseUrl: value),
            ),
          ),
          compatibilityControl: GlacierSwitchRow(
            key: const Key('llmLMStudioCompatibility'),
            label: 'LM Studio compatibility mode',
            description: 'Enable when using LM Studio for AI property and invoice extraction.',
            value: draft.lmStudioCompatibility,
            onChanged: editable
                ? (value) => widget.cubit.editLLM(lmStudioCompatibility: value)
                : null,
          ),
          credentialField: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Context length is managed by the external service. Your Ollama setting is retained.',
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                child: TextField(
                  key: const Key('llmApiKey'),
                  controller: _key,
                  enabled: editable && !draft.clearApiKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: saved.credentialConfigured
                        ? 'Replacement API key'
                        : 'API key (optional)',
                    helperText: 'Stored encrypted on the server. Leave blank to keep the stored key for this address.',
                    helperMaxLines: 3,
                    errorText: draft.apiKeyError,
                    errorMaxLines: 3,
                  ),
                  onChanged: (value) => widget.cubit.editLLM(apiKey: value),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  IndexedStack(
                    index: saved.credentialConfigured ? 1 : 0,
                    children: const [
                      AppStatusBadge(label: 'No API key stored'),
                      AppStatusBadge(label: 'API key stored'),
                    ],
                  ),
                  GlacierButton(
                    key: const Key('llmClearApiKey'),
                    onPressed: editable && saved.credentialConfigured
                        ? () => widget.cubit.editLLM(
                            clearApiKey: !draft.clearApiKey,
                          )
                        : null,
                    icon: draft.clearApiKey ? Icons.undo : Icons.delete_outline,
                    label: 'Remove stored key',
                    alternateLabel: 'Keep stored key',
                    showAlternateLabel: draft.clearApiKey,
                    kind: GlacierButtonKind.quiet,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Removing a key or changing the service address clears the stored key when you save.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          contextField: external
              ? const SizedBox.shrink()
              : AppModelContextField(
                  controller: _contextLength,
                  fieldKey: const Key('llmContextLength'),
                  checkKey: const Key('checkLLMModelContext'),
                  defaultKey: const Key('resetLLMContextLength'),
                  scope: 'Shared by AI property and invoice extraction. Independent of AI chat.',
                  enabled: editable,
                  loading: state.loadingModelContext,
                  errorText: draft.contextLengthError,
                  lookupError: state.modelContextError,
                  maxContextLength: state.modelContext?.maxContextLength,
                  requestedContextLength: draft.contextLengthValue,
                  onChanged: (value) =>
                      widget.cubit.editLLM(contextLength: value),
                  onCheck: draft.modelError != null
                      ? null
                      : widget.cubit.checkModelContext,
                  onDefault: () => widget.cubit.editLLM(contextLength: '32768'),
                ),
        ),
        const SizedBox(height: 20),
        GlacierWorkspaceGeometry.measureEndActions(
          context,
          followingExtent: 24,
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              GlacierButton(
                key: const Key('saveLLMSettings'),
                onPressed: widget.cubit.canSave
                    ? () => widget.cubit.save()
                    : null,
                label: 'Save settings',
                kind: GlacierButtonKind.primary,
              ),
              GlacierButton(
                key: const Key('resetLLMSettings'),
                onPressed: editable && state.dirty
                    ? widget.cubit.resetDraft
                    : null,
                label: 'Use saved settings',
                kind: GlacierButtonKind.quiet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'AI-only changes schedule AI processing across all libraries while documents stay searchable. OCR changes also rerun ingestion. Saved results are preserved when an AI step is disabled.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
