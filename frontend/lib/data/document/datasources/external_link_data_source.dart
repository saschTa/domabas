import 'package:url_launcher/url_launcher.dart';

final class ExternalLinkDataSource {
  Future<bool> open(Uri uri) => launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
}
