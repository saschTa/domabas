import 'package:web_socket_channel/web_socket_channel.dart';

abstract interface class RealtimeSocketAttempt {
  WebSocketChannel get channel;
  Future<void> get ready;
  void abort();
}

final class RealtimeSocketAttemptCancelled implements Exception {
  const RealtimeSocketAttemptCancelled();
}

typedef RealtimeSocketAttemptFactory = RealtimeSocketAttempt Function(
  Uri endpoint,
);
