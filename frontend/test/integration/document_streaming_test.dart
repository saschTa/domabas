import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/app/limited_response_client.dart';
import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/data/document/models/response_size_exception.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final document = Document(
    id: 'c70a9c09-efcc-4210-830c-b73c408ac2ae',
    title: 'File',
    description: '',
    createdAt: DateTime.utc(2026),
    file: DocumentFile(
      originalFilename: 'scan.png',
      mediaType: 'image/png',
      size: 8,
      sha256: 'hash',
      ingestedAt: DateTime.utc(2026),
      uploaderId: 'user',
    ),
  );
  late _StreamingClient upstream;
  late api.ApiClient apiClient;
  late RemoteDocumentRepository repository;
  setUp(() {
    upstream = _StreamingClient();
    apiClient = api.ApiClient(basePath: 'http://example.test')..client.close();
    apiClient.client = LimitedResponseClient(upstream, maximumBytes: 8);
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(api.DocumentsApi(apiClient)),
    );
  });
  tearDown(() async {
    apiClient.client.close();
    await upstream.body.close();
  });

  for (final declared in [false, true]) {
    test(
      'default transport permits 100 MiB with declared length $declared',
      () async {
        final bounded = LimitedResponseClient(upstream);
        upstream.length = declared ? 100 * 1024 * 1024 : null;
        final response = await bounded.send(
          http.Request('GET', Uri.parse('http://example.test/content')),
        );
        final received = response.stream.fold<int>(
          0,
          (total, bytes) => total + bytes.length,
        );
        final chunk = Uint8List(1024 * 1024);
        for (var index = 0; index < 100; index++) {
          upstream.body.add(chunk);
        }
        await upstream.body.close();
        expect(await received, 100 * 1024 * 1024);
      },
    );
  }

  test(
    'default transport refuses more than 100 MiB before buffering',
    () async {
      final bounded = LimitedResponseClient(upstream);
      upstream.length = 100 * 1024 * 1024 + 1;
      await expectLater(
        bounded.send(
          http.Request('GET', Uri.parse('http://example.test/content')),
        ),
        throwsA(isA<ResponseSizeException>()),
      );
      await upstream.cancelled.future;
    },
  );

  for (final contentLength in [null, 1]) {
    test(
      'streamed overflow with length $contentLength maps tooLarge and cancels upstream',
      () async {
        upstream.length = contentLength;
        final result = repository.download(document.originalRef!);
        final assertion = expectLater(
          result,
          throwsA(
            isA<DocumentFailure>().having(
              (failure) => failure.kind,
              'kind',
              DocumentFailureKind.tooLarge,
            ),
          ),
        );
        await upstream.started.future;
        upstream.body.add([1, 2, 3, 4]);
        upstream.body.add([5, 6, 7, 8, 9]);
        await assertion;
        await upstream.cancelled.future.timeout(const Duration(seconds: 2));
        expect(upstream.closed, isFalse);
      },
    );
  }

  test(
    'oversized declared response cancels stream without buffering it',
    () async {
      upstream.length = 100;
      await expectLater(
        repository.download(document.originalRef!),
        throwsA(
          isA<DocumentFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentFailureKind.tooLarge,
          ),
        ),
      );
      await upstream.cancelled.future;
    },
  );

  test(
    'binary bytes survive generated transport without JSON decoding',
    () async {
      final result = repository.download(document.originalRef!);
      await upstream.started.future;
      upstream.body.add([0, 255, 127, 13]);
      await upstream.body.close();
      expect(await result, [0, 255, 127, 13]);
    },
  );

  test(
    'consumer cancellation reaches the generated abortable request',
    () async {
      final consumer = Completer<void>();
      final result = repository.download(
        document.originalRef!,
        cancel: consumer.future,
      );
      final assertion = expectLater(result, throwsA(isA<DocumentFailure>()));
      await upstream.started.future;
      consumer.complete();
      await upstream.aborted.future;
      await assertion;
      expect(upstream.closed, isFalse);
    },
  );

  test(
    'scope cancellation aborts in-flight and refuses subsequent requests',
    () async {
      final result = repository.download(document.originalRef!);
      final assertion = expectLater(result, throwsA(isA<DocumentFailure>()));
      await upstream.started.future;
      repository.cancelRequests();
      await upstream.aborted.future;
      await assertion;
      await expectLater(
        repository.getById(document.id),
        throwsA(
          isA<DocumentFailure>().having(
            (failure) => failure.kind,
            'kind',
            DocumentFailureKind.cancelled,
          ),
        ),
      );
      expect(upstream.requests, 1);
    },
  );
}

final class _StreamingClient extends http.BaseClient {
  _StreamingClient() {
    body = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
  }
  late final StreamController<List<int>> body;
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final aborted = Completer<void>();
  int? length;
  int requests = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (request is http.Abortable) {
      unawaited(
        request.abortTrigger?.then((_) {
          if (!aborted.isCompleted) aborted.complete();
          if (!body.isClosed) {
            body.addError(http.RequestAbortedException(request.url));
            unawaited(body.close());
          }
        }),
      );
    }
    started.complete();
    return http.StreamedResponse(
      body.stream,
      200,
      contentLength: length,
      request: request,
      headers: const {'content-type': 'image/png'},
    );
  }

  @override
  void close() => closed = true;
}
