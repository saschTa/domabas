import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

class GlacierWorkspaceGeometry extends InheritedWidget {
  const GlacierWorkspaceGeometry({
    super.key,
    required this.trailingExtent,
    required this.overlayMinimumTop,
    required this.onToolbarBottomChanged,
    required this.onActivityPanelExtentChanged,
    this.endActionsHeight = 0,
    this.onEndActionsHeightChanged,
    required super.child,
  });
  final double trailingExtent, overlayMinimumTop, endActionsHeight;
  final ValueChanged<double>? onEndActionsHeightChanged;
  final ValueChanged<double> onToolbarBottomChanged,
      onActivityPanelExtentChanged;
  static GlacierWorkspaceGeometry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlacierWorkspaceGeometry>();
  static double trailingOf(BuildContext context, {double existingBottom = 0}) =>
      ((maybeOf(context)?.trailingExtent ?? existingBottom) - existingBottom)
          .clamp(0, double.infinity);
  static Widget measureEndActions(
    BuildContext context, {
    required Widget child,
    double followingExtent = 0,
  }) {
    final callback = maybeOf(context)?.onEndActionsHeightChanged;
    return callback == null
        ? child
        : _GlacierEndActionsMeasure(
            onChanged: callback,
            followingExtent: followingExtent,
            child: child,
          );
  }

  @override
  bool updateShouldNotify(GlacierWorkspaceGeometry oldWidget) =>
      trailingExtent != oldWidget.trailingExtent ||
      overlayMinimumTop != oldWidget.overlayMinimumTop ||
      endActionsHeight != oldWidget.endActionsHeight;
}

class _GlacierEndActionsMeasure extends SingleChildRenderObjectWidget {
  const _GlacierEndActionsMeasure({
    required this.onChanged,
    required this.followingExtent,
    required super.child,
  });
  final ValueChanged<double> onChanged;
  final double followingExtent;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlacierEndActions(onChanged, followingExtent);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlacierEndActions renderObject,
  ) => renderObject.update(onChanged, followingExtent);
}

class _RenderGlacierEndActions extends RenderProxyBox {
  _RenderGlacierEndActions(this.onChanged, this.followingExtent);
  ValueChanged<double> onChanged;
  double followingExtent;
  double? reported;
  void update(ValueChanged<double> callback, double extent) {
    onChanged = callback;
    followingExtent = extent;
    reported = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final extent = size.height + followingExtent;
    if (reported == extent) return;
    reported = extent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onChanged(extent);
    });
  }

  @override
  void detach() {
    final callback = onChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(0));
    super.detach();
  }
}
