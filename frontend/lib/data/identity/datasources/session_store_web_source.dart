import 'package:web/web.dart' as web;

import '../repos/session_store_sources.dart';

final class WebSessionMarkerDataSource implements SessionMarkerStorage {
  @override
  String? read(String key) => web.window.localStorage.getItem(key);

  @override
  void write(String key, String value) =>
      web.window.localStorage.setItem(key, value);

  @override
  void delete(String key) => web.window.localStorage.removeItem(key);
}
