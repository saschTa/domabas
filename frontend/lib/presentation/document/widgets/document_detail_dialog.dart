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
    DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        key: const Key('documentWindow'),
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
  int _tab = 0;
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
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text('Your changes have not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
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
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() {
        _inspector = true;
        _tab = tab;
      });
      return;
    }
    _inspectorRoute = true;
    try {
      await showDialog<void>(
        context: context,
        useSafeArea: true,
        barrierDismissible: false,
        builder: (detailsContext) => Dialog(
          key: const Key('documentInspectorWindow'),
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
    required int initialTab,
  }) => DefaultTabController(
    key: ValueKey('inspector-$initialTab'),
    length: _document.capabilities.readOcr ? 2 : 1,
    initialIndex: _document.capabilities.readOcr ? initialTab : 0,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Document details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?widget.appearanceAction,
              IconButton(
                tooltip: 'Close details',
                onPressed: _document.state.saving ? null : onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        TabBar(
          tabs: [
            const Tab(text: 'Properties'),
            if (_document.capabilities.readOcr)
              const Tab(text: 'Extracted text'),
          ],
        ),
        if (_document.state.error case final error?)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (_document.state.notice case final notice?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Semantics(liveRegion: true, child: Text(notice)),
          ),
        if (_document.state.reconcileRequired)
          TextButton(
            onPressed: _document.state.saving || _document.state.loading
                ? null
                : _document.load,
            child: const Text('Reload document'),
          ),
        Expanded(
          child: TabBarView(
            children: [
              DocumentPropertiesPanel(
                emailLinks: _emailLinks(),
                cubit: _document,
                onCancel: _cancelMetadata,
              ),
              if (_document.capabilities.readOcr)
                DocumentOcrPanel(cubit: _document, onCancel: _cancelOcr),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '“${_document.state.document?.title ?? 'This document'}” will be permanently removed from this library. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep document'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete document'),
          ),
        ],
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
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentCubit, DocumentState>(
        bloc: _document,
        builder: (context, state) => PopScope(
          canPop: _leaving || (!state.dirty && !state.saving),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_leave());
          },
          child: Scaffold(
            key: const Key('documentDetails'),
            backgroundColor: AppSemanticColors.of(context).documentCanvas,
            body: SafeArea(
              child: Column(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            key: const Key('closeDocument'),
                            tooltip: 'Back to documents',
                            onPressed: state.saving ? null : _leave,
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              state.document?.title ?? 'Opening document…',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (_document.capabilities.download &&
                              state.document?.file != null &&
                              !state.remotelyDeleted &&
                              !state.deleted)
                            IconButton.filledTonal(
                              key: const Key('downloadDocument'),
                              tooltip: state.downloading
                                  ? 'Downloading original…'
                                  : 'Download original',
                              style: IconButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                shape: const CircleBorder(),
                              ),
                              onPressed: _document.canDownloadOriginal
                                  ? _document.downloadOriginal
                                  : null,
                              icon: state.downloading
                                  ? const SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded),
                            ),
                          IconButton(
                            tooltip: 'Document details',
                            onPressed:
                                state.document == null || state.remotelyDeleted
                                ? null
                                : () => _showDetails(),
                            icon: const Icon(Icons.info_outline),
                          ),
                          ?widget.appearanceAction,
                          PopupMenuButton<String>(
                            tooltip: 'Document actions',
                            onSelected: (value) {
                              if (value == 'delete') unawaited(_delete());
                              if (value == 'licenses') {
                                showLicensePage(
                                  context: context,
                                  applicationName: 'Domabas',
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              if (_document.capabilities.delete)
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled:
                                      !state.saving &&
                                      !state.remotelyDeleted &&
                                      !state.reconcileRequired &&
                                      state.document != null,
                                  child: const Text('Delete document'),
                                ),
                              const PopupMenuItem(
                                value: 'licenses',
                                child: Text('Licenses'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppProgressSlot(active: state.loading || state.saving),
                  if (state.downloadError case final error?
                      when !state.remotelyDeleted && !state.deleted)
                    AppNotice(
                      message: error,
                      action: TextButton(
                        onPressed: _document.canDownloadOriginal
                            ? _document.downloadOriginal
                            : null,
                        child: const Text('Retry download'),
                      ),
                    ),
                  if (state.error case final error?
                      when !(_inspector &&
                          MediaQuery.sizeOf(context).width >= 1100))
                    AppNotice(
                      message: error,
                      action: TextButton(
                        onPressed: state.loading || state.saving
                            ? null
                            : _document.load,
                        child: const Text('Reload'),
                      ),
                    ),
                  if (state.notice case final notice?
                      when !(_inspector &&
                          MediaQuery.sizeOf(context).width >= 1100))
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(notice),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Focus(
                            focusNode: _canvasFocus,
                            child: _canvas(state),
                          ),
                        ),
                        if (_inspector &&
                            !state.remotelyDeleted &&
                            MediaQuery.sizeOf(context).width >= 1100)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                            child: SizedBox(
                              width: 360,
                              child: Material(
                                key: const Key('documentInspectorPanel'),
                                color: Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                    width: 1.5,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _inspectorContents(
                                  context,
                                  initialTab: _tab,
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
              OutlinedButton(
                onPressed: () => _showDetails(),
                child: const Text('View properties'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.document!.file!.isEmail) {
      final mail = state.document!;
      return ListView(
        key: const Key('email-document-view'),
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.mail_outline, size: 48),
          const SizedBox(height: 16),
          SelectableText(
            mail.subject.isEmpty ? mail.title : mail.subject,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (mail.sender.isNotEmpty) SelectableText('From: ${mail.sender}'),
          if (mail.recipients.isNotEmpty)
            SelectableText('To: ${mail.recipients.join(', ')}'),
          if (mail.cc.isNotEmpty) SelectableText('CC: ${mail.cc.join(', ')}'),
          if (mail.bcc.isNotEmpty)
            SelectableText('BCC: ${mail.bcc.join(', ')}'),
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
              SelectableText(text, key: const Key('email-body'))
            else
              Text(
                state.ocr?.status == 'pending'
                    ? 'Email text is being prepared.'
                    : 'No email body text is available.',
              ),
            TextButton(
              onPressed: state.ocrLoading ? null : _document.loadOcr,
              child: const Text('Refresh email text'),
            ),
          ],
          _emailLinks(),
        ],
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
              TextButton(
                onPressed: _document.loadOriginal,
                child: const Text('Retry original'),
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
