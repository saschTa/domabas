import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repos/session_store_sources.dart';

final class SecureSessionDataSource implements SecureTokenStorage {
  SecureSessionDataSource(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String token) =>
      _storage.write(key: key, value: token);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
