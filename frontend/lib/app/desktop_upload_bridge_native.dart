import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';

import 'desktop_upload_bridge.dart';
import 'desktop_upload_bridge_stub.dart';

DesktopUploadBridge createDesktopUploadBridge({
  required bool Function() canAcquire,
  required void Function() onBusyChanged,
}) => Platform.isLinux || Platform.isWindows
    ? NativeDesktopUploadBridge(
        canAcquire: canAcquire,
        onBusyChanged: onBusyChanged,
      )
    : InactiveDesktopUploadBridge();

final class NativeDesktopUploadBridge implements DesktopUploadBridge {
  NativeDesktopUploadBridge({
    required bool Function() canAcquire,
    required void Function() onBusyChanged,
  }) : _controller = DesktopDropController(
         canStartPortal: canAcquire,
         onPortalBusyChanged: (_) => onBusyChanged(),
       );
  final DesktopDropController _controller;
  DesktopDropRegistration? _registration;
  Object? _owner;
  @override
  bool get portalBusy => _controller.portalBusy;
  @override
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener) {
    if (identical(owner, _owner)) return;
    _registration?.dispose();
    _registration = null;
    _owner = owner;
    if (owner != null && listener != null) {
      _registration = _controller.listen((event) {
        listener(switch (event.kind) {
          DesktopDropEventKind.entered ||
          DesktopDropEventKind.updated => const DesktopUploadEvent(hover: true),
          DesktopDropEventKind.exited => const DesktopUploadEvent(hover: false),
          DesktopDropEventKind.files => DesktopUploadEvent(
            paths: event.paths,
            fromPortal: event.fromPortal,
          ),
          DesktopDropEventKind.rejected => DesktopUploadEvent(
            rejection: event.message ?? 'No files could be received.',
          ),
        });
      });
    }
  }

  @override
  Future<void> dispose() => _controller.dispose();
}
