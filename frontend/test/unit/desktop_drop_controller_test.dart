import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Lookup implements DesktopPortalLookup {
  final result = Completer<List<String>>();
  final closed = Completer<void>();
  int closes = 0;
  @override
  Future<List<String>> retrieve(String key) => result.future;
  @override
  Future<void> close() {
    closes++;
    return closed.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'portal captures registration token and drains before delivery',
    () async {
      final lookup = _Lookup();
      final controller = DesktopDropController(portalFactory: () => lookup);
      final events = <DesktopDropEvent>[];
      final registration = controller.listen(events.add);
      await controller.handleMethodCall(
        const MethodCall('performOperation_portal', [
          'key',
          [0.0, 0.0],
        ]),
      );
      await controller.handleMethodCall(const MethodCall('exited'));
      expect(events.single.kind, DesktopDropEventKind.exited);
      lookup.result.complete(['/tmp/one.pdf']);
      await Future<void>.delayed(Duration.zero);
      expect(controller.portalBusy, isTrue);
      expect(events, hasLength(1));
      lookup.closed.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events.last.paths, ['/tmp/one.pdf']);
      expect(controller.portalBusy, isFalse);
      expect(lookup.closes, 1);
      registration.dispose();
      await controller.dispose();
    },
  );

  test(
    'removed and re-added callback never receives old portal completion',
    () async {
      final lookup = _Lookup();
      final controller = DesktopDropController(portalFactory: () => lookup);
      final events = <DesktopDropEvent>[];
      void receive(DesktopDropEvent event) => events.add(event);
      final first = controller.listen(receive);
      await controller.handleMethodCall(
        const MethodCall('performOperation_portal', [
          'key',
          [0.0, 0.0],
        ]),
      );
      first.dispose();
      controller.listen(receive);
      lookup.result.complete(['/tmp/one.pdf']);
      lookup.closed.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await controller.dispose();
    },
  );

  test('deadline reports failure but keeps one RPC lease through late result and close', () async {
    final lookup = _Lookup();
    final controller = DesktopDropController(
      portalFactory: () => lookup,
      portalDeadline: const Duration(milliseconds: 5),
    );
    final events = <DesktopDropEvent>[];
    controller.listen(events.add);
    await controller.handleMethodCall(
      const MethodCall('performOperation_portal', [
        'key',
        [0.0, 0.0],
      ]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events.single.kind, DesktopDropEventKind.rejected);
    expect(controller.portalBusy, isTrue);
    await controller.handleMethodCall(
      const MethodCall('performOperation_portal', [
        'new',
        [0.0, 0.0],
      ]),
    );
    expect(events.last.message, contains('Finishing'));
    lookup.closed.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.portalBusy, isTrue);
    lookup.result.complete(['/tmp/late.pdf']);
    await Future<void>.delayed(Duration.zero);
    expect(controller.portalBusy, isFalse);
    expect(
      events.where((event) => event.kind == DesktopDropEventKind.files),
      isEmpty,
    );
    expect(lookup.closes, 1);
    await controller.dispose();
  });

  test('native count rejects whole batch while Linux URLs remain rejected candidates', () async {
    final controller = DesktopDropController();
    final events = <DesktopDropEvent>[];
    controller.listen(events.add);
    await controller.handleMethodCall(
      MethodCall('performOperation', List.filled(21, '/tmp/file.pdf')),
    );
    expect(events.single.kind, DesktopDropEventKind.rejected);
    await controller.handleMethodCall(
      const MethodCall('performOperation_linux', [
        'file:///tmp/one.pdf\nhttps://example.org/file.pdf',
        [0.0, 0.0],
      ]),
    );
    expect(events.last.paths, ['/tmp/one.pdf', 'https://example.org/file.pdf']);
    await controller.dispose();
  });
}
