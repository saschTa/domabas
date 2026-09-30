import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/scanner/models/scan.dart';
import '../../../ui/domabas_ui.dart';
import '../cubits/scanner_cubit.dart';
import '../widgets/scan_frame.dart';
import '../widgets/scan_image.dart';
import '../widgets/scan_properties_form.dart';

enum ScannerExit { saved, discarded, accepted, checkLibrary }

final class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.cubit,
    required this.previewBuilder,
    required this.canReadDocuments,
    this.appearanceAction,
  });
  final ScannerCubit cubit;
  final WidgetBuilder previewBuilder;
  final bool canReadDocuments;
  final Widget? appearanceAction;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

final class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  bool _leaving = false;
  bool _canPop = false;
  int _selectedCorner = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.cubit.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.cubit.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(widget.cubit.setForeground(state == AppLifecycleState.resumed));
  }

  void _finish(ScannerExit result) {
    if (!mounted || _canPop) return;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route == null || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop(result);
      } else {
        navigator.removeRoute(route, result);
      }
    });
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _leave({bool checkLibrary = false}) async {
    if (_leaving || _canPop) return;
    _leaving = true;
    try {
      final state = widget.cubit.state;
      if (state.capture != null || state.busy) {
        final confirmed = await _confirm(
          'Leave this scan?',
          state.busy
              ? 'Saved pages are retained. If an upload is in progress, it may have reached the library. Check the library before retrying.'
              : 'The page being corrected has not been kept. Leaving removes this capture; your kept pages and properties remain saved.',
          'Leave scan',
        );
        if (!mounted || !confirmed) return;
      }
      if (state.dirty && !await widget.cubit.flushProperties()) return;
      if (!mounted) return;
      _finish(
        checkLibrary
            ? ScannerExit.checkLibrary
            : widget.cubit.state.draft?.status == ScanDraftStatus.accepted
            ? ScannerExit.accepted
            : ScannerExit.saved,
      );
    } finally {
      _leaving = false;
    }
  }

  Future<void> _back() async {
    final state = widget.cubit.state;
    if (state.stage == ScannerStage.camera && !state.busy) {
      await widget.cubit.showReview();
    } else {
      await _leave();
    }
  }

  Future<void> _discard() async {
    if (!await _confirm(
          'Discard this scan?',
          'This removes the local draft and its scanned pages. An upload that already reached the library will remain there.',
          'Discard scan',
        ) ||
        !mounted) {
      return;
    }
    if (await widget.cubit.discard() && mounted) _finish(ScannerExit.discarded);
  }

  Future<void> _retry() async {
    if (await _confirm(
          'Retry the same upload?',
          'The earlier upload may already be in the library. This sends the exact saved PDF and properties again. Check the library first when possible.',
          'Retry upload',
        ) &&
        mounted) {
      await widget.cubit.retryUpload();
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ScannerCubit, ScannerState>(
    bloc: widget.cubit,
    builder: (context, state) => PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('closeScanner'),
            tooltip: 'Leave scan',
            onPressed: () => unawaited(_leave()),
            icon: const Icon(Icons.close),
          ),
          title: Text(switch (state.stage) {
            ScannerStage.camera => 'Scan a page',
            ScannerStage.correction => 'Adjust page corners',
            ScannerStage.review => 'Scan document',
          }),
          actions: [?widget.appearanceAction],
        ),
        body: AppPaperCanvas(child: SafeArea(child: _body(context, state))),
        bottomNavigationBar: state.stage == ScannerStage.review
            ? null
            : SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: state.stage == ScannerStage.camera
                        ? _cameraActions(state)
                        : _correctionActions(state),
                  ),
                ),
              ),
      ),
    ),
  );

  Widget _body(BuildContext context, ScannerState state) {
    if (state.loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Restoring scan'),
      );
    }
    if (state.draft == null) {
      return AppEmptyState(
        icon: Icons.document_scanner_outlined,
        title: 'Scanner could not open',
        message: state.error ?? 'This scanner is unavailable.',
        action: widget.cubit.allowed
            ? OutlinedButton(
                onPressed: widget.cubit.restore,
                child: const Text('Retry'),
              )
            : null,
      );
    }
    if (state.stage == ScannerStage.camera) return _camera(context, state);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: ValueKey(state.stage),
            padding: const EdgeInsets.all(16),
            children: [
              if (state.busy) ...[
                const AppStripedProgressIndicator(
                  semanticsLabel: 'Processing scan',
                ),
                if (state.submitting)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('cancelScanUpload'),
                      onPressed: widget.cubit.cancelUpload,
                      child: const Text('Cancel upload'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (state.error case final error?) ...[
                AppNotice(
                  message: error,
                  action: state.dirty && !state.busy
                      ? TextButton(
                          onPressed: widget.cubit.flushProperties,
                          child: const Text('Retry saving'),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              switch (state.stage) {
                ScannerStage.camera => const SizedBox.shrink(),
                ScannerStage.correction => _correction(
                  context,
                  state,
                  (constraints.maxHeight * .65).clamp(96, 420),
                ),
                ScannerStage.review => _review(context, state),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _camera(BuildContext context, ScannerState state) {
    final ready = state.camera.status == ScanCameraStatus.ready;
    final taking = state.camera.status == ScanCameraStatus.capturing;
    final processing = state.camera.status == ScanCameraStatus.processing;
    final hasPreview = ready || taking || processing;
    const instructions = [
      'Keep the whole page in view. Adjust corners after capture.',
      'Capturing… Hold steady.',
      'Photo captured. Preparing page…',
    ];
    final instructionIndex = taking
        ? 1
        : processing
        ? 2
        : 0;
    final guidance = instructions[instructionIndex];
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .25),
            child: SingleChildScrollView(
              key: const Key('scanCameraGuidance'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: IndexedStack(
                      index: instructionIndex,
                      children: [
                        for (final instruction in instructions)
                          Text(instruction),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 4,
                    child: state.busy
                        ? AppStripedProgressIndicator(semanticsLabel: guidance)
                        : null,
                  ),
                  if (state.error case final error?) ...[
                    const SizedBox(height: 8),
                    AppNotice(message: error),
                  ],
                  if (state.camera.message case final message? when ready) ...[
                    const SizedBox(height: 8),
                    AppNotice(message: message, tone: AppTone.warning),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              key: const Key('scanCameraViewport'),
              color: Colors.black,
              child: hasPreview
                  ? ScanFrame(
                      width: state.camera.width,
                      height: state.camera.height,
                      corners: ready ? state.camera.corners : null,
                      inset: 0,
                      child: widget.previewBuilder(context),
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: AppSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                switch (state.camera.status) {
                                  ScanCameraStatus.denied =>
                                    'Camera permission needed',
                                  ScanCameraStatus.unavailable =>
                                    'Camera unavailable',
                                  ScanCameraStatus.starting =>
                                    'Opening camera…',
                                  ScanCameraStatus.suspended => 'Camera paused',
                                  _ => 'Camera is not ready',
                                },
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                state.camera.message ?? 'Resume the app or try opening the camera again. Your saved pages are retained.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraActions(ScannerState state) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        key: const Key('captureScanPage'),
        onPressed: state.camera.status == ScanCameraStatus.ready && !state.busy
            ? widget.cubit.capture
            : null,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Capture page'),
      ),
      if (state.camera.status != ScanCameraStatus.ready &&
          !state.busy &&
          state.camera.status != ScanCameraStatus.starting)
        OutlinedButton(
          onPressed: widget.cubit.addPage,
          child: const Text('Open camera'),
        ),
      TextButton(
        onPressed: state.busy ? null : widget.cubit.showReview,
        child: const Text('Review scan'),
      ),
    ],
  );

  Widget _correction(
    BuildContext context,
    ScannerState state,
    double previewHeight,
  ) {
    final capture = state.capture!;
    final point = state.corners!.points[_selectedCorner];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Drag the numbered corners to the page edges, or use the corner controls below. Keep the corners in order without crossing edges.',
        ),
        SizedBox(
          height: previewHeight,
          child: ScanFrame(
            width: capture.width,
            height: capture.height,
            corners: state.corners,
            selected: _selectedCorner,
            onSelect: (index) => setState(() => _selectedCorner = index),
            onMove: state.editable ? widget.cubit.moveCorner : null,
            child: ScanImage(
              bytes: capture.preview,
              fit: BoxFit.contain,
              semanticLabel: 'Captured page before perspective correction',
              errorBuilder: (_, _, _) => const Center(
                child: Text('Preview unavailable. Retake this page.'),
              ),
            ),
          ),
        ),
        if (!state.validCorners) ...[
          const AppNotice(
            message: 'Choose four corners around the page without crossing edges. The selection must cover at least 1% of the image.',
          ),
          const SizedBox(height: 12),
        ],
        AppSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey(_selectedCorner),
                initialValue: _selectedCorner,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Corner controls'),
                items: [
                  for (var i = 0; i < 4; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('${i + 1}. ${ScanFrame.cornerNames[i]}'),
                    ),
                ],
                onChanged: state.editable
                    ? (value) => setState(() => _selectedCorner = value!)
                    : null,
              ),
              const SizedBox(height: 16),
              Text('Horizontal: ${(point.x * 100).round()}%'),
              Slider(
                key: const Key('scanCornerHorizontal'),
                value: point.x,
                divisions: 100,
                semanticFormatterCallback: (value) =>
                    '${ScanFrame.cornerNames[_selectedCorner]} horizontal ${(value * 100).round()} percent',
                onChanged: state.editable
                    ? (value) => widget.cubit.moveCorner(
                        _selectedCorner,
                        ScanPoint(value, point.y),
                      )
                    : null,
              ),
              Text('Vertical: ${(point.y * 100).round()}%'),
              Slider(
                key: const Key('scanCornerVertical'),
                value: point.y,
                divisions: 100,
                semanticFormatterCallback: (value) =>
                    '${ScanFrame.cornerNames[_selectedCorner]} vertical ${(value * 100).round()} percent',
                onChanged: state.editable
                    ? (value) => widget.cubit.moveCorner(
                        _selectedCorner,
                        ScanPoint(point.x, value),
                      )
                    : null,
              ),
              TextButton(
                onPressed: state.editable ? widget.cubit.resetCorners : null,
                child: const Text('Use whole image'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _correctionActions(ScannerState state) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        key: const Key('keepScanPage'),
        onPressed: state.editable && state.validCorners
            ? widget.cubit.keepPage
            : null,
        icon: const Icon(Icons.check),
        label: const Text('Keep page'),
      ),
      OutlinedButton(
        onPressed: state.editable ? widget.cubit.retake : null,
        child: const Text('Retake page'),
      ),
    ],
  );

  Widget _review(BuildContext context, ScannerState state) {
    final draft = state.draft!;
    if (draft.status == ScanDraftStatus.accepted) {
      return AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Scan uploaded',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Your PDF was accepted into this library.'),
            if (draft.cleanupPending) ...[
              const SizedBox(height: 12),
              AppNotice(
                message: draft.message ?? 'The upload succeeded. Some local scan files still need cleanup.',
                tone: AppTone.warning,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state.busy ? null : widget.cubit.retryCleanup,
                child: const Text('Retry local cleanup'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(_leave()),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!draft.editable) ...[
          AppNotice(
            tone: AppTone.warning,
            message:
                draft.message ??
                switch (draft.status) {
                  ScanDraftStatus.uncertain => 'The upload could not be confirmed. This draft is read-only because the saved upload may already be in the library.',
                  ScanDraftStatus.duplicate => 'This PDF is already in the library. The local scan is retained until you discard it.',
                  _ => 'The saved scan needs recovery. You can discard its local files to start again.',
                },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (widget.canReadDocuments)
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => unawaited(_leave(checkLibrary: true)),
                  child: const Text('Check library'),
                ),
              if (draft.status == ScanDraftStatus.uncertain)
                FilledButton(
                  onPressed: state.busy ? null : _retry,
                  child: const Text('Retry same upload'),
                ),
              OutlinedButton(
                onPressed: state.busy ? null : _discard,
                child: const Text('Discard scan'),
              ),
            ],
          ),
          if (!widget.canReadDocuments) ...[
            const SizedBox(height: 12),
            const Text(
              'You can upload to this library, but cannot view its documents. Ask someone with library access to check the earlier upload.',
            ),
          ],
          const SizedBox(height: 24),
        ],
        Text(
          'Pages · ${draft.pages.length}/20',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          draft.editable
              ? 'Pages are combined into one PDF in the order shown. Use the arrows to change their order.'
              : 'Pages are combined into one PDF in the order shown.',
        ),
        const SizedBox(height: 12),
        if (draft.pages.isEmpty)
          const AppSurface(
            padding: EdgeInsets.all(20),
            child: Text('Add your first page to begin.'),
          ),
        for (var index = 0; index < draft.pages.length; index++) ...[
          _page(context, draft.pages[index], index, state),
          const SizedBox(height: 8),
        ],
        if (draft.editable) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('addScanPage'),
              onPressed: state.editable && draft.pages.length < 20
                  ? widget.cubit.addPage
                  : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(draft.pages.isEmpty ? 'Add first page' : 'Add page'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Document properties',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (draft.editable)
          Semantics(
            liveRegion: true,
            child: Text(
              state.saving
                  ? 'Saving on this device…'
                  : state.dirty
                  ? 'Changes have not been saved.'
                  : 'Saved on this device.',
              key: const Key('scanSaveStatus'),
            ),
          ),
        const SizedBox(height: 16),
        ScanPropertiesForm(
          key: ValueKey(draft.id),
          properties: state.properties!,
          enabled: state.editable,
          errors: state.validation,
          validationAttempt: state.validationAttempt,
          onChanged: widget.cubit.setProperties,
        ),
        if (draft.editable) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const Key('uploadScan'),
                onPressed: state.editable && draft.pages.isNotEmpty
                    ? widget.cubit.submit
                    : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  state.busy ? 'Preparing / uploading…' : 'Upload PDF',
                ),
              ),
              OutlinedButton(
                onPressed: state.busy ? null : () => unawaited(_leave()),
                child: const Text('Save and close'),
              ),
              TextButton(
                onPressed: state.busy ? null : _discard,
                child: const Text('Discard scan'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _page(
    BuildContext context,
    ScanPage page,
    int index,
    ScannerState state,
  ) => AppSurface(
    key: ValueKey(page.id),
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final preview = Row(
          children: [
            SizedBox(
              width: 64,
              height: 80,
              child: ScanImage(
                bytes: page.thumbnail,
                fit: BoxFit.contain,
                semanticLabel: 'Page ${index + 1} preview',
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Page ${index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 4,
          children: [
            IconButton(
              key: Key('moveScanPageEarlier-$index'),
              tooltip: 'Move page ${index + 1} earlier',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: state.editable && index > 0
                  ? () => widget.cubit.movePage(page.id, index - 1)
                  : null,
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              key: Key('moveScanPageLater-$index'),
              tooltip: 'Move page ${index + 1} later',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: state.editable && index < state.draft!.pages.length - 1
                  ? () => widget.cubit.movePage(page.id, index + 1)
                  : null,
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              key: Key('removeScanPage-$index'),
              tooltip: 'Remove page ${index + 1}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: state.editable
                  ? () => widget.cubit.removePage(page.id)
                  : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preview,
              if (state.draft!.editable) ...[
                const SizedBox(height: 8),
                actions,
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: preview),
            if (state.draft!.editable) actions,
          ],
        );
      },
    ),
  );
}
