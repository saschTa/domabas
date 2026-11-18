import '../../ui/glacier/glacier_native_values.dart';

class DesktopWindowSnapshot {
  const DesktopWindowSnapshot({
    required this.revision,
    required this.state,
    required this.ready,
  });
  final int revision;
  final GlacierNativeWindowState state;
  final bool ready;
}

abstract interface class DesktopWindowPort {
  Stream<DesktopWindowSnapshot> get changes;
  Future<DesktopWindowSnapshot> initialize();
  Future<DesktopWindowSnapshot> setClientDecoration(bool enabled);
  Future<void> setLayout(int sequence, GlacierNativeWindowLayout layout);
  Future<void> request(GlacierNativeCommand command);
  Future<void> dispose();
}
