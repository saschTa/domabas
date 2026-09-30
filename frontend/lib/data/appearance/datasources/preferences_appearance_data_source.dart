import 'package:shared_preferences/shared_preferences.dart';

import '../repos/appearance_data_source.dart';

final class PreferencesAppearanceDataSource implements AppearanceDataSource {
  PreferencesAppearanceDataSource({
    SharedPreferencesAsync Function()? preferencesFactory,
  }) : _preferencesFactory = preferencesFactory ?? SharedPreferencesAsync.new;

  static const storageKey = 'domabas.appearance.v1';

  final SharedPreferencesAsync Function() _preferencesFactory;
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _client => _preferences ??= _preferencesFactory();

  @override
  Future<String?> read() async {
    final client = _client;
    try {
      return await client.getString(storageKey);
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> write(String value) async =>
      _client.setString(storageKey, value);
}
