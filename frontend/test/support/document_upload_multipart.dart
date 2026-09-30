import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';

Map<String, Uint8List> expectDocumentUploadMultipart({
  required List<int> body,
  required String contentType,
  required List<int> metadata,
  required List<int> original,
  required String filename,
  required String originalMediaType,
}) {
  final type = MediaType.parse(contentType);
  expect(type.mimeType, 'multipart/form-data');
  final boundary = type.parameters['boundary'];
  expect(boundary, isNotNull);
  final segments = latin1.decode(body).split('--$boundary');
  expect(segments.first, isEmpty);
  expect(segments.last, '--\r\n');
  final parts = segments.sublist(1, segments.length - 1);
  expect(parts, hasLength(2));
  final fields = <String, Uint8List>{};
  for (final part in parts) {
    expect(part, startsWith('\r\n'));
    expect(part, endsWith('\r\n'));
    final split = part.indexOf('\r\n\r\n');
    expect(split, greaterThan(2));
    final headerLines = part.substring(2, split).split('\r\n');
    final headers = <String, String>{};
    for (final line in headerLines) {
      final colon = line.indexOf(':');
      expect(colon, greaterThan(0));
      final name = line.substring(0, colon).toLowerCase();
      expect(
        headers.containsKey(name),
        isFalse,
        reason: 'Duplicate part header',
      );
      headers[name] = line.substring(colon + 1).trim();
    }
    expect(
      headers.keys,
      unorderedEquals(['content-type', 'content-disposition']),
      reason: 'The public upload contract rejects extra part headers.',
    );
    final disposition = headers['content-disposition']!;
    final name = RegExp(r'(?:^|; )name="([^"]+)"')
        .firstMatch(disposition)
        ?.group(1);
    expect(name, isIn(['metadata', 'file']));
    expect(fields.containsKey(name), isFalse, reason: 'Duplicate form part');
    final bytes = Uint8List.fromList(
      latin1.encode(part.substring(split + 4, part.length - 2)),
    );
    fields[name!] = bytes;
    if (name == 'metadata') {
      expect(disposition, 'form-data; name="metadata"');
      expect(headers['content-type'], 'application/json');
      expect(bytes, metadata);
    } else {
      expect(
        disposition,
        latin1.decode(
          utf8.encode('form-data; name="file"; filename="$filename"'),
        ),
      );
      expect(headers['content-type'], originalMediaType);
      expect(bytes, original);
    }
  }
  expect(fields.keys, unorderedEquals(['metadata', 'file']));
  return fields;
}
