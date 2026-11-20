import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/document_cubit.dart';

final class DocumentOcrPanel extends StatefulWidget {
  const DocumentOcrPanel({
    super.key,
    required this.cubit,
    required this.onCancel,
  });
  final DocumentCubit cubit;
  final VoidCallback onCancel;
  @override
  State<DocumentOcrPanel> createState() => _DocumentOcrPanelState();
}

final class _DocumentOcrPanelState extends State<DocumentOcrPanel> {
  final _text = TextEditingController();
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _editor = GlobalKey();
  List<TextRange> _matches = const [];
  int _match = 0;
  bool _wasEditing = false;
  int? _revision;

  @override
  void initState() {
    super.initState();
    _sync(widget.cubit.state);
  }

  @override
  void dispose() {
    _text.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync(DocumentState state) {
    final content = state.editingOcr
        ? state.ocrDraft ?? ''
        : state.ocr?.text ?? '';
    if (_wasEditing != state.editingOcr ||
        (!state.editingOcr && _revision != state.ocr?.revision)) {
      _text.text = content;
      _wasEditing = state.editingOcr;
      _revision = state.ocr?.revision;
      _find();
    }
  }

  void _find() {
    final query = _query.text;
    _matches = query.isEmpty
        ? const []
        : RegExp(RegExp.escape(query), caseSensitive: false)
              .allMatches(_text.text)
              .map((match) => TextRange(start: match.start, end: match.end))
              .toList(growable: false);
    _match = 0;
  }

  void _showMatch(int direction) {
    if (_matches.isEmpty) return;
    setState(() => _match = (_match + direction) % _matches.length);
    final range = _matches[_match];
    _text.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void reveal(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          (element.state as EditableTextState).bringIntoView(
            TextPosition(offset: range.start),
          );
        } else {
          element.visitChildElements(reveal);
        }
      }

      _editor.currentContext?.visitChildElements(reveal);
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<DocumentCubit, DocumentState>(
    bloc: widget.cubit,
    listener: (context, state) => _sync(state),
    builder: (context, state) {
      if (state.remotelyDeleted) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'This document was deleted. Copy any unsaved text before leaving.',
            ),
            if (state.ocrDraft case final draft?) SelectableText(draft),
          ],
        );
      }
      final ocr = state.ocr;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: AppRefreshable(
          onRefresh: state.ocrLoading || state.saving
              ? null
              : widget.cubit.loadOcr,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.ocrLoading) const AppStripedProgressIndicator(),
                    if (state.ocrError case final error?) ...[
                      Text(error),
                      GlacierButton(
                        label: 'Retry extracted text',
                        kind: GlacierButtonKind.quiet,
                        onPressed: state.ocrLoading
                            ? null
                            : widget.cubit.loadOcr,
                      ),
                    ],
                    if (ocr == null &&
                        !state.ocrLoading &&
                        state.ocrError == null)
                      const Text('Extracted text is unavailable.'),
                    if (ocr != null) ...[
                      Text(
                        ocr.available
                            ? '${ocr.origin == 'manual' ? 'Corrected' : 'Machine'} text · revision ${ocr.revision}'
                            : switch (ocr.reason) {
                                'no_original' =>
                                  'This document has no original file.',
                                'processing' =>
                                  'Text extraction is in progress.',
                                'processing_failed' => 'Text extraction failed. Retry processing or enter a correction.',
                                'legacy_text_missing' => 'Text is missing for this older document. Retry processing to recover it.',
                                _ => 'Extracted text is unavailable.',
                              },
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (ocr.available)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(switch (ocr.semanticIndexing) {
                            'pending' => 'Search indexing in progress. Saved text is available now.',
                            'failed' => 'Search indexing failed. Save the text again to retry indexing.',
                            'not_required' => 'No searchable text to index.',
                            'ready' => 'Search index up to date.',
                            _ => 'Search indexing unavailable.',
                          }, style: Theme.of(context).textTheme.bodySmall),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (state.editingOcr) ...[
                            GlacierButton(
                              kind: GlacierButtonKind.primary,
                              onPressed:
                                  state.saving ||
                                      state.conflict ||
                                      state.reconcileRequired
                                  ? null
                                  : widget.cubit.saveOcr,
                              label: state.saving
                                  ? 'Saving…'
                                  : 'Save extracted text',
                            ),
                            GlacierButton(
                              label: 'Cancel',
                              kind: GlacierButtonKind.quiet,
                              onPressed: state.saving ? null : widget.onCancel,
                            ),
                          ] else if (widget.cubit.capabilities.updateOcr &&
                              state.document?.file != null)
                            GlacierButton(
                              onPressed: state.saving
                                  ? null
                                  : widget.cubit.editOcr,
                              icon: Icons.edit_outlined,
                              label: 'Edit extracted text',
                            ),
                          if (state.conflict || state.reconcileRequired)
                            GlacierButton(
                              label: 'Reload latest',
                              kind: GlacierButtonKind.quiet,
                              onPressed: state.ocrLoading || state.saving
                                  ? null
                                  : widget.cubit.loadOcr,
                            ),
                          if (widget.cubit.capabilities.retry &&
                              (ocr.reason == 'legacy_text_missing' ||
                                  ocr.reason == 'processing_failed'))
                            GlacierButton(
                              label: 'Retry processing',
                              kind: GlacierButtonKind.quiet,
                              onPressed: state.saving
                                  ? null
                                  : widget.cubit.retryProcessing,
                            ),
                        ],
                      ),
                      if (ocr.available || state.editingOcr) ...[
                        const SizedBox(height: 12),
                        GlacierFindBar(
                          fieldKey: const Key('ocrSearch'),
                          controller: _query,
                          autofocus: false,
                          hint: 'Find in extracted text',
                          previousLabel: 'Previous text match',
                          nextLabel: 'Next text match',
                          resultLabel: _query.text.isEmpty
                              ? 'Text search has no page highlights.'
                              : _matches.isEmpty
                              ? 'No matches'
                              : '${_match + 1} of ${_matches.length} matches',
                          onChanged: (_) {
                            setState(_find);
                            _showMatch(0);
                          },
                          onPrevious: _matches.isEmpty
                              ? null
                              : () => _showMatch(-1),
                          onNext: _matches.isEmpty ? null : () => _showMatch(1),
                        ),
                        if (_text.text.isEmpty && !state.editingOcr)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('The saved extracted text is empty.'),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              if (ocr != null && (ocr.available || state.editingOcr))
                _textSliver(state),
            ],
          ),
        ),
      );
    },
  );

  Widget _textSliver(DocumentState state) {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !state.editingOcr &&
        _query.text.isEmpty) {
      return SliverToBoxAdapter(
        child: RepaintBoundary(
          child: _textSurface(
            SelectionArea(
              child: Text(
                _text.text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remaining =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        return SliverToBoxAdapter(
          child: SizedBox(
            height: remaining < 240 ? 240 : remaining,
            child: _textSurface(_editorContent(state)),
          ),
        );
      },
    );
  }

  Widget _textSurface(Widget content) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(padding: const EdgeInsets.all(12), child: content),
  );

  Widget _editorContent(DocumentState state) => TextField(
    key: _editor,
    controller: _text,
    focusNode: _focus,
    readOnly: !state.editingOcr || state.saving,
    maxLines: null,
    minLines: null,
    expands: true,
    textAlignVertical: TextAlignVertical.top,
    keyboardType: TextInputType.multiline,
    decoration: const InputDecoration(
      labelText: 'Extracted text',
      alignLabelWithHint: true,
      border: InputBorder.none,
    ),
    style: Theme.of(context).textTheme.bodyMedium!,
    cursorColor: Theme.of(context).colorScheme.primary,
    onChanged: (value) {
      widget.cubit.setOcrDraft(value);
      setState(_find);
    },
  );
}
