import 'package:flutter/services.dart';

final class MobileShareBatch {
  MobileShareBatch({
    required this.id,
    required Iterable<String> paths,
    this.error,
  }) : paths = List.unmodifiable(paths);
  final String id;
  final List<String> paths;
  final String? error;
}

class MobileShareDataSource {
  MobileShareDataSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.domabas/mobile_share');
  final MethodChannel _channel;

  void listen(void Function() changed) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') changed();
    });
  }

  Future<MobileShareBatch?> pending() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('pending');
    if (value == null) return null;
    return MobileShareBatch(
      id: value['id'] as String,
      paths: (value['paths'] as List).cast<String>(),
      error: value['error'] as String?,
    );
  }

  Future<void> release(String id) => _channel.invokeMethod<void>('release', id);

  Future<void> setSession(Map<String, String>? context) =>
      _channel.invokeMethod<void>('setSession', context);

  void dispose() => _channel.setMethodCallHandler(null);
}
