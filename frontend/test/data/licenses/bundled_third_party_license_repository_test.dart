import 'dart:convert';

import 'package:domabas/data/licenses/datasources/bundled_third_party_license_data_source.dart';
import 'package:domabas/data/licenses/repos/bundled_third_party_license_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _LicenseAssetBundle extends CachingAssetBundle {
  _LicenseAssetBundle(this.content);

  final String content;
  bool unavailable = false;
  int reads = 0;

  @override
  Future<ByteData> load(String key) async {
    expect(key, 'assets/licenses/third-party.json');
    reads++;
    if (unavailable) throw StateError('Asset is offline');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retains package notices and merges every runtime notice once',
    () async {
      final source = BundledThirdPartyLicenseDataSource(
        bundle: _LicenseAssetBundle(
          jsonEncode({
            'schemaVersion': 1,
            'texts': {'notice': 'Copyright Example.\n\nPermission granted.'},
            'entries': [
              {
                'id': 'dart:example',
                'name': 'example',
                'version': '1.0',
                'component': 'Flutter client',
                'license': 'MIT',
                'sourceUrl': '',
                'notices': [
                  {'title': 'LICENSE', 'textId': 'notice'},
                ],
              },
            ],
          }),
        ),
        licenses: () => Stream.fromIterable([
          LicenseEntryWithLineBreaks([
            'example',
          ], 'Copyright Example.\n\nPermission granted.'),
          LicenseEntryWithLineBreaks([
            'example',
            'native',
          ], 'Another copyright notice.'),
          LicenseEntryWithLineBreaks(['native'], 'Another copyright notice.'),
        ]),
      );
      final entries = await BundledThirdPartyLicenseRepository(
        dataSource: source,
      ).load();
      expect(entries.map((entry) => entry.name), ['example', 'native']);
      expect(entries.first.notices, hasLength(2));
      expect(entries.last.notices, hasLength(1));
      expect(() => entries.clear(), throwsUnsupportedError);
      expect(() => entries.first.notices.clear(), throwsUnsupportedError);
    },
  );

  test(
    'bundled repository inventory is usable without network or API',
    () async {
      final entries = await BundledThirdPartyLicenseRepository(
        dataSource: BundledThirdPartyLicenseDataSource(
          bundle: rootBundle,
          licenses: () => const Stream.empty(),
        ),
      ).load();
      for (final id in [
        'go:github.com/air-verse/air',
        'dart:dbus',
        'npm:sharp',
        'extra:Barlow Condensed font',
        'extra:DM Sans font',
        'maven:org.opencv:opencv',
      ]) {
        expect(
          entries.any((entry) => entry.id == id && entry.notices.isNotEmpty),
          isTrue,
          reason: id,
        );
      }
      expect(
        entries.every(
          (entry) => entry.notices.every((notice) => notice.text.isNotEmpty),
        ),
        isTrue,
      );
    },
  );

  test('corrupt inventory produces a recoverable load failure', () async {
    final repository = BundledThirdPartyLicenseRepository(
      dataSource: BundledThirdPartyLicenseDataSource(
        bundle: _LicenseAssetBundle('{"schemaVersion": 99}'),
        licenses: () => const Stream.empty(),
      ),
    );
    await expectLater(repository.load(), throwsFormatException);
  });

  test(
    'failed asset reads retry and successful reads stay cached offline',
    () async {
      final bundle = _LicenseAssetBundle(
        jsonEncode({
          'schemaVersion': 1,
          'texts': {'notice': 'Copyright Example. Permission granted.'},
          'entries': [
            {
              'id': 'dart:example',
              'name': 'example',
              'version': '1.0',
              'component': 'Flutter client',
              'license': 'MIT',
              'sourceUrl': '',
              'notices': [
                {'title': 'LICENSE', 'textId': 'notice'},
              ],
            },
          ],
        }),
      )..unavailable = true;
      final repository = BundledThirdPartyLicenseRepository(
        dataSource: BundledThirdPartyLicenseDataSource(
          bundle: bundle,
          licenses: () => const Stream.empty(),
        ),
      );
      await expectLater(repository.load(), throwsStateError);
      expect(bundle.reads, 1);

      bundle.unavailable = false;
      final online = await repository.load();
      expect(online.single.name, 'example');
      expect(bundle.reads, 2);

      bundle.unavailable = true;
      final offline = await repository.load();
      expect(
        offline.single.notices.single.text,
        online.single.notices.single.text,
      );
      expect(bundle.reads, 2);
    },
  );
}
