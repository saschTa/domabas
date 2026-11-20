import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../ui/domabas_ui.dart';
import '../cubits/document_cubit.dart';
import '../cubits/documents_cubit.dart';
import '../cubits/document_email_links_cubit.dart';
import 'document_email_links.dart';
import 'document_canvas.dart';
import 'document_password_form.dart';
import 'document_ocr_panel.dart';
import 'document_properties_panel.dart';
import 'document_route_scope.dart';

final class DocumentDetailDialog extends StatefulWidget {
  const DocumentDetailDialog({
    super.key,
    required this.documentId,
    required this.cubit,
    this.appearanceAction,
  });
  final String documentId;
  final DocumentsCubit cubit;
  final Widget? appearanceAction;

  static Future<void> open(
    BuildContext context, {
    required String documentId,
    required DocumentsCubit cubit,
    Widget? appearanceAction,
  }) => Navigator.of(context).push<void>(
    createGlacierDialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        key: const Key('documentWindow'),
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 8 : 24,
        ),
        constraints: const BoxConstraints(maxWidth: 1600),
        clipBehavior: Clip.antiAlias,
        child: DocumentDetailDialog(
          documentId: documentId,
          cubit: cubit,
          appearanceAction: appearanceAction,
        ),
      ),
    ),
  );

  @override
  State<DocumentDetailDialog> createState() => _DocumentDetailDialogState();
}

final class _DocumentDetailDialogState extends State<DocumentDetailDialog>
    with RouteAware {
  late final DocumentCubit _document = widget.cubit.openDocument(
    widget.documentId,
  );
  final _canvasFocus = FocusNode();
  late final DocumentEmailLinksCubit _links = widget.cubit.emailLinks(
    widget.documentId,
  );
  bool _inspector = true;
  bool _textSelected = false;
  bool _leaving = false;
  bool _inspectorRoute = false;
  bool _childRoute = false;
  RouteObserver<ModalRoute<void>>? _observer;
  @override
  void initState() {
    super.initState();
    widget.cubit.attachLinks(_document, _links);
    unawaited(_document.load());
    if (_document.capabilities.read) unawaited(_links.load());
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    _canvasFocus.dispose();
    unawaited(widget.cubit.closeDocument(_document));
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = DocumentRouteScope.maybeOf(context);
    if (observer == _observer) return;
    _observer?.unsubscribe(this);
    _observer = observer;
    final route = ModalRoute.of<void>(context);
    if (observer != null && route != null) observer.subscribe(this, route);
  }

  @override
  void didPush() => widget.cubit.setViewerActive(_document, true);
  @override
  void didPopNext() => widget.cubit.setViewerActive(_document, true);
  @override
  void didPushNext() =>
      widget.cubit.setViewerActive(_document, _inspectorRoute && !_childRoute);
  @override
  void didPop() => widget.cubit.setViewerActive(_document, false);

  Future<bool> _discard({bool? dirty}) async {
    if (_document.state.saving) return false;
    if (!(dirty ?? _document.state.dirty)) return true;
    return await showGlacierDialog<bool>(
          context: context,
          builder: (context) => GlacierDialog(
            title: 'Discard unsaved changes?',
            actions: [
              GlacierButton(
                label: 'Keep editing',
                kind: GlacierButtonKind.quiet,
                onPressed: () => Navigator.pop(context, false),
              ),
              GlacierButton(
                label: 'Discard',
                kind: GlacierButtonKind.danger,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
            child: const Text('Your changes have not been saved.'),
          ),
        ) ??
        false;
  }

  Future<void> _cancelMetadata() async {
    if (await _discard(dirty: _document.state.metadataDirty) && mounted) {
      _document.cancelMetadata();
    }
  }

  Future<void> _cancelOcr() async {
    if (await _discard(dirty: _document.state.ocrDirty) && mounted) {
      _document.cancelOcr();
    }
  }

  Future<void> _leave() async {
    if (_leaving || !await _discard() || !mounted) return;
    _document.discardDrafts();
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _openLinkedDocument(String id) async {
    if (id == widget.documentId || !await _discard() || !mounted) return;
    _document.discardDrafts();
    _childRoute = true;
    widget.cubit.setViewerActive(_document, false);
    try {
      await DocumentDetailDialog.open(
        context,
        documentId: id,
        cubit: widget.cubit,
        appearanceAction: widget.appearanceAction,
      );
    } finally {
      _childRoute = false;
      if (mounted) widget.cubit.setViewerActive(_document, true);
    }
  }

  Widget _emailLinks() =>
      DocumentEmailLinksPanel(cubit: _links, onOpen: _openLinkedDocument);

  Future<void> _showDetails({int tab = 0}) async {
    if (tab == 1 && _document.capabilities.readOcr) {
      setState(() => _textSelected = true);
      return;
    }
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() {
        _inspector = true;
      });
      return;
    }
    _inspectorRoute = true;
    try {
      await showGlacierDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (detailsContext) => Dialog(
          key: const Key('documentInspectorWindow'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 900),
          clipBehavior: Clip.antiAlias,
          child: BlocBuilder<DocumentCubit, DocumentState>(
            bloc: _document,
            builder: (context, state) => PopScope(
              canPop: !state.dirty && !state.saving,
              onPopInvokedWithResult: (didPop, _) async {
                if (!didPop && await _discard() && detailsContext.mounted) {
                  _document.discardDrafts();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (detailsContext.mounted) Navigator.pop(detailsContext);
                  });
                }
              },
              child: _inspectorContents(
                context,
                onClose: () async {
                  if (await _discard() && detailsContext.mounted) {
                    _document.discardDrafts();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (detailsContext.mounted) Navigator.pop(detailsContext);
                    });
                  }
                },
                initialTab: tab,
              ),
            ),
          ),
        ),
      );
    } finally {
      _inspectorRoute = false;
    }
    if (mounted) _canvasFocus.requestFocus();
  }

  Widget _inspectorContents(
    BuildContext context, {
    required VoidCallback onClose,
    int initialTab = 0,
  }) => GlacierSurface(
    radius: 16,
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Properties',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_document.capabilities.update &&
                  !_document.state.editingMetadata)
                GlacierIconButton(
                  label: 'Edit properties',
                  icon: Icons.edit_outlined,
                  onPressed:
                      _document.state.saving ||
                          _document.state.reconcileRequired
                      ? null
                      : _document.editMetadata,
                ),
              GlacierIconButton(
                label: 'Close details',
                icon: Icons.close,
                onPressed: _document.state.saving ? null : onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: DocumentPropertiesPanel(
            emailLinks: _emailLinks(),
            cubit: _document,
            onCancel: _cancelMetadata,
            showEditAction: false,
          ),
        ),
      ],
    ),
  );

  Future<void> _editProperties() async {
    _document.editMetadata();
    await _showDetails();
  }

  Future<void> _delete() async {
    final confirmed = await showGlacierDialog<bool>(
      context: context,
      builder: (context) => GlacierDialog(
        title: 'Delete document?',
        actions: [
          GlacierButton(
            label: 'Keep document',
            kind: GlacierButtonKind.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          GlacierButton(
            label: 'Delete document',
            kind: GlacierButtonKind.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
        child: Text(
          '“${_document.state.document?.title ?? 'This document'}” will be permanently removed from this library. This cannot be undone.',
        ),
      ),
    );
    if (confirmed == true && mounted) {
      final deleted = await _document.delete();
      if (deleted && mounted) {
        setState(() => _leaving = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DocumentCubit, DocumentState>(
    bloc: _document,
    builder: (context, state) {
      final available =
          state.document != null && !state.remotelyDeleted && !state.deleted;
      final editable = available && !state.saving && !state.reconcileRequired;
      final processing = state.document?.processing;
      final canRetry =
          _document.capabilities.retry &&
          available &&
          processing?.failureCode != 'encrypted_pdf' &&
          (processing?.state == 'failed' ||
              state.ocr?.reason == 'legacy_text_missing');
      final canRetryAI =
          _document.capabilities.retry &&
          available &&
          processing?.state == 'ready' &&
          (processing?.ai?.canRetry == true || state.pendingAIRetry != null);
      final canDownload =
          _document.capabilities.download &&
          available &&
          state.document?.file != null;
      final canDelete = _document.capabilities.delete && available;
      final compact = MediaQuery.sizeOf(context).width < 600;
      final close = GlacierIconButton(
        key: const Key('closeDocument'),
        label: 'Back to documents',
        icon: Icons.close,
        onPressed: state.saving ? null : _leave,
      );
      final actions = compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                GlacierMobileReaderToolbar(
                  onProperties: available ? _showDetails : null,
                  onResync: !editable
                      ? null
                      : canRetry
                      ? _document.retryProcessing
                      : _document.retryAIProcessing,
                  resyncLabel: canRetry ? 'Retry' : 'Retry AI',
                  showResync: canRetry || canRetryAI,
                  showDownload: canDownload,
                  showDelete: canDelete,
                  onDownload: _document.canDownloadOriginal
                      ? _document.downloadOriginal
                      : null,
                  onDelete: editable ? _delete : null,
                  downloadKey: const Key('downloadDocument'),
                  deleteKey: const Key('deleteDocument'),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    if (_document.capabilities.update)
                      GlacierButton(
                        label: 'Edit',
                        icon: Icons.edit_outlined,
                        onPressed: editable ? _editProperties : null,
                      ),
                    close,
                  ],
                ),
              ],
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_document.capabilities.update)
                  GlacierButton(
                    label: 'Edit properties',
                    icon: Icons.edit_outlined,
                    onPressed: editable ? _editProperties : null,
                  ),
                if (canRetry)
                  GlacierButton(
                    label: 'Retry processing',
                    icon: Icons.sync,
                    onPressed: editable ? _document.retryProcessing : null,
                  ),
                if (canRetryAI)
                  GlacierButton(
                    label: 'Retry AI processing',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: editable ? _document.retryAIProcessing : null,
                  ),
                if (canDownload)
                  GlacierIconButton(
                    key: const Key('downloadDocument'),
                    label: state.downloading
                        ? 'Downloading original…'
                        : 'Download original',
                    icon: Icons.file_download_outlined,
                    onPressed: _document.canDownloadOriginal
                        ? _document.downloadOriginal
                        : null,
                  ),
                if (canDelete)
                  GlacierIconButton(
                    key: const Key('deleteDocument'),
                    label: 'Delete document',
                    icon: Icons.delete_outline,
                    onPressed: editable ? _delete : null,
                  ),
                GlacierIconButton(
                  label: 'Document details',
                  icon: Icons.info_outline,
                  onPressed: available ? _showDetails : null,
                ),
                ?widget.appearanceAction,
                GlacierIconButton(
                  label: 'Licenses',
                  icon: Icons.policy_outlined,
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Domabas',
                  ),
                ),
                close,
              ],
            );
      Widget notices(Widget child) => Column(
        children: [
          AppProgressSlot(active: state.loading || state.saving),
          if (state.downloadError case final error? when available)
            AppNotice(
              message: error,
              action: GlacierButton(
                kind: GlacierButtonKind.quiet,
                onPressed: _document.canDownloadOriginal
                    ? _document.downloadOriginal
                    : null,
                label: 'Retry download',
              ),
            ),
          if (state.error case final error?)
            AppNotice(
              message: error,
              action: GlacierButton(
                kind: GlacierButtonKind.quiet,
                onPressed: state.loading || state.saving
                    ? null
                    : _document.load,
                label: 'Reload',
              ),
            ),
          if (state.notice case final notice?)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(liveRegion: true, child: Text(notice)),
            ),
          Expanded(child: child),
        ],
      );
      return PopScope(
        canPop: _leaving || (!state.dirty && !state.saving),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: SizedBox.expand(
          key: const Key('documentDetails'),
          child: GlacierReader(
            title: state.document?.title ?? 'Opening document…',
            contextLabel:
                state.document?.file?.originalFilename ?? 'Document properties',
            headerActions: actions,
            boundedHeader: true,
            showInspector: _inspector && !state.remotelyDeleted,
            inspectorBreakpoint: 1100,
            compactInspectorBelow: false,
            inspectorScrolls: false,
            inspectorPadding: EdgeInsets.zero,
            original: notices(
              Focus(focusNode: _canvasFocus, child: _canvas(state)),
            ),
            text: _document.capabilities.readOcr
                ? notices(
                    DocumentOcrPanel(cubit: _document, onCancel: _cancelOcr),
                  )
                : null,
            textSelected: _textSelected,
            onViewChanged: (value) => setState(() => _textSelected = value),
            toolbar: const SizedBox.shrink(),
            inspector: KeyedSubtree(
              key: const Key('documentInspectorPanel'),
              child: _inspectorContents(
                context,
                onClose: () async {
                  if (await _discard() && mounted) {
                    _document.discardDrafts();
                    setState(() => _inspector = false);
                    _canvasFocus.requestFocus();
                  }
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _canvas(DocumentState state) {
    if (state.remotelyDeleted) {
      return ListView(
        key: const Key('remotelyDeletedDocument'),
        padding: const EdgeInsets.all(24),
        children: [
          const Text('This document was deleted.'),
          const SizedBox(height: 12),
          if (state.metadataDraft case final draft?) ...[
            const Text('Unsaved properties'),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(draft.values),
            ),
          ],
          if (state.ocrDraft case final draft?) ...[
            const SizedBox(height: 12),
            const Text('Unsaved extracted text'),
            SelectableText(draft),
          ],
        ],
      );
    }
    if (state.document == null) {
      return state.loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Document unavailable.'));
    }
    if (state.document!.file == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 64),
              const SizedBox(height: 16),
              const Text('No original file'),
              const SizedBox(height: 12),
              SelectableText(
                state.document!.description.isEmpty
                    ? 'This document contains metadata only.'
                    : state.document!.description,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              GlacierButton(
                kind: GlacierButtonKind.quiet,
                onPressed: () => _showDetails(),
                label: 'View properties',
              ),
            ],
          ),
        ),
      );
    }
    if (state.document!.file!.isEmail) {
      final mail = state.document!;
      Widget selectableEmailText(String value, {Key? key, TextStyle? style}) =>
          SelectionArea(
            child: Text(value, key: key, style: style),
          );

      return AppRefreshable(
        onRefresh:
            _document.capabilities.readOcr && !state.ocrLoading && !state.saving
            ? _document.loadOcr
            : null,
        child: ListView(
          key: const Key('email-document-view'),
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.mail_outline, size: 48),
            const SizedBox(height: 16),
            selectableEmailText(
              mail.subject.isEmpty ? mail.title : mail.subject,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (mail.sender.isNotEmpty)
              selectableEmailText('From: ${mail.sender}'),
            if (mail.recipients.isNotEmpty)
              selectableEmailText('To: ${mail.recipients.join(', ')}'),
            if (mail.cc.isNotEmpty)
              selectableEmailText('CC: ${mail.cc.join(', ')}'),
            if (mail.bcc.isNotEmpty)
              selectableEmailText('BCC: ${mail.bcc.join(', ')}'),
            if (mail.documentDate.isNotEmpty) Text(mail.documentDate),
            const AppStripedDivider(height: 32, thickness: 8),
            if (!_document.capabilities.readOcr)
              const Text(
                'Your permissions do not allow viewing extracted email text.',
              )
            else ...[
              if (state.ocrLoading) const AppStripedProgressIndicator(),
              if (state.ocrError case final error?) AppNotice(message: error),
              if (state.ocr?.text case final text?)
                selectableEmailText(text, key: const Key('email-body'))
              else
                Text(
                  state.ocr?.status == 'pending'
                      ? 'Email text is being prepared.'
                      : 'No email body text is available.',
                ),
            ],
            _emailLinks(),
          ],
        ),
      );
    }
    if (state.document?.processing?.failureCode == 'encrypted_pdf') {
      return DocumentPasswordForm(cubit: _document, state: state);
    }
    if (!_document.capabilities.download) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your role does not allow viewing the original file. Properties and permitted extracted text are available in Details.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state.fileLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening original…'),
          ],
        ),
      );
    }
    if (state.fileError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.fileError!, textAlign: TextAlign.center),
              GlacierButton(
                kind: GlacierButtonKind.quiet,
                onPressed: _document.loadOriginal,
                label: 'Retry original',
              ),
            ],
          ),
        ),
      );
    }
    if (state.bytes == null) return const SizedBox.shrink();
    return state.document!.file!.isPdf
        ? DocumentPdfCanvas(
            bytes: state.bytes!,
            sourceName: '${widget.documentId}/${state.document!.file!.sha256}',
            onExtractedText: () => _showDetails(tab: 1),
            onRetry: _document.loadOriginal,
          )
        : DocumentImageCanvas(
            bytes: state.bytes!,
            onRetry: _document.loadOriginal,
          );
  }
}
