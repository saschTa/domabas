import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'glacier_native_values.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';

class GlacierNativeFrame extends StatefulWidget {
  const GlacierNativeFrame({
    super.key,
    required this.state,
    required this.commands,
    required this.child,
    this.feedback,
    this.contentNavigatorKey,
    this.contentModalOpen = false,
    this.layoutRevision = 0,
    this.windowOverlay,
    this.initialDrawerOpen = false,
  });
  final GlacierNativeWindowState state;
  final GlacierNativeWindowCommands commands;
  final Widget child;
  final Widget? windowOverlay;
  final String? feedback;
  final GlobalKey<NavigatorState>? contentNavigatorKey;
  final bool contentModalOpen;
  final int layoutRevision;
  final bool initialDrawerOpen;
  @override
  State<GlacierNativeFrame> createState() => _GlacierNativeFrameState();
}

class _GlacierNativeFrameState extends State<GlacierNativeFrame>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _frame = GlobalKey();
  final _captions = GlobalKey();
  final _titlebar = GlobalKey();
  final _exit = GlobalKey();
  final _captionKeys = {
    for (final command in GlacierNativeCommand.values) command: GlobalKey(),
  };
  final _primaryCaptionFocus = FocusNode(debugLabel: 'Native primary caption');
  final _exitFocus = FocusNode(debugLabel: 'Native fullscreen exit');
  late bool drawerOpen = widget.initialDrawerOpen;
  bool scheduled = false;
  bool modalOpen = false;
  late final _routes = _NativeRouteObserver(_scheduleLayout, _modalChanged);
  void _modalChanged(bool open) {
    if (!mounted || open == modalOpen) return;
    setState(() {
      modalOpen = open;
      if (open) drawerOpen = false;
    });
  }

  GlacierNativeWindowLayout? previous;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleLayout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _primaryCaptionFocus.dispose();
    _exitFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleLayout();
  @override
  void didUpdateWidget(GlacierNativeFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutRevision != widget.layoutRevision) previous = null;
    if (!oldWidget.state.fullscreen &&
        widget.state.fullscreen &&
        _primaryCaptionFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exitFocus.requestFocus();
      });
    }
    if (oldWidget.state.fullscreen &&
        !widget.state.fullscreen &&
        _exitFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _primaryCaptionFocus.requestFocus();
      });
    }
    _scheduleLayout();
  }

  void _setDrawer(bool value) {
    if (drawerOpen != value) setState(() => drawerOpen = value);
    _scheduleLayout();
  }

  void _scheduleLayout() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted) _reportLayout();
    });
  }

  void _reportLayout() {
    final frame = _frame.currentContext?.findRenderObject();
    if (frame is! RenderBox || !frame.hasSize) return;
    final viewport = Offset.zero & frame.size;
    Rect? rect(BuildContext? context) {
      final box = context?.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.isEmpty) {
        return null;
      }
      final result = box.localToGlobal(Offset.zero, ancestor: frame) & box.size;
      return result.overlaps(viewport) ? result.intersect(viewport) : null;
    }

    final exclusions = <Rect>[];
    void walk(Element element) {
      final w = element.widget;
      if (w is GlacierNativeDragRegion) return;
      if (w is Offstage && w.offstage) return;
      if (w is Visibility && !w.visible) return;
      if (w is ButtonStyleButton ||
          w is IconButton ||
          w is TextField ||
          w is EditableText ||
          w is DropdownButton ||
          w is InkWell ||
          w is Scrollbar ||
          w is Dialog ||
          (w is GestureDetector &&
              (w.onTap != null || w.onSecondaryTap != null))) {
        final bounds = rect(element);
        if (bounds != null) exclusions.add(bounds);
      }
      element.visitChildElements(walk);
    }

    (_frame.currentContext! as Element).visitChildElements(walk);
    final reservations = <Rect>[
      if (rect(_captions.currentContext) case final Rect r) r,
      if (rect(_exit.currentContext) case final Rect r) r,
    ];
    final layout = GlacierNativeWindowLayout(
      captionBounds: {
        for (final entry in _captionKeys.entries)
          if (rect(entry.value.currentContext) case final Rect bounds)
            entry.key: bounds,
      },
      viewport: frame.size,
      titlebar: rect(_titlebar.currentContext) ?? Rect.zero,
      candidateDragRegions: [
        if (rect(_titlebar.currentContext) case final Rect r) r,
      ],
      interactiveExclusions: exclusions,
      nativeControlReservations: reservations,
      resizeEdge: widget.state.mode == GlacierNativeWindowMode.restored ? 8 : 0,
      devicePixelRatio: widget.state.devicePixelRatio,
    );
    if (layout != previous) {
      previous = layout;
      widget.commands.onLayoutChanged?.call(layout);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final compact = size.width <= 760;
      final state = widget.state;
      final contentModalOpen = modalOpen || widget.contentModalOpen;
      final platform = switch (state.platform) {
        GlacierNativePlatform.macos => TargetPlatform.macOS,
        GlacierNativePlatform.windows => TargetPlatform.windows,
        GlacierNativePlatform.linux => TargetPlatform.linux,
      };
      final barHeight = GlacierNativeTitleBar.heightFor(
        context,
        state,
        size.width,
      );
      return Theme(
        data: Theme.of(context).copyWith(platform: platform),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                state.reduceMotion || MediaQuery.disableAnimationsOf(context),
          ),
          child: GlacierNativePresentationScope(
            state: state,
            viewport: size,
            titlebarHeight: barHeight,
            drawerOpen: drawerOpen,
            onDrawerChanged: _setDrawer,
            onLayoutChanged: _scheduleLayout,
            child: FocusTraversalGroup(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (contentModalOpen) {
                      (widget.contentNavigatorKey ?? _navigator).currentState
                          ?.maybePop();
                    } else if (drawerOpen) {
                      _setDrawer(false);
                    }
                  },
                  const SingleActivator(LogicalKeyboardKey.f11): () {
                    final command = state.fullscreen
                        ? GlacierNativeCommand.exitFullscreen
                        : GlacierNativeCommand.enterFullscreen;
                    if (state.supportedCommands.contains(command)) {
                      widget.commands.callback(command)?.call();
                    }
                  },
                },
                child: _NativeLayoutObserver(
                  onLayout: _scheduleLayout,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _scheduleLayout();
                      return false;
                    },
                    child: Stack(
                      key: _frame,
                      fit: StackFit.expand,
                      children: [
                        if (widget.contentNavigatorKey != null)
                          Positioned.fill(
                            top: barHeight,
                            child: GlacierNativePresentationScope(
                              state: state,
                              viewport: Size(
                                size.width,
                                size.height - barHeight,
                              ),
                              titlebarHeight: 0,
                              drawerOpen: drawerOpen,
                              onDrawerChanged: _setDrawer,
                              onLayoutChanged: _scheduleLayout,
                              child: widget.child,
                            ),
                          )
                        else
                          Navigator(
                            key: _navigator,
                            observers: [_routes],
                            onGenerateRoute: (_) => PageRouteBuilder<void>(
                              transitionDuration: Duration.zero,
                              pageBuilder: (context, _, _) => Builder(
                                builder: (context) {
                                  GlacierNativePresentationScope.maybeOf(
                                    context,
                                  );
                                  return widget.child;
                                },
                              ),
                            ),
                          ),
                        if (widget.windowOverlay != null)
                          Positioned.fill(
                            child: ExcludeFocus(
                              excluding: contentModalOpen || drawerOpen,
                              child: ExcludeSemantics(
                                excluding: contentModalOpen || drawerOpen,
                                child: IgnorePointer(
                                  ignoring: contentModalOpen || drawerOpen,
                                  child: widget.windowOverlay,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: GlacierNativeTitleBar(
                            key: _titlebar,
                            state: state,
                            commands: widget.commands,
                            captionKey: _captions,
                            captionKeys: _captionKeys,
                            exitKey: _exit,
                            primaryFocusNode: _primaryCaptionFocus,
                            exitFocusNode: _exitFocus,
                          ),
                        ),
                        if (widget.feedback?.isNotEmpty == true)
                          Positioned(
                            right: 20,
                            bottom: 12,
                            left: compact ? 20 : null,
                            child: GlacierNativeCommandFeedback(
                              message: widget.feedback!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class GlacierNativeTitleBar extends StatelessWidget {
  const GlacierNativeTitleBar({
    super.key,
    required this.state,
    required this.commands,
    this.primaryFocusNode,
    this.exitFocusNode,
    this.captionKey,
    this.captionKeys = const {},
    this.exitKey,
  });
  final GlacierNativeWindowState state;
  final GlacierNativeWindowCommands commands;
  final FocusNode? primaryFocusNode, exitFocusNode;
  final Key? captionKey, exitKey;
  final Map<GlacierNativeCommand, Key> captionKeys;
  static double heightFor(
    BuildContext context,
    GlacierNativeWindowState state,
    double width,
  ) {
    final large = MediaQuery.textScalerOf(context).scale(14) > 20;
    return large ? 52 : 44;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth <= 760;
      final large = MediaQuery.textScalerOf(context).scale(14) > 20;
      final baseHeight = large ? 52.0 : 44.0;
      final height = heightFor(context, state, constraints.maxWidth);
      final exitLabelStyle =
          Theme.of(context).textButtonTheme.style?.textStyle
              ?.resolve({})
              ?.copyWith(fontSize: 12) ??
          const TextStyle(fontSize: 12);
      final exitLabel = TextPainter(
        text: TextSpan(text: 'Exit full screen', style: exitLabelStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final compactExit = compact || large || exitLabel.width + 40 > 132;
      exitLabel.dispose();
      final exitWidth = compactExit ? 44.0 : 132.0;
      final exitReservation = exitWidth + 24;
      final traffic = state.platform == GlacierNativePlatform.macos;
      final left = state.controlsOnLeft;
      final closeOnly =
          state.platform == GlacierNativePlatform.linux &&
          (state.controlLayout == GlacierNativeControlLayout.closeOnly ||
              state.controlLayout == GlacierNativeControlLayout.closeOnlyLeft);
      var titleLeft = traffic
          ? 104.0
          : left
          ? (closeOnly ? 78.0 : 154.0)
          : 16.0;
      var titleRight = traffic
          ? (compact ? 16.0 : 104.0)
          : left
          ? 16.0
          : closeOnly
          ? 64.0
          : 154.0;
      if (state.decoration == GlacierNativeDecoration.host) {
        titleLeft = 16;
        titleRight = 16;
      }
      if (state.fullscreen) {
        titleLeft = state.captionsVisible
            ? (traffic
                  ? 104
                  : left
                  ? (closeOnly ? 78 : 154)
                  : 16)
            : 16;
        titleRight = state.captionsVisible && !left
            ? exitReservation + (closeOnly ? 48 : 138) + 16
            : exitReservation;
      }
      final tokens = GlacierTokens.of(context);
      return DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(decoration: TextDecoration.none),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: tokens.opaque ? 0 : 28,
              sigmaY: tokens.opaque ? 0 : 28,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.opaque ? tokens.solid : tokens.glass,
                border: Border(bottom: BorderSide(color: tokens.edge)),
              ),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GlacierNativeDragRegion(
                        commands: GlacierNativeWindowCommands(
                          onTitlebarDoubleClick:
                              state.supportedCommands.contains(
                                GlacierNativeCommand.titlebarDoubleClick,
                              )
                              ? commands.onTitlebarDoubleClick
                              : null,
                          onSystemMenu:
                              state.supportedCommands.contains(
                                GlacierNativeCommand.systemMenu,
                              )
                              ? commands.onSystemMenu
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      left: titleLeft,
                      right: titleRight,
                      top: 0,
                      height: baseHeight,
                      child: IgnorePointer(
                        child: Center(
                          child: Text.rich(
                            TextSpan(
                              text: state.title,
                              children: [
                                TextSpan(
                                  text: ' · ${state.library}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: tokens.muted,
                                  ),
                                ),
                              ],
                            ),
                            semanticsLabel: '${state.title} · ${state.library}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.28,
                              color: state.active
                                  ? Theme.of(context).colorScheme.onSurface
                                  : tokens.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (state.captionsVisible)
                      Positioned(
                        left: left ? (traffic ? 20 : 16) : null,
                        right: left
                            ? null
                            : state.fullscreen && state.controlsRevealed
                            ? exitReservation
                            : 0,
                        top: (baseHeight - (traffic ? 24 : 44)) / 2,
                        child: SizedBox(
                          key: captionKey,
                          child: GlacierNativeCaptionControls(
                            state: state,
                            commands: commands,
                            primaryFocusNode: primaryFocusNode,
                            captionKeys: captionKeys,
                          ),
                        ),
                      ),
                    if (state.fullscreen)
                      Positioned(
                        right: 12,
                        top: (baseHeight - 44) / 2,
                        child: SizedBox(
                          key: exitKey,
                          width: exitWidth,
                          height: 44,
                          child: compactExit
                              ? IconButton.outlined(
                                  focusNode: exitFocusNode,
                                  tooltip: 'Exit full screen',
                                  onPressed:
                                      state.supportedCommands.contains(
                                        GlacierNativeCommand.exitFullscreen,
                                      )
                                      ? commands.onExitFullscreen
                                      : null,
                                  style: IconButton.styleFrom(
                                    fixedSize: const Size.square(44),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: tokens.surface,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    side: BorderSide(color: tokens.border),
                                  ),
                                  icon: const Icon(
                                    Icons.fullscreen_exit,
                                    size: 20,
                                  ),
                                )
                              : TextButton.icon(
                                  focusNode: exitFocusNode,
                                  onPressed:
                                      state.supportedCommands.contains(
                                        GlacierNativeCommand.exitFullscreen,
                                      )
                                      ? commands.onExitFullscreen
                                      : null,
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(132, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    backgroundColor: tokens.surface,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    side: BorderSide(color: tokens.border),
                                  ),
                                  icon: const Icon(
                                    Icons.fullscreen_exit,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Exit full screen',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: exitLabelStyle,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class GlacierNativeCaptionControls extends StatelessWidget {
  const GlacierNativeCaptionControls({
    super.key,
    required this.state,
    required this.commands,
    this.primaryFocusNode,
    this.captionKeys = const {},
  });
  final GlacierNativeWindowState state;
  final GlacierNativeWindowCommands commands;
  final FocusNode? primaryFocusNode;
  final Map<GlacierNativeCommand, Key> captionKeys;
  @override
  Widget build(BuildContext context) {
    final traffic = state.platform == GlacierNativePlatform.macos;
    final linux = state.platform == GlacierNativePlatform.linux;
    return Opacity(
      opacity: state.active ? 1 : .65,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final command in state.captionCommands) ...[
            if (traffic && command != state.captionCommands.first)
              const SizedBox(width: 8),
            SizedBox(
              key: captionKeys[command],
              width: traffic ? 16 : 46,
              height: traffic ? 24 : 44,
              child: Tooltip(
                message: glacierNativeCommandLabel(command),
                child: Opacity(
                  opacity:
                      state.supportedCommands.contains(command) &&
                          commands.callback(command) != null
                      ? 1
                      : .42,
                  child: TextButton(
                    focusNode:
                        command == GlacierNativeCommand.maximize ||
                            command == GlacierNativeCommand.restore ||
                            command == GlacierNativeCommand.enterFullscreen ||
                            command == GlacierNativeCommand.exitFullscreen ||
                            state.captionCommands.length == 1
                        ? primaryFocusNode
                        : null,
                    onPressed: state.supportedCommands.contains(command)
                        ? commands.callback(command)
                        : null,
                    style: ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.all(linux ? 4 : 0),
                      ),
                      minimumSize: const WidgetStatePropertyAll(Size.zero),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: WidgetStatePropertyAll(
                        linux
                            ? const CircleBorder()
                            : const RoundedRectangleBorder(),
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) =>
                            states.contains(WidgetState.hovered) &&
                                command == GlacierNativeCommand.close &&
                                !traffic
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) =>
                            states.contains(WidgetState.hovered) && !traffic
                            ? command == GlacierNativeCommand.close
                                  ? const Color(0xffc42b1c)
                                  : GlacierTokens.of(context).surface
                            : linux && command == GlacierNativeCommand.close
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                      ),
                    ),
                    child: Semantics(
                      label: glacierNativeCommandLabel(command),
                      child: traffic
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: state.active
                                    ? switch (command) {
                                        GlacierNativeCommand.close =>
                                          const Color(0xffff5f57),
                                        GlacierNativeCommand.minimize =>
                                          const Color(0xfffebc2e),
                                        _ => const Color(0xff28c840),
                                      }
                                    : const Color(0xffa5afb0),
                                border: Border.all(
                                  color: const Color(0x22000000),
                                ),
                              ),
                              child: const SizedBox.square(dimension: 12),
                            )
                          : Icon(switch (command) {
                              GlacierNativeCommand.close => Icons.close,
                              GlacierNativeCommand.minimize => Icons.remove,
                              GlacierNativeCommand.restore => Icons.filter_none,
                              _ => Icons.crop_square,
                            }, size: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GlacierNativeDragRegion extends StatelessWidget {
  const GlacierNativeDragRegion({
    super.key,
    required this.commands,
    this.highlight = false,
  });
  final GlacierNativeWindowCommands commands;
  final bool highlight;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onDoubleTap: commands.onTitlebarDoubleClick,
    onSecondaryTap: commands.onSystemMenu,
    child: ColoredBox(
      color: highlight
          ? GlacierTokens.of(context).accent.withValues(alpha: .12)
          : Colors.transparent,
    ),
  );
}

class GlacierNativeCompactNavigation extends StatelessWidget {
  const GlacierNativeCompactNavigation({
    super.key,
    required this.child,
    required this.onDismiss,
  });
  final Widget child;
  final VoidCallback onDismiss;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onDismiss},
    child: Stack(
      children: [
        Positioned.fill(
          top:
              (GlacierNativePresentationScope.maybeOf(context)
                      ?.titlebarHeight ??
                  0) +
              60,
          child: GestureDetector(
            onTap: onDismiss,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlacierTokens.of(context).opaque ? 0 : 6,
                  sigmaY: GlacierTokens.of(context).opaque ? 0 : 6,
                ),
                child: const ColoredBox(color: Color(0x40102e35)),
              ),
            ),
          ),
        ),
        Positioned(
          top:
              (GlacierNativePresentationScope.maybeOf(context)
                      ?.titlebarHeight ??
                  0) +
              64,
          left: 12,
          bottom: 12,
          width: (MediaQuery.sizeOf(context).width - 24).clamp(0, 330),
          child: Material(
            type: MaterialType.transparency,
            child: FocusTraversalGroup(child: child),
          ),
        ),
      ],
    ),
  );
}

class GlacierNativeCommandFeedback extends StatelessWidget {
  const GlacierNativeCommandFeedback({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: GlacierSurface(
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, style: const TextStyle(fontSize: 12)),
      ),
    ),
  );
}

class _NativeRouteObserver extends NavigatorObserver {
  _NativeRouteObserver(this.onChanged, this.onModalChanged);
  final VoidCallback onChanged;
  final ValueChanged<bool> onModalChanged;
  int depth = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth++;
    onModalChanged(depth > 1);
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    depth--;
    onModalChanged(depth > 1);
    onChanged();
  }
}

class _NativeLayoutObserver extends SingleChildRenderObjectWidget {
  const _NativeLayoutObserver({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _NativeLayoutRender(onLayout);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _NativeLayoutRender renderObject,
  ) => renderObject.onLayout = onLayout;
}

class _NativeLayoutRender extends RenderProxyBox {
  _NativeLayoutRender(this.onLayout);
  VoidCallback onLayout;
  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}
