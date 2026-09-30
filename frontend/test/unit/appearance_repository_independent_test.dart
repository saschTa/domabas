import 'package:domabas/data/appearance/datasources/preferences_appearance_data_source.dart';
import 'package:domabas/data/appearance/repos/local_appearance_repository.dart';
import 'package:domabas/domain/appearance/models/appearance_preference.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Preferences implements SharedPreferencesAsync {
  final values = <String, Object?>{'unrelated.setting': 'retain me'};
  final reads = <String>[];
  final writes = <({String key, String value})>[];
  final _failures = <String, Object?>{};
  Object? get readFailure => _failures['read'];
  set readFailure(Object? value) => _failures['read'] = value;
  Object? get writeFailure => _failures['write'];
  set writeFailure(Object? value) => _failures['write'] = value;

  @override
  Future<String?> getString(String key) async {
    reads.add(key);
    if (readFailure case final failure?) throw failure;
    return values[key] as String?;
  }

  @override
  Future<void> setString(String key, String value) async {
    if (writeFailure case final failure?) throw failure;
    writes.add((key: key, value: value));
    values[key] = value;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected preference operation ${invocation.memberName}',
  );
}

void main() {
  for (final (raw, expected) in <(Object?, AppearancePreference)>[
    (null, AppearancePreference.system),
    ('', AppearancePreference.system),
    ('unknown', AppearancePreference.system),
    ('DARK', AppearancePreference.system),
    (' dark ', AppearancePreference.system),
    (42, AppearancePreference.system),
    (true, AppearancePreference.system),
    ('system', AppearancePreference.system),
    ('light', AppearancePreference.light),
    ('dark', AppearancePreference.dark),
  ]) {
    test(
      'stored $raw resolves to $expected without migration writes',
      () async {
        final preferences = _Preferences()
          ..values['domabas.appearance.v1'] = raw;
        final repository = LocalAppearanceRepository(
          PreferencesAppearanceDataSource(
            preferencesFactory: () => preferences,
          ),
        );
        expect(await repository.read(), expected);
        expect(preferences.reads, ['domabas.appearance.v1']);
        expect(preferences.writes, isEmpty);
        expect(preferences.values['unrelated.setting'], 'retain me');
      },
    );
  }

  test(
    'lazy construction failure is recoverable and only success is cached',
    () async {
      var constructions = 0;
      final preferences = _Preferences()
        ..values['domabas.appearance.v1'] = 'dark';
      final source = PreferencesAppearanceDataSource(
        preferencesFactory: () {
          constructions++;
          if (constructions == 1) throw StateError('plugin unavailable');
          return preferences;
        },
      );
      final repository = LocalAppearanceRepository(source);
      expect(constructions, 0);
      await expectLater(
        repository.read(),
        throwsA(isA<AppearanceStorageFailure>()),
      );
      expect(await repository.read(), AppearancePreference.dark);
      await repository.write(AppearancePreference.light);
      expect(await repository.read(), AppearancePreference.light);
      expect(constructions, 2);
      expect(preferences.values['unrelated.setting'], 'retain me');
    },
  );

  test(
    'all choices write only their canonical value to the dedicated key',
    () async {
      final preferences = _Preferences();
      final repository = LocalAppearanceRepository(
        PreferencesAppearanceDataSource(preferencesFactory: () => preferences),
      );
      for (final preference in AppearancePreference.values) {
        await repository.write(preference);
      }
      expect(preferences.writes, [
        (key: 'domabas.appearance.v1', value: 'system'),
        (key: 'domabas.appearance.v1', value: 'light'),
        (key: 'domabas.appearance.v1', value: 'dark'),
      ]);
      expect(preferences.values['unrelated.setting'], 'retain me');
      expect(preferences.reads, isEmpty);
    },
  );

  test(
    'denied read is a failure rather than silently restoring System',
    () async {
      final preferences = _Preferences()
        ..readFailure = PlatformException(
          code: 'access_denied',
          message: 'private details',
        );
      final repository = LocalAppearanceRepository(
        PreferencesAppearanceDataSource(preferencesFactory: () => preferences),
      );
      await expectLater(
        repository.read(),
        throwsA(isA<AppearanceStorageFailure>()),
      );
      preferences.readFailure = null;
      preferences.values['domabas.appearance.v1'] = 'light';
      expect(await repository.read(), AppearancePreference.light);
    },
  );

  test(
    'failed write preserves old storage and a retry writes current intent',
    () async {
      final preferences = _Preferences()
        ..values['domabas.appearance.v1'] = 'dark'
        ..writeFailure = PlatformException(
          code: 'quota',
          message: 'private details',
        );
      final repository = LocalAppearanceRepository(
        PreferencesAppearanceDataSource(preferencesFactory: () => preferences),
      );
      await expectLater(
        repository.write(AppearancePreference.light),
        throwsA(isA<AppearanceStorageFailure>()),
      );
      expect(preferences.values['domabas.appearance.v1'], 'dark');
      preferences.writeFailure = null;
      await repository.write(AppearancePreference.system);
      expect(await repository.read(), AppearancePreference.system);
      expect(preferences.writes, [
        (key: 'domabas.appearance.v1', value: 'system'),
      ]);
    },
  );
}
