import '../models/paperless_settings.dart';

abstract interface class PaperlessSettingsRepository {
  Future<PaperlessSettings> settings({Future<void>? cancel});
  Future<PaperlessSettings> updateSettings({
    required int retrievalConcurrency,
    required int expectedRevision,
    Future<void>? cancel,
  });
  void cancelRequests();
}
