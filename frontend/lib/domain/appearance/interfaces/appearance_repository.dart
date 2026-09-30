import '../models/appearance_preference.dart';

abstract interface class AppearanceRepository {
  Future<AppearancePreference> read();
  Future<void> write(AppearancePreference preference);
}
