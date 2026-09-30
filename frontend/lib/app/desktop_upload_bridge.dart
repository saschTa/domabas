import 'desktop_upload_bridge_stub.dart'
    if (dart.library.io) 'desktop_upload_bridge_native.dart'
    as platform;

final class DesktopUploadEvent {
  const DesktopUploadEvent({
    this.hover,
    this.paths,
    this.rejection,
    this.fromPortal = false,
  });
  final bool? hover;
  final List<String>? paths;
  final String? rejection;
  final bool fromPortal;
}

abstract interface class DesktopUploadBridge {
  bool get portalBusy;
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener);
  Future<void> dispose();
}

DesktopUploadBridge createDesktopUploadBridge({
  required bool Function() canAcquire,
  required void Function() onBusyChanged,
}) => platform.createDesktopUploadBridge(
  canAcquire: canAcquire,
  onBusyChanged: onBusyChanged,
);
