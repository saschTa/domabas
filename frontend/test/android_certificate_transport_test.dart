import 'dart:async';
import 'dart:io';

import 'package:domabas/app/http_client_native.dart';
import 'package:domabas/app/native_http_client_factory.dart';
import 'package:domabas/data/realtime/datasources/realtime_socket_attempt.dart';
import 'package:domabas/data/realtime/datasources/realtime_socket_factory_native.dart';
import 'package:domabas/data/server/datasources/android_trust_certificate_data_source.dart';
import 'package:domabas/data/server/datasources/readiness_server_data_source.dart';
import 'package:domabas/data/server/repos/server_sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const _channel = MethodChannel('dev.domabas/trusted_certificates');

void main() {
  _TlsTestBinding();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final ca = File('test/fixtures/tls/ca.pem').readAsStringSync();
  late NativeHttpClientFactory factory;
  var loads = 0;

  setUp(() {
    loads = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'loadTrustedCertificates');
      loads++;
      return ca;
    });
    factory = NativeHttpClientFactory(
      androidCertificates: AndroidTrustCertificateDataSource(),
    );
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test(
    'private CA enables readiness and API traffic with one load per client',
    () async {
      final server = await _startServer();
      final client = NativeHttpClient(clientFactory: factory.create);
      addTearDown(client.close);
      final results = await Future.wait([
        client.get(server.uri.resolve('/first')),
        client.post(server.uri.resolve('/second'), body: 'document contents'),
      ]);
      expect(results.map((response) => response.body), ['ok', 'ok']);
      expect(loads, 1);
      final readiness = ReadinessServerDataSource(
        clientFactory: () => NativeHttpClient(clientFactory: factory.create),
      );
      expect(
        await readiness.check(server.uri.toString()),
        ServerProbeResult.ready,
      );
      expect(loads, 2);
    },
  );

  test(
    'trust stays local to the client and does not enable unknown issuers',
    () async {
      final server = await _startServer();
      final trusted = NativeHttpClient(clientFactory: factory.create);
      final ordinary = NativeHttpClient();
      addTearDown(trusted.close);
      addTearDown(ordinary.close);
      expect((await trusted.get(server.uri)).statusCode, 200);
      await expectLater(
        ordinary.get(server.uri),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  for (final failure in ['hostname mismatch', 'expired certificate']) {
    test('HTTPS rejects $failure with a trusted issuer', () async {
      final server = await _startServer(
        expired: failure == 'expired certificate',
      );
      final uri = failure == 'hostname mismatch'
          ? server.uri.replace(host: '127.0.0.1')
          : server.uri;
      final client = NativeHttpClient(clientFactory: factory.create);
      addTearDown(client.close);
      await expectLater(client.get(uri), throwsA(isA<http.ClientException>()));
    });
  }

  test(
    'WSS uses the same private CA and preserves the realtime protocol',
    () async {
      final server = await _startServer();
      final attempt = createSocketAttempt(
        server.uri.replace(scheme: 'wss'),
        clientFactory: factory.create,
      );
      addTearDown(attempt.abort);
      final reply = attempt.channel.stream.first;
      await attempt.ready;
      expect(attempt.channel.protocol, 'domabas.realtime.v1');
      attempt.channel.sink.add('hello');
      expect(await reply, 'hello');
    },
  );

  for (final failure in [
    'hostname mismatch',
    'expired certificate',
    'unknown issuer',
  ]) {
    test('WSS rejects $failure', () async {
      final server = await _startServer(
        expired: failure == 'expired certificate',
      );
      final uri = server.uri.replace(
        scheme: 'wss',
        host: failure == 'hostname mismatch' ? '127.0.0.1' : 'localhost',
      );
      final attempt = createSocketAttempt(
        uri,
        clientFactory: failure == 'unknown issuer' ? null : factory.create,
      );
      addTearDown(attempt.abort);
      final subscription = attempt.channel.stream.listen(
        (_) {},
        onError: (_) {},
      );
      addTearDown(subscription.cancel);
      await expectLater(
        attempt.ready,
        throwsA(
          isA<WebSocketChannelException>().having(
            (error) => error.inner,
            'TLS failure',
            isA<HandshakeException>(),
          ),
        ),
      );
    });
  }

  for (final result in [null, '', 'invalid PEM']) {
    test('invalid native certificate bundle fails closed: $result', () async {
      messenger.setMockMethodCallHandler(_channel, (_) async => result);
      await expectLater(factory.create(), throwsA(isA<http.ClientException>()));
    });
  }

  test(
    'native load errors fail closed and a later request can retry',
    () async {
      final server = await _startServer();
      messenger.setMockMethodCallHandler(_channel, (_) async {
        throw PlatformException(code: 'certificate_store_unavailable');
      });
      final client = NativeHttpClient(clientFactory: factory.create);
      addTearDown(client.close);
      await expectLater(
        client.get(server.uri),
        throwsA(isA<http.ClientException>()),
      );
      messenger.setMockMethodCallHandler(_channel, (_) async => ca);
      expect((await client.get(server.uri)).statusCode, 200);
    },
  );

  test('native certificate loading has a deadline', () async {
    final pending = Completer<String>();
    messenger.setMockMethodCallHandler(_channel, (_) => pending.future);
    final bounded = NativeHttpClientFactory(
      androidCertificates: AndroidTrustCertificateDataSource(
        timeout: const Duration(milliseconds: 10),
      ),
    );
    await expectLater(bounded.create(), throwsA(isA<http.ClientException>()));
    pending.complete(ca);
  });

  test(
    'HTTP close during loading closes the late client without connecting',
    () async {
      final pending = Completer<HttpClient>();
      final native = _TrackedHttpClient();
      final client = NativeHttpClient(clientFactory: () => pending.future);
      final sent = expectLater(
        client.get(Uri.parse('https://localhost/')),
        throwsA(isA<http.ClientException>()),
      );
      client.close();
      client.close();
      pending.complete(native);
      await sent;
      expect(native.forceClosed, isTrue);
      await expectLater(
        client.get(Uri.parse('https://localhost/')),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test(
    'request abort during certificate loading prevents an HTTP request',
    () async {
      final pending = Completer<HttpClient>();
      final native = HttpClient();
      final client = NativeHttpClient(clientFactory: () => pending.future);
      addTearDown(client.close);
      final abort = Completer<void>();
      final sent = expectLater(
        client.send(
          http.AbortableRequest(
            'GET',
            Uri.parse('https://localhost:1/'),
            abortTrigger: abort.future,
          ),
        ),
        throwsA(isA<http.RequestAbortedException>()),
      );
      abort.complete();
      pending.complete(native);
      await sent;
    },
  );

  test(
    'WSS abort during loading closes the late client without connecting',
    () async {
      final pending = Completer<HttpClient>();
      final native = _TrackedHttpClient();
      final attempt = createSocketAttempt(
        Uri.parse('wss://localhost/'),
        clientFactory: () => pending.future,
      );
      final subscription = attempt.channel.stream.listen(
        (_) {},
        onError: (_) {},
      );
      addTearDown(subscription.cancel);
      final ready = expectLater(
        attempt.ready,
        throwsA(isA<RealtimeSocketAttemptCancelled>()),
      );
      attempt.abort();
      attempt.abort();
      await ready;
      pending.complete(native);
      await pumpEventQueue();
      expect(native.forceClosed, isTrue);
    },
  );
}

Future<({Uri uri})> _startServer({bool expired = false}) async {
  final context = SecurityContext()
    ..useCertificateChain(
      'test/fixtures/tls/${expired ? 'expired-server' : 'server'}.pem',
    )
    ..usePrivateKey('test/fixtures/tls/server-key.pem');
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  final sockets = <WebSocket>[];
  final subscription = server.listen(
    (request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('domabas.realtime.v1')
              ? 'domabas.realtime.v1'
              : null,
        );
        sockets.add(socket);
        socket.listen(socket.add);
      } else {
        await request.drain<void>();
        request.response.write(
          request.uri.path == '/readyz' ? '{"status":"ok"}' : 'ok',
        );
        await request.response.close();
      }
    },
    onError: (Object error) {
      expect(error, isA<HandshakeException>());
    },
  );
  addTearDown(() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  });
  return (uri: Uri.parse('https://localhost:${server.port}'));
}

final class _TrackedHttpClient implements HttpClient {
  bool forceClosed = false;

  @override
  void close({bool force = false}) => forceClosed = force;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TlsTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}
