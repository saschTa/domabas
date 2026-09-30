import 'dart:async';
import 'dart:convert';

import 'package:domabas/data/realtime/datasources/realtime_socket_attempt.dart';
import 'package:domabas/data/realtime/datasources/realtime_websocket_data_source.dart';
import 'package:domabas/data/realtime/repos/remote_realtime_repository.dart';
import 'package:domabas/domain/realtime/models/realtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _Sink implements WebSocketSink {
  final values = <Object?>[];
  final _done = Completer<void>();
  @override
  Future<void> get done => _done.future;
  @override
  void add(Object? data) => values.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => throw error;
  @override
  Future<void> addStream(Stream<Object?> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }
}

final class _Channel implements WebSocketChannel {
  final incoming = StreamController<Object?>.broadcast(sync: true);
  @override
  final _Sink sink = _Sink();
  @override
  String? protocol = 'domabas.realtime.v1';
  @override
  int? closeCode;
  @override
  String? get closeReason => null;
  @override
  Future<void> get ready => Future<void>.value();
  @override
  Stream<Object?> get stream => incoming.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

final class _Attempt implements RealtimeSocketAttempt {
  @override
  final _Channel channel = _Channel();
  final completion = Completer<void>();
  int abortCalls = 0;
  @override
  Future<void> get ready => completion.future;
  @override
  void abort() {
    abortCalls++;
  }

  void receive(String type, [List<String>? topics]) {
    channel.incoming.add(
      jsonEncode({'type': type, 'version': 1, 'topics': ?topics}),
    );
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late RealtimeWebSocketDataSource source;
  late RemoteRealtimeRepository repository;
  late List<_Attempt> attempts;
  late List<RealtimeEvent> events;
  late StreamSubscription<RealtimeEvent> subscription;
  const token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  setUp(() {
    attempts = [];
    events = [];
    source = RealtimeWebSocketDataSource(
      endpoint: 'https://example.test/prefix',
      token: token,
      connectTimeout: const Duration(milliseconds: 40),
      socketFactory: (endpoint) {
        expect(
          endpoint.toString(),
          'wss://example.test/prefix/api/v1/realtime',
        );
        final attempt = _Attempt();
        attempts.add(attempt);
        return attempt;
      },
    );
    repository = RemoteRealtimeRepository(source);
    subscription = repository.events.listen(events.add);
  });

  tearDown(() async {
    repository.dispose();
    await subscription.cancel();
    for (final attempt in attempts) {
      if (!attempt.completion.isCompleted) attempt.completion.complete();
      await attempt.channel.incoming.close();
    }
    await _settle();
  });

  test(
    'authentication waits for raw readiness and baseline maps canonical topics',
    () async {
      final connecting = repository.connect();
      final attempt = attempts.single;
      expect(attempt.channel.sink.values, isEmpty);
      await repository.connect();
      expect(attempts, hasLength(1));
      attempt.completion.complete();
      await connecting;
      expect(jsonDecode(attempt.channel.sink.values.single! as String), {
        'type': 'authenticate',
        'version': 1,
        'token': token,
      });
      expect(events, isEmpty);
      attempt.receive('ready', [
        'documents',
        'processing_configuration',
        'system_users',
      ]);
      expect(events.single.kind, RealtimeEventKind.ready);
      expect(events.single.topics, {
        RealtimeTopic.documents,
        RealtimeTopic.processingConfiguration,
        RealtimeTopic.systemUsers,
      });
      attempt.receive('heartbeat');
      attempt.receive('invalidate', ['documents']);
      expect(events.map((e) => e.kind), [
        RealtimeEventKind.ready,
        RealtimeEventKind.heartbeat,
        RealtimeEventKind.invalidate,
      ]);
    },
  );

  test(
    'timed-out raw attempt is physically aborted and late ready sends no token',
    () async {
      await repository.connect();
      final first = attempts.single;
      expect(first.abortCalls, 1);
      expect(events.single.kind, RealtimeEventKind.disconnected);
      final nextConnect = repository.connect();
      final second = attempts.last;
      first.completion.complete();
      first.receive('ready', ['documents']);
      await _settle();
      expect(first.channel.sink.values, isEmpty);
      expect(events, hasLength(1));
      second.completion.complete();
      await nextConnect;
      second.receive('ready', ['email']);
      expect(events.last.topics, {RealtimeTopic.email});
      expect(second.abortCalls, 0);
    },
  );

  test('disconnect fences a late rejected attempt after replacement', () async {
    final firstConnect = repository.connect();
    final first = attempts.single;
    repository.disconnect();
    final nextConnect = repository.connect();
    final second = attempts.last;
    second.completion.complete();
    await nextConnect;
    second.receive('ready', ['activity']);
    first.completion.completeError(StateError('stale handshake failure'));
    await firstConnect;
    expect(events, hasLength(1));
    expect(second.abortCalls, 0);
    expect(first.channel.sink.values, isEmpty);
  });

  test('wrong negotiated protocol aborts before authentication', () async {
    final connecting = repository.connect();
    attempts.single.channel.protocol = null;
    attempts.single.completion.complete();
    await connecting;
    expect(attempts.single.channel.sink.values, isEmpty);
    expect(attempts.single.abortCalls, 1);
    expect(events.single.closeCode, 1008);
  });

  for (final type in ['heartbeat', 'invalidate', 'resync']) {
    test('$type cannot replace required baseline', () async {
      final connecting = repository.connect();
      final attempt = attempts.single;
      attempt.completion.complete();
      await connecting;
      attempt.receive(type, type == 'heartbeat' ? null : ['documents']);
      expect(events.single.closeCode, 1008);
      expect(attempt.abortCalls, 1);
    });
  }

  test(
    'duplicate baseline and malformed frames each end a connection once',
    () async {
      final connecting = repository.connect();
      final attempt = attempts.single;
      attempt.completion.complete();
      await connecting;
      attempt.receive('ready', []);
      attempt.receive('ready', []);
      attempt.channel.incoming.add(
        '{"type":"heartbeat","version":1,"version":1}',
      );
      await _settle();
      expect(events.map((event) => event.kind), [
        RealtimeEventKind.ready,
        RealtimeEventKind.disconnected,
      ]);
      expect(events.last.closeCode, 1008);
      expect(attempt.abortCalls, 1);
    },
  );

  for (final code in [1000, 1001, 1013, 4401, 4403]) {
    test('preserves close code $code for session lifecycle policy', () async {
      final connecting = repository.connect();
      final attempt = attempts.single;
      attempt.completion.complete();
      await connecting;
      attempt.channel.closeCode = code;
      await attempt.channel.incoming.close();
      expect(events.single.closeCode, code);
      expect(attempt.abortCalls, 1);
    });
  }
}
