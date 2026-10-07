import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../ui/domabas_ui.dart';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_previews.dart';
import 'document_canvas_layout.dart';
import 'document_pdf_sizing.dart';
import 'document_pdf_selection_menu.dart';

final class DocumentPdfCanvas extends StatefulWidget {
  const DocumentPdfCanvas({
    super.key,
    required this.bytes,
    required this.sourceName,
    required this.onExtractedText,
    required this.onRetry,
  });
  final Uint8List bytes;
  final String sourceName;
  final VoidCallback onExtractedText;
  final VoidCallback onRetry;
  @override
  State<DocumentPdfCanvas> createState() => _DocumentPdfCanvasState();
}

final class _DocumentMotionPdfController extends PdfViewerController {
  bool reducedMotion = false;
  @override
  Future<void> ensureVisible(
    Rect rect, {
    Duration duration = const Duration(milliseconds: 200),
    double margin = 0,
  }) => super.ensureVisible(
    rect,
    duration: reducedMotion ? Duration.zero : duration,
    margin: margin,
  );
}

final class _DocumentPdfCanvasState extends State<DocumentPdfCanvas> {
  final _controller = _DocumentMotionPdfController();
  double _controlsHeight = 0;
  late final _sizing = DocumentPdfSizing(() => _controlsHeight);
  late PdfDocumentRefData _documentReference;
  PdfTextSearcher? _searcher;
  final _query = TextEditingController();
  final _page = TextEditingController(text: '1');
  final _searchFocus = FocusNode();
  bool _searchOpen = false;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _documentReference = _createReference();
    _controller.addListener(_changed);
  }

  PdfDocumentRefData _createReference() => PdfDocumentRefData(
    Uint8List.fromList(widget.bytes),
    sourceName: widget.sourceName,
    key: PdfDocumentRefKey(widget.sourceName, [widget.bytes]),
    passwordProvider: () async => null,
  );

  @override
  void didUpdateWidget(DocumentPdfCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.sourceName != widget.sourceName) {
      _searcher?.removeListener(_changed);
      _searcher?.dispose();
      _searcher = null;
      _ready = false;
      _page.text = '1';
      _documentReference = _createReference();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.reducedMotion = MediaQuery.disableAnimationsOf(context);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher?.removeListener(_changed);
    _searcher?.dispose();
    _controller.removeListener(_changed);
    _query.dispose();
    _page.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);
  void _find() {
    setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
  }

  void _hideSearch() {
    setState(() => _searchOpen = false);
    _searcher?.startTextSearch('');
    if (_controller.isReady) _controller.requestFocus();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): _find,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _find,
      if (_searchOpen)
        const SingleActivator(LogicalKeyboardKey.escape): _hideSearch,
    },
    child: DocumentCanvasLayout(
      onControlsHeight: (height) => _controlsHeight = height,
      search: _searchOpen
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    key: const Key('pdfSearch'),
                    controller: _query,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      labelText: 'Find in PDF',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Close PDF search',
                        onPressed: _hideSearch,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    onChanged: (query) => _searcher?.startTextSearch(query),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        (_searcher?.isSearching ?? false)
                            ? 'Searching…'
                            : (_searcher?.matches.isEmpty ?? true)
                            ? 'No matches'
                            : '${(_searcher?.currentIndex ?? -1) + 1} of ${_searcher?.matches.length ?? 0} matches',
                      ),
                      IconButton(
                        tooltip: 'Previous PDF match',
                        onPressed: (_searcher?.matches.isEmpty ?? true)
                            ? null
                            : () {
                                unawaited(_searcher?.goToPrevMatch());
                                _changed();
                              },
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: 'Next PDF match',
                        onPressed: (_searcher?.matches.isEmpty ?? true)
                            ? null
                            : () {
                                unawaited(_searcher?.goToNextMatch());
                                _changed();
                              },
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      if (!(_searcher?.isSearching ?? false) &&
                          (_searcher?.matches.isEmpty ?? true) &&
                          _query.text.isNotEmpty)
                        TextButton(
                          onPressed: widget.onExtractedText,
                          child: const Text('Find in extracted text'),
                        ),
                    ],
                  ),
                ],
              ),
            )
          : null,
      canvas: PdfViewer(
        _documentReference,
        key: ValueKey(_documentReference),
        controller: _controller,
        params: PdfViewerParams(
          sizeDelegateProvider: _sizing,
          textSelectionParams: const PdfTextSelectionParams(
            magnifier: PdfViewerSelectionMagnifierParams(enabled: false),
          ),
          buildContextMenu: documentPdfSelectionMenuBuilder,
          underflowAnchor: PdfPageAnchor.topCenter,
          maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
          backgroundColor: AppSemanticColors.of(context).documentCanvas,
          onViewerReady: (_, _) {
            if (mounted) {
              unawaited(
                _controller.goTo(
                  _sizing.fit(_controller, 1),
                  duration: Duration.zero,
                ),
              );
              _searcher?.removeListener(_changed);
              _searcher?.dispose();
              _searcher = PdfTextSearcher(_controller)..addListener(_changed);
              setState(() => _ready = true);
            }
          },
          onPageChanged: (page) {
            if (mounted) {
              _page.text = '${page ?? 1}';
              setState(() {});
            }
          },
          pagePaintCallbacks: [
            if (_searcher case final searcher?)
              searcher.pageTextMatchPaintCallback,
          ],
          errorBannerBuilder: (context, error, stack, reference) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'This PDF could not be opened. It may be damaged or password protected.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: widget.onRetry,
                    child: const Text('Retry original'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      controls: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          IconButton(
            tooltip: 'Previous document page',
            onPressed: !_ready || (_controller.pageNumber ?? 1) <= 1
                ? null
                : () => _controller.goToPage(
                    pageNumber: _controller.pageNumber! - 1,
                    duration: _duration,
                  ),
            icon: const Icon(Icons.chevron_left),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              key: const Key('pdfPage'),
              controller: _page,
              enabled: _ready,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Page',
                contentPadding: EdgeInsets.all(8),
              ),
              onSubmitted: (value) {
                final number = int.tryParse(value);
                if (number != null &&
                    number >= 1 &&
                    number <= _controller.pageCount) {
                  _controller.goToPage(pageNumber: number, duration: _duration);
                } else {
                  _page.text = '${_controller.pageNumber ?? 1}';
                }
              },
            ),
          ),
          Text('of ${_ready ? _controller.pageCount : '…'}'),
          IconButton(
            tooltip: 'Next document page',
            onPressed:
                !_ready ||
                    (_controller.pageNumber ?? 1) >= _controller.pageCount
                ? null
                : () => _controller.goToPage(
                    pageNumber: (_controller.pageNumber ?? 1) + 1,
                    duration: _duration,
                  ),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: !_ready
                ? null
                : () => _controller.zoomDown(duration: _duration),
            icon: const Icon(Icons.remove),
          ),
          Text(_ready ? '${(_controller.currentZoom * 100).round()}%' : '—'),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: !_ready
                ? null
                : () => _controller.zoomUp(duration: _duration),
            icon: const Icon(Icons.add),
          ),
          TextButton(
            onPressed: !_ready
                ? null
                : () => _controller.goTo(
                    _sizing.fit(_controller, _controller.pageNumber ?? 1),
                    duration: _duration,
                  ),
            child: const Text('Fit'),
          ),
          IconButton(
            tooltip: 'Find in PDF',
            onPressed: !_ready ? null : _find,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    ),
  );
}

final class DocumentImageCanvas extends StatefulWidget {
  const DocumentImageCanvas({
    super.key,
    required this.bytes,
    required this.onRetry,
  });
  final Uint8List bytes;
  final VoidCallback onRetry;
  @override
  State<DocumentImageCanvas> createState() => _DocumentImageCanvasState();
}

final class _DocumentImageCanvasState extends State<DocumentImageCanvas> {
  final _transform = TransformationController();
  double _controlsHeight = 0;
  ui.Image? _image;
  String? _failureMessage;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(DocumentImageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) unawaited(_decode());
  }

  Future<void> _decode() async {
    final generation = ++_generation;
    try {
      final image = await decodeDocumentImage(widget.bytes, longestEdge: 4096);
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _image = image;
        _failureMessage = null;
      });
      old?.dispose();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _failureMessage =
              error is FormatException &&
                  error.message.contains('50 million pixels')
              ? 'This image exceeds the supported size of 50 million pixels.'
              : 'This image could not be opened.',
        );
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 8.0);
    _transform.value = Matrix4.identity()..scaleByDouble(next, next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_failureMessage case final message?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(message, textAlign: TextAlign.center),
            ),
            TextButton(
              onPressed: widget.onRetry,
              child: const Text('Retry original'),
            ),
          ],
        ),
      );
    }
    if (_image == null) return const Center(child: CircularProgressIndicator());
    return DocumentCanvasLayout(
      onControlsHeight: (height) => _controlsHeight = height,
      canvas: LayoutBuilder(
        builder: (context, constraints) => ClipRect(
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 8,
            child: SizedBox.expand(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, _controlsHeight + 16),
                child: RawImage(image: _image, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
      controls: ValueListenableBuilder<Matrix4>(
        valueListenable: _transform,
        builder: (context, value, child) => Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            const Text('Page 1 of 1'),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () => _zoom(1 / 1.25),
              icon: const Icon(Icons.remove),
            ),
            Text('${(value.getMaxScaleOnAxis() * 100).round()}%'),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () => _zoom(1.25),
              icon: const Icon(Icons.add),
            ),
            TextButton(
              onPressed: () => _transform.value = Matrix4.identity(),
              child: const Text('Fit'),
            ),
          ],
        ),
      ),
    );
  }
}
