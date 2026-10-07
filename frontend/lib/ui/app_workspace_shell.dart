import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_navigation_button.dart';
import 'app_navigation_motion.dart';
import 'app_presenters.dart';
import 'app_paper_canvas.dart';
import 'app_theme.dart';
import 'app_workspace_action.dart';

@immutable
final class AppNavigationItem {
  const AppNavigationItem({
    required this.id,
    required this.label,
    required this.icon,
    this.key,
  });

  final String id;
  final String label;
  final IconData icon;
  final Key? key;
}

@immutable
final class AppNavigationGroup {
  AppNavigationGroup({
    required this.id,
    required this.label,
    required this.icon,
    required List<AppNavigationItem> items,
    String? compactLabel,
    this.collapsible = true,
  }) : compactLabel = compactLabel ?? label,
       items = List.unmodifiable(items);

  final String id;
  final String label;
  final String compactLabel;
  final IconData icon;
  final List<AppNavigationItem> items;
  final bool collapsible;
}

final class AppWorkspaceShell extends StatefulWidget {
  const AppWorkspaceShell({
    super.key,
    required this.groups,
    required this.selectedId,
    required this.onSelected,
    required this.libraryPicker,
    required this.accountLabel,
    required this.onLogout,
    required this.child,
    this.actions = const [],
    this.utilityActions = const [],
    this.activityIndicator,
    this.mobileGroups,
    this.mobilePrimaryGroupIds,
  });

  final List<AppNavigationGroup> groups;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Widget libraryPicker;
  final String accountLabel;
  final VoidCallback onLogout;
  final Widget child;
  final List<AppWorkspaceAction> actions;
  final List<AppWorkspaceAction> utilityActions;
  final Widget? activityIndicator;
  final List<AppNavigationGroup>? mobileGroups;
  final List<String>? mobilePrimaryGroupIds;

  @override
  State<AppWorkspaceShell> createState() => _AppWorkspaceShellState();
}

final class _WorkspaceMenuInteraction {
  _WorkspaceMenuInteraction(this.generation, this.groupId, this.navigator);
  final int generation;
  final String groupId;
  final NavigatorState navigator;
  Route<String>? route;
}

final class _AppWorkspaceShellState extends State<AppWorkspaceShell>
    with WidgetsBindingObserver {
  final Set<String> _collapsedGroups = {};
  final Map<String, FocusNode> _triggers = {};
  final ScrollController _bottomScroll = ScrollController();
  final GlobalKey _activityKey = GlobalKey();
  double _activityHeight = 0;
  bool _measuringActivity = false;
  _WorkspaceMenuInteraction? _menu;
  int _generation = 0;
  int? _layout;
  bool _reduceMotion = false;

  List<AppNavigationGroup> get _groups =>
      widget.groups.where((group) => group.items.isNotEmpty).toList();

  List<AppNavigationGroup> _mobileGroups(AppWorkspaceShell shell) {
    final groups = (shell.mobileGroups ?? shell.groups).where(
      (group) => group.items.isNotEmpty,
    );
    final primary = shell.mobilePrimaryGroupIds;
    if (primary == null) return groups.toList();
    final remaining = groups.where((group) => !primary.contains(group.id));
    return [
      for (final id in primary) ...groups.where((group) => group.id == id),
      if (remaining.isNotEmpty)
        AppNavigationGroup(
          id: 'more',
          label: 'More',
          icon: Icons.menu_rounded,
          items: [for (final group in remaining) ...group.items],
        ),
    ];
  }

  List<AppNavigationGroup> get _menuGroups => [
    ..._groups,
    ..._mobileGroups(widget),
  ];

  List<AppNavigationGroup> _currentGroups(AppWorkspaceShell shell) =>
      _layout == 0
      ? _mobileGroups(shell)
      : shell.groups.where((group) => group.items.isNotEmpty).toList();

  void _measureActivity() {
    if (_measuringActivity) return;
    _measuringActivity = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuringActivity = false;
      if (!mounted) return;
      final box = _activityKey.currentContext?.findRenderObject();
      final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
      if ((height - _activityHeight).abs() > .5) {
        setState(() => _activityHeight = height);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTriggers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(_updateMotion);
  }

  void _updateMotion() {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (reduced != _reduceMotion) {
      _reduceMotion = reduced;
      _invalidateMenu();
    }
  }

  @override
  void didUpdateWidget(AppWorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _menu;
    if (current != null) {
      final before = _currentGroups(oldWidget)
          .where((group) => group.id == current.groupId)
          .firstOrNull;
      final after = _currentGroups(widget)
          .where((group) => group.id == current.groupId)
          .firstOrNull;
      if (before == null ||
          after == null ||
          before.collapsible != after.collapsible ||
          before.items.length != after.items.length ||
          !before.items.every(
            (item) => after.items.any((other) => other.id == item.id),
          )) {
        _invalidateMenu();
      }
    }
    _syncTriggers();
  }

  void _syncTriggers() {
    final ids = _menuGroups.map((group) => group.id).toSet();
    for (final id in _triggers.keys.where((id) => !ids.contains(id)).toList()) {
      _triggers.remove(id)!.dispose();
      _collapsedGroups.remove(id);
    }
    for (final id in ids) {
      _triggers.putIfAbsent(id, () => FocusNode(debugLabel: 'navigation-$id'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invalidateMenu(restoreFocus: false);
    for (final node in _triggers.values) {
      node.dispose();
    }
    _bottomScroll.dispose();
    super.dispose();
  }

  void _removeRoute(_WorkspaceMenuInteraction menu) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = menu.route;
      if (route != null &&
          menu.navigator.mounted &&
          route.navigator == menu.navigator &&
          route.isActive) {
        menu.navigator.removeRoute(route);
      }
    });
  }

  void _restoreFocus(String groupId, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _menu != null) return;
      final node = _triggers[groupId];
      final triggerContext = node?.context;
      if (triggerContext == null || !triggerContext.mounted) return;
      final render = triggerContext.findRenderObject();
      if (node != null &&
          node.canRequestFocus &&
          render is RenderBox &&
          render.attached &&
          render.hasSize &&
          !render.size.isEmpty) {
        node.requestFocus();
      }
    });
  }

  void _invalidateMenu({bool restoreFocus = true}) {
    final current = _menu;
    _menu = null;
    _generation++;
    if (current == null) return;
    _removeRoute(current);
    if (restoreFocus) _restoreFocus(current.groupId, _generation);
  }

  bool _active(AppNavigationGroup group) =>
      group.items.any((item) => item.id == widget.selectedId);

  void _select(String id) {
    if (mounted &&
        _currentGroups(widget)
            .any((group) => group.items.any((item) => item.id == id))) {
      widget.onSelected(id);
    }
  }

  Future<void> _openGroup(
    AppNavigationGroup group,
    BuildContext triggerContext, {
    required bool mobile,
  }) async {
    if (!mounted ||
        !triggerContext.mounted ||
        _menu != null ||
        _layout != (mobile ? 0 : 1)) {
      return;
    }
    final current = _currentGroups(widget)
        .where((value) => value.id == group.id)
        .firstOrNull;
    if (current == null ||
        !current.collapsible ||
        current.items.length != group.items.length ||
        !current.items.every(
          (item) => group.items.any((other) => other.id == item.id),
        )) {
      return;
    }
    final navigator = Navigator.of(context);
    RelativeRect? position;
    if (!mobile) {
      final box = triggerContext.findRenderObject();
      final overlay = navigator.overlay?.context.findRenderObject();
      if (box is! RenderBox ||
          overlay is! RenderBox ||
          !box.attached ||
          !overlay.attached ||
          !box.hasSize ||
          !overlay.hasSize) {
        return;
      }
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final menu = _WorkspaceMenuInteraction(++_generation, group.id, navigator);
    setState(() => _menu = menu);
    String? result;
    if (mobile && group.id == 'more') {
      final themes = InheritedTheme.capture(
        from: context,
        to: navigator.context,
      );
      final route = RawDialogRoute<String>(
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        barrierColor: Colors.black54,
        requestFocus: true,
        transitionDuration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 340),
              height: double.infinity,
              child: Material(
                key: const Key('workspaceMoreDrawer'),
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(child: _chooser(context, group, menu)),
              ),
            ),
          ),
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
      );
      menu.route = route;
      result = await navigator.push(route);
    } else if (mobile) {
      final media = MediaQuery.of(context);
      final route = ModalBottomSheetRoute<String>(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: _chooser(context, group, menu),
        ),
        isScrollControlled: true,
        useSafeArea: true,
        requestFocus: true,
        modalBarrierColor: Colors.black54,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          maxHeight:
              (media.size.height -
                  media.padding.top -
                  media.viewInsets.bottom) *
              .8,
        ),
        sheetAnimationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
      );
      menu.route = route;
      result = await navigator.push(route);
    } else {
      result = await showMenu<String>(
        context: context,
        position: position!,
        requestFocus: true,
        popUpAnimationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
        items: [
          for (final item in group.items)
            PopupMenuItem<String>(
              key: item.key,
              value: item.id,
              height: 48,
              child: Builder(
                builder: (context) {
                  final route = ModalRoute.of<String>(context);
                  if (menu.route == null &&
                      route != null &&
                      route.navigator == navigator) {
                    menu.route = route;
                    if (_menu != menu || menu.generation != _generation) {
                      _removeRoute(menu);
                    }
                  }
                  return _leafContent(item);
                },
              ),
            ),
        ],
      );
    }
    if (!mounted || _menu != menu || menu.generation != _generation) return;
    final completedGroup = _currentGroups(widget)
        .where((value) => value.id == group.id)
        .firstOrNull;
    setState(() => _menu = null);
    _restoreFocus(group.id, _generation);
    if (result != null &&
        completedGroup != null &&
        completedGroup.items.any((item) => item.id == result)) {
      _select(result);
    }
  }

  void _finishMenu(_WorkspaceMenuInteraction menu, [String? result]) {
    final route = menu.route;
    if (!mounted ||
        _menu != menu ||
        menu.generation != _generation ||
        !menu.navigator.mounted ||
        route == null ||
        route.navigator != menu.navigator ||
        !route.isCurrent) {
      return;
    }
    menu.navigator.pop(result);
  }

  Widget _chooser(
    BuildContext context,
    AppNavigationGroup group,
    _WorkspaceMenuInteraction menu,
  ) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () => _finishMenu(menu),
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            key: const Key('closeNavigationChooser'),
            tooltip: 'Close navigation',
            onPressed: () => _finishMenu(menu),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const Key('navigationChooserScroll'),
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    group.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.accountLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final item in group.items) ...[
                  if (group.id == 'more' &&
                      (widget.mobileGroups ?? widget.groups).any(
                        (entry) =>
                            entry.collapsible &&
                            entry.items.isNotEmpty &&
                            entry.items.first.id == item.id,
                      ))
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Semantics(
                        header: true,
                        child: Text(
                          (widget.mobileGroups ?? widget.groups)
                              .firstWhere(
                                (entry) =>
                                    entry.items.isNotEmpty &&
                                    entry.items.first.id == item.id,
                              )
                              .label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: AppNavigationButton(
                      key: item.key,
                      label: item.label,
                      selected: item.id == widget.selectedId,
                      reduceMotion: _reduceMotion,
                      onPressed: () => _finishMenu(menu, item.id),
                      child: _leafContent(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < AppLayout.mobileBreakpoint;
      final desktop = constraints.maxWidth >= AppLayout.desktopBreakpoint;
      final layout = mobile
          ? 0
          : desktop
          ? 2
          : 1;
      if (_layout != null && _layout != layout) _invalidateMenu();
      _layout = layout;
      final media = MediaQuery.of(context);
      final showBottom = mobile && media.viewInsets.bottom == 0;
      final usableHeight =
          (constraints.maxHeight - media.padding.top - media.viewInsets.bottom)
              .clamp(0.0, constraints.maxHeight);
      final inset = mobile ? 12.0 : 16.0;
      _measureActivity();
      return Scaffold(
        extendBody: true,
        floatingActionButton: widget.activityIndicator == null
            ? null
            : NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  _measureActivity();
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: SizedBox(
                    key: _activityKey,
                    child: widget.activityIndicator,
                  ),
                ),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: showBottom
            ? _bottomNavigation(usableHeight * .4)
            : null,
        body: AppPaperCanvas(
          child: SafeArea(
            bottom: !showBottom,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!mobile)
                  Padding(
                    padding: EdgeInsets.fromLTRB(inset, inset, 0, inset),
                    child: SizedBox(
                      width: desktop ? 256 : 88,
                      child: desktop ? _sidebar() : _rail(),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) => Column(
                      children: [
                        _header(mobile, inset),
                        Expanded(
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              padding: MediaQuery.paddingOf(context).copyWith(
                                bottom:
                                    MediaQuery.paddingOf(context).bottom +
                                    (_activityHeight > 0
                                        ? _activityHeight + 32
                                        : 0),
                              ),
                            ),
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  List<AppWorkspaceAction> get _utilities => [
    ...widget.utilityActions,
    AppWorkspaceAction(
      id: 'logout',
      label: 'Sign out',
      icon: Icons.logout_rounded,
      onPressed: () async => widget.onLogout(),
    ),
  ];

  Widget _header(bool mobile, double inset) => Padding(
    padding: EdgeInsets.fromLTRB(inset, inset, inset, 0),
    child: AppSurface(
      key: const Key('workspaceHeader'),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          final primary = widget.actions
              .where((action) => action.id == 'uploadFiles')
              .firstOrNull;
          final showPrimary = primary != null && constraints.maxWidth >= 320;
          final labeled = constraints.maxWidth >= 620 && !largeText;
          final visible = <AppWorkspaceAction>[
            if (showPrimary) primary,
            if (constraints.maxWidth >= 800 && !largeText)
              ...widget.actions.where(
                (action) =>
                    action.id == 'scanDocument' || action.id == 'newDocument',
              ),
          ];
          final overflow = widget.actions
              .where((action) => !visible.contains(action))
              .toList();
          return Row(
            key: const Key('workspaceHeaderRow'),
            children: [
              Expanded(child: widget.libraryPicker),
              for (final action in visible) ...[
                const SizedBox(width: 8),
                AppWorkspaceActionButton(
                  action: action,
                  primary: identical(action, primary),
                  labeled: labeled,
                ),
              ],
              if (overflow.isNotEmpty || mobile) ...[
                const SizedBox(width: 8),
                AppWorkspaceActionMenu(
                  key: const Key('workspaceMore'),
                  owner: widget.selectedId,
                  actions: overflow,
                  utilities: mobile ? _utilities : const [],
                  accountLabel: mobile ? widget.accountLabel : null,
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  Widget _sidebar() => AppSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
          child: Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Domabas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in _groups) ...[
                  if (group.collapsible) _groupHeader(group),
                  if (!group.collapsible ||
                      !_collapsedGroups.contains(group.id))
                    for (final item in group.items) _destination(item, group),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .3,
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final action in _utilities)
                      AppWorkspaceActionButton(action: action),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        size: 24,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Tooltip(
                          message: widget.accountLabel,
                          child: Text(
                            widget.accountLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
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
      ],
    ),
  );

  Widget _groupHeader(AppNavigationGroup group) {
    final collapsed = _collapsedGroups.contains(group.id);
    return AppNavigationButton(
      key: Key('navigation-${group.id}'),
      label: group.label,
      outlinedHover: true,
      selected: _active(group),
      expanded: !collapsed,
      focusNode: _triggers[group.id],
      reduceMotion: _reduceMotion,
      onPressed: () => setState(() {
        if (collapsed) {
          _collapsedGroups.remove(group.id);
        } else {
          _collapsedGroups.add(group.id);
        }
      }),
      child: Row(
        children: [
          Icon(group.icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(group.label)),
          const SizedBox(width: 4),
          AppNavigationRotation(
            turns: collapsed ? 0 : .5,
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: const Icon(Icons.expand_more, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _destination(AppNavigationItem item, AppNavigationGroup group) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: AppNavigationButton(
          key: item.key,
          label: item.label,
          selected: item.id == widget.selectedId,
          focusNode: group.collapsible ? null : _triggers[group.id],
          outlinedHover: true,
          reduceMotion: _reduceMotion,
          onPressed: () => _select(item.id),
          child: _leafContent(item, dot: true),
        ),
      );

  Widget _leafContent(AppNavigationItem item, {bool dot = false}) => Row(
    children: [
      Icon(item.icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(item.label)),
      if (item.id == widget.selectedId) ...[
        const SizedBox(width: 8),
        Icon(dot ? Icons.circle : Icons.check_rounded, size: dot ? 6 : 18),
      ],
    ],
  );

  Widget _rail() => AppSurface(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
    child: Column(
      children: [
        const _BrandMark(),
        const SizedBox(height: 28),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final group in _groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Tooltip(
                      message: group.label,
                      excludeFromSemantics: true,
                      child: Builder(
                        builder: (context) => AppNavigationButton(
                          key: group.collapsible
                              ? Key('navigation-${group.id}')
                              : group.items.first.key,
                          label: group.label,
                          outlinedHover: true,
                          selected: _active(group),
                          expanded: group.collapsible
                              ? _menu?.groupId == group.id
                              : null,
                          focusNode: _triggers[group.id],
                          reduceMotion: _reduceMotion,
                          padding: const EdgeInsets.all(12),
                          onPressed: () => group.collapsible
                              ? _openGroup(group, context, mobile: false)
                              : _select(group.items.first.id),
                          child: Icon(group.icon),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppWorkspaceActionMenu(
            key: const Key('workspaceAccount'),
            owner: widget.selectedId,
            actions: const [],
            utilities: _utilities,
            accountLabel: widget.accountLabel,
            label: 'Account',
            icon: Icons.account_circle_outlined,
          ),
        ),
      ],
    ),
  );

  Widget _bottomNavigation(double maxHeight) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Workspace navigation',
    child: ConstrainedBox(
      key: const Key('workspaceBottomNavigation'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Scrollbar(
            controller: _bottomScroll,
            child: SingleChildScrollView(
              controller: _bottomScroll,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final groups = _mobileGroups(widget);
                  if (groups.isEmpty) return const SizedBox.shrink();
                  final style = Theme.of(context).textTheme.labelMedium!
                      .copyWith(fontWeight: FontWeight.w600);
                  Size labelSize(AppNavigationGroup group) {
                    final painter = TextPainter(
                      text: TextSpan(text: group.compactLabel, style: style),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: Directionality.of(context),
                      maxLines: 1,
                    )..layout();
                    final size = painter.size;
                    painter.dispose();
                    return size;
                  }

                  final documents = groups
                      .where((group) => group.id == 'documents')
                      .firstOrNull;
                  final sides = groups
                      .where((group) => group != documents)
                      .toList();
                  final leftCount = sides.length ~/ 2;
                  final left = sides.take(leftCount).toList();
                  final right = sides.skip(leftCount).toList();
                  final centerWidth = documents == null
                      ? 0.0
                      : (labelSize(documents).width + 12).clamp(76.0, 96.0);
                  final wingWidth = (constraints.maxWidth - centerWidth) / 2;
                  bool wingFits(List<AppNavigationGroup> entries) =>
                      entries.isEmpty ||
                      entries.every(
                        (group) =>
                            wingWidth / entries.length >= 48 &&
                            labelSize(group).width + 10 <=
                                wingWidth / entries.length &&
                            labelSize(group).height <= 20,
                      );
                  final notched =
                      documents != null &&
                      constraints.maxWidth >= 336 &&
                      sides.length <= 4 &&
                      labelSize(documents).width + 8 <= centerWidth &&
                      labelSize(documents).height <= 20 &&
                      wingFits(left) &&
                      wingFits(right);
                  if (notched) {
                    Widget wing(List<AppNavigationGroup> entries) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Row(
                          children: [
                            for (final group in entries)
                              Expanded(
                                child: _bottomButton(
                                  group,
                                  style: style,
                                  notched: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    final colors = Theme.of(context).colorScheme;
                    return SizedBox(
                      height: 92,
                      child: CustomPaint(
                        key: const Key('workspaceNotchedNavigation'),
                        painter: _WorkspaceNavigationSurfacePainter(
                          surface: colors.surface,
                          shadow: AppElevation.materialShadow(colors),
                        ),
                        child: FocusTraversalGroup(
                          policy: ReadingOrderTraversalPolicy(),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              wing(left),
                              SizedBox(
                                width: centerWidth,
                                child: _bottomButton(
                                  documents,
                                  style: style,
                                  notched: true,
                                  raised: true,
                                ),
                              ),
                              wing(right),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  final ordered = [?documents, ...sides];
                  final remaining = ordered.skip(1).toList();
                  final paired = remaining.every(
                    (group) =>
                        labelSize(group).width + 86 <=
                        (constraints.maxWidth - 12) / 2,
                  );
                  return AppSurface(
                    key: const Key('workspaceNavigationFallback'),
                    elevation: AppElevation.floating,
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _bottomButton(
                          ordered.first,
                          style: style,
                          horizontal: true,
                        ),
                        for (
                          var index = 0;
                          index < remaining.length;
                          index += paired ? 2 : 1
                        )
                          if (paired && index + 1 < remaining.length)
                            Row(
                              children: [
                                Expanded(
                                  child: _bottomButton(
                                    remaining[index],
                                    style: style,
                                    horizontal: true,
                                  ),
                                ),
                                Expanded(
                                  child: _bottomButton(
                                    remaining[index + 1],
                                    style: style,
                                    horizontal: true,
                                  ),
                                ),
                              ],
                            )
                          else
                            _bottomButton(
                              remaining[index],
                              style: style,
                              horizontal: true,
                            ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bottomButton(
    AppNavigationGroup group, {
    required TextStyle style,
    bool horizontal = false,
    bool notched = false,
    bool raised = false,
  }) {
    final selected = _active(group);
    final colors = Theme.of(context).colorScheme;
    final prominent = group.id == 'documents';
    final icon = Container(
      key: prominent ? const Key('navigationDocumentsCircle') : null,
      width: raised
          ? 56
          : horizontal
          ? 32
          : 28,
      height: raised
          ? 56
          : horizontal
          ? 32
          : 28,
      decoration: BoxDecoration(
        color: prominent ? colors.primary : colors.primary.withValues(alpha: 0),
        shape: BoxShape.circle,
        boxShadow: prominent ? AppElevation.control.shadows(context) : const [],
      ),
      child: Icon(
        group.icon,
        color: prominent
            ? colors.onPrimary
            : selected
            ? colors.primary
            : colors.onSurfaceVariant,
        size: raised ? 28 : 24,
      ),
    );
    final label = Text(
      group.compactLabel,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: style.copyWith(
        color: selected ? colors.onSurface : colors.onSurfaceVariant,
      ),
    );
    final marker = AppNavigationDecoration(
      key: Key('navigation-marker-${group.id}'),
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: selected ? 1 : 0),
        shape: BoxShape.circle,
      ),
      child: const SizedBox(width: 4, height: 4),
    );
    return Builder(
      builder: (context) => AppNavigationButton(
        key: group.collapsible
            ? Key('navigation-${group.id}')
            : group.items.first.key,
        label: group.label,
        selected: selected,
        expanded: group.collapsible ? _menu?.groupId == group.id : null,
        focusNode: _triggers[group.id],
        reduceMotion: _reduceMotion,
        fillSelection: false,
        fillInteraction: !raised,
        padding: notched
            ? const EdgeInsets.symmetric(horizontal: 2)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        onPressed: () => group.collapsible
            ? _openGroup(group, context, mobile: true)
            : _select(group.items.first.id),
        child: horizontal
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: label),
                  const SizedBox(width: 8),
                  marker,
                ],
              )
            : Column(
                mainAxisSize: raised ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: raised
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 4),
                  label,
                  const SizedBox(height: 4),
                  marker,
                ],
              ),
      ),
    );
  }
}

final class _WorkspaceNavigationSurfacePainter extends CustomPainter {
  const _WorkspaceNavigationSurfacePainter({
    required this.surface,
    required this.shadow,
  });

  final Color surface;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final host = Rect.fromLTRB(.5, 24.5, size.width - .5, size.height - .5);
    final rounded = Path()
      ..addRRect(RRect.fromRectAndRadius(host, const Radius.circular(24)));
    final cutout = const CircularNotchedRectangle().getOuterPath(
      host,
      Rect.fromCircle(center: Offset(size.width / 2, 30), radius: 32),
    );
    final path = Path.combine(PathOperation.intersect, rounded, cutout);
    canvas.drawShadow(path, shadow, 12, true);
    canvas.drawPath(path, Paint()..color = surface);
  }

  @override
  bool shouldRepaint(_WorkspaceNavigationSurfacePainter oldDelegate) =>
      surface != oldDelegate.surface || shadow != oldDelegate.shadow;
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Image.asset(
      'assets/branding/domabas-mark.png',
      color: Theme.of(context).colorScheme.onPrimary,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
    ),
  );
}
