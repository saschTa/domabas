import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_job_progress.dart';
import 'glacier_controls.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';
import 'glacier_native_values.dart';
import 'glacier_workspace_geometry.dart';

@immutable
class GlacierActivityJob {
  const GlacierActivityJob({
    required this.id,
    required this.title,
    required this.status,
    this.stage,
    this.library,
    this.progress,
    this.running = false,
    this.failed = false,
    this.terminal = false,
    this.onOpen,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));
  final String id, title, status;
  final String? stage, library;
  final double? progress;
  final bool running, failed, terminal;
  final VoidCallback? onOpen;
}

@immutable
class GlacierActivitySummary {
  const GlacierActivitySummary({
    required this.title,
    required this.detail,
    this.count,
    this.running = false,
    this.visible = true,
  });
  final String title, detail;
  final int? count;
  final bool running, visible;
}

class GlacierActivityDock extends StatefulWidget {
  const GlacierActivityDock({
    super.key,
    required this.jobs,
    required this.onOpenActivity,
    this.breakdown,
    this.summary,
    this.continuationLabel,
    this.truncated = false,
    this.stale = false,
    this.refreshError,
    this.onRetryRefresh,
    this.onDismissReceipt,
    this.compact = false,
  });
  final List<GlacierActivityJob> jobs;
  final GlacierActivitySummary? summary;
  final String? continuationLabel;
  final VoidCallback onOpenActivity;
  final String? breakdown, refreshError;
  final bool truncated, stale, compact;
  final VoidCallback? onRetryRefresh, onDismissReceipt;
  bool get isVisible =>
      summary?.visible ?? (jobs.isNotEmpty || refreshError != null);
  @override
  State<GlacierActivityDock> createState() => _GlacierActivityDockState();
}

class _GlacierActivityDockState extends State<GlacierActivityDock>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _tokenFocus = FocusNode();
  final _tapGroup = Object();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  bool _open = false,
      _pinned = false,
      _tokenHovered = false,
      _panelHovered = false,
      _focused = false,
      _suppressFocus = false;
  int _hoverRequest = 0;
  double _reportedPanelExtent = 0;
  void _reportPanelExtent(double extent) {
    if ((_reportedPanelExtent - extent).abs() < .5) return;
    _reportedPanelExtent = extent;
    final geometry = GlacierWorkspaceGeometry.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) geometry?.onActivityPanelExtentChanged(extent);
    });
  }

  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
  bool get _compact =>
      widget.compact ||
      MediaQuery.sizeOf(context).width < 700 ||
      MediaQuery.sizeOf(context).height < 360;
  double get _panelMaximum {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    final geometry = GlacierWorkspaceGeometry.maybeOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final measured = geometry?.endActionsHeight ?? 0;
    final lane = (measured > 64 * scale ? measured : 64 * scale) + 16;
    return (box.localToGlobal(Offset.zero).dy -
            (geometry?.overlayMinimumTop ?? 16) -
            lane -
            8)
        .clamp(0.0, 420.0);
  }

  bool get _canUsePanel =>
      !_compact &&
      _panelMaximum >= 196 * MediaQuery.textScalerOf(context).scale(1);
  int? get _count =>
      widget.summary == null ? widget.jobs.length : widget.summary!.count;
  String get _title {
    if (widget.summary != null) return widget.summary!.title;
    if (widget.jobs.isEmpty) return 'Activity unavailable';
    if (widget.jobs.length == 1 && !widget.truncated) {
      return widget.jobs.first.title;
    }
    final noun = widget.jobs.every((job) => !job.terminal)
        ? 'active jobs'
        : 'recent jobs';
    return '${widget.jobs.length}${widget.truncated ? '+' : ''} $noun';
  }

  String get _subtitle =>
      widget.summary?.detail ??
      (widget.refreshError != null
          ? 'Updates unavailable'
          : widget.stale
          ? 'Last known activity · updates paused'
          : widget.jobs.length == 1
          ? (widget.jobs.first.terminal
                ? widget.jobs.first.status
                : widget.jobs.first.stage ?? widget.jobs.first.status)
          : (widget.breakdown ?? 'Latest recorded activity'));
  void _show() {
    if (_open || !widget.isVisible || !_canUsePanel) return;
    setState(() => _open = true);
    _portal.show();
    _animation.forward(from: _reduced ? 1 : 0);
  }

  void _close({bool returnFocus = false, bool immediate = false}) {
    _hoverRequest++;
    _suppressFocus = true;
    if (mounted) {
      setState(() {
        _open = false;
        _pinned = false;
      });
    }
    if (_reduced || immediate) {
      _animation.value = 0;
      _portal.hide();
      _reportPanelExtent(0);
    } else {
      _animation.reverse().then((_) {
        if (mounted && !_open) {
          _portal.hide();
          _reportPanelExtent(0);
        }
      });
    }
    if (returnFocus) _tokenFocus.requestFocus();
  }

  void _hover({required bool token, required bool entered}) {
    if (token) {
      _tokenHovered = entered;
    } else {
      _panelHovered = entered;
    }
    final request = ++_hoverRequest;
    if (entered) _suppressFocus = false;
    Future<void>.delayed(Duration(milliseconds: entered ? 120 : 160), () {
      if (!mounted || request != _hoverRequest) return;
      if (_tokenHovered || _panelHovered) {
        _show();
      } else if (!_pinned && !_focused) {
        _close();
      }
    });
  }

  void _toggle() {
    _tokenFocus.requestFocus();
    if (!_canUsePanel) {
      if (_open) _close();
      widget.onOpenActivity();
      return;
    }
    if (_pinned) {
      _close(returnFocus: true);
    } else {
      setState(() => _pinned = true);
      _show();
    }
  }

  @override
  void didUpdateWidget(covariant GlacierActivityDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVisible && _open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  @override
  void dispose() {
    _hoverRequest++;
    _animation.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  Widget _mark(BuildContext context, GlacierActivityJob? job) =>
      widget.stale || widget.refreshError != null
      ? Icon(
          Icons.cloud_off_outlined,
          size: 18,
          color: GlacierTokens.of(context).muted,
        )
      : (widget.summary?.running ?? job?.running) == true
      ? const ExcludeSemantics(child: AppJobSpinner())
      : Icon(
          job?.failed == true
              ? Icons.error_outline
              : job?.terminal == true
              ? Icons.check_circle_outline
              : Icons.schedule,
          size: 18,
          color: job?.failed == true
              ? Theme.of(context).colorScheme.error
              : GlacierTokens.of(context).accent,
        );

  Widget _token(BuildContext context) {
    final multiple = (_count ?? widget.jobs.length) > 1 || widget.truncated;
    final token = GlacierSurface(
      radius: 13,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('activity-dock-token'),
          focusNode: _tokenFocus,
          borderRadius: BorderRadius.circular(13),
          onTap: _toggle,
          child: Semantics(
            expanded: _canUsePanel ? _open : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: _compact
                    ? 48
                    : multiple
                    ? 60
                    : 48,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _compact ? 14 : 12,
                  vertical: 8,
                ),
                child: _compact
                    ? Center(child: _mark(context, widget.jobs.firstOrNull))
                    : Row(
                        children: [
                          _mark(context, widget.jobs.firstOrNull),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: GlacierTokens.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _open ? Icons.expand_more : Icons.expand_less,
                            size: 18,
                            color: GlacierTokens.of(context).muted,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: _compact ? '$_title · $_subtitle' : '',
      child: AnimatedSize(
        alignment: Alignment.bottomRight,
        duration: _reduced ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: _compact ? 48 : 280,
          child: Stack(
            children: [
              if (multiple && !_compact)
                Positioned(
                  top: 0,
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: GlacierTokens.of(context).glass,
                      border: Border.all(color: GlacierTokens.of(context).edge),
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(top: multiple && !_compact ? 6 : 0),
                child: token,
              ),
              if (_compact &&
                  (_count ?? 0) > 1 &&
                  (widget.summary != null ||
                      GlacierNativePresentationScope.maybeOf(context) != null))
                Positioned(
                  right: 3,
                  top: 3,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 14),
                        height: 14,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '$_count',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, double height) => GlacierSurface(
    radius: 16,
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Your activity',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              GlacierIconButton(
                label: 'Close activity preview',
                icon: Icons.close,
                onPressed: () => _close(returnFocus: true),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.summary != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      widget.summary!.detail,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (widget.stale || widget.refreshError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.refreshError ??
                              'Updates paused. Showing last known activity.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (widget.onRetryRefresh != null)
                          GlacierButton(
                            label: 'Check updates',
                            kind: GlacierButtonKind.quiet,
                            onPressed: widget.onRetryRefresh,
                          ),
                      ],
                    ),
                  ),
                AnimatedSwitcher(
                  duration: _reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  child: Column(
                    key: ValueKey(widget.jobs.map((job) => job.id).join('/')),
                    children: [
                      for (final job in widget.jobs)
                        _GlacierDockJobRow(
                          key: ValueKey(job.id),
                          job: job,
                          stale: widget.stale || widget.refreshError != null,
                          onOpen: job.onOpen == null
                              ? null
                              : () {
                                  _close(returnFocus: true);
                                  job.onOpen!();
                                },
                        ),
                    ],
                  ),
                ),
                if (widget.truncated)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      widget.continuationLabel ?? 'Only loaded activity is shown. More jobs may be running.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              GlacierButton(
                label: 'View all activity',
                kind: GlacierButtonKind.quiet,
                onPressed: () {
                  _close(returnFocus: true);
                  widget.onOpenActivity();
                },
              ),
              if (widget.onDismissReceipt != null &&
                  widget.jobs.every((job) => job.terminal))
                GlacierButton(
                  label: 'Dismiss receipt',
                  kind: GlacierButtonKind.quiet,
                  onPressed: () {
                    _close();
                    widget.onDismissReceipt!();
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) {
        if (_open) _close();
      },
      child: Focus(
        onFocusChange: (focused) {
          _focused = focused;
          if (focused && !_suppressFocus) {
            _show();
          } else if (!focused) {
            _suppressFocus = false;
            if (!_pinned && !_tokenHovered && !_panelHovered) _close();
          }
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _close(returnFocus: true),
          },
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _portal,
            overlayLocation:
                GlacierNativePresentationScope.maybeOf(context) == null
                ? OverlayChildLocation.rootOverlay
                : OverlayChildLocation.nearestOverlay,
            overlayChildBuilder: (context, info) {
              final anchor = MatrixUtils.transformRect(
                info.childPaintTransform,
                Offset.zero & info.childSize,
              );
              final width = 320.0.clamp(0.0, info.overlaySize.width - 32);
              final maximum = _panelMaximum;
              if (!_canUsePanel) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _open) {
                    _close(
                      returnFocus: _focused && !_tokenFocus.hasFocus,
                      immediate: true,
                    );
                  }
                });
                return const SizedBox.shrink();
              }
              final height =
                  ((widget.jobs.length * 88.0 +
                              112 +
                              (widget.stale || widget.refreshError != null
                                  ? 72
                                  : 0)) *
                          MediaQuery.textScalerOf(context).scale(1))
                      .clamp(0.0, maximum);
              _reportPanelExtent(height + 8);
              return Positioned(
                left: (anchor.right - width).clamp(
                  16.0,
                  info.overlaySize.width - width - 16,
                ),
                top: (anchor.top - height - 8).clamp(
                  16.0,
                  info.overlaySize.height - height - 16,
                ),
                width: width,
                height: height,
                child: TapRegion(
                  groupId: _tapGroup,
                  child: MouseRegion(
                    onEnter: (_) => _hover(token: false, entered: true),
                    onExit: (_) => _hover(token: false, entered: false),
                    child: FadeTransition(
                      opacity: _animation,
                      child: SlideTransition(
                        position:
                            Tween(
                              begin: const Offset(0, .035),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: _panel(context, height),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: MouseRegion(
              onEnter: (_) => _hover(token: true, entered: true),
              onExit: (_) => _hover(token: true, entered: false),
              child: _token(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlacierDockJobRow extends StatelessWidget {
  const _GlacierDockJobRow({
    super.key,
    required this.job,
    required this.stale,
    this.onOpen,
  });
  final GlacierActivityJob job;
  final bool stale;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: GlacierTokens.of(context).border),
      ),
    ),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (job.library != null)
                    Text(
                      job.library!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    job.stage == null
                        ? job.status
                        : '${job.status} · ${job.stage}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onOpen != null)
              GlacierIconButton(
                label: 'Open ${job.title}',
                icon: Icons.chevron_right,
                onPressed: onOpen,
              ),
          ],
        ),
        if (job.progress != null) ...[
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: job.progress, end: job.progress),
            duration: stale || MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 2,
              semanticsLabel: '${job.title} recorded progress',
              semanticsValue: '${(job.progress! * 100).round()}%',
            ),
          ),
        ],
      ],
    ),
  );
}
