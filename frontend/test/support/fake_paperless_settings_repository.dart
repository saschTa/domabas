import 'package:domabas/domain/paperless/interfaces/paperless_settings_repository.dart';
import 'package:domabas/domain/paperless/models/paperless_settings.dart';

PaperlessSettings testPaperlessSettings({
  int concurrency = 1,
  int revision = 1,
}) => PaperlessSettings(
  retrievalConcurrency: concurrency,
  revision: revision,
  minimumRetrievalConcurrency: 1,
  maximumRetrievalConcurrency: 10,
);

final class FakePaperlessSettingsRepository
    implements PaperlessSettingsRepository {
  PaperlessSettings current = testPaperlessSettings();
  int reads = 0;
  final writes = <({int concurrency, int revision})>[];
  Future<PaperlessSettings> Function()? onRead;
  Future<PaperlessSettings> Function()? onWrite;
  Future<void>? lastCancel;

  @override
  void cancelRequests() {}

  @override
  Future<PaperlessSettings> settings({Future<void>? cancel}) async {
    reads++;
    lastCancel = cancel;
    return onRead == null ? current : onRead!();
  }

  @override
  Future<PaperlessSettings> updateSettings({
    required int retrievalConcurrency,
    required int expectedRevision,
    Future<void>? cancel,
  }) async {
    writes.add((concurrency: retrievalConcurrency, revision: expectedRevision));
    lastCancel = cancel;
    if (onWrite != null) return onWrite!();
    current = testPaperlessSettings(
      concurrency: retrievalConcurrency,
      revision: expectedRevision + 1,
    );
    return current;
  }
}
