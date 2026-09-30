import 'package:shared_preferences/shared_preferences.dart';

import '../repos/server_sources.dart';

final class PreferencesServerDataSource implements ServerPreferencesSource {
  PreferencesServerDataSource({
    SharedPreferencesAsync Function()? preferencesFactory,
  }) : _factory = preferencesFactory ?? SharedPreferencesAsync.new;

  static const storageKey = 'domabas.server.v1';

  final SharedPreferencesAsync Function() _factory;
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _client => _preferences ??= _factory();

  @override
  Future<String?> read() => _client.getString(storageKey);

  @override
  Future<void> write(String value) => _client.setString(storageKey, value);
}
