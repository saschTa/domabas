import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'native_http_client_factory.dart';

http.Client createHttpClient() => NativeHttpClient();

final class NativeHttpClient extends http.BaseClient {
  NativeHttpClient({Future<HttpClient> Function()? clientFactory})
    : _clientFactory = clientFactory ?? createNativeHttpClient;

  final Future<HttpClient> Function() _clientFactory;
  Future<IOClient>? _pendingClient;
  IOClient? _client;
  bool _closed = false;

  Future<IOClient> _open() async {
    try {
      final native = await _clientFactory();
      if (_closed) {
        native.close(force: true);
        throw http.ClientException('HTTP client is closed.');
      }
      return _client = IOClient(native);
    } catch (_) {
      _pendingClient = null;
      rethrow;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('HTTP client is closed.', request.url);
    }
    final cancelled = request is http.Abortable
        ? request.abortTrigger?.then<IOClient>(
            (_) => throw http.RequestAbortedException(request.url),
          )
        : null;
    final pending = _pendingClient ??= _open();
    final client = await (cancelled == null
        ? pending
        : Future.any([cancelled, pending]));
    if (_closed) {
      throw http.ClientException('HTTP client is closed.', request.url);
    }
    try {
      return await client.send(request);
    } on TlsException {
      throw http.ClientException(
        'Could not establish a trusted TLS connection.',
        request.url,
      );
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _client?.close();
  }
}
