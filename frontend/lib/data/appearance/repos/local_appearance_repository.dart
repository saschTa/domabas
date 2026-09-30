import '../../../domain/appearance/interfaces/appearance_repository.dart';
import '../../../domain/appearance/models/appearance_preference.dart';
import 'appearance_data_source.dart';

final class LocalAppearanceRepository implements AppearanceRepository {
  LocalAppearanceRepository(this._source);

  final AppearanceDataSource _source;

  @override
  Future<AppearancePreference> read() async {
    try {
      return switch (await _source.read()) {
        'light' => AppearancePreference.light,
        'dark' => AppearancePreference.dark,
        _ => AppearancePreference.system,
      };
    } catch (_) {
      throw const AppearanceStorageFailure();
    }
  }

  @override
  Future<void> write(AppearancePreference preference) async {
    try {
      await _source.write(preference.name);
    } catch (_) {
      throw const AppearanceStorageFailure();
    }
  }
}
