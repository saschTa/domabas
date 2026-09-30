import 'package:domabas/domain/appearance/interfaces/appearance_repository.dart';
import 'package:domabas/domain/appearance/models/appearance_preference.dart';

final class FakeAppearanceRepository implements AppearanceRepository {
  AppearancePreference stored = AppearancePreference.system;
  Future<AppearancePreference> Function()? onRead;
  Future<void> Function(AppearancePreference)? onWrite;
  int reads = 0;
  int activeWrites = 0;
  int maximumActiveWrites = 0;
  final writes = <AppearancePreference>[];

  @override
  Future<AppearancePreference> read() async {
    reads++;
    return onRead == null ? stored : await onRead!();
  }

  @override
  Future<void> write(AppearancePreference preference) async {
    writes.add(preference);
    activeWrites++;
    if (activeWrites > maximumActiveWrites) {
      maximumActiveWrites = activeWrites;
    }
    try {
      if (onWrite != null) await onWrite!(preference);
      stored = preference;
    } finally {
      activeWrites--;
    }
  }
}
