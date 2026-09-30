import '../domain/identity/interfaces/session_store.dart';
import 'persistent_session_store_native.dart'
    if (dart.library.js_interop) 'persistent_session_store_web.dart'
    as platform;

SessionStore createPersistentSessionStore(String apiBaseUrl) =>
    platform.createSessionStore(apiBaseUrl);
