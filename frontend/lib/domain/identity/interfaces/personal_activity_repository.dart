import '../models/personal_activity.dart';

abstract interface class PersonalActivityRepository {
  void cancelRequests();
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  });
}
