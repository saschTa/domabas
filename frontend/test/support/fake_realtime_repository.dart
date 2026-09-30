import 'dart:async';

import 'package:domabas/domain/realtime/interfaces/realtime_repository.dart';
import 'package:domabas/domain/realtime/models/realtime.dart';

class FakeRealtimeRepository implements RealtimeRepository {
  final _events = StreamController<RealtimeEvent>.broadcast(sync: true);
  int connectCalls = 0, disconnectCalls = 0, disposeCalls = 0;
  Future<void> Function()? onConnect;
  bool get disposed => disposeCalls > 0;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  void emit(RealtimeEvent event) {
    if (!disposed) _events.add(event);
  }

  @override
  Future<void> connect() {
    connectCalls++;
    return onConnect?.call() ?? Future<void>.value();
  }

  @override
  void disconnect() {
    disconnectCalls++;
  }

  @override
  void dispose() {
    if (disposed) return;
    disposeCalls++;
    unawaited(_events.close());
  }
}
