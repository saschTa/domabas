import 'package:flutter/material.dart';

@immutable
final class AppWorkspaceAction {
  const AppWorkspaceAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.detail,
    this.badge,
  });
  final String id, label;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final String? detail, badge;

  String get tooltip => detail == null ? label : '$label. $detail';
  Widget get visual => Badge(
    isLabelVisible: badge != null,
    label: badge == null ? null : Text(badge!),
    child: Icon(icon, size: 20),
  );
}

typedef AppWorkspaceActionBuilder = Widget Function(
  BuildContext context,
  AppWorkspaceAction action,
);

final class AppWorkspaceActionButton extends StatelessWidget {
  const AppWorkspaceActionButton({
    super.key,
    required this.action,
    this.primary = false,
    this.labeled = false,
  });
  final AppWorkspaceAction action;
  final bool primary, labeled;

  @override
  Widget build(BuildContext context) {
    if (primary && labeled) {
      return FilledButton.icon(
        key: Key(action.id),
        onPressed: action.onPressed,
        icon: action.visual,
        label: Text(action.label, maxLines: 1),
      );
    }
    if (primary) {
      return IconButton.filled(
        key: Key(action.id),
        tooltip: action.tooltip,
        onPressed: action.onPressed,
        icon: action.visual,
      );
    }
    return IconButton(
      key: Key(action.id),
      tooltip: action.tooltip,
      onPressed: action.onPressed,
      icon: action.visual,
    );
  }
}

final class AppWorkspaceActionMenu extends StatefulWidget {
  const AppWorkspaceActionMenu({
    super.key,
    required this.actions,
    required this.owner,
    this.utilities = const [],
    this.accountLabel,
    this.label = 'More actions',
    this.icon = Icons.more_horiz,
  });
  final List<AppWorkspaceAction> actions, utilities;
  final Object owner;
  final String? accountLabel;
  final String label;
  final IconData icon;

  @override
  State<AppWorkspaceActionMenu> createState() => _AppWorkspaceActionMenuState();
}

final class _AppWorkspaceActionMenuState extends State<AppWorkspaceActionMenu> {
  final _focus = FocusNode();
  final _updates = ValueNotifier(0);
  RawDialogRoute<void>? _route;
  ModalRoute<dynamic>? _ownerRoute;
  Size? _viewport;
  TextScaler? _textScaler;
  int _generation = 0;
  bool _activating = false;

  List<AppWorkspaceAction> get _actions => [
    ...widget.actions,
    ...widget.utilities,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    if (_viewport != null && (_viewport != size || _textScaler != scaler)) {
      _invalidate();
    }
    _viewport = size;
    _textScaler = scaler;
  }

  @override
  void didUpdateWidget(AppWorkspaceActionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = [
      ...oldWidget.actions,
      ...oldWidget.utilities,
    ].map((action) => action.id).join('/');
    if (oldWidget.owner != widget.owner ||
        oldIds != _actions.map((action) => action.id).join('/')) {
      _invalidate();
    } else if (_route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _route != null) _updates.value++;
      });
    }
  }

  void _restoreFocus(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          !_activating &&
          _route == null &&
          _ownerRoute?.isCurrent == true &&
          _focus.context != null &&
          _focus.canRequestFocus) {
        _focus.requestFocus();
      }
    });
  }

  void _invalidate({bool restoreFocus = true}) {
    final route = _route;
    _route = null;
    final generation = ++_generation;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
      if (restoreFocus) _restoreFocus(generation);
    }
  }

  Future<void> _show() async {
    if (_route != null ||
        _activating ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _ownerRoute = ModalRoute.of(context);
    final generation = ++_generation;
    late final RawDialogRoute<void> route;
    route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => ValueListenableBuilder(
        valueListenable: _updates,
        builder: (context, _, _) => !mounted || _route != route
            ? const SizedBox.shrink()
            : Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close actions',
                              onPressed: () {
                                if (_route == route && route.isCurrent) {
                                  route.navigator?.pop();
                                }
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final action in widget.actions)
                                _item(context, action, route, generation),
                              if (widget.utilities.isNotEmpty) ...[
                                if (widget.actions.isNotEmpty) const Divider(),
                                if (widget.accountLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      widget.accountLabel!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                for (final action in widget.utilities)
                                  _item(context, action, route, generation),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
    _route = route;
    await Navigator.of(context).push(route);
    if (!mounted || _route != route || generation != _generation) return;
    _route = null;
    _restoreFocus(generation);
  }

  Widget _item(
    BuildContext context,
    AppWorkspaceAction action,
    RawDialogRoute<void> route,
    int generation,
  ) => TextButton(
    key: Key(action.id),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: Alignment.centerLeft,
    ),
    onPressed: action.onPressed == null
        ? null
        : () => _activate(action.id, route, generation),
    child: Row(
      children: [
        action.visual,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action.label),
              if (action.detail != null)
                Text(
                  action.detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _activate(
    String id,
    RawDialogRoute<void> route,
    int generation,
  ) async {
    if (!mounted ||
        _activating ||
        generation != _generation ||
        _route != route ||
        !route.isCurrent) {
      return;
    }
    final action = _actions.where((value) => value.id == id).firstOrNull;
    if (action?.onPressed == null) return;
    _activating = true;
    _route = null;
    route.navigator?.removeRoute(route);
    try {
      await action!.onPressed!();
    } finally {
      _activating = false;
      if (mounted) _restoreFocus(generation);
    }
  }

  @override
  void dispose() {
    _invalidate(restoreFocus: false);
    _focus.dispose();
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: _focus,
    tooltip: widget.label,
    onPressed: _show,
    icon: Icon(widget.icon),
  );
}
