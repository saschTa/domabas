import '../data/identity/repos/session_store_browser.dart';
import '../data/identity/datasources/session_store_web_source.dart';
import '../domain/identity/interfaces/session_store.dart';

SessionStore createSessionStore(String apiBaseUrl) => BrowserSessionStore(
  apiBaseUrl: apiBaseUrl,
  storage: WebSessionMarkerDataSource(),
);
