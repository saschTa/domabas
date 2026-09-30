import 'package:http/http.dart' as http;

final class SessionClient extends http.BaseClient {
  SessionClient(
    this._inner, {
    required this.token,
    required this.onUnauthorized,
  });

  final http.Client _inner;
  final String token;
  final void Function() onUnauthorized;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer $token';
    final response = await _inner.send(request);
    if (!_closed && response.statusCode == 401) onUnauthorized();
    return response;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
