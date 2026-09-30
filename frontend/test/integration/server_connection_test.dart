import 'dart:async';
import 'dart:io';

import 'package:domabas/data/server/datasources/readiness_server_data_source.dart';
import 'package:domabas/data/server/repos/server_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late HttpServer server;
  late String address;
  late _TrackingClient client;
  late ReadinessServerDataSource source;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    address = 'http://127.0.0.1:${server.port}/installation';
    client = _TrackingClient(http.Client());
    source = ReadinessServerDataSource(
      clientFactory: () => client,
      timeout: const Duration(milliseconds: 300),
    );
  });
  tearDown(() async => server.close(force: true));

  test(
    'generated readiness check preserves base path and sends no credentials',
    () async {
      String? authorization;
      String? cookie;
      String? path;
      server.listen((request) async {
        authorization = request.headers.value('authorization');
        cookie = request.headers.value('cookie');
        path = request.uri.path;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"status":"ok"}');
        await request.response.close();
      });
      expect(await source.check(address), ServerProbeResult.ready);
      expect(path, '/installation/readyz');
      expect(authorization, isNull);
      expect(cookie, isNull);
      expect(client.closed, isTrue);
    },
  );

  test('redirect is rejected without contacting its target', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('location', '/login');
      await request.response.close();
    });
    expect(await source.check(address), ServerProbeResult.invalidResponse);
    expect(requests, 1);
    expect(client.closed, isTrue);
  });

  test('HTML success is not accepted as a ready server', () async {
    server.listen((request) async {
      request.response.write('<html>Sign in to the proxy</html>');
      await request.response.close();
    });
    expect(await source.check(address), ServerProbeResult.invalidResponse);
  });

  test('unready server is distinct from an unreachable one', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    expect(await source.check(address), ServerProbeResult.notReady);
  });

  test('oversized response is bounded and its connection is closed', () async {
    server.listen((request) async {
      request.response.write('x' * 9000);
      await request.response.close();
    });
    await expectLater(source.check(address), throwsA(anything));
    expect(client.closed, isTrue);
  });

  test('stalled response times out and closes its owned client', () async {
    server.listen((request) {});
    await expectLater(source.check(address), throwsA(isA<TimeoutException>()));
    expect(client.closed, isTrue);
  });
}

final class _TrackingClient extends http.BaseClient {
  _TrackingClient(this.inner);
  final http.Client inner;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);
  @override
  void close() {
    closed = true;
    inner.close();
  }
}
