import 'package:flutter/material.dart';

import '../../../domain/document/models/document.dart';

final class ScanPropertiesForm extends StatefulWidget {
  const ScanPropertiesForm({
    super.key,
    required this.properties,
    required this.enabled,
    required this.errors,
    required this.onChanged,
    this.validationAttempt = 0,
  });
  final DocumentProperties properties;
  final bool enabled;
  final Map<String, String> errors;
  final ValueChanged<DocumentProperties> onChanged;
  final int validationAttempt;

  @override
  State<ScanPropertiesForm> createState() => _ScanPropertiesFormState();
}

final class _ScanPropertiesFormState extends State<ScanPropertiesForm> {
  static const _order = [
    'title',
    'description',
    'tags',
    'kind',
    'documentDate',
    'sender',
    'recipients',
    'cc',
    'bcc',
    'subject',
    'messageId',
  ];
  final _focus = {for (final key in _order) key: FocusNode()};
  final _anchors = {for (final key in _order) key: GlobalKey()};
  late final Map<String, TextEditingController> _fields = {
    for (final entry in widget.properties.values.entries)
      entry.key: TextEditingController(
        text: entry.value is List
            ? (entry.value as List).join('\n')
            : '${entry.value}',
      ),
  };

  @override
  void didUpdateWidget(ScanPropertiesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.validationAttempt != oldWidget.validationAttempt &&
        widget.errors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final field = _order.where(widget.errors.containsKey).firstOrNull;
        if (field == null) return;
        _focus[field]!.requestFocus();
        final target = _anchors[field]!.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .15,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text;
  List<String> _list(String key) =>
      _text(key).isEmpty ? const [] : _text(key).split('\n');

  void _changed([String? _]) => widget.onChanged(
    DocumentProperties(
      title: _text('title'),
      description: _text('description'),
      tags: _list('tags'),
      kind: _text('kind'),
      sender: _text('sender'),
      recipients: _list('recipients'),
      cc: _list('cc'),
      bcc: _list('bcc'),
      documentDate: _text('documentDate'),
      subject: _text('subject'),
      messageId: _text('messageId'),
    ),
  );

  Widget _field(String key, String label, {int lines = 1, String? helper}) =>
      Padding(
        key: _anchors[key],
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          key: Key('scan-$key'),
          controller: _fields[key],
          focusNode: _focus[key],
          readOnly: !widget.enabled,
          onChanged: _changed,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            errorText: widget.errors[key],
            errorMaxLines: 4,
            helperMaxLines: 3,
            alignLabelWithHint: lines > 1,
          ),
          textInputAction: lines == 1
              ? TextInputAction.next
              : TextInputAction.newline,
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field('title', 'Title'),
      _field('description', 'Description', lines: 3),
      _field('tags', 'Tags', lines: 2, helper: 'One tag per line.'),
      KeyedSubtree(
        key: _anchors['kind'],
        child: DropdownButtonFormField<String>(
          key: const Key('scan-kind'),
          focusNode: _focus['kind'],
          initialValue: ['document', 'letter', 'email'].contains(_text('kind'))
              ? _text('kind')
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Kind',
            errorText: widget.errors['kind'],
          ),
          items: const [
            DropdownMenuItem(value: 'document', child: Text('Document')),
            DropdownMenuItem(value: 'letter', child: Text('Letter')),
            DropdownMenuItem(value: 'email', child: Text('Email')),
          ],
          onChanged: !widget.enabled
              ? null
              : (value) {
                  _fields['kind']!.text = value!;
                  _changed();
                },
        ),
      ),
      const SizedBox(height: 16),
      _field(
        'documentDate',
        'Document date',
        helper: 'YYYY-MM-DD. Leave empty if unknown.',
      ),
      _field('sender', 'Sender'),
      _field(
        'recipients',
        'Recipients',
        lines: 2,
        helper: 'One recipient per line.',
      ),
      _field('cc', 'CC', lines: 2, helper: 'One recipient per line.'),
      _field('bcc', 'BCC', lines: 2, helper: 'One recipient per line.'),
      _field('subject', 'Subject'),
      _field('messageId', 'Message ID'),
    ],
  );
}
