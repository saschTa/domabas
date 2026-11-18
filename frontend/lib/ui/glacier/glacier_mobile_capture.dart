import 'package:flutter/material.dart';

import 'glacier_controls.dart';
import 'glacier_mobile_foundations.dart';
import 'glacier_theme.dart';

enum GlacierMobileCaptureState {
  ready,
  permission,
  unavailable,
  restored,
  storageError,
  pending,
  limit,
}

enum GlacierMobileScanState { ready, pending, recovery }

enum GlacierMobileUploadState {
  sending,
  accepted,
  rejected,
  duplicate,
  uncertain,
}

enum GlacierMobileShareState {
  ready,
  auth,
  blocked,
  existing,
  setup,
  sending,
  accepted,
  uncertain,
}

class GlacierMobileScanHandoff extends StatelessWidget {
  const GlacierMobileScanHandoff({
    super.key,
    required this.platform,
    this.state = GlacierMobileCaptureState.ready,
    this.library = 'Personal',
    this.savedPages = 3,
    this.onScan,
    this.onUpload,
    this.onSettings,
    this.onCheckAvailability,
    this.onKeepPage,
    this.onReview,
    this.onRetryPending,
    this.onDiscardPending,
    this.onDiscardDraft,
  });
  final TargetPlatform platform;
  final GlacierMobileCaptureState state;
  final String library;
  final int savedPages;
  final VoidCallback? onScan,
      onUpload,
      onSettings,
      onCheckAvailability,
      onKeepPage,
      onReview,
      onRetryPending,
      onDiscardPending,
      onDiscardDraft;
  @override
  Widget build(BuildContext context) {
    final ios = platform == TargetPlatform.iOS;
    final blocked = [
      GlacierMobileCaptureState.permission,
      GlacierMobileCaptureState.unavailable,
      GlacierMobileCaptureState.pending,
      GlacierMobileCaptureState.limit,
    ].contains(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlacierMobileNotice(
          title: 'Destination: $library library',
          message: 'Your scan stays in this account and library until you submit it.',
          attention: false,
        ),
        if (state == GlacierMobileCaptureState.permission)
          GlacierMobileNotice(
            title: 'Camera access is off',
            message: 'Allow camera access in system settings, or upload a file instead.',
            action: GlacierButton(
              label: 'Open system settings',
              onPressed: onSettings,
            ),
          ),
        if (state == GlacierMobileCaptureState.unavailable)
          GlacierMobileNotice(
            title: 'Scanner is unavailable',
            message: ios
                ? 'This device does not support the system document camera. You can upload a file.'
                : 'Google Play services is required. Check that it is installed, enabled and up to date. Your draft is unchanged.',
            action: GlacierButton(
              label: 'Check availability',
              onPressed: onCheckAvailability,
            ),
          ),
        if (state == GlacierMobileCaptureState.storageError)
          GlacierMobileNotice(
            title: 'Draft could not be saved',
            message: 'Free some device storage and try again. The returned page is retained.',
            action: GlacierButton(label: 'Keep page', onPressed: onKeepPage),
          ),
        if (state == GlacierMobileCaptureState.limit)
          GlacierMobileNotice(
            title: '20-page limit reached',
            message: 'No returned pages were imported. Review the saved draft before scanning again.',
            action: GlacierButton(
              label: 'Review saved pages',
              onPressed: onReview,
            ),
          ),
        if (state == GlacierMobileCaptureState.pending)
          GlacierMobileNotice(
            title: '2 scans still need saving',
            message: 'Saved pages are safe. Finish importing or discard the remaining scans before adding pages or uploading.',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GlacierButton(
                  label: 'Retry saving scans',
                  onPressed: onRetryPending,
                ),
                GlacierButton(
                  label: 'Discard remaining scans',
                  kind: GlacierButtonKind.quiet,
                  onPressed: onDiscardPending,
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 36,
                color: GlacierTokens.of(context).accent,
              ),
              const SizedBox(height: 18),
              Text(
                state == GlacierMobileCaptureState.restored
                    ? 'Your saved draft is ready'
                    : 'Turn paper into a document',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Text(
                ios
                    ? 'Apple’s document camera handles capture and crop. Return here to review your pages.'
                    : 'Google’s document scanner handles capture and crop. Add one page at a time, then review them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GlacierTokens.of(context).muted),
              ),
              const SizedBox(height: 18),
              GlacierButton(
                label: state == GlacierMobileCaptureState.restored
                    ? 'Continue draft · $savedPages pages'
                    : 'Scan pages',
                kind: GlacierButtonKind.primary,
                onPressed: blocked ? null : onScan,
              ),
              const SizedBox(height: 12),
              GlacierButton(
                label: 'Upload a file instead',
                onPressed: state == GlacierMobileCaptureState.pending
                    ? null
                    : onUpload,
              ),
            ],
          ),
        ),
        Text('Before you scan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(
          'Up to 20 pages per draft. Saved pages and their order stay on this device for this account and library.',
          style: TextStyle(color: GlacierTokens.of(context).muted),
        ),
        if (!ios) ...[
          const SizedBox(height: 12),
          Text(
            'Google processes images on this device and receives SDK usage and performance metrics. The first scan may need internet access to prepare the scanner.',
            style: TextStyle(color: GlacierTokens.of(context).muted),
          ),
        ],
        if (state == GlacierMobileCaptureState.restored) ...[
          const SizedBox(height: 24),
          GlacierButton(
            label: 'Discard saved draft',
            kind: GlacierButtonKind.danger,
            onPressed: onDiscardDraft,
          ),
        ],
      ],
    );
  }
}

@immutable
class GlacierMobileScanPageValue {
  const GlacierMobileScanPageValue({required this.id, required this.preview});
  final String id;
  final Widget preview;
}

class GlacierMobileScanPage extends StatelessWidget {
  const GlacierMobileScanPage({
    super.key,
    required this.number,
    required this.preview,
    this.onEarlier,
    this.onLater,
    this.onRemove,
    this.earlierKey,
    this.laterKey,
    this.removeKey,
    this.showActions = true,
  });
  final Key? earlierKey, laterKey, removeKey;
  final bool showActions;
  final int number;
  final Widget preview;
  final VoidCallback? onEarlier, onLater, onRemove;
  @override
  Widget build(BuildContext context) => GlacierMobileSurface(
    padding: const EdgeInsets.all(8),
    radius: 14,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 170,
            child: ColoredBox(
              color: GlacierTokens.of(context).preview,
              child: preview,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
          child: Text(
            'Page $number',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (showActions)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              SizedBox.square(
                dimension: 48,
                child: GlacierIconButton(
                  key: earlierKey,
                  label: 'Move page $number earlier',
                  icon: Icons.keyboard_arrow_up,
                  onPressed: onEarlier,
                ),
              ),
              SizedBox.square(
                dimension: 48,
                child: GlacierIconButton(
                  key: laterKey,
                  label: 'Move page $number later',
                  icon: Icons.keyboard_arrow_down,
                  onPressed: onLater,
                ),
              ),
              SizedBox.square(
                dimension: 48,
                child: GlacierIconButton(
                  key: removeKey,
                  label: 'Remove page $number',
                  icon: Icons.delete_outline,
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class GlacierMobileScanReview extends StatelessWidget {
  const GlacierMobileScanReview({
    super.key,
    required this.pages,
    required this.details,
    this.state = GlacierMobileScanState.ready,
    this.library = 'Personal',
    this.pendingCount = 2,
    this.onMove,
    this.onRemove,
    this.onAddPage,
    this.onDiscard,
    this.onUpload,
    this.onRetryPending,
    this.onDiscardPending,
    this.onRecover,
  });
  final List<GlacierMobileScanPageValue> pages;
  final Widget details;
  final GlacierMobileScanState state;
  final String library;
  final int pendingCount;
  final void Function(String id, int destination)? onMove;
  final ValueChanged<String>? onRemove;
  final VoidCallback? onAddPage,
      onDiscard,
      onUpload,
      onRetryPending,
      onDiscardPending,
      onRecover;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (state == GlacierMobileScanState.pending)
        GlacierMobileNotice(
          title: '$pendingCount more scans need saving',
          message:
              '${pages.length} pages are saved. Upload and new capture are paused until the remaining scans are handled.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlacierButton(
                label: 'Retry saving remaining scans',
                onPressed: onRetryPending,
              ),
              GlacierButton(
                label: 'Discard remaining scans',
                kind: GlacierButtonKind.quiet,
                onPressed: onDiscardPending,
              ),
            ],
          ),
        ),
      if (state == GlacierMobileScanState.recovery)
        GlacierMobileNotice(
          title: 'Saved draft needs recovery',
          message: 'A referenced page is unavailable. Submission is blocked to avoid sending an incomplete document.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlacierButton(label: 'Retry loading draft', onPressed: onRecover),
              GlacierButton(
                label: 'Discard draft',
                kind: GlacierButtonKind.danger,
                onPressed: onDiscard,
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Review your pages',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${pages.length} of 20',
                style: TextStyle(
                  fontSize: 11.7,
                  height: 1.2,
                  color: GlacierTokens.of(context).accent,
                ),
              ),
            ),
          ],
        ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = MediaQuery.textScalerOf(context).scale(15) >= 26
              ? 1
              : 2;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < pages.length; i++)
                SizedBox(
                  width: width,
                  child: GlacierMobileScanPage(
                    number: i + 1,
                    preview: pages[i].preview,
                    onEarlier: i == 0 || onMove == null
                        ? null
                        : () => onMove!(pages[i].id, i - 1),
                    onLater: i == pages.length - 1 || onMove == null
                        ? null
                        : () => onMove!(pages[i].id, i + 1),
                    onRemove: onRemove == null
                        ? null
                        : () => onRemove!(pages[i].id),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      GlacierMobileActionBar(
        children: [
          GlacierButton(
            label: 'Add page',
            onPressed:
                state == GlacierMobileScanState.ready && pages.length < 20
                ? onAddPage
                : null,
          ),
          GlacierButton(
            label: 'Discard draft',
            kind: GlacierButtonKind.danger,
            onPressed: onDiscard,
          ),
        ],
      ),
      const SizedBox(height: 24),
      Text('Document details', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      details,
      GlacierMobileNotice(
        title: 'Destination: $library library',
        message: 'Saved pages remain in this draft until upload is confirmed.',
        attention: false,
      ),
      GlacierButton(
        label: 'Upload ${pages.length}-page PDF',
        kind: GlacierButtonKind.primary,
        onPressed: state == GlacierMobileScanState.ready && pages.isNotEmpty
            ? onUpload
            : null,
      ),
      if (state != GlacierMobileScanState.ready) ...[
        const SizedBox(height: 12),
        Text(
          'Upload is unavailable while this draft needs attention.',
          style: TextStyle(color: GlacierTokens.of(context).muted),
        ),
      ],
    ],
  );
}

class GlacierMobileUploadForm extends StatefulWidget {
  const GlacierMobileUploadForm({
    super.key,
    this.metadataOnly = false,
    this.filename = '',
    this.fileDetail = '',
    this.library = 'Personal',
    this.values = const {},
    this.onChooseFiles,
    this.onRemoveFile,
    this.onLibrary,
    this.onMetadataOnly,
    this.onSubmit,
  });
  final bool metadataOnly;
  final String filename, fileDetail, library;
  final Map<String, String> values;
  final VoidCallback? onChooseFiles, onRemoveFile, onLibrary, onMetadataOnly;
  final ValueChanged<Map<String, String>>? onSubmit;
  @override
  State<GlacierMobileUploadForm> createState() =>
      _GlacierMobileUploadFormState();
}

class _GlacierMobileUploadFormState extends State<GlacierMobileUploadForm> {
  late final Map<String, TextEditingController> fields;
  bool expanded = false;
  String? titleError;
  @override
  void initState() {
    super.initState();
    fields = {
      for (final label in [
        'Title',
        'Tags',
        'Description',
        'Kind',
        'Document date',
        'Sender',
        'Recipients',
        'CC',
        'BCC',
        'Subject',
        'Message ID',
      ])
        label: TextEditingController(text: widget.values[label] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    if (fields['Title']!.text.trim().isEmpty) {
      setState(() => titleError = 'Enter a title');
      return;
    }
    widget.onSubmit?.call(
      Map.unmodifiable(fields.map((k, v) => MapEntry(k, v.text))),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.metadataOnly)
        const GlacierMobileNotice(
          title: 'Metadata-only document',
          message: 'Create a record without uploading an original file.',
          attention: false,
        )
      else ...[
        GlacierMobileSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add originals',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'PDF, PNG, JPEG or EML · up to 100 MB each',
                style: TextStyle(color: GlacierTokens.of(context).muted),
              ),
              const SizedBox(height: 12),
              GlacierButton(
                label: 'Choose files',
                icon: Icons.upload_file_outlined,
                onPressed: widget.onChooseFiles,
              ),
              if (widget.filename.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: GlacierTokens.of(context).accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.filename,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.fileDetail,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    GlacierIconButton(
                      label: 'Remove selected file',
                      icon: Icons.close,
                      onPressed: widget.onRemoveFile,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Destination', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GlacierMobileRecordRow(
          title: '${widget.library} library',
          detail: 'Only you have access',
          icon: Icons.library_books_outlined,
          onTap: widget.onLibrary,
        ),
        const SizedBox(height: 24),
      ],
      GlacierMobileField(
        label: 'Title',
        controller: fields['Title'],
        errorText: titleError,
      ),
      if (widget.metadataOnly)
        GlacierMobileField(
          label: 'Description',
          controller: fields['Description'],
          maxLines: 3,
        ),
      GlacierMobileField(label: 'Tags', controller: fields['Tags']),
      if (!widget.metadataOnly) ...[
        TextButton(
          onPressed: () => setState(() => expanded = !expanded),
          child: Row(
            children: [
              Icon(expanded ? Icons.arrow_drop_down : Icons.arrow_right),
              const Flexible(child: Text('Document properties')),
            ],
          ),
        ),
        if (expanded)
          for (final label in [
            'Description',
            'Kind',
            'Document date',
            'Sender',
            'Recipients',
            'CC',
            'BCC',
            'Subject',
            'Message ID',
          ])
            GlacierMobileField(
              label: label,
              controller: fields[label],
              maxLines: label == 'Description' ? 3 : 1,
            ),
        const SizedBox(height: 16),
      ],
      GlacierButton(
        label: widget.metadataOnly
            ? 'Create document record'
            : 'Upload original',
        kind: GlacierButtonKind.primary,
        onPressed:
            widget.onSubmit == null ||
                (!widget.metadataOnly && widget.filename.isEmpty)
            ? null
            : submit,
      ),
      if (!widget.metadataOnly) ...[
        const SizedBox(height: 12),
        GlacierButton(
          label: 'Create metadata without a file',
          kind: GlacierButtonKind.quiet,
          onPressed: widget.onMetadataOnly,
        ),
      ],
    ],
  );
}

class GlacierMobileUploadOutcome extends StatelessWidget {
  const GlacierMobileUploadOutcome({
    super.key,
    required this.state,
    required this.filename,
    this.detail = '',
    this.onCheck,
    this.onRetryExact,
    this.onOpen,
    this.onProcessing,
    this.onChooseAnother,
    this.onBack,
  });
  final GlacierMobileUploadState state;
  final String filename, detail;
  final VoidCallback? onCheck,
      onRetryExact,
      onOpen,
      onProcessing,
      onChooseAnother,
      onBack;
  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (state) {
      GlacierMobileUploadState.sending => (
        'Sending original…',
        'Keep this screen open. Your draft is retained until the server responds.',
      ),
      GlacierMobileUploadState.accepted => (
        'Original accepted',
        'Home project notes is saved in Personal library. Text extraction and indexing continue in the background.',
      ),
      GlacierMobileUploadState.rejected => (
        'Original was not accepted',
        'The file exceeds the 100 MB upload limit. Choose a smaller original.',
      ),
      GlacierMobileUploadState.duplicate => (
        'Already in this library',
        'The same original is already saved. Open the existing document instead of sending it again.',
      ),
      GlacierMobileUploadState.uncertain => (
        'Upload outcome unknown',
        'The server may have accepted this original. Check its receipt before retrying. Your draft is read-only.',
      ),
    };
    return GlacierMobileSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state == GlacierMobileUploadState.sending)
              const Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Icon(
                state == GlacierMobileUploadState.accepted
                    ? Icons.check
                    : state == GlacierMobileUploadState.uncertain
                    ? Icons.schedule
                    : Icons.info_outline,
                size: 36,
                color: GlacierTokens.of(context).accent,
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: GlacierTokens.of(context).muted),
            ),
            const SizedBox(height: 18),
            Text(
              filename,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (state == GlacierMobileUploadState.uncertain) ...[
              GlacierButton(
                label: 'Check receipt',
                kind: GlacierButtonKind.primary,
                onPressed: onCheck,
              ),
              const SizedBox(height: 12),
              GlacierButton(
                label: 'Retry this exact upload',
                kind: GlacierButtonKind.quiet,
                onPressed: onRetryExact,
              ),
            ] else if (state == GlacierMobileUploadState.sending)
              GlacierButton(
                label: 'Check status',
                kind: GlacierButtonKind.primary,
                onPressed: onCheck,
              )
            else if (state == GlacierMobileUploadState.accepted ||
                state == GlacierMobileUploadState.duplicate) ...[
              GlacierButton(
                label: 'Open document',
                kind: GlacierButtonKind.primary,
                onPressed: onOpen,
              ),
              const SizedBox(height: 12),
              GlacierButton(label: 'View processing', onPressed: onProcessing),
            ] else
              GlacierButton(
                label: 'Choose another file',
                kind: GlacierButtonKind.primary,
                onPressed: onChooseAnother,
              ),
            const SizedBox(height: 12),
            GlacierButton(
              label: 'Back to documents',
              kind: GlacierButtonKind.quiet,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class GlacierMobileReceiptValue {
  const GlacierMobileReceiptValue({
    required this.filename,
    required this.detail,
    this.icon = Icons.description_outlined,
    this.onOpen,
  });
  final String filename, detail;
  final IconData icon;
  final VoidCallback? onOpen;
}

class GlacierMobileUploadReceipts extends StatelessWidget {
  const GlacierMobileUploadReceipts({
    super.key,
    required this.receipts,
    this.continuation,
  });
  final List<GlacierMobileReceiptValue> receipts;
  final Widget? continuation;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Recent uploads', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      for (final receipt in receipts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlacierMobileRecordRow(
            title: receipt.filename,
            detail: receipt.detail,
            icon: receipt.icon,
            onTap: receipt.onOpen,
          ),
        ),
      ?continuation,
    ],
  );
}

class GlacierMobileIncomingShare extends StatelessWidget {
  const GlacierMobileIncomingShare({
    super.key,
    required this.files,
    this.state = GlacierMobileShareState.ready,
    this.library = 'Personal',
    this.serverAndAccount = '',
    this.onSignIn,
    this.onLibrary,
    this.onReviewWaiting,
    this.onDiscardWaiting,
    this.onCheck,
    this.onUpload,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.showActions = true,
  });
  final bool showActions;
  final List<GlacierMobileReceiptValue> files;
  final GlacierMobileShareState state;
  final String library, serverAndAccount, cancelLabel;
  final VoidCallback? onSignIn,
      onLibrary,
      onReviewWaiting,
      onDiscardWaiting,
      onCheck,
      onUpload,
      onCancel;
  @override
  Widget build(BuildContext context) => _ShareReview(
    files: files,
    state: state,
    library: library,
    serverAndAccount: serverAndAccount,
    onSignIn: onSignIn,
    onLibrary: onLibrary,
    onReviewWaiting: onReviewWaiting,
    onDiscardWaiting: onDiscardWaiting,
    onCheck: onCheck,
    onUpload: onUpload,
    onCancel: onCancel,
    cancelLabel: cancelLabel,
    showActions: showActions,
  );
}

class GlacierMobileShareExtension extends StatelessWidget {
  const GlacierMobileShareExtension({
    super.key,
    required this.files,
    this.state = GlacierMobileShareState.ready,
    this.library = 'Personal',
    this.serverAndAccount = '',
    this.onCheck,
    this.onUpload,
    this.onClose,
  });
  final List<GlacierMobileReceiptValue> files;
  final GlacierMobileShareState state;
  final String library, serverAndAccount;
  final VoidCallback? onCheck, onUpload, onClose;
  @override
  Widget build(BuildContext context) => _ShareReview(
    files: files,
    state: state,
    library: library,
    serverAndAccount: serverAndAccount,
    extension: true,
    onCheck: onCheck,
    onUpload: onUpload,
    onCancel: onClose,
  );
}

class _ShareReview extends StatelessWidget {
  const _ShareReview({
    required this.files,
    required this.state,
    required this.library,
    required this.serverAndAccount,
    this.extension = false,
    this.onSignIn,
    this.onLibrary,
    this.onReviewWaiting,
    this.onDiscardWaiting,
    this.onCheck,
    this.onUpload,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.showActions = true,
  });
  final List<GlacierMobileReceiptValue> files;
  final GlacierMobileShareState state;
  final String library, serverAndAccount, cancelLabel;
  final bool extension, showActions;
  final VoidCallback? onSignIn,
      onLibrary,
      onReviewWaiting,
      onDiscardWaiting,
      onCheck,
      onUpload,
      onCancel;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlacierMobileNotice(
        title: extension ? 'Save to Domabas' : '${files.length} shared files',
        message: extension
            ? 'This extension uses your signed-in server and selected library. Keep it open until a receipt appears.'
            : 'Review the destination before uploading. Files wait here if you need to finish setup or sign in.',
        attention: false,
      ),
      if ([
        GlacierMobileShareState.setup,
        GlacierMobileShareState.auth,
      ].contains(state))
        GlacierMobileNotice(
          title: 'Open Domabas to continue',
          message: extension
              ? 'Configure a server and sign in in the main app, then share these files again. The extension cannot change your account or library.'
              : 'Sign in to continue with this staged batch.',
          action: !extension && onSignIn == null
              ? null
              : GlacierButton(
                  label: extension ? 'Close extension' : 'Sign in',
                  kind: GlacierButtonKind.primary,
                  onPressed: extension ? onCancel : onSignIn,
                ),
        ),
      if (state == GlacierMobileShareState.blocked)
        GlacierMobileNotice(
          title: 'Upload access required',
          message: 'This library does not allow your account to upload. Choose a permitted library.',
          action: onLibrary == null
              ? null
              : GlacierButton(label: 'Choose library', onPressed: onLibrary),
        ),
      if (state == GlacierMobileShareState.existing)
        GlacierMobileNotice(
          title: 'Another shared batch is waiting',
          message: 'The new files have not replaced it. Finish or explicitly discard the waiting batch first.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlacierButton(
                label: 'Review waiting batch',
                onPressed: onReviewWaiting,
              ),
              GlacierButton(
                label: 'Discard waiting batch',
                kind: GlacierButtonKind.danger,
                onPressed: onDiscardWaiting,
              ),
            ],
          ),
        ),
      if (state == GlacierMobileShareState.uncertain)
        GlacierMobileNotice(
          title: 'Receipt unknown',
          message: 'Do not send these files again until their saved status is checked.',
          action: GlacierButton(label: 'Check receipt', onPressed: onCheck),
        ),
      if (state == GlacierMobileShareState.sending)
        const GlacierMobileNotice(
          title: 'Sending originals…',
          message: 'Keep this view open until a receipt appears.',
        ),
      if (state == GlacierMobileShareState.accepted)
        GlacierMobileNotice(
          title: 'Originals accepted',
          message: 'Processing continues in $library library.',
          attention: false,
        ),
      if (library.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Destination', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GlacierMobileSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$library library',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                serverAndAccount,
                style: TextStyle(color: GlacierTokens.of(context).muted),
              ),
              if (!extension && onLibrary != null)
                GlacierButton(
                  label: 'Change library',
                  kind: GlacierButtonKind.quiet,
                  onPressed: onLibrary,
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),
      GlacierMobileSurface(
        child: Column(
          children: [
            for (final file in files)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: GlacierTokens.of(context).border),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(file.icon, color: GlacierTokens.of(context).accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.filename,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            file.detail,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (showActions) ...[
        const SizedBox(height: 18),
        if (state == GlacierMobileShareState.ready ||
            state == GlacierMobileShareState.accepted) ...[
          GlacierButton(
            label: state == GlacierMobileShareState.accepted
                ? 'Done'
                : 'Upload ${files.length} files',
            kind: GlacierButtonKind.primary,
            onPressed: state == GlacierMobileShareState.accepted
                ? onCancel
                : onUpload,
          ),
          const SizedBox(height: 12),
        ],
        GlacierButton(
          label: cancelLabel,
          kind: GlacierButtonKind.quiet,
          onPressed: onCancel,
        ),
      ],
      if (extension) ...[
        const SizedBox(height: 12),
        Text(
          'No background upload queue is promised. If the extension closes before a receipt, check the library before sharing again.',
          style: TextStyle(color: GlacierTokens.of(context).muted),
        ),
      ],
    ],
  );
}
