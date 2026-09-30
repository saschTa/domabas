import 'dart:async';

import 'package:domabas/data/identity/repos/session_store_browser.dart';
import 'package:domabas/data/identity/models/session_store_key.dart';
import 'package:domabas/data/identity/repos/session_store_native.dart';
import 'package:domabas/data/identity/repos/session_store_sources.dart';
import 'package:domabas/domain/identity/models/identity_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final unavailable = isA<IdentityFailure>().having(
    (failure) => failure.kind,
    'kind',
    IdentityFailureKind.unavailable,
  );

  test(
    'storage keys normalize endpoints and preserve installation isolation',
    () {
      expect(
        sessionStoreKey('HTTPS://EXAMPLE.COM:443/api/'),
        sessionStoreKey('https://example.com/api'),
      );
      expect(
        sessionStoreKey('http://example.com:80/'),
        sessionStoreKey('http://example.com'),
      );
      final endpoints = [
        'https://example.com/api',
        'https://example.com/another-api',
        'https://another.example.com/api',
        'https://example.com:8443/api',
        'http://example.com/api',
      ];
      expect(
        endpoints.map(sessionStoreKey).toSet(),
        hasLength(endpoints.length),
      );
      for (final invalid in [
        'file:///api',
        'https://user:secret@example.com/api',
        'https://example.com/api?tenant=1',
        'https://example.com/api#fragment',
      ]) {
        expect(() => sessionStoreKey(invalid), throwsArgumentError);
      }
    },
  );

  test('native save, restore and clear isolate API installations', () async {
    final storage = _SecureStorage();
    final first = NativeSessionStore(
      apiBaseUrl: 'https://example.com/first',
      storage: storage,
    );
    final second = NativeSessionStore(
      apiBaseUrl: 'https://example.com/second',
      storage: storage,
    );
    expect(await first.isSignedOut(), isTrue);
    expect(await first.readToken(), isNull);
    await first.saveToken('first-token');
    await second.saveToken('second-token');
    expect(await first.isSignedOut(), isFalse);
    expect(await first.readToken(), 'first-token');
    expect(await second.readToken(), 'second-token');
    expect(storage.values.values.toSet(), {'first-token', 'second-token'});
    await first.clear();
    expect(await first.isSignedOut(), isTrue);
    expect(await second.readToken(), 'second-token');
  });

  test(
    'native failures remain unavailable and retain prior credentials',
    () async {
      final storage = _SecureStorage();
      final store = NativeSessionStore(
        apiBaseUrl: 'https://example.com',
        storage: storage,
      );
      await store.saveToken('existing-token');
      storage.failure = StateError('platform storage denied');
      await expectLater(store.readToken(), throwsA(unavailable));
      await expectLater(store.isSignedOut(), throwsA(unavailable));
      await expectLater(store.saveToken('replacement'), throwsA(unavailable));
      await expectLater(store.clear(), throwsA(unavailable));
      expect(storage.values.values.single, 'existing-token');
      storage.failure = null;
      expect(await store.readToken(), 'existing-token');
      await store.clear();
      expect(await store.readToken(), isNull);
    },
  );

  test('native readback catches ignored writes and deletions', () async {
    final storage = _SecureStorage()..ignoreWrites = true;
    final store = NativeSessionStore(
      apiBaseUrl: 'https://example.com',
      storage: storage,
    );
    await expectLater(store.saveToken('token'), throwsA(unavailable));
    await expectLater(store.saveToken(''), throwsA(unavailable));
    storage.ignoreWrites = false;
    await store.saveToken('token');
    storage.ignoreDeletes = true;
    await expectLater(store.clear(), throwsA(unavailable));
    expect(await store.readToken(), 'token');
  });

  test('timed out native writes cannot overtake a subsequent clear', () async {
    final pendingWrite = Completer<void>();
    final storage = _SecureStorage()..pendingWrite = pendingWrite;
    final store = NativeSessionStore(
      apiBaseUrl: 'https://example.com',
      storage: storage,
      operationTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(store.saveToken('late-token'), throwsA(unavailable));
    final clearing = store.clear();
    pendingWrite.complete();
    await clearing;
    expect(await store.readToken(), isNull);
    expect(storage.values, isEmpty);
  });

  test('browser stores only an endpoint-scoped sign-out marker', () async {
    final storage = _MarkerStorage();
    final first = BrowserSessionStore(
      apiBaseUrl: 'https://example.com/first',
      storage: storage,
    );
    final second = BrowserSessionStore(
      apiBaseUrl: 'https://example.com/second',
      storage: storage,
    );
    expect(await first.isSignedOut(), isFalse);
    expect(await first.readToken(), isNull);
    await first.clear();
    expect(await first.isSignedOut(), isTrue);
    expect(await second.isSignedOut(), isFalse);
    expect(storage.values.values.single, '1');
    await first.saveToken('never-write-this-bearer');
    expect(await first.isSignedOut(), isFalse);
    expect(await first.readToken(), isNull);
    expect(storage.values, isEmpty);
    expect(storage.writes, ['1']);
  });

  test(
    'browser denial and silent writes cannot bypass sign-out fencing',
    () async {
      final storage = _MarkerStorage()..failure = StateError('storage denied');
      final store = BrowserSessionStore(
        apiBaseUrl: 'https://example.com',
        storage: storage,
      );
      await expectLater(store.isSignedOut(), throwsA(unavailable));
      await expectLater(store.clear(), throwsA(unavailable));
      await expectLater(store.saveToken('ignored'), throwsA(unavailable));
      storage.failure = null;
      storage.ignoreWrites = true;
      await expectLater(store.clear(), throwsA(unavailable));
      storage.ignoreWrites = false;
      await store.clear();
      storage.ignoreDeletes = true;
      await expectLater(store.saveToken('ignored'), throwsA(unavailable));
      expect(await store.isSignedOut(), isTrue);
    },
  );
}

final class _SecureStorage implements SecureTokenStorage {
  final values = <String, String>{};
  Object? failure;
  Completer<void>? pendingWrite;
  bool ignoreWrites = false;
  bool ignoreDeletes = false;

  @override
  Future<String?> read(String key) async {
    if (failure != null) throw failure!;
    return values[key];
  }

  @override
  Future<void> write(String key, String token) async {
    if (failure != null) throw failure!;
    await pendingWrite?.future;
    if (!ignoreWrites) values[key] = token;
  }

  @override
  Future<void> delete(String key) async {
    if (failure != null) throw failure!;
    if (!ignoreDeletes) values.remove(key);
  }
}

final class _MarkerStorage implements SessionMarkerStorage {
  final values = <String, String>{};
  final writes = <String>[];
  Object? failure;
  bool ignoreWrites = false;
  bool ignoreDeletes = false;

  @override
  String? read(String key) {
    if (failure != null) throw failure!;
    return values[key];
  }

  @override
  void write(String key, String value) {
    if (failure != null) throw failure!;
    writes.add(value);
    if (!ignoreWrites) values[key] = value;
  }

  @override
  void delete(String key) {
    if (failure != null) throw failure!;
    if (!ignoreDeletes) values.remove(key);
  }
}
