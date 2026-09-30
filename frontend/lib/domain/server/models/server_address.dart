final class ServerAddress {
  const ServerAddress._(this.value);

  factory ServerAddress.parse(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        RegExp(r'\s').hasMatch(value) ||
        uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'Enter an HTTP or HTTPS server address without a username, password, query or fragment.',
      );
    }
    final path = uri.normalizePath().path.replaceAll(RegExp(r'/+$'), '');
    return ServerAddress._('${uri.origin}$path');
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is ServerAddress && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
