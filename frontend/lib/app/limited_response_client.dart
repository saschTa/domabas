import 'package:http/http.dart' as http;

import '../domain/document/models/document_limits.dart';
import '../data/document/models/response_size_exception.dart';

final class LimitedResponseClient extends http.BaseClient {
  LimitedResponseClient(
    this._inner, {
    this.maximumBytes = documentOriginalByteLimit,
  });

  final http.Client _inner;
  final int maximumBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final thumbnail = RegExp(r'/api/v1/documents/[^/]+/thumbnail$')
        .hasMatch(request.url.path);
    final limit = thumbnail && maximumBytes > documentThumbnailByteLimit
        ? documentThumbnailByteLimit
        : maximumBytes;
    final response = await _inner.send(request);
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw ResponseSizeException();
    }
    return http.StreamedResponse(
      _bounded(response.stream, limit),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  Stream<List<int>> _bounded(Stream<List<int>> source, int limit) async* {
    var received = 0;
    await for (final chunk in source) {
      received += chunk.length;
      if (received > limit) {
        throw ResponseSizeException();
      }
      yield chunk;
    }
  }

  @override
  void close() => _inner.close();
}
