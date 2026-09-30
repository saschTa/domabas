import '../models/paperless.dart';

abstract interface class PaperlessRepository {
  Future<PaperlessOptions> options({Future<void>? cancel});
  Future<PaperlessRunPage> runs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  });
  Future<PaperlessOutcomePage> outcomes(
    String id, {
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  });
  Future<PaperlessRun> get(String id, {Future<void>? cancel});
  Future<PaperlessRun> start(
    String requestId,
    PaperlessConnection connection, {
    Future<void>? cancel,
  });
  Future<PaperlessRun> cancelRun(String id, {Future<void>? cancel});
  void cancelRequests();
}
