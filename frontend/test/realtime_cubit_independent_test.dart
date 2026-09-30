import 'dart:async';

import 'package:domabas/domain/realtime/models/realtime.dart';
import 'package:domabas/presentation/realtime/cubits/realtime_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_realtime_repository.dart';

Future<void> _until(bool Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!condition()) {
    if (deadline.elapsed > const Duration(seconds: 2)) {
      fail('Realtime condition did not become true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  late FakeRealtimeRepository repository;
  late RealtimeCubit cubit;
  var sessionEnds = 0;

  setUp(() {
    repository = FakeRealtimeRepository();
    sessionEnds = 0;
    cubit = RealtimeCubit(
      repository,
      onSessionEnded: () => sessionEnds++,
      connectTimeout: const Duration(milliseconds: 150),
      heartbeatTimeout: const Duration(milliseconds: 120),
      resyncInterval: const Duration(seconds: 10),
      random: () => .5,
    );
  });
  tearDown(() async {
    await cubit.close();
    repository.dispose();
  });

  test(
    'ready establishes baseline; hints preserve scope; resync replaces scope',
    () {
      cubit.setActive(true);
      expect(cubit.state.status, RealtimeStatus.connecting);
      expect(repository.connectCalls, 1);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.email, RealtimeTopic.activity],
        ),
      );
      expect(cubit.state.healthy, isTrue);
      expect(cubit.state.invalidated, {
        RealtimeTopic.email,
        RealtimeTopic.activity,
      });
      final revision = cubit.state.revision;
      repository.emit(RealtimeEvent(RealtimeEventKind.heartbeat));
      expect(cubit.state.revision, revision);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.invalidate,
          topics: [RealtimeTopic.email],
        ),
      );
      expect(cubit.state.topics, {RealtimeTopic.email, RealtimeTopic.activity});
      expect(cubit.state.invalidated, {RealtimeTopic.email});
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.resync,
          topics: [RealtimeTopic.activity],
        ),
      );
      expect(cubit.state.topics, {RealtimeTopic.activity});
      expect(cubit.state.invalidated, {RealtimeTopic.activity});
    },
  );

  test('healthy safety pass excludes all job topics', () async {
    await cubit.close();
    cubit = RealtimeCubit(
      repository,
      onSessionEnded: () => sessionEnds++,
      resyncInterval: const Duration(milliseconds: 25),
    );
    cubit.setActive(true);
    repository.emit(
      RealtimeEvent(RealtimeEventKind.ready, topics: RealtimeTopic.values),
    );
    final revision = cubit.state.revision;
    await _until(() => cubit.state.revision > revision);
    expect(cubit.state.invalidated, {
      RealtimeTopic.documents,
      RealtimeTopic.identity,
      RealtimeTopic.members,
      RealtimeTopic.systemUsers,
    });
    expect(repository.connectCalls, 1);
  });

  test(
    'heartbeat extends watchdog; silence reconnects once with fallback state',
    () async {
      cubit.setActive(true);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.documents],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      repository.emit(RealtimeEvent(RealtimeEventKind.heartbeat));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(cubit.state.healthy, isTrue);
      await _until(() => cubit.state.status == RealtimeStatus.reconnecting);
      expect(repository.disconnectCalls, 1);
      await _until(() => repository.connectCalls == 2);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.documents],
        ),
      );
      expect(cubit.state.invalidated, {RealtimeTopic.documents});
      expect(sessionEnds, 0);
    },
  );

  test(
    'background disconnects and ignores late events; foreground needs baseline',
    () async {
      cubit.setActive(true);
      repository.emit(
        RealtimeEvent(RealtimeEventKind.ready, topics: [RealtimeTopic.email]),
      );
      cubit.setActive(false);
      final disconnects = repository.disconnectCalls;
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.documents],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(cubit.state.status, RealtimeStatus.inactive);
      expect(repository.connectCalls, 1);
      expect(repository.disconnectCalls, disconnects);
      cubit.setActive(true);
      expect(repository.connectCalls, 2);
      expect(cubit.state.healthy, isFalse);
      expect(cubit.state.topics, isEmpty);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.identity],
        ),
      );
      expect(cubit.state.invalidated, {RealtimeTopic.identity});
    },
  );

  for (final code in [4401, 4403]) {
    test('authorization close $code ends exact scope without retry', () async {
      cubit.setActive(true);
      repository.emit(
        RealtimeEvent(RealtimeEventKind.disconnected, closeCode: code),
      );
      repository.emit(
        RealtimeEvent(RealtimeEventKind.disconnected, closeCode: code),
      );
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(sessionEnds, 1);
      expect(cubit.state.status, RealtimeStatus.unavailable);
      expect(repository.connectCalls, 1);
    });
  }

  test(
    'late connect rejection cannot interrupt a reactivated healthy scope',
    () async {
      final oldConnect = Completer<void>();
      repository.onConnect = () => oldConnect.future;
      cubit.setActive(true);
      cubit.setActive(false);
      repository.onConnect = () async {};
      cubit.setActive(true);
      repository.emit(
        RealtimeEvent(
          RealtimeEventKind.ready,
          topics: [RealtimeTopic.activity],
        ),
      );
      final disconnects = repository.disconnectCalls;
      oldConnect.completeError(
        StateError('old attempt failed after replacement'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.healthy, isTrue);
      expect(repository.disconnectCalls, disconnects);
      expect(cubit.state.topics, {RealtimeTopic.activity});
    },
  );

  test(
    'close cancels retry and ignores all future repository events',
    () async {
      cubit.setActive(true);
      repository.emit(
        RealtimeEvent(RealtimeEventKind.disconnected, closeCode: 1013),
      );
      await cubit.close();
      repository.emit(
        RealtimeEvent(RealtimeEventKind.ready, topics: [RealtimeTopic.email]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(repository.connectCalls, 1);
      expect(cubit.isClosed, isTrue);
      expect(sessionEnds, 0);
    },
  );
}
