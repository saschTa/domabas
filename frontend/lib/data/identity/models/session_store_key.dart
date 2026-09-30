import 'dart:convert';

String sessionStoreKey(String apiBaseUrl) {
  final endpoint = Uri.tryParse(apiBaseUrl);
  if (endpoint == null ||
      !endpoint.hasAuthority ||
      !{'http', 'https'}.contains(endpoint.scheme) ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    throw ArgumentError('Session storage requires an HTTP(S) API endpoint.');
  }
  final path = endpoint.path.replaceAll(RegExp(r'/+$'), '');
  final normalized = '${endpoint.origin}$path';
  final encoded = base64Url.encode(utf8.encode(normalized)).replaceAll('=', '');
  return 'domabas.session.v1.$encoded';
}
