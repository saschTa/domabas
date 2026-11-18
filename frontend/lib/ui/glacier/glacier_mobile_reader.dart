import 'package:flutter/material.dart';

import 'glacier_controls.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';

enum GlacierMobileReaderState {
  ready,
  text,
  find,
  image,
  email,
  locked,
  missing,
  error,
  deleted,
  readOnly,
}

enum GlacierMobileEditState { ready, conflict, uncertain, deleted, saving }

class GlacierMobileReaderToolbar extends StatelessWidget {
  const GlacierMobileReaderToolbar({
    super.key,
    this.onProperties,
    this.onResync,
    this.onDownload,
    this.onDelete,
    this.showResync = true,
    this.showDownload = true,
    this.showDelete = true,
    this.downloadKey,
    this.deleteKey,
    this.resyncLabel = 'Resync',
  });
  final VoidCallback? onProperties, onResync, onDownload, onDelete;
  final bool showResync, showDownload, showDelete;
  final Key? downloadKey, deleteKey;
  final String resyncLabel;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    glass: true,
    radius: 13,
    padding: const EdgeInsets.all(4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(11) >= 20;
        final width =
            (constraints.maxWidth - (large ? 4 : 12)) / (large ? 2 : 4);
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final action in <(String, IconData, VoidCallback?)>[
              ('Properties', Icons.edit_outlined, onProperties),
              if (showResync) (resyncLabel, Icons.refresh_rounded, onResync),
              if (showDownload)
                ('Download', Icons.download_outlined, onDownload),
              if (showDelete) ('Delete', Icons.delete_outline, onDelete),
            ])
              SizedBox(
                width: width,
                child: TextButton(
                  key: action.$1 == 'Download'
                      ? downloadKey
                      : action.$1 == 'Delete'
                      ? deleteKey
                      : null,
                  onPressed: action.$3,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.$2, size: 21),
                      const SizedBox(height: 4),
                      Text(
                        action.$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class GlacierMobileOriginalCanvas extends StatelessWidget {
  const GlacierMobileOriginalCanvas({
    super.key,
    required this.child,
    this.label = 'Original document page',
  });
  final Widget child;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Container(
      constraints: const BoxConstraints(minHeight: 470),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: GlacierTokens.of(context).preview,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ColoredBox(color: Colors.white, child: child),
        ),
      ),
    ),
  );
}

class GlacierMobileReaderFindBar extends StatelessWidget {
  const GlacierMobileReaderFindBar({
    super.key,
    required this.controller,
    this.matchLabel = '',
    this.onChanged,
    this.onPrevious,
    this.onNext,
  });
  final TextEditingController controller;
  final String matchLabel;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onPrevious, onNext;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    glass: true,
    radius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: 'Find in this file',
                  semanticCounterText: 'Find in file',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            if (MediaQuery.textScalerOf(context).scale(13) < 22)
              ..._actions(context),
          ],
        ),
        if (MediaQuery.textScalerOf(context).scale(13) >= 22)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _actions(context),
          ),
      ],
    ),
  );
  List<Widget> _actions(BuildContext context) => [
    Text(matchLabel, style: Theme.of(context).textTheme.bodySmall),
    GlacierIconButton(
      label: 'Previous match',
      icon: Icons.keyboard_arrow_up,
      onPressed: onPrevious,
    ),
    GlacierIconButton(
      label: 'Next match',
      icon: Icons.keyboard_arrow_down,
      onPressed: onNext,
    ),
  ];
}

class GlacierMobileReader extends StatelessWidget {
  const GlacierMobileReader({
    super.key,
    required this.original,
    required this.properties,
    this.state = GlacierMobileReaderState.ready,
    this.text = '',
    this.textController,
    this.passwordController,
    this.onTextChanged,
    this.onSaveText,
    this.onRevisions,
    this.onOriginal,
    this.onText,
    this.onFind,
    this.findBar,
    this.onProperties,
    this.onResync,
    this.onDownload,
    this.onDelete,
    this.onRetry,
    this.onUnlock,
    this.onCopy,
    this.onPreviousPage,
    this.onNextPage,
    this.onFit,
    this.onZoomIn,
    this.pageLabel = 'Page 1 of 3',
    this.processing,
    this.email,
  });
  final Widget original, properties;
  final GlacierMobileReaderState state;
  final String text, pageLabel;
  final TextEditingController? textController, passwordController;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onSaveText,
      onRevisions,
      onOriginal,
      onText,
      onFind,
      onProperties,
      onResync,
      onDownload,
      onDelete,
      onRetry,
      onUnlock,
      onCopy,
      onPreviousPage,
      onNextPage,
      onFit,
      onZoomIn;
  final Widget? findBar, processing, email;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileReaderToolbar(
        onProperties: state == GlacierMobileReaderState.readOnly
            ? null
            : onProperties,
        onResync: state == GlacierMobileReaderState.readOnly ? null : onResync,
        onDownload: onDownload,
        onDelete: state == GlacierMobileReaderState.readOnly ? null : onDelete,
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GlacierButton(
            label: 'Original',
            kind: state == GlacierMobileReaderState.text
                ? GlacierButtonKind.secondary
                : GlacierButtonKind.primary,
            onPressed: onOriginal,
          ),
          GlacierButton(
            label: 'Text',
            kind: state == GlacierMobileReaderState.text
                ? GlacierButtonKind.primary
                : GlacierButtonKind.secondary,
            onPressed: onText,
          ),
          GlacierIconButton(
            label: 'Find in document',
            icon: Icons.search,
            onPressed: onFind,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (state == GlacierMobileReaderState.find && findBar != null) ...[
        findBar!,
        const SizedBox(height: 12),
      ],
      if ([
        GlacierMobileReaderState.locked,
        GlacierMobileReaderState.missing,
        GlacierMobileReaderState.error,
        GlacierMobileReaderState.deleted,
      ].contains(state))
        _ReaderUnavailable(
          state: state,
          passwordController: passwordController,
          onRetry: onRetry,
          onUnlock: onUnlock,
          onCopy: onCopy,
        )
      else if (state == GlacierMobileReaderState.text) ...[
        GlacierMobileSurface(
          padding: const EdgeInsets.all(24),
          radius: 12,
          child: TextFormField(
            controller: textController,
            initialValue: textController == null ? text : null,
            onChanged: onTextChanged,
            maxLines: null,
            minLines: 12,
            decoration: const InputDecoration(
              semanticCounterText: 'Extracted document text',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GlacierButton(
              label: 'Save text',
              kind: GlacierButtonKind.primary,
              onPressed: onSaveText,
            ),
            GlacierButton(label: 'Revision history', onPressed: onRevisions),
          ],
        ),
      ] else if (state == GlacierMobileReaderState.email && email != null)
        email!
      else
        GlacierMobileOriginalCanvas(child: original),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          GlacierIconButton(
            label: 'Previous page',
            icon: Icons.chevron_left,
            onPressed: onPreviousPage,
          ),
          Text(pageLabel, style: Theme.of(context).textTheme.bodySmall),
          GlacierIconButton(
            label: 'Next page',
            icon: Icons.chevron_right,
            onPressed: onNextPage,
          ),
          GlacierButton(
            label: 'Fit width',
            kind: GlacierButtonKind.quiet,
            onPressed: onFit,
          ),
          GlacierIconButton(
            label: 'Zoom in',
            icon: Icons.add,
            onPressed: onZoomIn,
          ),
        ],
      ),
      const SizedBox(height: 12),
      properties,
      if (processing != null) ...[
        const SizedBox(height: 24),
        Text('Processing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        processing!,
      ],
    ],
  );
}

class _ReaderUnavailable extends StatelessWidget {
  const _ReaderUnavailable({
    required this.state,
    this.passwordController,
    this.onRetry,
    this.onUnlock,
    this.onCopy,
  });
  final GlacierMobileReaderState state;
  final TextEditingController? passwordController;
  final VoidCallback? onRetry, onUnlock, onCopy;
  @override
  Widget build(BuildContext context) {
    final locked = state == GlacierMobileReaderState.locked;
    final deleted = state == GlacierMobileReaderState.deleted;
    return GlacierMobileSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(
              locked ? Icons.lock_outline : Icons.error_outline,
              size: 36,
              color: GlacierTokens.of(context).accent,
            ),
            const SizedBox(height: 18),
            Text(
              locked
                  ? 'Password-protected original'
                  : deleted
                  ? 'Document deleted elsewhere'
                  : state == GlacierMobileReaderState.missing
                  ? 'Original unavailable'
                  : 'Original could not load',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              locked
                  ? 'Enter the PDF password to open this original.'
                  : deleted
                  ? 'Your unsaved text is retained. Copy it before leaving.'
                  : 'Metadata remains available. Try loading the original again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (locked)
              GlacierMobileField(
                label: 'PDF password',
                controller: passwordController,
                obscureText: true,
              ),
            GlacierButton(
              label: locked
                  ? 'Unlock original'
                  : deleted
                  ? 'Copy retained text'
                  : 'Try again',
              kind: GlacierButtonKind.primary,
              onPressed: locked
                  ? onUnlock
                  : deleted
                  ? onCopy
                  : onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class GlacierMobileDocumentProperties extends StatefulWidget {
  const GlacierMobileDocumentProperties({
    super.key,
    required this.values,
    this.state = GlacierMobileEditState.ready,
    this.tags = const [],
    this.onSave,
    this.onDraftChanged,
    this.onRecover,
    this.onCopyDraft,
    this.onAddTag,
    this.onRemoveTag,
    this.links,
    this.revisions,
  });
  final Map<String, String> values;
  final GlacierMobileEditState state;
  final List<String> tags;
  final ValueChanged<Map<String, String>>? onSave;
  final ValueChanged<Map<String, String>>? onDraftChanged;
  final VoidCallback? onRecover, onCopyDraft, onAddTag;
  final ValueChanged<String>? onRemoveTag;
  final Widget? links, revisions;
  @override
  State<GlacierMobileDocumentProperties> createState() =>
      _GlacierMobileDocumentPropertiesState();
}

class _GlacierMobileDocumentPropertiesState
    extends State<GlacierMobileDocumentProperties> {
  late final Map<String, TextEditingController> fields;
  bool expanded = false;
  void draftChanged(String _) => widget.onDraftChanged?.call(
    Map.unmodifiable(fields.map((key, value) => MapEntry(key, value.text))),
  );
  @override
  void initState() {
    super.initState();
    fields = {
      for (final name in [
        'Title',
        'Description',
        'Document type',
        'Document date',
        'Sender',
        'Recipients',
        'CC',
        'BCC',
        'Subject',
        'Message ID',
      ])
        name: TextEditingController(text: widget.values[name] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.state != GlacierMobileEditState.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state == GlacierMobileEditState.conflict ||
            widget.state == GlacierMobileEditState.uncertain)
          GlacierMobileNotice(
            title: widget.state == GlacierMobileEditState.conflict
                ? 'Changed elsewhere'
                : 'Save outcome unknown',
            message: widget.state == GlacierMobileEditState.conflict
                ? 'Your draft is retained. Reload the saved value before applying changes.'
                : 'Check the saved value before trying again. Your draft remains here.',
            action: GlacierButton(
              label: widget.state == GlacierMobileEditState.conflict
                  ? 'Reload saved value'
                  : 'Check saved value',
              onPressed: widget.onRecover,
            ),
          ),
        if (widget.state == GlacierMobileEditState.deleted)
          GlacierMobileNotice(
            title: 'Document deleted elsewhere',
            message: 'Keep a copy of your draft before leaving.',
            action: GlacierButton(
              label: 'Copy draft',
              onPressed: widget.onCopyDraft,
            ),
          ),
        if (widget.state == GlacierMobileEditState.saving)
          const GlacierMobileNotice(
            title: 'Saving…',
            message: 'Keep this screen open until the response arrives.',
          ),
        GlacierMobileField(
          label: 'Title',
          controller: fields['Title'],
          onChanged: draftChanged,
          enabled: !blocked,
        ),
        GlacierMobileField(
          label: 'Description',
          controller: fields['Description'],
          onChanged: draftChanged,
          maxLines: 3,
          enabled: !blocked,
        ),
        const SizedBox(height: 8),
        Text('Tags', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in widget.tags)
              OutlinedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: Text(tag),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  foregroundColor: GlacierTokens.of(context).accent,
                  disabledForegroundColor: GlacierTokens.of(context).muted,
                  side: BorderSide(color: GlacierTokens.of(context).accent),
                ),
                onPressed: blocked || widget.onRemoveTag == null
                    ? null
                    : () => widget.onRemoveTag!(tag),
              ),
            GlacierButton(
              label: 'Add tag',
              onPressed: blocked ? null : widget.onAddTag,
            ),
          ],
        ),
        const SizedBox(height: 24),
        for (final label in [
          'Document type',
          'Document date',
          'Sender',
          'Recipients',
        ])
          GlacierMobileField(
            label: label,
            controller: fields[label],
            onChanged: draftChanged,
            enabled: !blocked,
          ),
        TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                size: 22,
              ),
              const Flexible(child: Text('Email properties')),
            ],
          ),
        ),
        if (expanded)
          for (final label in ['CC', 'BCC', 'Subject', 'Message ID'])
            GlacierMobileField(
              label: label,
              controller: fields[label],
              onChanged: draftChanged,
              enabled: !blocked,
            ),
        const SizedBox(height: 16),
        GlacierButton(
          label: 'Save properties',
          kind: GlacierButtonKind.primary,
          onPressed: blocked || widget.onSave == null
              ? null
              : () => widget.onSave!(
                  Map.unmodifiable(
                    fields.map((key, value) => MapEntry(key, value.text)),
                  ),
                ),
        ),
        if (widget.links != null) ...[
          const SizedBox(height: 24),
          Text(
            'Related documents',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          widget.links!,
        ],
        if (widget.revisions != null) ...[
          const SizedBox(height: 24),
          Text('Revisions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          widget.revisions!,
        ],
      ],
    );
  }
}
