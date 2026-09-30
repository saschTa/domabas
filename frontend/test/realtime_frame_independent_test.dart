import 'dart:convert';

import 'package:domabas/data/realtime/datasources/realtime_frame_parser.dart';
import 'package:domabas/data/realtime/datasources/realtime_websocket_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('strict realtime frames on VM and web', () {
    test('all legal types and escaped field names have one interpretation', () {
      for (final type in ['ready', 'invalidate', 'resync']) {
        expect(
          parseRealtimeFrame(
            '{"ty\\u0070e":"$type","version":1,"topics":'
            '["documents","processing","processing_configuration",'
            '"email","paperless","chat","activity","identity","members","system_users"]}',
          ),
          {'type': type, 'version': 1, 'topics': realtimeTopics.toList()},
        );
      }
      expect(parseRealtimeFrame(' \n{"version":1,"type":"heartbeat"}\t'), {
        'type': 'heartbeat',
        'version': 1,
      });
    });

    final invalid = <String, Object?>{
      'binary': utf8.encode('{"type":"heartbeat","version":1}'),
      'null': null,
      'duplicate ordinary key':
          '{"type":"ready","type":"ready","version":1,"topics":[]}',
      'duplicate escaped key':
          r'{"type":"ready","ty\u0070e":"ready","version":1,"topics":[]}',
      'duplicate escaped topic':
          r'{"type":"ready","version":1,"topics":["email","em\u0061il"]}',
      'unknown field': '{"type":"heartbeat","version":1,"id":"secret"}',
      'null field': '{"type":"ready","version":1,"topics":null}',
      'null version': '{"type":"heartbeat","version":null}',
      'heartbeat topics': '{"type":"heartbeat","version":1,"topics":[]}',
      'ready without topics': '{"type":"ready","version":1}',
      'auth from server': '{"type":"authenticate","version":1,"topics":[]}',
      'float version': '{"type":"heartbeat","version":1.0}',
      'exponent version': '{"type":"heartbeat","version":1e0}',
      'boolean version': '{"type":"heartbeat","version":true}',
      'string version': '{"type":"heartbeat","version":"1"}',
      'wrong version': '{"type":"heartbeat","version":2}',
      'trailing value': '{"type":"heartbeat","version":1}{}',
      'trailing comma': '{"type":"ready","version":1,"topics":["email",]}',
      'nested topics': '{"type":"ready","version":1,"topics":[["email"]]}',
      'nested field': '{"type":{"type":"ready"},"version":1,"topics":[]}',
      'unknown topic': '{"type":"ready","version":1,"topics":["users"]}',
      'escaped high surrogate':
          r'{"type":"ready","version":1,"topics":["\ud800"]}',
      'escaped low surrogate':
          r'{"type":"ready","version":1,"topics":["\udfff"]}',
      'escaped high then ordinary':
          r'{"type":"ready","version":1,"topics":["\ud800a"]}',
      'raw high surrogate':
          '{"type":"${String.fromCharCode(0xd800)}","version":1}',
      'raw low surrogate':
          '{"type":"${String.fromCharCode(0xdfff)}","version":1}',
      'literal newline': '{"type":"heart\nbeat","version":1}',
      'bad escape': r'{"type":"heart\qbeat","version":1}',
      'unicode whitespace': '\u00a0{"type":"heartbeat","version":1}',
    };
    for (final entry in invalid.entries) {
      test('rejects ${entry.key}', () {
        expect(() => parseRealtimeFrame(entry.value), throwsFormatException);
      });
    }

    test('512 byte boundary includes whitespace and counts UTF-8 bytes', () {
      const frame = '{"type":"heartbeat","version":1}';
      final exact = frame.padRight(512);
      expect(parseRealtimeFrame(exact)['type'], 'heartbeat');
      expect(() => parseRealtimeFrame('$exact '), throwsFormatException);
      final multibyte = '{"type":"${'é' * 250}","version":1}';
      expect(multibyte.length, lessThan(512));
      expect(utf8.encode(multibyte).length, greaterThan(512));
      expect(() => parseRealtimeFrame(multibyte), throwsFormatException);
    });
  });

  group('realtime endpoint preserves configured authority and prefix', () {
    for (final entry in <String, String>{
      'https://example.test/proxy/v2/':
          'wss://example.test/proxy/v2/api/v1/realtime',
      'http://example.test:7357/root///':
          'ws://example.test:7357/root/api/v1/realtime',
      'https://[::1]:9443/prefix': 'wss://[::1]:9443/prefix/api/v1/realtime',
      'http://127.0.0.1:8080': 'ws://127.0.0.1:8080/api/v1/realtime',
    }.entries) {
      test(entry.key, () {
        expect(realtimeEndpoint(entry.key).toString(), entry.value);
      });
    }
    for (final endpoint in [
      'file:///tmp/api',
      'http:/missing-authority',
      'https://user:password@example.test',
      'https://example.test?token=secret',
      'https://example.test#fragment',
    ]) {
      test('rejects $endpoint', () {
        expect(() => realtimeEndpoint(endpoint), throwsArgumentError);
      });
    }
  });
}
