import 'package:flutter/widgets.dart';

final class DocumentRouteScope extends InheritedWidget {
  const DocumentRouteScope({
    super.key,
    required this.observer,
    required super.child,
  });
  final RouteObserver<ModalRoute<void>> observer;

  static RouteObserver<ModalRoute<void>>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DocumentRouteScope>()
          ?.observer;

  @override
  bool updateShouldNotify(DocumentRouteScope oldWidget) =>
      observer != oldWidget.observer;
}
