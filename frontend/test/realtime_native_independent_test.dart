import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:domabas/data/realtime/datasources/realtime_socket_attempt.dart';
import 'package:domabas/data/realtime/datasources/realtime_socket_factory_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native abort closes a real socket stalled before HTTP upgrade',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final request = Completer<String>();
      final remoteClosed = Completer<void>();
      final listener = server.listen((socket) {
        accepted.complete(socket);
        final bytes = <int>[];
        socket.listen((data) {
          bytes.addAll(data);
          final text = ascii.decode(bytes);
          if (text.contains('\r\n\r\n') && !request.isCompleted) {
            request.complete(text);
          }
        }, onDone: remoteClosed.complete);
      });
      final attempt = createSocketAttempt(
        Uri.parse('ws://127.0.0.1:${server.port}/held'),
      );
      final ready = expectLater(
        attempt.ready,
        throwsA(isA<RealtimeSocketAttemptCancelled>()),
      );
      final streamErrors = <Object>[];
      final incoming = attempt.channel.stream.listen(
        (_) {},
        onError: streamErrors.add,
      );
      addTearDown(() async {
        attempt.abort();
        if (accepted.isCompleted) (await accepted.future).destroy();
        await incoming.cancel();
        await listener.cancel();
        await server.close();
      });
      final headers = await request.future.timeout(const Duration(seconds: 2));
      expect(
        headers.toLowerCase(),
        contains('sec-websocket-protocol: domabas.realtime.v1'),
      );
      expect(headers.toLowerCase(), isNot(contains('authorization:')));
      attempt.abort();
      attempt.abort();
      await ready;
      await remoteClosed.future.timeout(const Duration(seconds: 2));
    },
  );
}
