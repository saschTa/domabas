import 'dart:convert';

import 'package:domabas/data/document/datasources/document_upload_remote_data_source.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload_validation.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

DocumentProperties scanProperties([Map<String, Object> changes = const {}]) =>
    DocumentProperties(
      title: changes['title'] as String? ?? 'Scanner fixture',
      description: changes['description'] as String? ?? '',
      tags: changes['tags'] as List<String>? ?? const [],
      kind: changes['kind'] as String? ?? 'document',
      sender: changes['sender'] as String? ?? '',
      recipients: changes['recipients'] as List<String>? ?? const [],
      cc: changes['cc'] as List<String>? ?? const [],
      bcc: changes['bcc'] as List<String>? ?? const [],
      documentDate: changes['documentDate'] as String? ?? '',
      subject: changes['subject'] as String? ?? '',
      messageId: changes['messageId'] as String? ?? '',
    );

void main() {
  test('raw invalid UTF-16 and NUL fail every scalar and list field before normalization', () {
    for (final field in [
      'title',
      'description',
      'sender',
      'subject',
      'messageId',
      'documentDate',
      'kind',
      'tags',
      'recipients',
      'cc',
      'bcc',
    ]) {
      for (final invalid in ['\ud800', '\udc00', 'x\ud800z', '\u0000']) {
        final value = scanProperties({
          field: ['tags', 'recipients', 'cc', 'bcc'].contains(field)
              ? <String>[' $invalid ']
              : ' $invalid ',
        });
        expect(
          DocumentUploadValidation.validate(value),
          contains(field),
          reason: '$field ${invalid.codeUnits}',
        );
        expect(
          () => DocumentUploadValidation.normalize(value),
          throwsArgumentError,
        );
      }
    }
  });
  test('Go whitespace, simple Unicode lowercasing and scalar tag order match backend', () {
    final normalized = DocumentUploadValidation.normalize(
      scanProperties({
        'title': '\u00a0 Test \u3000',
        'tags': <String>['\u{10400}', '\ue000', 'ΟΣ', 'İ', '\uFEFFKEEP\uFEFF'],
        'sender': '\u0085Sender\u2000',
        'recipients': <String>[' A ', 'a'],
        'description': ' \n\t\u0085kept ',
      }),
    );
    expect(normalized.title, 'Test');
    expect(normalized.sender, 'Sender');
    expect(normalized.tags, [
      'i',
      'οσ',
      '\ue000',
      '\uFEFFkeep\uFEFF',
      '\u{10428}',
    ]);
    expect(normalized.recipients, ['A', 'a']);
    expect(normalized.description, ' \n\t\u0085kept ');
    for (final tags in [
      <String>[' A', 'a '],
      <String>['İ', 'i'],
      <String>['ΟΣ', 'οσ'],
    ]) {
      expect(
        DocumentUploadValidation.validate(scanProperties({'tags': tags})),
        contains('tags'),
      );
    }
  });
  test(
    'calendar, Unicode limits, display controls and list empties are validated',
    () {
      for (final date in [
        '0000-01-01',
        '2025-02-29',
        '2026-04-31',
        '2026-1-01',
      ]) {
        expect(
          DocumentUploadValidation.validate(
            scanProperties({'documentDate': date}),
          ),
          contains('documentDate'),
        );
      }
      expect(
        DocumentUploadValidation.validate(
          scanProperties({'documentDate': '2024-02-29', 'title': '🚀' * 200}),
        ),
        isEmpty,
      );
      expect(
        DocumentUploadValidation.validate(
          scanProperties({'title': '🚀' * 201}),
        ),
        contains('title'),
      );
      expect(
        DocumentUploadValidation.validate(scanProperties({'title': '\tTitle'})),
        contains('title'),
      );
      expect(
        DocumentUploadValidation.validate(
          scanProperties({
            'tags': <String>['ok', ''],
          }),
        ),
        contains('tags'),
      );
      expect(
        DocumentUploadValidation.validate(
          scanProperties({'recipients': List.filled(21, 'x')}),
        ),
        contains('recipients'),
      );
    },
  );
  test(
    'prepared metadata is sparse, complete and frozen against caller mutation',
    () {
      final client = api.ApiClient();
      addTearDown(client.client.close);
      final source = DocumentUploadRemoteDataSource(client);
      final minimal = source.prepare(scanProperties());
      expect(jsonDecode(utf8.decode(minimal.bytes)), {
        'title': 'Scanner fixture',
        'kind': 'document',
      });
      final raw = scanProperties({
        'description': 'Exact\nnotes',
        'tags': <String>['B', 'a'],
        'kind': 'email',
        'sender': ' Sender ',
        'recipients': <String>[' To '],
        'cc': <String>[' Copy '],
        'bcc': <String>[' Hidden '],
        'documentDate': '2026-09-18',
        'subject': ' Subject ',
        'messageId': ' <id> ',
      });
      final prepared = source.prepare(raw);
      expect(
        jsonDecode(utf8.decode(prepared.bytes)),
        DocumentUploadValidation.normalize(raw).values,
      );
      expect(() => prepared.bytes[0] = 0, throwsUnsupportedError);
      expect(
        () => source.prepare(
          scanProperties({
            'description': '🚀' * 4000,
            'recipients': List.generate(20, (i) => '$i${'🚀' * 318}'),
          }),
        ),
        throwsArgumentError,
      );
    },
  );
}
