import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../ui/glacier.dart';
import 'platform/desktop_window_channel.dart';
import 'platform/desktop_window_controller.dart';

class NativeDesktopHost extends StatefulWidget {
  const NativeDesktopHost({super.key, required this.child, this.controller});
  final Widget child;
  final DesktopWindowController? controller;
  @override
  State<NativeDesktopHost> createState() => _NativeDesktopHostState();
}

class _NativeDesktopHostState extends State<NativeDesktopHost> {
  DesktopWindowController? _controller;
  @override
  void initState() {
    super.initState();
    final desktop =
        !kIsWeb &&
        const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform);
    _controller =
        widget.controller ??
        (desktop ? DesktopWindowController(DesktopWindowChannel()) : null);
    if (_controller != null) unawaited(_controller!.initialize());
  }

  @override
  void dispose() {
    if (widget.controller == null) unawaited(_controller?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DesktopWindowScope(controller: _controller, child: widget.child);
}

class _DesktopWindowScope extends InheritedWidget {
  const _DesktopWindowScope({required this.controller, required super.child});
  final DesktopWindowController? controller;
  @override
  bool updateShouldNotify(_DesktopWindowScope oldWidget) =>
      controller != oldWidget.controller;
}

class DesktopWindowRouteObserver extends NavigatorObserver {
  final modalOpen = ValueNotifier(false);
  bool _disposed = false;
  void dispose() {
    _disposed = true;
    modalOpen.dispose();
  }

  final List<Route<dynamic>> _routes = [];
  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) modalOpen.value = _routes.length > 1;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _changed();
  }
}

class NativeDesktopFrame extends StatelessWidget {
  const NativeDesktopFrame({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.observer,
    this.library = 'Domabas',
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final DesktopWindowRouteObserver observer;
  final String library;
  @override
  Widget build(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<_DesktopWindowScope>()
        ?.controller;
    if (controller == null) return child;
    return Overlay.wrap(
      child: BlocBuilder<DesktopWindowController, DesktopWindowStatus>(
        bloc: controller,
        builder: (context, _) => ValueListenableBuilder<bool>(
          valueListenable: observer.modalOpen,
          builder: (context, modalOpen, _) {
            if (!controller.frameVisible) return child;
            final snapshot = controller.snapshot!;
            return GlacierNativeFrame(
              state: snapshot.state.copyWith(
                library: library,
                controlsRevealed:
                    controller.recovering || snapshot.state.controlsRevealed,
                supportedCommands: controller.recovering
                    ? snapshot.state.supportedCommands.intersection({
                        GlacierNativeCommand.close,
                        GlacierNativeCommand.exitFullscreen,
                      })
                    : snapshot.state.supportedCommands,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                reduceMotion: MediaQuery.disableAnimationsOf(context),
              ),
              feedback: controller.recovering ? controller.error : null,
              layoutRevision: snapshot.revision,
              contentNavigatorKey: navigatorKey,
              contentModalOpen: modalOpen,
              commands: GlacierNativeWindowCommands(
                onClose: () => controller.request(GlacierNativeCommand.close),
                onMinimize: () =>
                    controller.request(GlacierNativeCommand.minimize),
                onMaximize: () =>
                    controller.request(GlacierNativeCommand.maximize),
                onRestore: () =>
                    controller.request(GlacierNativeCommand.restore),
                onEnterFullscreen: () =>
                    controller.request(GlacierNativeCommand.enterFullscreen),
                onExitFullscreen: () =>
                    controller.request(GlacierNativeCommand.exitFullscreen),
                onTitlebarDoubleClick: () => controller.request(
                  GlacierNativeCommand.titlebarDoubleClick,
                ),
                onSystemMenu: () =>
                    controller.request(GlacierNativeCommand.systemMenu),
                onLayoutChanged: controller.layoutChanged,
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }
}
