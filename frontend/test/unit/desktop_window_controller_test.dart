import 'dart:async';

import 'package:domabas/app/platform/desktop_window_channel.dart';
import 'package:domabas/app/platform/desktop_window_controller.dart';
import 'package:domabas/app/platform/desktop_window_port.dart';
import 'package:domabas/ui/glacier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class WindowPortFake implements DesktopWindowPort {
  WindowPortFake({this.platform = GlacierNativePlatform.windows});
  final GlacierNativePlatform platform;
  int missingInitializations = 0;
  int rejectedDecorations = 0;
  final events = StreamController<DesktopWindowSnapshot>.broadcast(sync: true);
  final calls = <String>[];
  int revision = 0;
  bool failInitialize = false,
      failLayout = false,
      pendingLayout = false,
      failCommand = false,
      disposed = false;
  Completer<void>? layoutGate;
  bool pendingFullscreenRecovery = false, failRecovery = false;
  DesktopWindowSnapshot snapshot({
    bool client = false,
    int? rev,
    GlacierNativeWindowMode mode = GlacierNativeWindowMode.restored,
  }) => DesktopWindowSnapshot(
    revision: rev ?? ++revision,
    ready: true,
    state: GlacierNativeWindowState(
      platform: platform,
      mode: mode,
      decoration: client
          ? GlacierNativeDecoration.client
          : GlacierNativeDecoration.host,
    ),
  );
  @override
  Stream<DesktopWindowSnapshot> get changes => events.stream;
  @override
  Future<DesktopWindowSnapshot> initialize() async {
    calls.add('initialize');
    if (failInitialize || missingInitializations-- > 0) {
      throw MissingPluginException();
    }
    return snapshot();
  }

  @override
  Future<DesktopWindowSnapshot> setClientDecoration(bool enabled) async {
    calls.add('decoration:$enabled');
    if (enabled && rejectedDecorations-- > 0) {
      throw PlatformException(code: 'not_ready');
    }
    if (!enabled && failRecovery) throw StateError('recovery');
    if (!enabled && pendingFullscreenRecovery) {
      return snapshot(client: true, mode: GlacierNativeWindowMode.fullscreen);
    }
    return snapshot(client: enabled);
  }

  @override
  Future<void> setLayout(int sequence, GlacierNativeWindowLayout layout) async {
    calls.add('layout:$sequence');
    if (pendingLayout) throw PlatformException(code: 'layout_pending');
    if (failLayout) throw StateError('layout');
    await layoutGate?.future;
  }

  @override
  Future<void> request(GlacierNativeCommand command) async {
    calls.add(command.name);
    if (failCommand) throw StateError('command');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
  }
}

GlacierNativeWindowLayout layout() => GlacierNativeWindowLayout(
  viewport: const Size(800, 600),
  titlebar: const Rect.fromLTWH(0, 0, 800, 44),
  candidateDragRegions: const [Rect.fromLTWH(0, 0, 800, 44)],
  interactiveExclusions: const [Rect.fromLTWH(662, 0, 138, 44)],
  nativeControlReservations: const [],
  captionBounds: const {
    GlacierNativeCommand.maximize: Rect.fromLTWH(708, 0, 46, 44),
  },
);
Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'decoration waits for current accepted layout and native state',
    () async {
      final port = WindowPortFake()..layoutGate = Completer<void>();
      final controller = DesktopWindowController(port);
      await controller.initialize();
      expect(
        controller.snapshot!.state.decoration,
        GlacierNativeDecoration.host,
      );
      controller.layoutChanged(layout());
      await flush();
      expect(port.calls, ['initialize', 'layout:1']);
      port.layoutGate!.complete();
      await flush();
      expect(port.calls.last, 'decoration:true');
      expect(
        controller.snapshot!.state.decoration,
        GlacierNativeDecoration.client,
      );
      await controller.close();
    },
  );
  test(
    'missing bridge keeps system decorations and removes client capability',
    () async {
      final port = WindowPortFake()..failInitialize = true;
      final controller = DesktopWindowController(port);
      await controller.initialize();
      expect(controller.available, false);
      expect(port.calls.where((value) => value == 'initialize'), hasLength(10));
      expect(port.calls.last, 'decoration:false');
      controller.request(GlacierNativeCommand.close);
      await flush();
      expect(port.calls, isNot(contains('close')));
      await controller.close();
    },
  );
  test(
    'invalid layout recovers system chrome without enabling client chrome',
    () async {
      final port = WindowPortFake()..failLayout = true;
      final controller = DesktopWindowController(port);
      await controller.initialize();
      controller.layoutChanged(layout());
      await flush();
      expect(controller.available, false);
      expect(port.calls, contains('decoration:false'));
      expect(port.calls, isNot(contains('decoration:true')));
      await controller.close();
    },
  );
  test(
    'resize race waits for next layout instead of abandoning native frame',
    () async {
      final port = WindowPortFake()..pendingLayout = true;
      final controller = DesktopWindowController(port);
      await controller.initialize();
      controller.layoutChanged(layout());
      await flush();
      expect(controller.available, true);
      expect(port.calls, isNot(contains('decoration:true')));
      port.pendingLayout = false;
      controller.layoutChanged(layout());
      await flush();
      expect(port.calls.last, 'decoration:true');
      await controller.close();
    },
  );
  test('stale queued layouts cannot enable client decoration', () async {
    final port = WindowPortFake()..layoutGate = Completer<void>();
    final controller = DesktopWindowController(port);
    await controller.initialize();
    controller.layoutChanged(layout());
    await flush();
    controller.layoutChanged(layout());
    port.layoutGate!.complete();
    await flush();
    expect(port.calls, [
      'initialize',
      'layout:1',
      'layout:2',
      'decoration:true',
    ]);
    await controller.close();
  });
  test(
    'commands never predict OS mode and older host snapshots are ignored',
    () async {
      final port = WindowPortFake();
      final controller = DesktopWindowController(port);
      await controller.initialize();
      controller.request(GlacierNativeCommand.maximize);
      await flush();
      expect(controller.snapshot!.state.mode, GlacierNativeWindowMode.restored);
      port.events.add(
        port.snapshot(rev: 10, mode: GlacierNativeWindowMode.maximized),
      );
      port.events.add(port.snapshot(rev: 9));
      expect(
        controller.snapshot!.state.mode,
        GlacierNativeWindowMode.maximized,
      );
      await controller.close();
    },
  );
  test(
    'command failure restores host decoration and does not retry the command',
    () async {
      final port = WindowPortFake()..failCommand = true;
      final controller = DesktopWindowController(port);
      await controller.initialize();
      controller.request(GlacierNativeCommand.maximize);
      await flush();
      expect(port.calls, ['initialize', 'maximize', 'decoration:false']);
      expect(controller.available, false);
      await controller.close();
    },
  );
  test('dispose cancels pending activation and host listeners', () async {
    final port = WindowPortFake()..layoutGate = Completer<void>();
    final controller = DesktopWindowController(port);
    await controller.initialize();
    controller.layoutChanged(layout());
    await flush();
    await controller.close();
    port.layoutGate!.complete();
    await flush();
    expect(port.disposed, true);
    expect(port.events.hasListener, false);
    expect(port.calls, isNot(contains('decoration:true')));
  });
  test(
    'typed caption geometry is immutable and participates in layout equality',
    () {
      final first = layout();
      expect(() => first.captionBounds.clear(), throwsUnsupportedError);
      expect(first, layout());
      expect(first.hashCode, layout().hashCode);
      expect(first.canDragAt(const Offset(720, 20)), false);
    },
  );
  test(
    'channel encodes typed caption regions and rejects a foreign protocol',
    () async {
      const channel = MethodChannel('dev.domabas/desktop_window');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? arguments;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setLayoutRegions') {
          arguments = call.arguments as Map;
          return null;
        }
        return {'protocolVersion': 2};
      });
      final port = DesktopWindowChannel();
      await port.setLayout(7, layout());
      expect(arguments!['sequence'], 7);
      expect((arguments!['captions'] as Map)['maximize'], [
        708.0,
        0.0,
        46.0,
        44.0,
      ]);
      await expectLater(port.initialize(), throwsFormatException);
      await port.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  test('fullscreen recovery retains controls until actual host exit and decoration acknowledgement', () async {
    final port = WindowPortFake()..pendingFullscreenRecovery = true;
    final controller = DesktopWindowController(port);
    await controller.initialize();
    port.events.add(
      port.snapshot(client: true, mode: GlacierNativeWindowMode.fullscreen),
    );
    port.failLayout = true;
    controller.layoutChanged(layout());
    await flush();
    expect(controller.available, false);
    expect(controller.frameVisible, true);
    expect(controller.snapshot!.state.fullscreen, true);
    controller.request(GlacierNativeCommand.maximize);
    await flush();
    expect(port.calls, isNot(contains('maximize')));
    controller.request(GlacierNativeCommand.exitFullscreen);
    await flush();
    expect(
      port.calls.where((call) => call == 'decoration:false'),
      hasLength(2),
    );
    port.events.add(port.snapshot(client: true));
    expect(
      controller.frameVisible,
      true,
      reason: 'Leaving fullscreen alone has not restored system chrome',
    );
    port.events.add(port.snapshot(client: false));
    expect(controller.frameVisible, false);
    await controller.close();
  });
  test(
    'failed fullscreen restoration keeps Exit retry and Close available',
    () async {
      final port = WindowPortFake()..failRecovery = true;
      final controller = DesktopWindowController(port);
      await controller.initialize();
      port.events.add(
        port.snapshot(client: true, mode: GlacierNativeWindowMode.fullscreen),
      );
      port.failLayout = true;
      controller.layoutChanged(layout());
      await flush();
      expect(controller.frameVisible, true);
      controller.request(GlacierNativeCommand.close);
      await flush();
      expect(port.calls, contains('close'));
      controller.request(GlacierNativeCommand.exitFullscreen);
      await flush();
      expect(
        port.calls.where((call) => call == 'decoration:false'),
        hasLength(2),
      );
      expect(controller.snapshot!.state.fullscreen, true);
      await controller.close();
    },
  );
  test('channel preserves Linux leading single Close layout', () async {
    const channel = MethodChannel('dev.domabas/desktop_window');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'protocolVersion': 1,
        'revision': 1,
        'platform': 'linux',
        'ready': true,
        'mode': 'restored',
        'active': true,
        'clientDecoration': true,
        'devicePixelRatio': 1.0,
        'controlLayout': 'closeOnlyLeft',
        'commands': ['close'],
      },
    );
    final port = DesktopWindowChannel();
    final state = (await port.initialize()).state;
    expect(state.controlsOnLeft, true);
    expect(state.captionCommands, [GlacierNativeCommand.close]);
    await port.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
