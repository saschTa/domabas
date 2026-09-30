@TestOn('browser')
library;

import 'package:domabas/data/realtime/datasources/realtime_socket_attempt.dart';
import 'package:domabas/data/realtime/datasources/realtime_socket_factory_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/html.dart';

void main() {
  test(
    'browser abort closes CONNECTING transport and settles owned ready',
    () async {
      for (var replacement = 0; replacement < 5; replacement++) {
        final attempt = createSocketAttempt(
          Uri.parse('ws://127.0.0.1:65533/held'),
        );
        final channel = attempt.channel as HtmlWebSocketChannel;
        final errors = <Object>[];
        final incoming = channel.stream.listen(
          (Object? _) {},
          onError: errors.add,
        );
        final ready = expectLater(
          attempt.ready,
          throwsA(isA<RealtimeSocketAttemptCancelled>()),
        );
        expect(channel.innerWebSocket.readyState, 0);
        attempt.abort();
        attempt.abort();
        expect(channel.innerWebSocket.readyState, anyOf(2, 3));
        await ready.timeout(const Duration(seconds: 1));
        await incoming.cancel();
      }
    },
  );
}
