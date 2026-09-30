import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/data/document/datasources/document_upload_remote_data_source.dart';
import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../integration_test/scanner_fixtures.dart';
import '../support/document_upload_multipart.dart';

void main() {
  final pdf = Uint8List.fromList(
    utf8.encode('%PDF-1.7\nscanner payload\n%%EOF'),
  );
  late HttpServer server;
  late api.ApiClient client;
  late DocumentUploadRemoteDataSource source;
  late Future<void> Function(HttpRequest) respond;
  final requests = <Map<String, dynamic>>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = api.ApiClient(basePath: 'http://127.0.0.1:${server.port}')
      ..client.close();
    client.client = SessionClient(
      http.Client(),
      token: 'scanner-test-token',
      onUnauthorized: () {},
    );
    source = DocumentUploadRemoteDataSource(
      client,
      timeout: const Duration(milliseconds: 150),
    );
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      requests.add({
        'bytes': bytes,
        'type': request.headers.contentType.toString(),
        'auth': request.headers.value('authorization'),
        'uri': request.uri.path,
      });
      await respond(request);
    });
  });
  tearDown(() async {
    client.client.close();
    await server.close(force: true);
  });

  Map<String, Object> accepted() => {
    'id': 'c70a9c09-efcc-4210-830c-b73c408ac2ae',
    'title': 'Scanner fixture',
    'description': '',
    'createdAt': '2026-09-18T12:00:00Z',
    'file': {
      'originalFilename': 'scan-test.pdf',
      'mediaType': 'application/pdf',
      'size': pdf.length,
      'sha256': sha256.convert(pdf).toString(),
      'ingestedAt': '2026-09-18T12:00:00Z',
      'uploaderId': 'a70a9c09-efcc-4210-830c-b73c408ac2ae',
    },
  };
  Future<void> reply(
    HttpRequest request,
    int status, [
    Object body = const {},
  ]) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<Object?> failure() async {
    try {
      await source.send(
        pdf,
        source.prepare(scanProperties()),
        'scan-test.pdf',
        Completer<void>().future,
      );
    } catch (error) {
      return error;
    }
    return null;
  }

  test('real authenticated multipart contains exactly two parts and exact frozen bytes', () async {
    final metadata = source.prepare(
      scanProperties({
        'tags': <String>['Z', 'a'],
        'sender': ' Sender ',
        'recipients': <String>['Recipient'],
        'cc': <String>['Copy'],
        'bcc': <String>['Hidden'],
        'documentDate': '2026-09-18',
        'subject': 'World 世界',
        'messageId': '<message>',
        'description': 'Notes\nline',
        'kind': 'email',
      }),
    );
    respond = (request) => reply(request, 202, accepted());
    final result = await source.send(
      pdf,
      metadata,
      'scan-test.pdf',
      Completer<void>().future,
    );
    expect(result.id, accepted()['id']);
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request['auth'], 'Bearer scanner-test-token');
    expect(request['uri'], '/api/v1/documents/upload');
    final fields = expectDocumentUploadMultipart(
      body: request['bytes'] as List<int>,
      contentType: request['type'] as String,
      metadata: metadata.bytes,
      original: pdf,
      filename: 'scan-test.pdf',
      originalMediaType: 'application/pdf',
    );
    expect(
      jsonDecode(utf8.decode(fields['metadata']!)),
      containsPair('subject', 'World 世界'),
    );
  });
  for (final status in [400, 401, 403, 409, 413, 429, 500, 503, 200]) {
    test(
      'actual HTTP $status preserves rejection/duplicate/uncertainty distinction',
      () async {
        respond = (request) => reply(request, status);
        final error = await failure();
        expect(
          error,
          isA<DocumentUploadException>().having(
            (e) => e.disposition,
            'disposition',
            status == 409
                ? DocumentUploadDisposition.duplicate
                : [400, 401, 403, 413, 429].contains(status)
                ? DocumentUploadDisposition.rejected
                : DocumentUploadDisposition.uncertain,
          ),
        );
        expect(requests, hasLength(1));
      },
    );
  }
  test(
    'malformed acceptance and wrapped transport 400 remain uncertain',
    () async {
      respond = (request) => reply(request, 202, {'id': 'not-valid'});
      expect(
        await failure(),
        isA<DocumentUploadException>().having(
          (e) => e.disposition,
          'disposition',
          DocumentUploadDisposition.uncertain,
        ),
      );
      await server.close(force: true);
      expect(
        await failure(),
        isA<DocumentUploadException>().having(
          (e) => e.disposition,
          'disposition',
          DocumentUploadDisposition.uncertain,
        ),
      );
    },
  );
  test('body deadline physically aborts a stalled response and never automatically retries', () async {
    respond = (request) async {
      request.response.statusCode = 202;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{');
      await request.response.flush();
    };
    final clock = Stopwatch()..start();
    expect(
      await failure().timeout(const Duration(seconds: 3)),
      isA<DocumentUploadException>().having(
        (e) => e.disposition,
        'disposition',
        DocumentUploadDisposition.uncertain,
      ),
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(requests, hasLength(1));
  });
  test('pre-dispatch cancellation sends nothing and does not poison the next attempt', () async {
    respond = (request) => reply(request, 202, accepted());
    final cancel = Completer<void>()..complete();
    await expectLater(
      source.send(
        pdf,
        source.prepare(scanProperties()),
        'scan-test.pdf',
        cancel.future,
      ),
      throwsA(
        isA<DocumentUploadException>().having(
          (e) => e.disposition,
          'disposition',
          DocumentUploadDisposition.rejected,
        ),
      ),
    );
    expect(requests, isEmpty);
    await source.send(
      pdf,
      source.prepare(scanProperties()),
      'scan-test.pdf',
      Completer<void>().future,
    );
    expect(requests, hasLength(1));
  });
  test('finite late decoded 202 wins over cancellation while transport ownership drains', () async {
    final underlying = _LateClient(jsonEncode(accepted()));
    client.client.close();
    client.client = underlying;
    final cancel = Completer<void>();
    final send = source.send(
      pdf,
      source.prepare(scanProperties()),
      'scan-test.pdf',
      cancel.future,
    );
    await underlying.started.future;
    cancel.complete();
    await underlying.aborted.future;
    var finished = false;
    unawaited(
      send.then((_) {
        finished = true;
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(finished, isFalse);
    underlying.release.complete();
    expect((await send).id, accepted()['id']);
  });
}

final class _LateClient extends http.BaseClient {
  _LateClient(this.body);
  final String body;
  final started = Completer<void>(),
      aborted = Completer<void>(),
      release = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    unawaited(
      (request as http.Abortable).abortTrigger!.then((_) => aborted.complete()),
    );
    started.complete();
    await release.future;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 202);
  }
}
