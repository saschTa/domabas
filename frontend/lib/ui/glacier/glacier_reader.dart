import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_job_progress.dart';

import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';

final class GlacierReader extends StatelessWidget {
  const GlacierReader({
    super.key,
    required this.title,
    required this.contextLabel,
    required this.original,
    required this.inspector,
    required this.toolbar,
    this.text,
    this.textSelected = false,
    this.onViewChanged,
    this.onEdit,
    this.onResync,
    this.onDownload,
    this.onDelete,
    this.onClose,
    this.onBack,
    this.find,
    this.onFind,
    this.onCloseFind,
    this.headerActions,
    this.boundedHeader = false,
    this.showInspector = true,
    this.inspectorScrolls = true,
    this.compactInspectorBelow = true,
    this.inspectorBreakpoint = 720,
    this.inspectorPadding = const EdgeInsets.all(22),
  });
  final Widget? headerActions;
  final bool boundedHeader;
  final bool showInspector, inspectorScrolls, compactInspectorBelow;
  final double inspectorBreakpoint;
  final EdgeInsets inspectorPadding;
  final String title, contextLabel;
  final Widget original, inspector, toolbar;
  final Widget? text, find;
  final bool textSelected;
  final ValueChanged<bool>? onViewChanged;
  final VoidCallback? onEdit,
      onResync,
      onDownload,
      onDelete,
      onClose,
      onBack,
      onFind,
      onCloseFind;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): ?onFind,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): ?onFind,
      if (find != null && onCloseFind != null)
        const SingleActivator(LogicalKeyboardKey.escape): onCloseFind!,
    },
    child: Focus(
      autofocus: true,
      child: GlacierSurface(
        padding: EdgeInsets.zero,
        radius: 20,
        blur: false,
        child: Column(
          children: [
            if (boundedHeader)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .42,
                ),
                child: SingleChildScrollView(child: _header(context)),
              )
            else
              _header(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvas = ColoredBox(
                    color: GlacierTokens.of(context).preview,
                    child: Column(
                      children: [
                        Container(
                          color: GlacierTokens.of(context).solid
                              .withValues(alpha: .78),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: LayoutBuilder(
                            builder: (context, width) {
                              final viewSwitch = _ReaderViewSwitch(
                                hasText: text != null,
                                textSelected: textSelected,
                                onChanged: onViewChanged,
                              );
                              if (width.maxWidth >= 650) {
                                return Row(
                                  children: [
                                    viewSwitch,
                                    const SizedBox(width: 16),
                                    Expanded(child: toolbar),
                                  ],
                                );
                              }
                              return Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [viewSwitch, toolbar],
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: textSelected && text != null
                                    ? text!
                                    : original,
                              ),
                              if (find != null)
                                Positioned(
                                  top: 8,
                                  left: 12,
                                  right: 12,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 450,
                                      ),
                                      child: find!,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  final details = Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.copyWith(
                        titleMedium: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontSize: 14),
                        bodyMedium: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontSize: 13),
                      ),
                    ),
                    child: Padding(padding: inspectorPadding, child: inspector),
                  );
                  if (!showInspector ||
                      (!compactInspectorBelow &&
                          constraints.maxWidth < inspectorBreakpoint)) {
                    return canvas;
                  }
                  if (constraints.maxWidth < inspectorBreakpoint) {
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(height: 480, child: canvas),
                          details,
                        ],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: canvas),
                      SizedBox(
                        width: constraints.maxWidth < 1100 ? 300 : 350,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: GlacierTokens.of(context).border,
                              ),
                            ),
                          ),
                          child: inspectorScrolls
                              ? SingleChildScrollView(child: details)
                              : details,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: GlacierTokens.of(context).border),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Row(
          children: [
            if (onBack != null)
              GlacierIconButton(
                label: 'Back to invoice',
                icon: Icons.arrow_back,
                onPressed: onBack,
              ),
            if (onBack == null) ...[
              Icon(
                Icons.description_outlined,
                size: 22,
                color: GlacierTokens.of(context).muted,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 18, letterSpacing: -.45),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
        final actions =
            headerActions ??
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onEdit != null)
                  GlacierButton(
                    label: constraints.maxWidth < 500
                        ? 'Edit'
                        : 'Edit properties',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                if (onResync != null)
                  GlacierButton(
                    label: 'Resync',
                    icon: Icons.sync,
                    onPressed: onResync,
                  ),
                if (onDownload != null)
                  GlacierIconButton(
                    label: 'Download original',
                    icon: Icons.file_download_outlined,
                    onPressed: onDownload,
                  ),
                if (onDelete != null)
                  GlacierIconButton(
                    label: 'Delete document',
                    icon: Icons.delete_outline,
                    onPressed: onDelete,
                  ),
                GlacierIconButton(
                  label: 'Close document',
                  icon: Icons.close,
                  onPressed: onClose,
                ),
              ],
            );
        return constraints.maxWidth < 850
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 12), actions],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  actions,
                ],
              );
      },
    ),
  );
}

final class _ReaderViewSwitch extends StatelessWidget {
  const _ReaderViewSwitch({
    required this.hasText,
    required this.textSelected,
    this.onChanged,
  });
  final bool hasText, textSelected;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: GlacierTokens.of(context).muted.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Wrap(
        children: [
          for (final value in [false, if (hasText) true])
            Semantics(
              selected: value == textSelected,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  backgroundColor: value == textSelected
                      ? GlacierTokens.of(context).solid
                      : Colors.transparent,
                  foregroundColor: value == textSelected
                      ? Theme.of(context).colorScheme.onSurface
                      : GlacierTokens.of(context).muted,
                  textStyle: const TextStyle(fontSize: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: onChanged == null ? null : () => onChanged!(value),
                child: Text(value ? 'Text' : 'Original'),
              ),
            ),
        ],
      ),
    ),
  );
}

final class GlacierPdfToolbar extends StatelessWidget {
  const GlacierPdfToolbar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.zoomLabel,
    this.onPrevious,
    this.onNext,
    this.onZoomOut,
    this.onZoomIn,
    this.onFit,
    this.onFind,
    this.onPageChanged,
  });
  final int page, pageCount;
  final String zoomLabel;
  final VoidCallback? onPrevious, onNext, onZoomOut, onZoomIn, onFit, onFind;
  final ValueChanged<int>? onPageChanged;
  @override
  Widget build(BuildContext context) => IconButtonTheme(
    data: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        maximumSize: const Size(36, 36),
        padding: const EdgeInsets.all(6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pages = Wrap(
            spacing: 2,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GlacierIconButton(
                label: 'Previous page',
                icon: Icons.chevron_left,
                onPressed: page > 1 ? onPrevious : null,
              ),
              _GlacierPageField(
                page: page,
                pageCount: pageCount,
                onChanged: onPageChanged,
              ),
              Text('/ $pageCount', semanticsLabel: 'of $pageCount pages'),
              GlacierIconButton(
                label: 'Next page',
                icon: Icons.chevron_right,
                onPressed: page < pageCount ? onNext : null,
              ),
            ],
          );
          final zoom = Wrap(
            spacing: 2,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GlacierIconButton(
                label: 'Zoom out',
                icon: Icons.remove,
                onPressed: onZoomOut,
              ),
              Text(zoomLabel),
              GlacierIconButton(
                label: 'Zoom in',
                icon: Icons.add,
                onPressed: onZoomIn,
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: onFit,
                child: const Text('Fit'),
              ),
              GlacierIconButton(
                label: 'Find in document',
                icon: Icons.search,
                onPressed: onFind,
              ),
            ],
          );
          return constraints.maxWidth >= 480
              ? Row(children: [pages, const Spacer(), zoom])
              : Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [pages, zoom],
                );
        },
      ),
    ),
  );
}

final class GlacierFindBar extends StatelessWidget {
  const GlacierFindBar({
    super.key,
    required this.controller,
    required this.resultLabel,
    this.onSubmitted,
    this.onChanged,
    this.onPrevious,
    this.onNext,
    this.onClose,
    this.searching = false,
    this.fieldKey,
    this.focusNode,
    this.autofocus = true,
    this.hint = 'Find in document',
    this.previousLabel = 'Previous match',
    this.nextLabel = 'Next match',
    this.closeLabel = 'Close find',
  });
  final TextEditingController controller;
  final String resultLabel, hint, previousLabel, nextLabel, closeLabel;
  final ValueChanged<String>? onSubmitted, onChanged;
  final VoidCallback? onPrevious, onNext, onClose;
  final bool searching, autofocus;
  final Key? fieldKey;
  final FocusNode? focusNode;
  Widget _field(BuildContext context) => TextField(
    key: fieldKey,
    focusNode: focusNode,
    controller: controller,
    autofocus: autofocus,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      filled: false,
      hintText: hint,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
  List<Widget> _actions(BuildContext context) => [
    if (searching)
      const AppJobSpinner(label: 'Finding matches')
    else
      Semantics(
        liveRegion: true,
        child: Text(resultLabel, style: Theme.of(context).textTheme.labelSmall),
      ),
    GlacierIconButton(
      label: previousLabel,
      icon: Icons.keyboard_arrow_up,
      onPressed: onPrevious,
    ),
    GlacierIconButton(
      label: nextLabel,
      icon: Icons.keyboard_arrow_down,
      onPressed: onNext,
    ),
  ];
  @override
  Widget build(BuildContext context) => GlacierSurface(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    radius: 11,
    child: LayoutBuilder(
      builder: (context, width) {
        final close = onClose == null
            ? const SizedBox.shrink()
            : GlacierIconButton(
                label: closeLabel,
                icon: Icons.close,
                onPressed: onClose,
              );
        final input = Row(
          children: [
            const Icon(Icons.search, size: 18),
            const SizedBox(width: 8),
            Expanded(child: _field(context)),
            close,
          ],
        );
        if (width.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              input,
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _actions(context),
              ),
            ],
          );
        }
        return Row(
          children: [
            const Icon(Icons.search, size: 18),
            const SizedBox(width: 8),
            Expanded(child: _field(context)),
            ..._actions(context),
            close,
          ],
        );
      },
    ),
  );
}

final class GlacierOriginalState extends StatelessWidget {
  const GlacierOriginalState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.description_outlined,
    this.action,
    this.child,
  });
  final String title, message;
  final IconData icon;
  final Widget? action, child;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (child != null)
              Padding(padding: const EdgeInsets.only(top: 20), child: child),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 20), child: action),
          ],
        ),
      ),
    ),
  );
}

final class GlacierExtractedText extends StatelessWidget {
  const GlacierExtractedText({
    super.key,
    required this.text,
    required this.revisionLabel,
    this.onEdit,
    this.feedback,
  });
  final String text, revisionLabel;
  final VoidCallback? onEdit;
  final Widget? feedback;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(revisionLabel, style: Theme.of(context).textTheme.titleSmall),
            if (onEdit != null)
              GlacierButton(
                label: 'Edit text',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Searchable text, separate from the original.'),
        if (feedback != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: feedback,
          ),
        const SizedBox(height: 20),
        SelectableText(text.isEmpty ? 'No extracted text is available.' : text),
      ],
    ),
  );
}

final class _GlacierPageField extends StatefulWidget {
  const _GlacierPageField({
    required this.page,
    required this.pageCount,
    this.onChanged,
  });
  final int page, pageCount;
  final ValueChanged<int>? onChanged;
  @override
  State<_GlacierPageField> createState() => _GlacierPageFieldState();
}

final class _GlacierPageFieldState extends State<_GlacierPageField> {
  late final controller = TextEditingController(text: '${widget.page}');
  String? error;
  @override
  void didUpdateWidget(_GlacierPageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.pageCount != widget.pageCount) {
      controller.text = '${widget.page}';
      error = null;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: error == null ? 44 : 150,
    child: TextField(
      controller: controller,
      enabled: widget.onChanged != null && widget.pageCount > 0,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        hintText: 'Page',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        errorText: error,
      ),
      onSubmitted: (value) {
        final page = int.tryParse(value);
        if (page == null || page < 1 || page > widget.pageCount) {
          setState(() {
            error = 'Choose 1–${widget.pageCount}';
            controller.text = '${widget.page}';
          });
          return;
        }
        setState(() => error = null);
        widget.onChanged?.call(page);
      },
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    ),
  );
}
