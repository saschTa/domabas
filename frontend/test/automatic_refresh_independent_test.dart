import 'dart:async';

import 'package:domabas/scheduling/automatic_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _until(bool Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!condition()) {
    if (deadline.elapsed > const Duration(seconds: 2)) {
      fail('Automatic refresh did not make progress');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  test('busy mutation retains one coalesced hint until it settles', () async {
    var busy = true, reads = 0;
    final refresh = AutomaticRefresh(
      read: () async {
        reads++;
      },
      busy: () => busy,
      coalesce: const Duration(milliseconds: 5),
      interval: () => const Duration(milliseconds: 20),
    );
    addTearDown(refresh.dispose);
    refresh.setActive(true);
    for (var i = 0; i < 100; i++) {
      refresh.invalidate();
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, 0);
    busy = false;
    await _until(() => reads == 1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(reads, 1);
  });

  test(
    'hint arriving during read drains exactly once after minimum interval',
    () async {
      final first = Completer<void>();
      final clock = Stopwatch()..start();
      final starts = <Duration>[];
      var active = 0, maximumActive = 0;
      final refresh = AutomaticRefresh(
        read: () async {
          starts.add(clock.elapsed);
          active++;
          if (active > maximumActive) maximumActive = active;
          if (starts.length == 1) await first.future;
          active--;
        },
        busy: () => false,
        coalesce: const Duration(milliseconds: 5),
        interval: () => const Duration(milliseconds: 50),
      );
      addTearDown(refresh.dispose);
      refresh.setActive(true);
      refresh.invalidate();
      await _until(() => starts.length == 1);
      for (var i = 0; i < 100; i++) {
        refresh.invalidate();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(starts, hasLength(1));
      final completedAt = clock.elapsed;
      first.complete();
      await _until(() => starts.length == 2);
      expect(
        starts[1] - completedAt,
        greaterThanOrEqualTo(const Duration(milliseconds: 45)),
      );
      expect(maximumActive, 1);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(starts, hasLength(2));
    },
  );

  test(
    'hidden hints and hint during hidden in-flight read survive activation',
    () async {
      final first = Completer<void>();
      var reads = 0;
      final refresh = AutomaticRefresh(
        read: () async {
          if (++reads == 1) await first.future;
        },
        busy: () => false,
        coalesce: const Duration(milliseconds: 5),
        interval: () => const Duration(milliseconds: 20),
      );
      addTearDown(refresh.dispose);
      refresh.invalidate();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reads, 0);
      refresh.setActive(true);
      await _until(() => reads == 1);
      refresh.setActive(false);
      refresh.invalidate();
      first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(reads, 1);
      refresh.setActive(true);
      await _until(() => reads == 2);
      refresh.setActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, 2);
    },
  );

  test('dispose fences pending and in-flight follow-up timers', () async {
    final gate = Completer<void>();
    var reads = 0;
    final refresh = AutomaticRefresh(
      read: () async {
        reads++;
        await gate.future;
      },
      busy: () => false,
      coalesce: const Duration(milliseconds: 5),
      interval: () => Duration.zero,
    );
    refresh.setActive(true);
    refresh.invalidate();
    await _until(() => reads == 1);
    refresh.invalidate();
    refresh.dispose();
    refresh.setActive(true);
    refresh.invalidate();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reads, 1);
  });
}
