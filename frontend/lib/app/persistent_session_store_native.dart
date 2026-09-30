import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/identity/repos/session_store_native.dart';
import '../data/identity/datasources/session_store_secure_source.dart';
import '../domain/identity/interfaces/session_store.dart';

SessionStore createSessionStore(String apiBaseUrl) => NativeSessionStore(
  apiBaseUrl: apiBaseUrl,
  storage: SecureSessionDataSource(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(
        storageNamespace: 'domabas_sessions_v1',
        resetOnError: false,
        migrateOnAlgorithmChange: false,
      ),
      iOptions: IOSOptions(
        accountName: 'domabas.sessions.v1',
        accessibility: KeychainAccessibility.unlocked_this_device,
        synchronizable: false,
      ),
      mOptions: MacOsOptions(
        accountName: 'domabas.sessions.v1',
        accessibility: KeychainAccessibility.unlocked_this_device,
        synchronizable: false,
        usesDataProtectionKeychain: false,
      ),
    ),
  ),
);
