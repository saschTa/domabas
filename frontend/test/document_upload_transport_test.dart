import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition.dart';
import 'package:domabas/data/document/datasources/document_upload_remote_data_source.dart';
import 'package:domabas/data/document/models/prepared_document_upload_metadata.dart';
import 'package:domabas/data/document/repos/remote_document_upload_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/domain/document/models/document_upload_validation.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/document_upload_multipart.dart';

Map<String, Object?> _receipt(Uint8List bytes, String filename, String media) =>
    {
      'id': '672811c8-f858-4e09-a2aa-4505512dc761',
      'title': DocumentUploadNames.title(filename),
      'description': '',
      'createdAt': '2026-09-18T12:20:00Z',
      'file': <String, Object?>{
        'originalFilename': filename,
        'mediaType': media,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'ingestedAt': '2026-09-18T12:20:00.123456789Z',
        'uploaderId': '6b8d3db5-be80-48c4-b4d3-a0c215d76e1d',
      },
    };

void main() {
  for (final split in [false, true]) {
    test(
      'an upload accepted with ${split ? 'separate AI' : 'legacy property extraction'} remains a valid receipt',
      () async {
        final bytes = Uint8List.fromList(
          utf8.encode('%PDF-1.7\noriginal\n%%EOF'),
        );
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        client.client = MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                ..._receipt(bytes, 'test.pdf', 'application/pdf'),
                'processing': {
                  'state': split ? 'ready' : 'processing',
                  'stage': split ? 'complete' : 'enriching',
                  'generation': 1,
                  'configurationRevision': 1,
                  'updatedAt': '2026-09-19T12:00:00Z',
                  'ocrEngine': 'tesseract',
                  'ocrVersion': '5.5.3',
                  'ocrModel': 'tessdata_fast',
                  'ocrLanguage': 'eng',
                  'ocrSegmentation': 'auto',
                  'embeddingModel': 'nomic-embed-text:v1.5',
                  'embeddingDigest': 'a' * 64,
                  'embeddingDimensions': 768,
                  'extractionMethod': 'ocr',
                  if (split)
                    'ai': {
                      'jobId': '22222222-2222-4222-8222-222222222222',
                      'attempt': 1,
                      'configurationRevision': 1,
                      'status': 'failed',
                      'stage': 'invoicing',
                      'failureCode': 'inference_unavailable',
                      'updatedAt': '2026-09-19T12:00:00Z',
                    },
                },
              }),
            ),
            202,
          ),
        );
        addTearDown(client.client.close);
        final source = DocumentUploadRemoteDataSource(client);
        final result = await source.sendOriginal(
          bytes,
          source.prepare(DocumentUploadNames.properties('test.pdf')),
          'test.pdf',
          Completer<void>().future,
        );
        expect(result.processing!.stage, split ? 'complete' : 'enriching');
        expect(result.processing!.ai?.status, split ? 'failed' : null);
      },
    );
  }

  for (final scanner in [false, true]) {
    test(
      '${scanner ? 'scanner' : 'general'} Unicode metadata uses only contract-permitted raw multipart headers and exact UTF-8 bytes',
      () async {
        final bytes = Uint8List.fromList(
          utf8.encode('%PDF-1.7\nexact original\n%%EOF'),
        );
        final filename = scanner
            ? 'scan-unicode.pdf'
            : 'Invoice _April_ Grüße.pdf';
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        final source = DocumentUploadRemoteDataSource(client);
        final properties = DocumentProperties(
          title: 'Invoice _April_ Grüße 世界',
          description: 'Überweisung\n受取人',
          subject: 'April • 四月',
          tags: const [],
          kind: 'document',
          sender: '',
          recipients: const [],
          cc: const [],
          bcc: const [],
          documentDate: '',
          messageId: '',
        );
        final metadata = source.prepare(properties);
        var calls = 0;
        client.client = MockClient((request) async {
          calls++;
          final fields = expectDocumentUploadMultipart(
            body: request.bodyBytes,
            contentType: request.headers['content-type']!,
            metadata: metadata.bytes,
            original: bytes,
            filename: filename,
            originalMediaType: 'application/pdf',
          );
          expect(
            jsonDecode(utf8.decode(fields['metadata']!)),
            containsPair('title', properties.title),
          );
          final receipt = _receipt(bytes, filename, 'application/pdf')
            ..['title'] = properties.title;
          return http.Response.bytes(utf8.encode(jsonEncode(receipt)), 202);
        });
        addTearDown(client.client.close);
        final cancel = Completer<void>().future;
        final result = await (scanner
            ? source.send(bytes, metadata, filename, cancel)
            : source.sendOriginal(bytes, metadata, filename, cancel));
        expect(calls, 1);
        expect(result.title, properties.title);
      },
    );
  }

  test('safe filenames remain scalar-valid, bounded and idempotent at trim boundaries', () {
    for (final raw in [
      ' report "世界" /\\\n.PDF ',
      '\ud800name\udc00.pdf',
      '${'é' * 126}  😀.pdf',
      '${'界' * 84}   😀.pdf',
      '.',
      '..',
      '',
      '\u0000',
      '\ufefforiginal.pdf\ufeff',
    ]) {
      final name = DocumentUploadNames.filename(raw);
      expect(DocumentUploadValidation.validScalars(name), isTrue);
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, DocumentUploadValidation.trim(name));
      expect(DocumentUploadNames.filename(name), name);
      expect(name.contains('"'), isFalse);
      expect(
        DocumentUploadValidation.validate(DocumentUploadNames.properties(name)),
        isEmpty,
      );
    }
    expect(DocumentUploadNames.filename('\ud800name\udc00.pdf'), '_name_.pdf');
    expect(DocumentUploadNames.filename('${'界' * 84}   😀.pdf'), '界' * 84);
    expect(DocumentUploadNames.title('World.PDF'), 'World');
    expect(DocumentUploadNames.title('.pdf'), '.pdf');
  });

  for (final fixture in [
    (
      bytes: <int>[37, 80, 68, 70, 45, 49],
      media: 'application/pdf',
      outgoing: 'application/pdf',
    ),
    (
      bytes: <int>[137, 80, 78, 71, 13, 10, 26, 10],
      media: 'image/png',
      outgoing: 'image/png',
    ),
    (
      bytes: <int>[255, 216, 255, 42],
      media: 'image/jpeg',
      outgoing: 'image/jpeg',
    ),
    (
      bytes: utf8.encode('From: test@example.com\r\nSubject: test\r\n\r\nBody'),
      media: 'message/rfc822',
      outgoing: 'application/octet-stream',
    ),
  ]) {
    test(
      'actual byte prefix selects ${fixture.media} independent of misleading extension',
      () async {
        final bytes = Uint8List.fromList(fixture.bytes);
        final filename = DocumentUploadNames.filename('März "世界".wrong');
        final client = api.ApiClient(basePath: 'http://example.test/base')
          ..client.close();
        addTearDown(client.client.close);
        var calls = 0;
        client.client = MockClient((request) async {
          calls++;
          expect(request.url.path, '/base/api/v1/documents/upload');
          final body = latin1.decode(request.bodyBytes);
          expect(RegExp(r'name="file"').allMatches(body), hasLength(1));
          expect(RegExp(r'name="metadata"').allMatches(body), hasLength(1));
          expect(body, contains('content-type: ${fixture.outgoing}'));
          expect(body, contains(latin1.decode(bytes)));
          expect(body, isNot(contains('%22')));
          return http.Response.bytes(
            utf8.encode(jsonEncode(_receipt(bytes, filename, fixture.media))),
            202,
          );
        });
        final source = DocumentUploadRemoteDataSource(client);
        final result = await source.sendOriginal(
          bytes,
          source.prepare(DocumentUploadNames.properties(filename)),
          filename,
          Completer<void>().future,
        );
        expect(calls, 1);
        expect(result.file!.sha256, sha256.convert(bytes).toString());
        expect(result.file!.originalFilename, filename);
        expect(result.file!.mediaType, fixture.media);
      },
    );
  }

  final mutations = <String, void Function(Map<String, Object?>)>{
    'missing description': (value) => value.remove('description'),
    'wrong description type': (value) => value['description'] = 3,
    'wrong title': (value) => value['title'] = 'Different',
    'null tags': (value) => value['tags'] = null,
    'wrong tag member': (value) => value['tags'] = <Object>[12],
    'oversized whitespace sender': (value) => value['sender'] = ' ' * 321,
    'oversized trimmed tag': (value) =>
        value['tags'] = <String>['${' ' * 64}x'],
    'missing file name': (value) =>
        (value['file']! as Map<String, Object?>).remove('originalFilename'),
    'different file name': (value) =>
        (value['file']! as Map<String, Object?>)['originalFilename'] =
            'other.pdf',
    'size string': (value) =>
        (value['file']! as Map<String, Object?>)['size'] = '6',
    'hash mismatch': (value) =>
        (value['file']! as Map<String, Object?>)['sha256'] = 'a' * 64,
    'media mismatch': (value) =>
        (value['file']! as Map<String, Object?>)['mediaType'] = 'image/png',
    'missing uploader': (value) =>
        (value['file']! as Map<String, Object?>).remove('uploaderId'),
    'invalid uploader': (value) =>
        (value['file']! as Map<String, Object?>)['uploaderId'] = 'private',
    'overflowing date': (value) => value['createdAt'] = '2026-02-30T12:20:00Z',
    'missing timestamp': (value) =>
        (value['file']! as Map<String, Object?>).remove('ingestedAt'),
    'invalid processing': (value) => value['processing'] = <String, Object>{},
  };
  for (final mutation in mutations.entries) {
    test(
      'wire validation rejects ${mutation.key} without relying on generated assertions',
      () async {
        final bytes = Uint8List.fromList(utf8.encode('%PDF-1'));
        final raw = _receipt(bytes, 'test.pdf', 'application/pdf');
        mutation.value(raw);
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        client.client = MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(raw)), 202),
        );
        addTearDown(client.client.close);
        final source = DocumentUploadRemoteDataSource(client);
        await expectLater(
          source.sendOriginal(
            bytes,
            source.prepare(DocumentUploadNames.properties('test.pdf')),
            'test.pdf',
            Completer<void>().future,
          ),
          throwsA(
            isA<DocumentUploadException>().having(
              (error) => error.disposition,
              'outcome',
              DocumentUploadDisposition.uncertain,
            ),
          ),
        );
      },
    );
  }

  for (final status in [415, 409, 503]) {
    test(
      'HTTP $status has a definite rejection, duplicate or unknown outcome',
      () async {
        final client = api.ApiClient(basePath: 'http://example.test')
          ..client.close();
        client.client = MockClient((_) async => http.Response('{}', status));
        addTearDown(client.client.close);
        final source = DocumentUploadRemoteDataSource(client);
        await expectLater(
          source.sendOriginal(
            Uint8List.fromList([1, 2, 3]),
            source.prepare(DocumentUploadNames.properties('test.bin')),
            'test.bin',
            Completer<void>().future,
          ),
          throwsA(
            isA<DocumentUploadException>().having(
              (error) => error.disposition,
              'outcome',
              switch (status) {
                415 => DocumentUploadDisposition.rejected,
                409 => DocumentUploadDisposition.duplicate,
                _ => DocumentUploadDisposition.uncertain,
              },
            ),
          ),
        );
      },
    );
  }

  test('general unknown outcome asks for a new selection rather than a retained scanner retry', () async {
    final client = api.ApiClient(basePath: 'http://example.test')
      ..client.close();
    client.client = MockClient((_) async => http.Response('{}', 503));
    addTearDown(client.client.close);
    final acquisition = _Acquisition();
    addTearDown(acquisition.dispose);
    final selected = acquisition.capture(
      1,
      reserve: (_) => true,
      handleAt: (_) => _Handle(Uint8List.fromList(utf8.encode('%PDF-1'))),
    );
    final repository = RemoteDocumentUploadRepository(
      acquisition,
      DocumentUploadRemoteDataSource(client),
    );
    addTearDown(repository.dispose);
    final result = await repository.upload(
      selected.candidates.single,
      cancel: Completer<void>().future,
      onSending: () {},
    );
    expect(result.outcome, DocumentUploadOutcome.uncertain);
    expect(result.message, contains('before selecting this file again'));
    expect(result.message, isNot(contains('retry')));
  });

  test('observed 202 survives cancellation and a failing acceptance callback, then releases handle', () async {
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1'));
    final client = api.ApiClient(basePath: 'http://example.test')
      ..client.close();
    final late = _LateClient(
      jsonEncode(_receipt(bytes, 'test.pdf', 'application/pdf')),
    );
    client.client = late;
    addTearDown(client.client.close);
    final acquisition = _Acquisition();
    final selected = acquisition.capture(
      1,
      reserve: (_) => true,
      handleAt: (_) => _Handle(bytes),
    );
    final repository = RemoteDocumentUploadRepository(
      acquisition,
      DocumentUploadRemoteDataSource(client),
    );
    addTearDown(repository.dispose);
    addTearDown(acquisition.dispose);
    final cancel = Completer<void>();
    var accepted = 0, settled = false;
    final pending = repository
        .upload(
          selected.candidates.single,
          cancel: cancel.future,
          onSending: () {},
          onAccepted: (_) {
            accepted++;
            throw StateError('UI disposed');
          },
        )
        .then((value) {
          settled = true;
          return value;
        });
    await late.started.future;
    cancel.complete();
    await late.aborted.future;
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    late.release.complete();
    final result = await pending;
    expect(result.outcome, DocumentUploadOutcome.accepted);
    expect(accepted, 1);
    await expectLater(
      acquisition.read(selected.candidates.single.id, Completer<void>().future),
      throwsA(isA<DocumentUploadReadException>()),
    );
  });
}

final class _Acquisition extends DocumentUploadAcquisition {
  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) async => DocumentUploadSelection(cancelled: true);
  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => throw UnimplementedError();
}

final class _Handle implements DocumentUploadHandle {
  const _Handle(this.bytes);
  final Uint8List bytes;
  @override
  String get displayName => 'test.pdf';
  @override
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) async => bytes;
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
      (request as http.Abortable).abortTrigger!.then((_) {
        if (!aborted.isCompleted) aborted.complete();
      }),
    );
    started.complete();
    await release.future;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 202);
  }
}
