import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import 'realtime_socket_attempt.dart';

RealtimeSocketAttempt createSocketAttempt(
  Uri endpoint, {
  Future<HttpClient> Function()? clientFactory,
}) => _NativeRealtimeSocketAttempt(endpoint, clientFactory ?? _defaultClient);

Future<HttpClient> _defaultClient() async => HttpClient();

final class _NativeRealtimeSocketAttempt implements RealtimeSocketAttempt {
  _NativeRealtimeSocketAttempt(
    Uri endpoint,
    Future<HttpClient> Function() clientFactory,
  ) {
    channel = IOWebSocketChannel(_connect(endpoint, clientFactory));
    channel.ready.then(
      (_) {
        if (_aborted) {
          unawaited(channel.sink.close());
        } else if (!_ready.isCompleted) {
          _ready.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        _client?.close(force: true);
        if (!_ready.isCompleted) _ready.completeError(error, stack);
      },
    );
  }

  Future<WebSocket> _connect(
    Uri endpoint,
    Future<HttpClient> Function() clientFactory,
  ) async {
    final client = _client = await clientFactory();
    if (_aborted) {
      client.close(force: true);
      throw const RealtimeSocketAttemptCancelled();
    }
    client.connectionTimeout = const Duration(seconds: 10);
    final socket = await WebSocket.connect(
      endpoint.toString(),
      protocols: const ['domabas.realtime.v1'],
      customClient: client,
    );
    _socket = socket;
    client.close();
    if (_aborted) {
      unawaited(socket.close());
      throw const RealtimeSocketAttemptCancelled();
    }
    return socket;
  }

  HttpClient? _client;
  final _ready = Completer<void>();
  WebSocket? _socket;
  bool _aborted = false;
  @override
  late final IOWebSocketChannel channel;
  @override
  Future<void> get ready => _ready.future;

  @override
  void abort() {
    if (_aborted) return;
    _aborted = true;
    _client?.close(force: true);
    if (!_ready.isCompleted) {
      _ready.completeError(const RealtimeSocketAttemptCancelled());
    }
    unawaited(_socket?.close());
    unawaited(channel.sink.close().then<void>((_) {}, onError: (_) {}));
  }
}
