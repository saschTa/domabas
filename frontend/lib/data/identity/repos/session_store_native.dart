import 'dart:async';

import '../../../domain/identity/models/identity_failure.dart';
import '../../../domain/identity/interfaces/session_store.dart';
import '../models/session_store_key.dart';
import 'session_store_sources.dart';

final class NativeSessionStore implements SessionStore {
  NativeSessionStore({
    required String apiBaseUrl,
    required this._storage,
    this._operationTimeout = const Duration(seconds: 5),
  }) : _key = '${sessionStoreKey(apiBaseUrl)}.credential';

  final String _key;
  final SecureTokenStorage _storage;
  final Duration _operationTimeout;
  Future<void> _pending = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() operation) async {
    final current = _pending.then((_) => operation());
    _pending = current.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      return await current.timeout(_operationTimeout);
    } catch (_) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  }

  @override
  Future<String?> readToken() => _run(() => _storage.read(_key));

  @override
  Future<bool> isSignedOut() async => await readToken() == null;

  @override
  Future<void> saveToken(String token) => _run(() async {
    if (token.isEmpty) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
    await _storage.write(_key, token);
    if (await _storage.read(_key) != token) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  });

  @override
  Future<void> clear() => _run(() async {
    await _storage.delete(_key);
    if (await _storage.read(_key) != null) {
      throw const IdentityFailure(IdentityFailureKind.unavailable);
    }
  });
}
