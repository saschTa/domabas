import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/session_store.dart';
import '../models/session_store_key.dart';
import 'session_store_sources.dart';

final class BrowserSessionStore implements SessionStore {
  BrowserSessionStore({required String apiBaseUrl, required this._storage})
    : _key = '${sessionStoreKey(apiBaseUrl)}.signed_out';

  final String _key;
  final SessionMarkerStorage _storage;

  Future<T> _run<T>(T Function() operation) async {
    try {
      return operation();
    } catch (_) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  }

  @override
  Future<String?> readToken() async => null;

  @override
  Future<bool> isSignedOut() => _run(() => _storage.read(_key) != null);

  @override
  Future<void> saveToken(String token) => _run(() {
    _storage.delete(_key);
    if (_storage.read(_key) != null) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  });

  @override
  Future<void> clear() => _run(() {
    _storage.write(_key, '1');
    if (_storage.read(_key) != '1') {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  });
}
