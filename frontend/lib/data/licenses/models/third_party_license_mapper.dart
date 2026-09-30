import '../../../domain/licenses/models/third_party_license.dart';

final class ThirdPartyLicenseMapper {
  const ThirdPartyLicenseMapper();

  List<ThirdPartyLicense> fromInventory(Map<String, dynamic> inventory) {
    if (inventory['schemaVersion'] != 1) {
      throw const FormatException('Unsupported license inventory.');
    }
    final texts = inventory['texts'] as Map<String, dynamic>;
    return (inventory['entries'] as List<dynamic>).map((value) {
      final entry = value as Map<String, dynamic>;
      return ThirdPartyLicense(
        id: entry['id'] as String,
        name: entry['name'] as String,
        version: entry['version'] as String,
        component: entry['component'] as String,
        license: entry['license'] as String,
        sourceUrl: entry['sourceUrl'] as String,
        notices: (entry['notices'] as List<dynamic>).map((value) {
          final notice = value as Map<String, dynamic>;
          return ThirdPartyLicenseNotice(
            title: notice['title'] as String,
            text: texts[notice['textId']] as String,
          );
        }).toList(),
      );
    }).toList();
  }
}
