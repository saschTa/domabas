import 'desktop_upload_bridge.dart';

DesktopUploadBridge createDesktopUploadBridge({
  required bool Function() canAcquire,
  required void Function() onBusyChanged,
}) => InactiveDesktopUploadBridge();

final class InactiveDesktopUploadBridge implements DesktopUploadBridge {
  @override
  bool get portalBusy => false;
  @override
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener) {}
  @override
  Future<void> dispose() async {}
}
