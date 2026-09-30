import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domabas/app/limited_response_client.dart';
import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas/domain/document/models/document_limits.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import '../support/document_thumbnail_fixture.dart';

void main() {
  const id = 'c70a9c09-efcc-4210-830c-b73c408ac2ae';
  final bytes = img.encodeJpg(img.Image(width: 20, height: 30));
  final descriptor = documentThumbnailFixture(bytes);
  final reference = DocumentThumbnailRef(id: id, thumbnail: descriptor);
  final wire = {
    'sourceSha256': descriptor.sourceSha256,
    'sha256': descriptor.sha256,
    'rendererRevision': 1,
    'mediaType': 'image/jpeg',
    'width': 20,
    'height': 30,
    'size': bytes.length,
  };

  RemoteDocumentRepository repository(http.Client client) {
    final transport = api.ApiClient(basePath: 'http://example.test');
    transport.client.close();
    transport.client = LimitedResponseClient(client);
    addTearDown(transport.client.close);
    return RemoteDocumentRepository(
      DocumentRemoteDataSource(api.DocumentsApi(transport)),
    );
  }

  Matcher failure(DocumentFailureKind kind) => throwsA(
    isA<DocumentFailure>().having((value) => value.kind, 'kind', kind),
  );

  test(
    'thumbnail GET sends output identity and receives validated JPEG bytes',
    () async {
      final source = repository(
        MockClient((request) async {
          expect(request.url.path, '/api/v1/documents/$id/thumbnail');
          expect(request.url.queryParameters, {'sha256': descriptor.sha256});
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(await source.thumbnail(reference), bytes);
    },
  );

  for (final problem in [
    'mime',
    'hash',
    'size',
    'dimensions',
    'jpeg',
    'oversized SOF',
    'truncated segment',
    'duplicate frame',
    'EXIF metadata',
    'missing',
  ]) {
    test('thumbnail rejects $problem without an original fallback', () async {
      var calls = 0;
      var responseBytes = bytes;
      var expected = descriptor;
      if (problem == 'hash') {
        responseBytes = Uint8List.fromList([...bytes]..[50] ^= 1);
      }
      if (problem == 'size') responseBytes = bytes.sublist(0, bytes.length - 1);
      if (problem == 'dimensions') {
        expected = DocumentThumbnail(
          sha256: descriptor.sha256,
          sourceSha256: descriptor.sourceSha256,
          rendererRevision: 1,
          mediaType: 'image/jpeg',
          width: 21,
          height: 30,
          size: bytes.length,
        );
      }
      if (problem == 'jpeg') {
        responseBytes = Uint8List.fromList([1, 2, 3]);
        expected = DocumentThumbnail(
          sha256: sha256.convert(responseBytes).toString(),
          sourceSha256: descriptor.sourceSha256,
          rendererRevision: 1,
          mediaType: 'image/jpeg',
          width: 20,
          height: 30,
          size: responseBytes.length,
        );
      }
      if (problem == 'oversized SOF') {
        responseBytes = Uint8List.fromList([
          0xff,
          0xd8,
          0xff,
          0xc0,
          0,
          17,
          8,
          0xff,
          0xff,
          0xff,
          0xff,
          3,
          1,
          0x22,
          0,
          2,
          0x11,
          1,
          3,
          0x11,
          1,
          0xff,
          0xd9,
        ]);
      }
      if (problem == 'truncated segment') {
        responseBytes = Uint8List.fromList([
          0xff,
          0xd8,
          0xff,
          0xe0,
          0xff,
          0xff,
          0xff,
          0xd9,
        ]);
      }
      if (problem == 'duplicate frame') {
        responseBytes = Uint8List.fromList([
          ...bytes.sublist(0, bytes.length - 2),
          0xff,
          0xc0,
          0,
          17,
          8,
          0xff,
          0xff,
          0xff,
          0xff,
          3,
          1,
          0x22,
          0,
          2,
          0x11,
          1,
          3,
          0x11,
          1,
          0xff,
          0xd9,
        ]);
      }
      if (problem == 'EXIF metadata') {
        responseBytes = Uint8List.fromList([
          ...bytes.sublist(0, 2),
          0xff,
          0xe1,
          0,
          2,
          ...bytes.sublist(2),
        ]);
      }
      if ([
        'oversized SOF',
        'truncated segment',
        'duplicate frame',
        'EXIF metadata',
      ].contains(problem)) {
        expected = DocumentThumbnail(
          sha256: sha256.convert(responseBytes).toString(),
          sourceSha256: descriptor.sourceSha256,
          rendererRevision: 1,
          mediaType: 'image/jpeg',
          width: 20,
          height: 30,
          size: responseBytes.length,
        );
      }
      final source = repository(
        MockClient((request) async {
          calls++;
          expect(request.url.path, endsWith('/thumbnail'));
          return http.Response.bytes(
            responseBytes,
            problem == 'missing' ? 404 : 200,
            headers: {
              'content-type': problem == 'mime' ? 'image/png' : 'image/jpeg',
            },
          );
        }),
      );
      await expectLater(
        source.thumbnail(DocumentThumbnailRef(id: id, thumbnail: expected)),
        failure(
          problem == 'missing'
              ? DocumentFailureKind.notFound
              : DocumentFailureKind.invalidResponse,
        ),
      );
      expect(calls, 1);
    });
  }

  for (final declared in [false, true]) {
    test(
      'thumbnail streaming cap aborts ${declared ? 'declared' : 'actual'} overflow before buffering',
      () async {
        final upstream = _ThumbnailStreamingClient(declared);
        final source = repository(upstream);
        final assertion = expectLater(
          source.thumbnail(reference),
          failure(DocumentFailureKind.tooLarge),
        );
        await upstream.started.future;
        if (!declared) {
          upstream.body.add(Uint8List(documentThumbnailByteLimit));
          upstream.body.add([1]);
        }
        await assertion;
        await upstream.cancelled.future.timeout(const Duration(seconds: 2));
        await upstream.body.close();
      },
    );
  }

  for (final search in [false, true]) {
    for (final problem in [
      'valid',
      'absent',
      'null',
      'scalar',
      'source',
      'width',
      'fractional',
      'missing',
    ]) {
      test(
        '${search ? 'search' : 'browse'} validates thumbnail $problem descriptor',
        () async {
          final thumbnail = Map<String, Object>.from(wire);
          if (problem == 'source') thumbnail['sourceSha256'] = 'b' * 64;
          if (problem == 'width') thumbnail['width'] = 257;
          if (problem == 'fractional') thumbnail['size'] = 1.5;
          if (problem == 'missing') thumbnail.remove('sha256');
          final document = {
            'id': id,
            'title': 'Invoice',
            'description': '',
            'createdAt': '2026-09-24T00:00:00Z',
            'kind': 'document',
            'tags': <String>[],
            if (search)
              'original': {
                'sha256': descriptor.sourceSha256,
                'mediaType': 'application/pdf',
                'size': 1000,
              },
            if (!search)
              'file': {
                'originalFilename': 'original.pdf',
                'mediaType': 'application/pdf',
                'size': 1000,
                'sha256': descriptor.sourceSha256,
                'ingestedAt': '2026-09-24T00:00:00Z',
                'uploaderId': id,
              },
            if (problem != 'absent')
              'thumbnail': problem == 'null'
                  ? null
                  : problem == 'scalar'
                  ? 'bad'
                  : thumbnail,
          };
          final source = repository(
            MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'items': [
                    search
                        ? {'document': document, 'score': 1.0, 'snippet': ''}
                        : document,
                  ],
                  'total': 1,
                }),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          );
          final result = search
              ? source
                    .search(DocumentSearchCriteria())
                    .then((page) => page.items.single.thumbnail)
              : source.list().then((page) => page.items.single.thumbnail);
          if (problem == 'valid') {
            expect((await result)!.sha256, descriptor.sha256);
          } else if (problem == 'absent' || problem == 'null') {
            expect(await result, isNull);
          } else {
            await expectLater(
              result,
              failure(DocumentFailureKind.invalidResponse),
            );
          }
        },
      );
    }
  }
}

final class _ThumbnailStreamingClient extends http.BaseClient {
  _ThumbnailStreamingClient(this.declared);
  final bool declared;
  final started = Completer<void>();
  final cancelled = Completer<void>();
  late final body = StreamController<List<int>>(
    onCancel: () {
      if (!cancelled.isCompleted) cancelled.complete();
    },
  );
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    return http.StreamedResponse(
      body.stream,
      200,
      contentLength: declared ? documentThumbnailByteLimit + 1 : null,
      headers: {'content-type': 'image/jpeg'},
      request: request,
    );
  }
}
