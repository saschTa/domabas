import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum GlacierNativePlatform { macos, windows, linux }

enum GlacierNativeWindowMode { restored, maximized, fullscreen }

enum GlacierNativeDecoration { client, host }

enum GlacierNativeControlLayout { standard, closeOnly, left, closeOnlyLeft }

enum GlacierNativeCommand {
  close,
  minimize,
  maximize,
  restore,
  enterFullscreen,
  exitFullscreen,
  titlebarDoubleClick,
  systemMenu,
}

@immutable
class GlacierNativeWindowState {
  GlacierNativeWindowState({
    required this.platform,
    this.mode = GlacierNativeWindowMode.restored,
    this.active = true,
    this.controlsRevealed = false,
    Set<GlacierNativeCommand> supportedCommands = const {
      ...GlacierNativeCommand.values,
    },
    this.decoration = GlacierNativeDecoration.client,
    this.controlLayout = GlacierNativeControlLayout.standard,
    this.title = 'Domabas',
    this.library = 'Personal library',
    this.devicePixelRatio = 1,
    this.reduceMotion = false,
    this.opaque = false,
  }) : supportedCommands = Set.unmodifiable(supportedCommands);
  final GlacierNativePlatform platform;
  final GlacierNativeWindowMode mode;
  final GlacierNativeDecoration decoration;
  final GlacierNativeControlLayout controlLayout;
  final Set<GlacierNativeCommand> supportedCommands;
  final bool active, controlsRevealed, reduceMotion, opaque;
  final String title, library;
  final double devicePixelRatio;
  bool get fullscreen => mode == GlacierNativeWindowMode.fullscreen;
  bool get captionsVisible =>
      decoration == GlacierNativeDecoration.client &&
      (!fullscreen || controlsRevealed);
  bool get controlsOnLeft =>
      platform == GlacierNativePlatform.macos ||
      controlLayout == GlacierNativeControlLayout.left ||
      controlLayout == GlacierNativeControlLayout.closeOnlyLeft;
  List<GlacierNativeCommand> get captionCommands => List.unmodifiable(
    platform == GlacierNativePlatform.macos
        ? [
            GlacierNativeCommand.close,
            GlacierNativeCommand.minimize,
            fullscreen
                ? GlacierNativeCommand.exitFullscreen
                : GlacierNativeCommand.enterFullscreen,
          ]
        : platform == GlacierNativePlatform.linux &&
              (controlLayout == GlacierNativeControlLayout.closeOnly ||
                  controlLayout == GlacierNativeControlLayout.closeOnlyLeft)
        ? [GlacierNativeCommand.close]
        : [
            GlacierNativeCommand.minimize,
            mode == GlacierNativeWindowMode.maximized
                ? GlacierNativeCommand.restore
                : GlacierNativeCommand.maximize,
            GlacierNativeCommand.close,
          ],
  );
  GlacierNativeWindowState copyWith({
    GlacierNativePlatform? platform,
    GlacierNativeWindowMode? mode,
    bool? active,
    bool? controlsRevealed,
    Set<GlacierNativeCommand>? supportedCommands,
    GlacierNativeDecoration? decoration,
    GlacierNativeControlLayout? controlLayout,
    String? title,
    String? library,
    double? devicePixelRatio,
    bool? reduceMotion,
    bool? opaque,
  }) => GlacierNativeWindowState(
    platform: platform ?? this.platform,
    mode: mode ?? this.mode,
    active: active ?? this.active,
    controlsRevealed: controlsRevealed ?? this.controlsRevealed,
    supportedCommands: supportedCommands ?? this.supportedCommands,
    decoration: decoration ?? this.decoration,
    controlLayout: controlLayout ?? this.controlLayout,
    title: title ?? this.title,
    library: library ?? this.library,
    devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    opaque: opaque ?? this.opaque,
  );
}

@immutable
class GlacierNativeWindowLayout {
  GlacierNativeWindowLayout({
    required this.viewport,
    required this.titlebar,
    required List<Rect> candidateDragRegions,
    required List<Rect> interactiveExclusions,
    required List<Rect> nativeControlReservations,
    Map<GlacierNativeCommand, Rect> captionBounds = const {},
    this.resizeEdge = 8,
    this.devicePixelRatio = 1,
  }) : captionBounds = Map.unmodifiable(captionBounds),
       candidateDragRegions = List.unmodifiable(candidateDragRegions),
       interactiveExclusions = List.unmodifiable(interactiveExclusions),
       nativeControlReservations = List.unmodifiable(nativeControlReservations);
  final Size viewport;
  final Rect titlebar;
  final List<Rect> candidateDragRegions,
      interactiveExclusions,
      nativeControlReservations;
  final double resizeEdge, devicePixelRatio;
  final Map<GlacierNativeCommand, Rect> captionBounds;
  bool canDragAt(Offset point) =>
      point.dx >= resizeEdge &&
      point.dy >= resizeEdge &&
      point.dx < viewport.width - resizeEdge &&
      point.dy < viewport.height - resizeEdge &&
      candidateDragRegions.any((r) => r.contains(point)) &&
      !interactiveExclusions.any((r) => r.contains(point)) &&
      !nativeControlReservations.any((r) => r.contains(point));
  @override
  bool operator ==(Object other) =>
      other is GlacierNativeWindowLayout &&
      mapEquals(captionBounds, other.captionBounds) &&
      viewport == other.viewport &&
      titlebar == other.titlebar &&
      resizeEdge == other.resizeEdge &&
      devicePixelRatio == other.devicePixelRatio &&
      listEquals(candidateDragRegions, other.candidateDragRegions) &&
      listEquals(interactiveExclusions, other.interactiveExclusions) &&
      listEquals(nativeControlReservations, other.nativeControlReservations);
  @override
  int get hashCode => Object.hash(
    viewport,
    titlebar,
    resizeEdge,
    devicePixelRatio,
    Object.hashAll(candidateDragRegions),
    Object.hashAll(interactiveExclusions),
    Object.hashAll(nativeControlReservations),
    Object.hashAllUnordered(
      captionBounds.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

@immutable
class GlacierNativeWindowCommands {
  const GlacierNativeWindowCommands({
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onRestore,
    this.onEnterFullscreen,
    this.onExitFullscreen,
    this.onTitlebarDoubleClick,
    this.onSystemMenu,
    this.onLayoutChanged,
  });
  final VoidCallback? onClose,
      onMinimize,
      onMaximize,
      onRestore,
      onEnterFullscreen,
      onExitFullscreen,
      onTitlebarDoubleClick,
      onSystemMenu;
  final ValueChanged<GlacierNativeWindowLayout>? onLayoutChanged;
  VoidCallback? callback(GlacierNativeCommand command) => switch (command) {
    GlacierNativeCommand.close => onClose,
    GlacierNativeCommand.minimize => onMinimize,
    GlacierNativeCommand.maximize => onMaximize,
    GlacierNativeCommand.restore => onRestore,
    GlacierNativeCommand.enterFullscreen => onEnterFullscreen,
    GlacierNativeCommand.exitFullscreen => onExitFullscreen,
    GlacierNativeCommand.titlebarDoubleClick => onTitlebarDoubleClick,
    GlacierNativeCommand.systemMenu => onSystemMenu,
  };
}

String glacierNativeCommandLabel(GlacierNativeCommand command) =>
    switch (command) {
      GlacierNativeCommand.close => 'Close window',
      GlacierNativeCommand.minimize => 'Minimize window',
      GlacierNativeCommand.maximize => 'Maximize window',
      GlacierNativeCommand.restore => 'Restore window',
      GlacierNativeCommand.enterFullscreen => 'Enter full screen',
      GlacierNativeCommand.exitFullscreen => 'Exit full screen',
      GlacierNativeCommand.titlebarDoubleClick =>
        'Native titlebar double click',
      GlacierNativeCommand.systemMenu => 'System window menu',
    };

class GlacierNativePresentationScope extends InheritedWidget {
  const GlacierNativePresentationScope({
    super.key,
    required this.state,
    required this.viewport,
    this.titlebarHeight = 44,
    required this.drawerOpen,
    required this.onDrawerChanged,
    required this.onLayoutChanged,
    required super.child,
  });
  final GlacierNativeWindowState state;
  final Size viewport;
  final double titlebarHeight;
  final bool drawerOpen;
  final ValueChanged<bool> onDrawerChanged;
  final VoidCallback onLayoutChanged;
  static GlacierNativePresentationScope? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlacierNativePresentationScope>();
  bool get compact => viewport.width <= 760;
  double get sidebarTopInset => 0;
  double get compactTopInset => titlebarHeight + 64;
  double get leftReservation => 0;
  double get rightReservation => 0;
  double toolbarTrailingInset() => 0;
  double toolbarLeadingInset(double workspaceLeft) => 0;
  @override
  bool updateShouldNotify(GlacierNativePresentationScope oldWidget) =>
      state != oldWidget.state ||
      viewport != oldWidget.viewport ||
      titlebarHeight != oldWidget.titlebarHeight ||
      drawerOpen != oldWidget.drawerOpen;
}

class GlacierNativeContentInsets extends InheritedWidget {
  const GlacierNativeContentInsets({
    super.key,
    required this.insets,
    this.scrollBottomInset = 0,
    required super.child,
  });
  final EdgeInsets insets;
  final double scrollBottomInset;
  static double scrollBottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlacierNativeContentInsets>()
          ?.scrollBottomInset ??
      0;
  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlacierNativeContentInsets>()
          ?.insets ??
      EdgeInsets.zero;
  @override
  bool updateShouldNotify(GlacierNativeContentInsets oldWidget) =>
      insets != oldWidget.insets ||
      scrollBottomInset != oldWidget.scrollBottomInset;
}
