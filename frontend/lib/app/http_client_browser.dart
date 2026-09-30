import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createHttpClient() => _BrowserSessionClient();

final class _BrowserSessionClient extends http.BaseClient {
  final BrowserClient _inner = BrowserClient()..withCredentials = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['X-Domabas-Browser'] = '1';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
