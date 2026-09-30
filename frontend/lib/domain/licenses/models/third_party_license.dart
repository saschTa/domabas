final class ThirdPartyLicenseNotice {
  const ThirdPartyLicenseNotice({required this.title, required this.text});

  final String title;
  final String text;
}

final class ThirdPartyLicense {
  ThirdPartyLicense({
    required this.id,
    required this.name,
    required this.version,
    required this.component,
    required this.license,
    required this.sourceUrl,
    required List<ThirdPartyLicenseNotice> notices,
  }) : notices = List.unmodifiable(notices);

  final String id;
  final String name;
  final String version;
  final String component;
  final String license;
  final String sourceUrl;
  final List<ThirdPartyLicenseNotice> notices;
}
