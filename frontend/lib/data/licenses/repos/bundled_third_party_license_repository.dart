import '../../../domain/licenses/interfaces/third_party_license_repository.dart';
import '../../../domain/licenses/models/third_party_license.dart';
import '../datasources/bundled_third_party_license_data_source.dart';
import '../models/third_party_license_mapper.dart';

final class BundledThirdPartyLicenseRepository
    implements ThirdPartyLicenseRepository {
  const BundledThirdPartyLicenseRepository({required this._dataSource});

  final BundledThirdPartyLicenseDataSource _dataSource;

  @override
  Future<List<ThirdPartyLicense>> load() async {
    final entries = const ThirdPartyLicenseMapper().fromInventory(
      await _dataSource.loadInventory(),
    );
    final runtime = <String, List<ThirdPartyLicenseNotice>>{};
    await for (final entry in _dataSource.runtimeLicenses()) {
      final text = entry.paragraphs.map((p) => p.text).join('\n\n');
      for (final package in entry.packages) {
        final notices = runtime.putIfAbsent(package, () => []);
        if (!notices.any((notice) => notice.text == text)) {
          notices.add(
            ThirdPartyLicenseNotice(title: 'Bundled notice', text: text),
          );
        }
      }
    }
    for (final package in runtime.entries) {
      final existingIndex = entries.indexWhere(
        (entry) => entry.name == package.key && entry.id.startsWith('dart:'),
      );
      if (existingIndex >= 0) {
        final existing = entries[existingIndex];
        String normalize(String text) =>
            text.replaceAll(RegExp(r'\s+'), ' ').trim();
        final notices = [...existing.notices];
        for (final notice in package.value) {
          if (!notices.any(
            (n) => normalize(n.text) == normalize(notice.text),
          )) {
            notices.add(notice);
          }
        }
        entries[existingIndex] = ThirdPartyLicense(
          id: existing.id,
          name: existing.name,
          version: existing.version,
          component: existing.component,
          license: existing.license,
          sourceUrl: existing.sourceUrl,
          notices: notices,
        );
      } else {
        entries.add(
          ThirdPartyLicense(
            id: 'flutter-runtime:${package.key}',
            name: package.key,
            version: '',
            component: 'Flutter runtime',
            license: 'See notices',
            sourceUrl: '',
            notices: package.value,
          ),
        );
      }
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(entries);
  }
}
