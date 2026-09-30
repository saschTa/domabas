import 'package:domabas/app/api_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web deployment follows the browser origin, including custom ports', () {
    expect(
      ApiEndpoint.resolve(
        '',
        browserUri: Uri.parse('https://documents.example:8443/library?id=1'),
      ).baseUrl,
      'https://documents.example:8443',
    );
  });

  test('explicit API override works for web and native development', () {
    for (final browserUri in [null, Uri.parse('https://documents.example')]) {
      expect(
        ApiEndpoint.resolve(
          'http://10.0.2.2:8080/',
          browserUri: browserUri,
        ).baseUrl,
        'http://10.0.2.2:8080',
      );
    }
    expect(ApiEndpoint.resolve('').baseUrl, 'http://localhost:8080');
  });

  test(
    'local browser API uses the page hostname and keeps its port and path',
    () {
      for (final apiHost in ['localhost', '127.0.0.1']) {
        for (final browserHost in ['localhost', '127.0.0.1']) {
          expect(
            ApiEndpoint.resolve(
              'http://$apiHost:8080/backend/',
              browserUri: Uri.parse('http://$browserHost:7357/library'),
            ).baseUrl,
            'http://$browserHost:8080/backend',
          );
        }
      }
    },
  );

  test('local alias resolution preserves other explicit endpoint choices', () {
    final cases = [
      ('http://127.0.0.1:8080', null),
      ('http://localhost:8080', null),
      ('http://127.0.0.2:8080', 'http://localhost:7357'),
      ('http://[::1]:8080', 'http://localhost:7357'),
      ('http://127.0.0.1:8080', 'http://[::1]:7357'),
      ('http://10.0.2.2:8080', 'http://localhost:7357'),
      ('http://127.0.0.1:8080', 'https://localhost:7357'),
      ('https://127.0.0.1:8080', 'http://localhost:7357'),
      ('http://127.0.0.1:8080', 'https://documents.example'),
      ('https://api.example', 'http://localhost:7357'),
    ];
    for (final (endpoint, browser) in cases) {
      expect(
        ApiEndpoint.resolve(
          endpoint,
          browserUri: browser == null ? null : Uri.parse(browser),
        ).baseUrl,
        endpoint,
      );
    }
  });

  test('rejects ambiguous or credential-bearing API configuration', () {
    for (final value in [
      '/api',
      'ftp://example.test',
      'https://user:password@example.test',
      'https://example.test?token=value',
      'https://example.test#fragment',
    ]) {
      expect(() => ApiEndpoint.resolve(value), throwsArgumentError);
    }
  });
}
