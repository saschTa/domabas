import 'package:domabas/domain/identity/interfaces/personal_activity_repository.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';

class FakeActivityRepository implements PersonalActivityRepository {
  bool cancelled = false;
  PersonalActivity activity = PersonalActivity(
    active: const [],
    finished: const [],
    activeTruncated: false,
    generatedAt: DateTime.utc(2026),
  );
  @override
  void cancelRequests() {
    cancelled = true;
  }

  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async => activity;
}
