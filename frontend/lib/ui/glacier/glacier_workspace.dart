import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';

import 'glacier_controls.dart';
import 'glacier_native_values.dart';
import 'glacier_native_frame.dart';
import 'glacier_surfaces.dart';
import 'glacier_theme.dart';
import 'glacier_workspace_geometry.dart';
import 'glacier_interaction.dart';

@immutable
class GlacierDestination {
  const GlacierDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.children = const [],
    this.key,
  });
  final String id, label;
  final Key? key;
  final IconData icon;
  final List<GlacierDestination> children;
}

class GlacierWorkspace extends StatefulWidget {
  const GlacierWorkspace({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.child,
    required this.onSearch,
    required this.libraryLabel,
    required this.accountLabel,
    this.toolbar,
    this.brand,
    this.activityDock,
    this.onLibrary,
    this.onActivity,
    this.onAppearance,
    this.onAccount,
    this.accountFocusNode,
    this.initiallyCollapsed = false,
    this.backgroundValues = const [],
    this.activityBackground = false,
    this.plainBackground = false,
    this.backgroundGrid = false,
    this.backgroundSoftness = 8,
  });
  final List<GlacierDestination> destinations;
  final String selected, libraryLabel, accountLabel;
  final ValueChanged<String> onSelected;
  final Widget child;
  final Widget? toolbar;
  final Widget? brand, activityDock;
  final VoidCallback? onSearch;
  final FocusNode? accountFocusNode;
  final VoidCallback? onLibrary, onActivity, onAppearance, onAccount;
  final bool initiallyCollapsed;
  final List<double> backgroundValues;
  final bool activityBackground;
  final bool plainBackground, backgroundGrid;
  final double backgroundSoftness;
  @override
  State<GlacierWorkspace> createState() => _GlacierWorkspaceState();
}

class _GlacierWorkspaceState extends State<GlacierWorkspace> {
  late bool _collapsed = widget.initiallyCollapsed;
  bool _expandedByUser = false;
  final Set<String> _openGroups = {};
  final _dockKey = GlobalKey();
  double _dockHeight = 0;
  double _panelExtent = 0, _toolbarBottom = 0, _endActionsHeight = 0;
  Widget _geometry(Widget child) => GlacierWorkspaceGeometry(
    trailingExtent: _dockHeight == 0
        ? 18
        : (_dockHeight + _panelExtent + 32).ceilToDouble(),
    overlayMinimumTop: _toolbarBottom,
    endActionsHeight: _endActionsHeight,
    onEndActionsHeightChanged: _endActionsCallback(widget.selected),
    onToolbarBottomChanged: (value) {
      if (mounted && (value - _toolbarBottom).abs() > .5) {
        setState(() => _toolbarBottom = value);
      }
    },
    onActivityPanelExtentChanged: (value) {
      if (mounted && (value - _panelExtent).abs() > .5) {
        setState(() => _panelExtent = value);
      }
    },
    child: child,
  );
  ValueChanged<double> _endActionsCallback(String selected) => (value) {
    if (mounted &&
        widget.selected == selected &&
        (value - _endActionsHeight).abs() > .5) {
      setState(() => _endActionsHeight = value);
    }
  };
  @override
  void initState() {
    super.initState();
    _revealSelectedGroup();
  }

  void _revealSelectedGroup() {
    for (final item in widget.destinations) {
      if (item.children.any((child) => child.id == widget.selected)) {
        _openGroups.add(item.id);
      }
    }
  }

  @override
  void didUpdateWidget(covariant GlacierWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _endActionsHeight = 0;
      _revealSelectedGroup();
    }
  }

  final _scaffold = GlobalKey<ScaffoldState>();
  final _nativeMenuFocus = FocusNode(debugLabel: 'Native navigation trigger');
  final _nativeSearchFocus = FocusNode(debugLabel: 'Native drawer search');
  bool _nativeDrawerWasOpen = false;
  @override
  void dispose() {
    _nativeMenuFocus.dispose();
    _nativeSearchFocus.dispose();
    super.dispose();
  }

  void _closeDrawer() {
    final native = GlacierNativePresentationScope.maybeOf(context);
    if (native != null) {
      native.onDrawerChanged(false);
      _nativeMenuFocus.requestFocus();
    } else {
      _scaffold.currentState?.closeDrawer();
    }
  }

  void _select(String id) {
    widget.onSelected(id);
    _closeDrawer();
  }

  void _measureDock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _dockKey.currentContext?.findRenderObject();
      final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
      if ((height - _dockHeight).abs() > .5) {
        setState(() => _dockHeight = height);
      }
    });
  }

  String get _accountInitials {
    final name = widget.accountLabel.trim();
    if (name.isEmpty) return '';
    if (name.contains('@')) return name.characters.first.toUpperCase();
    return name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
  }

  Widget _navigation(bool rail, {bool drawer = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in widget.destinations)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: item.children.isEmpty
              ? _GlacierNavTrigger(
                  key: item.key,
                  item: item,
                  rail: rail,
                  selected: widget.selected == item.id,
                  onPressed: () => _select(item.id),
                )
              : _GlacierNavigationGroup(
                  key: ValueKey(item.id),
                  item: item,
                  rail: rail,
                  selected: widget.selected,
                  expanded: _openGroups.contains(item.id) && !rail,
                  onToggle: () => setState(() {
                    if (rail) {
                      _collapsed = false;
                      _expandedByUser = true;
                      _openGroups.add(item.id);
                    } else if (!_openGroups.remove(item.id)) {
                      _openGroups.add(item.id);
                    }
                  }),
                  onClose: () => setState(() => _openGroups.remove(item.id)),
                  onSelected: _select,
                ),
        ),
    ],
  );

  Widget _folded(bool hidden, Widget child) => ExcludeSemantics(
    excluding: hidden,
    child: ExcludeFocus(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: hidden ? 0 : 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) =>
              hidden && (value == 0 || MediaQuery.disableAnimationsOf(context))
              ? const SizedBox.shrink()
              : ClipRect(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    heightFactor: value,
                    child: Opacity(
                      opacity: value,
                      child: OverflowBox(
                        fit: OverflowBoxFit.deferToChild,
                        minWidth: 202,
                        maxWidth: 202,
                        alignment: Alignment.bottomLeft,
                        child: child,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );

  Widget _sidebar(bool rail, {bool drawer = false}) => GlacierSurface(
    radius: drawer
        ? (GlacierNativePresentationScope.maybeOf(context) == null ? 0 : 20)
        : GlacierNativePresentationScope.maybeOf(context)?.state.mode ==
              GlacierNativeWindowMode.maximized
        ? 12
        : 20,
    padding: const EdgeInsets.fromLTRB(11, 17, 11, 12),
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxHeight < 440
          ? SingleChildScrollView(
              primary: false,
              child: _sidebarContents(rail, drawer: drawer, scrollAll: true),
            )
          : _sidebarContents(rail, drawer: drawer),
    ),
  );
  Widget _sidebarContents(
    bool rail, {
    required bool drawer,
    bool scrollAll = false,
  }) => Column(
    mainAxisSize: scrollAll ? MainAxisSize.min : MainAxisSize.max,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 62,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              height: 42,
              top: drawer
                  ? 0
                  : (GlacierNativePresentationScope.maybeOf(context)
                                ?.sidebarTopInset ??
                            0) /
                        2,
              child: Row(
                children: [
                  if (!rail)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: [
                            if (widget.brand != null) ...[
                              SizedBox.square(
                                dimension: 28,
                                child: widget.brand,
                              ),
                              const SizedBox(width: 5),
                            ],
                            const Expanded(
                              child: Text(
                                'domabas.',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  GlacierIconButton(
                    label: drawer
                        ? 'Close navigation'
                        : rail
                        ? 'Expand sidebar'
                        : 'Collapse sidebar',
                    icon: drawer
                        ? Icons.close
                        : rail
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left,
                    onPressed: () {
                      if (drawer) {
                        _closeDrawer();
                      } else {
                        setState(() {
                          _collapsed = !rail;
                          _expandedByUser = rail;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (rail)
        SizedBox(
          height: 48,
          child: GlacierIconButton(
            label: 'Search · Cmd/Ctrl+K',
            icon: Icons.search,
            onPressed: widget.onSearch,
          ),
        )
      else
        SizedBox(
          height: 48,
          child: glacierInteractionOutline(
            focusOffset: -2,
            builder: (states, _) => OutlinedButton(
              statesController: states,
              focusNode:
                  drawer &&
                      GlacierNativePresentationScope.maybeOf(context) != null
                  ? _nativeSearchFocus
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: GlacierTokens.of(context).muted,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: widget.onSearch,
              child: const Row(
                children: [
                  Icon(Icons.search, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  Text('⌘ K', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      _folded(
        rail,
        SizedBox(
          width: 202,
          height: 39,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 14,
                  color: GlacierTokens.of(context).muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.libraryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: GlacierTokens.of(context).muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (scrollAll)
        _navigation(rail, drawer: drawer)
      else
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            child: _navigation(rail, drawer: drawer),
          ),
        ),
      _folded(
        rail,
        SizedBox(
          width: 202,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: GlacierIconButton(
                        key: const Key('librarySwitcher'),
                        label: 'Select library',
                        icon: Icons.library_books_outlined,
                        onPressed: widget.onLibrary,
                      ),
                    ),
                    Expanded(
                      child: GlacierIconButton(
                        label: 'Activity',
                        icon: Icons.monitor_heart_outlined,
                        onPressed: widget.onActivity,
                      ),
                    ),
                    Expanded(
                      child: GlacierIconButton(
                        label: 'Appearance',
                        icon: Icons.light_mode_outlined,
                        onPressed: widget.onAppearance,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Divider(),
      const SizedBox(height: 10),
      if (rail)
        SizedBox(
          height: 52,
          child: GlacierIconButton(
            key: const Key('workspaceAccount'),
            label:
                'Account and utilities. ${widget.accountLabel}. Library: ${widget.libraryLabel}',
            focusNode: widget.accountFocusNode,
            icon: Icons.person_outline,
            onPressed: widget.onAccount,
          ),
        )
      else
        TextButton(
          key: const Key('workspaceAccount'),
          focusNode: widget.accountFocusNode,
          onPressed: widget.onAccount,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
          child: Row(
            children: [
              Container(
                width: 33,
                height: 33,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: GlacierTokens.of(context).border),
                ),
                child: Text(
                  _accountInitials,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.libraryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: GlacierTokens.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz, size: 16),
            ],
          ),
        ),
    ],
  );
  Widget _nativeWorkspace(
    BuildContext context,
    BoxConstraints constraints,
    GlacierNativePresentationScope native,
  ) {
    final compact = native.compact;
    final rail =
        _collapsed || (constraints.maxWidth < 1050 && !_expandedByUser);
    final reduced =
        native.state.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (_nativeDrawerWasOpen != native.drawerOpen) {
      _nativeDrawerWasOpen = native.drawerOpen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (native.drawerOpen) {
            _nativeSearchFocus.requestFocus();
          } else {
            _nativeMenuFocus.requestFocus();
          }
        }
      });
    }
    if (!compact && native.drawerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) native.onDrawerChanged(false);
      });
    }
    _measureDock();
    final workspaceLeft = 24 + (rail ? 76.0 : 224.0) + 20;
    final content = GlacierNativeContentInsets(
      scrollBottomInset: 0,
      insets: EdgeInsets.only(
        left: native.toolbarLeadingInset(workspaceLeft),
        right: native.toolbarTrailingInset(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.toolbar != null) ...[
            widget.toolbar!,
            const SizedBox(height: 20),
          ],
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(child: widget.child),
                if (widget.activityDock != null)
                  Positioned(
                    right: compact ? 8 : 20,
                    bottom: 16,
                    child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _measureDock();
                        native.onLayoutChanged();
                        return false;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: SizedBox(
                          key: _dockKey,
                          child: widget.activityDock,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlacierActivityBackdrop(
        values: widget.backgroundValues,
        atmosphere: !widget.activityBackground,
        plain: widget.plainBackground,
        grid: widget.backgroundGrid,
        softness: widget.backgroundSoftness,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: native.drawerOpen,
              child: ExcludeSemantics(
                excluding: native.drawerOpen,
                child: IgnorePointer(
                  ignoring: native.drawerOpen,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 24,
                      compact
                          ? native.compactTopInset
                          : native.titlebarHeight + 16,
                      compact ? 12 : 24,
                      compact ? 12 : 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact) ...[
                          AnimatedContainer(
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            width: rail ? 76 : 224,
                            clipBehavior: Clip.hardEdge,
                            decoration: const BoxDecoration(),
                            onEnd: native.onLayoutChanged,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: rail ? 76 : 224,
                              maxWidth: rail ? 76 : 224,
                              child: _sidebar(rail),
                            ),
                          ),
                          const SizedBox(width: 20),
                        ],
                        Expanded(child: content),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (compact)
              Positioned(
                left: 12,
                right: 12,
                top: native.titlebarHeight + 8,
                height: 48,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: native.leftReservation,
                    right: native.rightReservation,
                  ),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: IconButton(
                          focusNode: _nativeMenuFocus,
                          tooltip: native.drawerOpen
                              ? 'Close navigation'
                              : 'Open navigation',
                          onPressed: () =>
                              native.onDrawerChanged(!native.drawerOpen),
                          icon: const Icon(Icons.menu, size: 20),
                        ),
                      ),
                      const Spacer(),
                      SizedBox.square(
                        dimension: 44,
                        child: IconButton(
                          tooltip: 'Search · Cmd/Ctrl+K',
                          onPressed: native.drawerOpen ? null : widget.onSearch,
                          icon: const Icon(Icons.search, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (compact && native.drawerOpen)
              GlacierNativeCompactNavigation(
                onDismiss: _closeDrawer,
                child: _sidebar(false, drawer: true),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (widget.onSearch != null)
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            widget.onSearch!,
      if (widget.onSearch != null)
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            widget.onSearch!,
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final native = GlacierNativePresentationScope.maybeOf(context);
          if (native != null) {
            return _geometry(_nativeWorkspace(context, constraints, native));
          }
          final compact = constraints.maxWidth < 700;
          final rail =
              _collapsed || (constraints.maxWidth < 1050 && !_expandedByUser);
          final reduced =
              MediaQuery.disableAnimationsOf(context) ||
              View.of(context)
                  .platformDispatcher
                  .accessibilityFeatures
                  .reduceMotion;
          _measureDock();
          return _geometry(
            Scaffold(
              key: _scaffold,
              backgroundColor: Colors.transparent,
              drawer: compact
                  ? Drawer(
                      width: 280,
                      child: SafeArea(child: _sidebar(false, drawer: true)),
                    )
                  : null,
              body: GlacierActivityBackdrop(
                values: widget.backgroundValues,
                atmosphere: !widget.activityBackground,
                plain: widget.plainBackground,
                grid: widget.backgroundGrid,
                softness: widget.backgroundSoftness,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 24,
                      vertical: compact ? 8 : 16,
                    ),
                    child: Row(
                      children: [
                        if (!compact)
                          AnimatedContainer(
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            width: rail ? 76 : 224,
                            clipBehavior: Clip.hardEdge,
                            decoration: const BoxDecoration(),
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: rail ? 76 : 224,
                              maxWidth: rail ? 76 : 224,
                              child: _sidebar(rail),
                            ),
                          ),
                        if (!compact) const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (compact)
                                Row(
                                  children: [
                                    GlacierIconButton(
                                      label: 'Open navigation',
                                      icon: Icons.menu,
                                      onPressed: () =>
                                          _scaffold.currentState?.openDrawer(),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'domabas',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    GlacierIconButton(
                                      label: 'Search · Cmd/Ctrl+K',
                                      icon: Icons.search,
                                      onPressed: widget.onSearch,
                                    ),
                                  ],
                                ),
                              if (widget.toolbar != null)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: (constraints.maxHeight * .32)
                                        .clamp(80, 220),
                                  ),
                                  child: SingleChildScrollView(
                                    primary: false,
                                    child: widget.toolbar!,
                                  ),
                                ),
                              if (widget.toolbar != null)
                                const SizedBox(height: 20),
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRect(child: widget.child),
                                    if (widget.activityDock != null)
                                      Positioned(
                                        right: compact ? 8 : 20,
                                        bottom: 16,
                                        child:
                                            NotificationListener<
                                              SizeChangedLayoutNotification
                                            >(
                                              onNotification: (_) {
                                                _measureDock();
                                                return false;
                                              },
                                              child: SizeChangedLayoutNotifier(
                                                child: SizedBox(
                                                  key: _dockKey,
                                                  child: widget.activityDock,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _GlacierNavTrigger extends StatelessWidget {
  const _GlacierNavTrigger({
    super.key,
    required this.item,
    required this.rail,
    required this.selected,
    required this.onPressed,
    this.expanded,
    this.focusNode,
    this.minimumHeight = 46,
    this.focusOffset = 3,
  });
  final GlacierDestination item;
  final bool rail, selected;
  final bool? expanded;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final double minimumHeight, focusOffset;
  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTokens.of(context);
    final foreground = selected ? tokens.onSelectedNavigation : tokens.muted;
    return Tooltip(
      message: rail ? item.label : '',
      excludeFromSemantics: true,
      child: glacierInteractionOutline(
        focusOffset: focusOffset,
        builder: (states, _) => Semantics(
          container: true,
          button: true,
          label: rail ? item.label : null,
          selected: selected,
          expanded: expanded,
          child: Material(
            color: selected ? tokens.selectedNavigation : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              statesController: states,
              focusColor: Colors.transparent,
              key: ValueKey('navigation-trigger-${item.id}'),
              focusNode: focusNode,
              borderRadius: BorderRadius.circular(10),
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 20, color: foreground),
                      if (!rail) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (expanded != null)
                          AnimatedRotation(
                            turns: expanded! ? .25 : 0,
                            duration:
                                MediaQuery.disableAnimationsOf(context) ||
                                    View.of(context)
                                        .platformDispatcher
                                        .accessibilityFeatures
                                        .reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: foreground,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlacierNavigationGroup extends StatefulWidget {
  const _GlacierNavigationGroup({
    super.key,
    required this.item,
    required this.rail,
    required this.selected,
    required this.expanded,
    required this.onToggle,
    required this.onClose,
    required this.onSelected,
  });
  final GlacierDestination item;
  final bool rail, expanded;
  final String selected;
  final VoidCallback onToggle, onClose;
  final ValueChanged<String> onSelected;
  @override
  State<_GlacierNavigationGroup> createState() =>
      _GlacierNavigationGroupState();
}

class _GlacierNavigationGroupState extends State<_GlacierNavigationGroup>
    with SingleTickerProviderStateMixin {
  final _triggerFocus = FocusNode();
  final _childrenFocus = FocusScopeNode();
  final _firstFocus = FocusNode();
  final _revealTarget = GlobalKey();
  int get _revealIndex {
    final index = widget.item.children.indexWhere(
      (item) => item.id == widget.selected,
    );
    return index < 0 ? 0 : index;
  }

  late final _animation = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final _height = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  bool get _reduced =>
      MediaQuery.disableAnimationsOf(context) ||
      View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _revealChild();
  }

  void _revealChild() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !widget.expanded) return;
    final target = _revealTarget.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: _reduced ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced) _animation.value = widget.expanded ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _GlacierNavigationGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) {
      if (oldWidget.selected != widget.selected && widget.expanded) {
        _revealChild();
      }
      return;
    }
    if (!widget.expanded && _childrenFocus.hasFocus) {
      _triggerFocus.requestFocus();
    }
    if (_reduced) {
      _animation.value = widget.expanded ? 1 : 0;
      if (widget.expanded) _revealChild();
    } else if (widget.expanded) {
      _animation.forward().then((_) => _revealChild());
    } else {
      _animation.reverse();
    }
  }

  void _close() {
    if (!widget.expanded) return;
    _triggerFocus.requestFocus();
    widget.onClose();
  }

  @override
  void dispose() {
    _height.dispose();
    _animation.dispose();
    _triggerFocus.dispose();
    _childrenFocus.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): _close,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): _close,
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (!widget.expanded) {
                widget.onToggle();
              } else {
                _firstFocus.requestFocus();
              }
            },
          },
          child: _GlacierNavTrigger(
            key: widget.item.key,
            item: widget.item,
            rail: widget.rail,
            selected:
                widget.item.id == widget.selected ||
                widget.item.children.any((item) => item.id == widget.selected),
            expanded: widget.expanded,
            focusNode: _triggerFocus,
            onPressed: widget.onToggle,
          ),
        ),
        ExcludeSemantics(
          excluding: !widget.expanded,
          child: ExcludeFocus(
            excluding: !widget.expanded,
            child: IgnorePointer(
              ignoring: !widget.expanded,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => _animation.isDismissed
                    ? const SizedBox.shrink()
                    : SizeTransition(
                        key: ValueKey('navigation-children-${widget.item.id}'),
                        sizeFactor: _height,
                        alignment: Alignment.topCenter,
                        child: OverflowBox(
                          fit: OverflowBoxFit.deferToChild,
                          alignment: Alignment.topLeft,
                          minWidth: widget.rail ? 202 : null,
                          maxWidth: widget.rail ? 202 : null,
                          child: FocusScope(
                            node: _childrenFocus,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12, top: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var i = 0;
                                    i < widget.item.children.length;
                                    i++
                                  )
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: KeyedSubtree(
                                        key: i == _revealIndex
                                            ? _revealTarget
                                            : null,
                                        child: _GlacierNavTrigger(
                                          key: widget.item.children[i].key,
                                          minimumHeight: 44,
                                          focusOffset: -2,
                                          item: widget.item.children[i],
                                          rail: false,
                                          selected:
                                              widget.selected ==
                                              widget.item.children[i].id,
                                          focusNode: i == 0
                                              ? _firstFocus
                                              : null,
                                          onPressed: () => widget.onSelected(
                                            widget.item.children[i].id,
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
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
