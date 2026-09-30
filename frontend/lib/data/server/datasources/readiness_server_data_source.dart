import 'dart:async';
import 'dart:convert';

import 'package:domabas_api/api.dart' as api;
import 'package:http/http.dart' as http;

import '../repos/server_sources.dart';

final class ReadinessServerDataSource implements ServerConnectionSource {
  ReadinessServerDataSource({
    required this._clientFactory,
    this.timeout = const Duration(seconds: 8),
  });

  final http.Client Function() _clientFactory;
  final Duration timeout;

  @override
  Future<ServerProbeResult> check(String address) async {
    final client = _ServerReadinessProbeClient(_clientFactory());
    final generated = api.ApiClient(basePath: address);
    generated.client.close();
    generated.client = client;
    final abort = Completer<void>();
    try {
      final response = await api.SystemApi(generated)
          .readinessWithHttpInfo(abortTrigger: abort.future)
          .timeout(timeout);
      if (response.statusCode == 503) return ServerProbeResult.notReady;
      if (response.statusCode != 200) return ServerProbeResult.invalidResponse;
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        return body is Map<String, dynamic> && body['status'] == 'ok'
            ? ServerProbeResult.ready
            : ServerProbeResult.invalidResponse;
      } on FormatException {
        return ServerProbeResult.invalidResponse;
      }
    } finally {
      abort.complete();
      client.close();
    }
  }
}

final class _ServerReadinessProbeClient extends http.BaseClient {
  _ServerReadinessProbeClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    final response = await _inner.send(request);
    return http.StreamedResponse(
      _bounded(response.stream),
      response.statusCode,
      headers: response.headers,
      request: response.request,
    );
  }

  Stream<List<int>> _bounded(Stream<List<int>> source) async* {
    var size = 0;
    await for (final bytes in source) {
      size += bytes.length;
      if (size > 8192) throw const FormatException('Response is too large');
      yield bytes;
    }
  }

  @override
  void close() => _inner.close();
}
