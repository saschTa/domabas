import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/document/models/document.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/document_cubit.dart';
import 'processing_widgets.dart';

final class DocumentPropertiesPanel extends StatelessWidget {
  const DocumentPropertiesPanel({
    super.key,
    required this.cubit,
    required this.onCancel,
    this.emailLinks,
  });
  final DocumentCubit cubit;
  final VoidCallback onCancel;
  final Widget? emailLinks;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentCubit, DocumentState>(
    bloc: cubit,
    builder: (context, state) {
      if (state.remotelyDeleted) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'This document was deleted. Copy any unsaved properties before leaving.',
            ),
            if (state.metadataDraft case final draft?)
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(draft.values),
              ),
          ],
        );
      }
      final document = state.document;
      if (document == null) return const SizedBox.shrink();
      if (state.editingMetadata) {
        return _DocumentPropertiesForm(
          key: ValueKey(document.id),
          cubit: cubit,
          onCancel: onCancel,
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ?emailLinks,
          if (cubit.capabilities.update)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: state.saving ? null : cubit.editMetadata,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit properties'),
              ),
            ),
          for (final entry in DocumentProperties.fromDocument(
            document,
          ).values.entries)
            _DocumentProperty(
              label: switch (entry.key) {
                'documentDate' => 'Document date',
                'messageId' => 'Message ID',
                'cc' => 'CC',
                'bcc' => 'BCC',
                _ => '${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
              },
              value: entry.value is List
                  ? (entry.value as List).join(', ')
                  : '${entry.value}',
            ),
          _DocumentProperty(
            label: 'Created',
            value: document.createdAt.toLocal().toString(),
          ),
          if (document.file case final file?) ...[
            const AppStripedDivider(height: 32, thickness: 8),
            Text(
              'Original file',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _DocumentProperty(label: 'Filename', value: file.originalFilename),
            _DocumentProperty(label: 'Media type', value: file.mediaType),
            _DocumentProperty(label: 'Size', value: '${file.size} bytes'),
            _DocumentProperty(label: 'SHA-256', value: file.sha256),
            _DocumentProperty(label: 'Uploader', value: file.uploaderId),
            _DocumentProperty(
              label: 'Ingested',
              value: file.ingestedAt.toLocal().toString(),
            ),
          ],
          if (document.processing case final processing?) ...[
            const AppStripedDivider(height: 32, thickness: 8),
            Text(
              'Document ingestion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _DocumentProperty(
              label: 'Ingestion',
              value: processing.state == 'ready'
                  ? 'Searchable'
                  : '${processingLabel(processing.state)} / ${processingLabel(processing.stage)}',
            ),
            if (processing.failureCode != null)
              _DocumentProperty(
                label: 'Failure',
                value: processingFailure(processing.failureCode),
              ),
            _DocumentProperty(
              label: 'Generation / configuration',
              value:
                  '${processing.generation} / ${processing.configurationRevision}',
            ),
            _DocumentProperty(
              label: 'Updated',
              value: processing.updatedAt.toLocal().toString(),
            ),
            _DocumentProperty(
              label: 'Extraction',
              value: processing.extractionMethod == 'mime'
                  ? 'MIME body text · domabas-mime 1'
                  : processing.extractionMethod == null
                  ? 'Method not recorded'
                  : '${processing.ocrEngine} ${processing.ocrVersion}',
            ),
            if (processing.extractionMethod == 'ocr')
              _DocumentProperty(label: 'OCR model', value: processing.ocrModel),
            if (processing.extractionMethod == 'ocr')
              _DocumentProperty(
                label: 'Language / segmentation',
                value:
                    '${processing.ocrLanguage} / ${processing.ocrSegmentation}',
              ),
            _DocumentProperty(
              label: 'Embedding model',
              value: processing.embeddingModel,
            ),
            _DocumentProperty(
              label: 'Embedding digest',
              value: processing.embeddingDigest,
            ),
            _DocumentProperty(
              label: 'Embedding dimensions',
              value: '${processing.embeddingDimensions}',
            ),
            const AppStripedDivider(height: 32, thickness: 8),
            Text(
              'AI processing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (processing.ai case final ai?) ...[
              _DocumentProperty(
                label: 'AI status / stage',
                value:
                    '${processingLabel(ai.status)} / ${processingLabel(ai.stage)}',
              ),
              _DocumentProperty(
                label: 'AI attempt / configuration',
                value: '${ai.attempt} / ${ai.configurationRevision}',
              ),
              if (ai.invoiceClassification case final classification?)
                _DocumentProperty(
                  label: 'Invoice decision',
                  value: invoiceClassificationLabel(classification),
                ),
              if (ai.failureCode != null)
                _DocumentProperty(
                  label: 'AI failure',
                  value: processingFailure(ai.failureCode),
                ),
              if (processing.state == 'ready') ...[
                const SizedBox(height: 12),
                const Text(
                  'The document remains searchable while optional processing runs or needs attention.',
                ),
              ],
              if (cubit.capabilities.retry &&
                  processing.state == 'ready' &&
                  (ai.canRetry || state.pendingAIRetry != null)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('retryDocumentAI'),
                  onPressed: state.saving ? null : cubit.retryAIProcessing,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    state.pendingAIRetry == null
                        ? 'Retry AI processing'
                        : 'Retry same AI request',
                  ),
                ),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No separate AI attempt recorded. Optional processing starts after ingestion when enabled or when embedded invoice XML is present.',
                ),
              ),
          ],
          if (cubit.capabilities.retry &&
              (document.processing?.state == 'failed' ||
                  state.ocr?.reason == 'legacy_text_missing'))
            OutlinedButton.icon(
              onPressed: state.saving ? null : cubit.retryProcessing,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry processing'),
            ),
        ],
      );
    },
  );
}

final class _DocumentProperty extends StatelessWidget {
  const _DocumentProperty({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(value.isEmpty ? '—' : value),
      ],
    ),
  );
}

final class _DocumentPropertiesForm extends StatefulWidget {
  const _DocumentPropertiesForm({
    super.key,
    required this.cubit,
    required this.onCancel,
  });
  final DocumentCubit cubit;
  final VoidCallback onCancel;
  @override
  State<_DocumentPropertiesForm> createState() =>
      _DocumentPropertiesFormState();
}

final class _DocumentPropertiesFormState
    extends State<_DocumentPropertiesForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields = {
    for (final entry in widget.cubit.state.metadataDraft!.values.entries)
      entry.key: TextEditingController(
        text: entry.value is List
            ? (entry.value as List).join('\n')
            : '${entry.value}',
      ),
  };
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text;
  void _changed([String? _]) {
    widget.cubit.setMetadataDraft(
      DocumentProperties(
        title: _text('title'),
        description: _text('description'),
        tags: DocumentProperties.splitList(_text('tags')),
        kind: _text('kind'),
        sender: _text('sender'),
        recipients: DocumentProperties.splitList(_text('recipients')),
        cc: DocumentProperties.splitList(_text('cc')),
        bcc: DocumentProperties.splitList(_text('bcc')),
        documentDate: _text('documentDate'),
        subject: _text('subject'),
        messageId: _text('messageId'),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    int maxLength = 320,
    int lines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: Key('edit-$key'),
      controller: _fields[key],
      enabled: !widget.cubit.state.saving,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
      ),
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 3,
      onChanged: _changed,
      validator:
          validator ??
          (value) => (value ?? '').runes.length > maxLength
              ? 'Use $maxLength characters or fewer.'
              : null,
    ),
  );
  Widget _list(String key, String label, {bool tags = false}) {
    final items = DocumentProperties.splitList(_text(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          key,
          '$label (one per line)',
          lines: 2,
          validator: (value) =>
              DocumentProperties.validateList(value, tags: tags),
        ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var index = 0; index < items.length; index++)
                  InputChip(
                    label: Text(items[index]),
                    onDeleted: widget.cubit.state.saving
                        ? null
                        : () {
                            final next = [...items]..removeAt(index);
                            _fields[key]!.text = next.join('\n');
                            _changed();
                          },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _field('title', 'Title', validator: DocumentDraft.validateTitle),
        _field(
          'description',
          'Description',
          lines: 3,
          validator: DocumentDraft.validateDescription,
        ),
        _list('tags', 'Tags', tags: true),
        DropdownButtonFormField<String>(
          initialValue: _text('kind'),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: const [
            DropdownMenuItem(value: 'document', child: Text('Document')),
            DropdownMenuItem(value: 'letter', child: Text('Letter')),
            DropdownMenuItem(value: 'email', child: Text('Email')),
          ],
          onChanged: widget.cubit.state.saving
              ? null
              : (value) {
                  _fields['kind']!.text = value!;
                  _changed();
                },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                'documentDate',
                'Date (YYYY-MM-DD)',
                validator: DocumentProperties.validateDate,
              ),
            ),
            IconButton(
              tooltip: 'Choose document date',
              onPressed: widget.cubit.state.saving
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1),
                        lastDate: DateTime(9999),
                        initialDate:
                            DateTime.tryParse(_text('documentDate')) ??
                            DateTime.now(),
                      );
                      if (date != null && mounted) {
                        _fields['documentDate']!.text = date
                            .toIso8601String()
                            .substring(0, 10);
                        _changed();
                      }
                    },
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ],
        ),
        ExpansionTile(
          title: const Text('Communication details'),
          tilePadding: EdgeInsets.zero,
          maintainState: true,
          children: [
            _field('sender', 'Sender'),
            _list('recipients', 'Recipients'),
            _list('cc', 'CC'),
            _list('bcc', 'BCC'),
            _field('subject', 'Subject', maxLength: 200),
            _field('messageId', 'Message ID', maxLength: 512),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed:
                  widget.cubit.state.saving ||
                      widget.cubit.state.reconcileRequired
                  ? null
                  : () {
                      if (_form.currentState!.validate()) {
                        _changed();
                        widget.cubit.saveMetadata();
                      }
                    },
              child: Text(
                widget.cubit.state.saving ? 'Saving…' : 'Save properties',
              ),
            ),
            TextButton(
              onPressed: widget.cubit.state.saving ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    ),
  );
}
