import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

final class AppRefreshable extends StatefulWidget {
  const AppRefreshable({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function()? onRefresh;
  final Widget child;

  @override
  State<AppRefreshable> createState() => _AppRefreshableState();
}

final class _AppRefreshableState extends State<AppRefreshable> {
  static const _refreshAction = CustomSemanticsAction(label: 'Refresh');
  final _indicator = GlobalKey<RefreshIndicatorState>();
  Future<void>? _pending;
  ScrollPhysics? _platformPhysics;
  ScrollPhysics _physics = const AlwaysScrollableScrollPhysics();

  Future<void> _refresh() async {
    if (_pending case final pending?) return pending;
    final callback = widget.onRefresh;
    if (callback == null) return;
    final pending = Future<void>.sync(callback);
    _pending = pending;
    try {
      await pending;
    } finally {
      _pending = null;
    }
  }

  void _show() {
    if (widget.onRefresh != null &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _indicator.currentState?.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    final platformPhysics = behavior.getScrollPhysics(context);
    if (_platformPhysics != platformPhysics) {
      _platformPhysics = platformPhysics;
      _physics = AlwaysScrollableScrollPhysics(parent: platformPhysics);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _show,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _show,
        const SingleActivator(LogicalKeyboardKey.f5): _show,
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: Semantics(
          customSemanticsActions: {
            if (widget.onRefresh != null) _refreshAction: _show,
          },
          child: ScrollConfiguration(
            behavior: behavior.copyWith(physics: _physics),
            child: LayoutBuilder(
              builder: (context, constraints) => RefreshIndicator.adaptive(
                key: _indicator,
                onRefresh: _refresh,
                notificationPredicate: (notification) =>
                    widget.onRefresh != null &&
                    notification.depth == 0 &&
                    notification.metrics.axis == Axis.vertical,
                child: ConstrainedBox(
                  constraints: constraints,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
