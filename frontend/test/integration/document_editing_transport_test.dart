import 'dart:convert';

import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const id = 'c70a9c09-efcc-4210-830c-b73c408ac2ae';
  final original = Document(
    id: id,
    title: 'Original',
    description: '',
    createdAt: DateTime.utc(2026, 9, 17),
  );
  late Future<http.Response> Function(http.Request) respond;
  late api.ApiClient client;
  late RemoteDocumentRepository repository;
  setUp(() {
    client = api.ApiClient(basePath: 'http://example.test')..client.close();
    client.client = MockClient((request) => respond(request));
    repository = RemoteDocumentRepository(
      DocumentRemoteDataSource(api.DocumentsApi(client)),
    );
  });
  tearDown(() => client.client.close());

  test(
    'every editable property round-trips and optional fields clear explicitly',
    () async {
      final edited = DocumentProperties(
        title: 'Revised letter',
        description: 'New description\nSecond paragraph',
        tags: ['finance', 'reviewed'],
        kind: 'email',
        sender: 'Sender <sender@example.test>',
        recipients: ['Reader <reader@example.test>'],
        cc: ['Copy <copy@example.test>'],
        bcc: ['Hidden <hidden@example.test>'],
        documentDate: '2026-09-18',
        subject: 'Revised subject',
        messageId: '<revised@example.test>',
      );
      Map<String, Object> expected = edited.values;
      Map<String, Object> current = edited.values;
      var calls = 0;
      respond = (request) async {
        calls++;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/documents/$id');
        final fields = jsonDecode(request.body) as Map<String, dynamic>;
        expect(fields, expected);
        expect(fields.values, isNot(contains(null)));
        expect(fields, isNot(contains('file')));
        expect(fields, isNot(contains('processing')));
        return http.Response(
          jsonEncode({
            'id': id,
            'createdAt': '2026-09-17T00:00:00Z',
            ...current,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      final updated = await repository.update(original, edited);
      expect(DocumentProperties.fromDocument(updated).values, edited.values);
      expect(updated.createdAt, original.createdAt);
      final cleared = DocumentProperties(
        title: edited.title,
        description: '',
        tags: [],
        kind: edited.kind,
        sender: '',
        recipients: [],
        cc: [],
        bcc: [],
        documentDate: '',
        subject: '',
        messageId: '',
      );
      current = cleared.values;
      expected = {...cleared.values}
        ..remove('title')
        ..remove('kind');
      final emptied = await repository.update(updated, cleared);
      expect(DocumentProperties.fromDocument(emptied).values, cleared.values);
      expect(calls, 2);
      expect(await repository.update(emptied, cleared), same(emptied));
      expect(calls, 2);
    },
  );

  test(
    'OCR transport preserves exact Unicode text, empty correction and revision',
    () async {
      var revision = 7;
      var text = '  Exact\r\n世界 🚀\t trailing  ';
      respond = (request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/documents/$id/ocr');
        expect(jsonDecode(request.body), {'revision': revision, 'text': text});
        return http.Response(
          jsonEncode({
            'status': 'available',
            'revision': revision + 1,
            'text': text,
            'origin': 'manual',
            'reason': null,
            'semanticIndexing': text.isEmpty ? 'not_required' : 'pending',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      };
      final corrected = await repository.updateOcr(id, revision, text);
      expect(corrected.text, text);
      expect(corrected.revision, 8);
      expect(corrected.origin, 'manual');
      expect(corrected.reason, isNull);
      expect(corrected.semanticIndexing, 'pending');
      revision = 8;
      text = '';
      final empty = await repository.updateOcr(id, revision, text);
      expect(empty.available, isTrue);
      expect(empty.text, '');
      expect(empty.revision, 9);
      expect(empty.semanticIndexing, 'not_required');
    },
  );
}
