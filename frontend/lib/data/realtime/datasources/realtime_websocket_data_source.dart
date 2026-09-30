import 'dart:async';
import 'dart:convert';

import 'package:domabas_api/api.dart' as api;

import '../models/realtime_record.dart';
import 'realtime_frame_parser.dart';
import 'realtime_socket_attempt.dart';
import 'realtime_socket_factory.dart';

Uri realtimeEndpoint(String baseUrl) {
  final base = Uri.parse(baseUrl);
  if (!const {'http', 'https'}.contains(base.scheme) ||
      !base.hasAuthority ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    throw ArgumentError('Realtime requires a valid HTTP(S) API endpoint');
  }
  return Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/realtime')
      .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');
}

final class RealtimeWebSocketDataSource {
  RealtimeWebSocketDataSource({
    required String endpoint,
    required this._token,
    RealtimeSocketAttemptFactory? socketFactory,
    this.connectTimeout = const Duration(seconds: 10),
  }) : _endpoint = realtimeEndpoint(endpoint),
       _socketFactory = socketFactory ?? createSocketAttempt;

  final Uri _endpoint;
  final String _token;
  final RealtimeSocketAttemptFactory _socketFactory;
  final Duration connectTimeout;
  final _events = StreamController<RealtimeRecord>.broadcast(sync: true);
  RealtimeSocketAttempt? _attempt;
  StreamSubscription<Object?>? _subscription;
  int _epoch = 0;
  bool _disposed = false, _ready = false;
  Stream<RealtimeRecord> get events => _events.stream;

  Future<void> connect() async {
    if (_disposed || _attempt != null) return;
    final epoch = ++_epoch;
    try {
      final attempt = _attempt = _socketFactory(_endpoint);
      _subscription = attempt.channel.stream.cast<Object?>().listen(
        (value) => _receive(epoch, value),
        onError: (Object _) => _ended(epoch, null),
        onDone: () => _ended(epoch, attempt.channel.closeCode),
      );
      await attempt.ready.timeout(connectTimeout);
      if (_disposed || epoch != _epoch) {
        attempt.abort();
        return;
      }
      if (attempt.channel.protocol != 'domabas.realtime.v1') {
        _ended(epoch, 1008);
        return;
      }
      final auth = api.RealtimeAuthenticate.fromJson({
        'type': 'authenticate',
        'version': 1,
        'token': _token,
      });
      if (auth == null) throw const FormatException('Invalid authentication');
      attempt.channel.sink.add(jsonEncode(auth.toJson()));
    } catch (_) {
      _ended(epoch, null);
    }
  }

  void _receive(int epoch, Object? value) {
    if (_disposed || epoch != _epoch) return;
    try {
      final frame = parseRealtimeFrame(value);
      final kind = frame['type']! as String;
      if (!_ready && kind != 'ready' || _ready && kind == 'ready') {
        throw const FormatException('Unexpected realtime frame');
      }
      final valid = switch (kind) {
        'ready' => api.RealtimeReady.fromJson(frame) != null,
        'invalidate' => api.RealtimeInvalidation.fromJson(frame) != null,
        'resync' => api.RealtimeResync.fromJson(frame) != null,
        'heartbeat' => api.RealtimeHeartbeat.fromJson(frame) != null,
        _ => false,
      };
      if (!valid) throw const FormatException('Invalid realtime frame');
      _ready = true;
      _events.add(
        RealtimeRecord(
          kind,
          topics: frame['topics'] as List<String>? ?? const [],
        ),
      );
    } catch (_) {
      _ended(epoch, 1008);
    }
  }

  void _ended(int epoch, int? code) {
    if (_disposed || epoch != _epoch) return;
    disconnect();
    _events.add(RealtimeRecord('disconnected', closeCode: code));
  }

  void disconnect() {
    _epoch++;
    _ready = false;
    final attempt = _attempt;
    _attempt = null;
    attempt?.abort();
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    unawaited(_events.close());
  }
}
