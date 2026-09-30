import 'dart:convert';

import 'package:domabas/data/document/datasources/document_remote_data_source.dart';
import 'package:domabas/data/document/repos/remote_document_repository.dart';
import 'package:domabas/domain/document/models/document_failure.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'unlock sends password only in the body and maps wrong passwords safely',
    () async {
      final client = api.ApiClient(basePath: 'http://example.test')
        ..client.close();
      addTearDown(client.client.close);
      var calls = 0;
      client.client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/v1/documents/pdf/unlock');
        expect(request.url.query, isEmpty);
        expect(jsonDecode(request.body), {
          'password': ' pässword ',
          'generation': 4,
        });
        return calls == 1
            ? http.Response(
                '{"code":"invalid_pdf_password","message":"untrusted body"}',
                400,
              )
            : http.Response('{}', 202);
      });
      final repository = RemoteDocumentRepository(
        DocumentRemoteDataSource(api.DocumentsApi(client)),
      );
      await expectLater(
        repository.unlock('pdf', 4, ' pässword '),
        throwsA(
          isA<DocumentFailure>().having(
            (e) => e.kind,
            'kind',
            DocumentFailureKind.invalidPassword,
          ),
        ),
      );
      expect(calls, 1);
      await repository.unlock('pdf', 4, ' pässword ');
      expect(calls, 2);
    },
  );
}
