import 'dart:async';

import 'package:web_socket_channel/html.dart';

import 'realtime_socket_attempt.dart';

RealtimeSocketAttempt createSocketAttempt(Uri endpoint) =>
    _BrowserRealtimeSocketAttempt(endpoint);

final class _BrowserRealtimeSocketAttempt implements RealtimeSocketAttempt {
  _BrowserRealtimeSocketAttempt(Uri endpoint)
    : channel = HtmlWebSocketChannel.connect(
        endpoint,
        protocols: const ['domabas.realtime.v1'],
      ) {
    channel.ready.then(
      (_) {
        if (_aborted) {
          channel.innerWebSocket.close();
        } else if (!_ready.isCompleted) {
          _ready.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_ready.isCompleted) _ready.completeError(error, stack);
      },
    );
  }

  final _ready = Completer<void>();
  bool _aborted = false;
  @override
  final HtmlWebSocketChannel channel;
  @override
  Future<void> get ready => _ready.future;

  @override
  void abort() {
    if (_aborted) return;
    _aborted = true;
    channel.innerWebSocket.close();
    if (!_ready.isCompleted) {
      _ready.completeError(const RealtimeSocketAttemptCancelled());
    }
    unawaited(channel.sink.close().then<void>((_) {}, onError: (_) {}));
  }
}
