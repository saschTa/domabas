import 'package:flutter/material.dart';

final class AppNavigationDecoration extends ImplicitlyAnimatedWidget {
  const AppNavigationDecoration({
    super.key,
    required super.duration,
    required this.decoration,
    required this.child,
  });

  final Decoration decoration;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AppNavigationDecoration> createState() =>
      _AppNavigationDecorationState();
}

final class _AppNavigationDecorationState
    extends AnimatedWidgetBaseState<AppNavigationDecoration> {
  DecorationTween? _decoration;

  @override
  void didUpdateWidget(AppNavigationDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration == Duration.zero) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _decoration = visitor(
      _decoration,
      widget.decoration,
      (dynamic value) => DecorationTween(begin: value as Decoration),
    ) as DecorationTween?;
  }

  @override
  Widget build(BuildContext context) {
    final decoration = _decoration!.evaluate(animation);
    return DecoratedBox(
      decoration: decoration,
      child: Padding(padding: decoration.padding, child: widget.child),
    );
  }
}

final class AppNavigationRotation extends ImplicitlyAnimatedWidget {
  const AppNavigationRotation({
    super.key,
    required super.duration,
    required this.turns,
    required this.child,
  });

  final double turns;
  final Widget child;

  @override
  AnimatedWidgetBaseState<AppNavigationRotation> createState() =>
      _AppNavigationRotationState();
}

final class _AppNavigationRotationState
    extends AnimatedWidgetBaseState<AppNavigationRotation> {
  Tween<double>? _turns;

  @override
  void didUpdateWidget(AppNavigationRotation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration == Duration.zero) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _turns = visitor(
      _turns,
      widget.turns,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns!.animate(animation),
    child: widget.child,
  );
}
