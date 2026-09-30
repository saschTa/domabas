final class ApiEndpoint {
  ApiEndpoint._(this.baseUrl);

  factory ApiEndpoint.resolve(String configured, {Uri? browserUri}) {
    final value = configured.isNotEmpty
        ? configured
        : browserUri != null
        ? browserUri.origin
        : 'http://localhost:8080';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        configured,
        'API_BASE_URL',
        'Use an HTTP(S) server URL without credentials, query, or fragment',
      );
    }
    const localAliases = {'localhost', '127.0.0.1'};
    final endpoint =
        uri.scheme == 'http' &&
            browserUri?.scheme == 'http' &&
            localAliases.contains(uri.host) &&
            localAliases.contains(browserUri?.host)
        ? uri.replace(host: browserUri!.host).toString()
        : value;
    return ApiEndpoint._(endpoint.replaceAll(RegExp(r'/+$'), ''));
  }

  final String baseUrl;
}
