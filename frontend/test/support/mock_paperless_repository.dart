import 'package:domabas/domain/paperless/interfaces/paperless_repository.dart';
import 'package:domabas/domain/paperless/models/paperless.dart';

final class MockPaperlessRepository implements PaperlessRepository {
  PaperlessOptions configuration = const PaperlessOptions(pageSize: 100);
  List<PaperlessRun> jobs = [];
  Map<String, int>? counts;
  final details = <String, PaperlessRun>{};
  final requestIds = <String>[];
  final tokens = <String>[];
  final servers = <String>[];
  final cancellations = <String>[];
  PaperlessFailure? startFailure;
  Future<List<PaperlessRun>>? pendingList;
  Future<void>? observedCancel, outcomeCancel;
  Future<PaperlessOutcomePage>? pendingOutcomes;
  int lists = 0;
  final listRequests = <(String?, String?)>[];
  final outcomeRequests = <(String?, String?)>[];
  bool cancelled = false;
  @override
  Future<PaperlessOptions> options({Future<void>? cancel}) async =>
      configuration;
  @override
  Future<PaperlessRunPage> runs({
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async {
    lists++;
    listRequests.add((cursor, status));
    observedCancel = cancel;
    final items = (await (pendingList ?? Future.value(jobs)))
        .where(
          (run) =>
              (!activeOnly || run.active) &&
              (status == null || run.status == status),
        )
        .toList();
    final offset = int.parse(cursor ?? '0');
    return PaperlessRunPage(
      items.skip(offset).take(limit),
      counts: counts,
      nextCursor: offset + limit < items.length
          ? (offset + limit).toString()
          : null,
    );
  }

  @override
  Future<PaperlessOutcomePage> outcomes(
    String id, {
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async {
    outcomeCancel = cancel;
    outcomeRequests.add((cursor, status));
    if (pendingOutcomes case final pending?) return pending;
    final items = (details[id] ?? jobs.firstWhere((r) => r.id == id)).outcomes
        .where((outcome) => status == null || outcome.status == status)
        .toList();
    final offset = int.parse(cursor ?? '0');
    return PaperlessOutcomePage(
      items.skip(offset).take(limit),
      nextCursor: offset + limit < items.length
          ? (offset + limit).toString()
          : null,
    );
  }

  @override
  Future<PaperlessRun> get(String id, {Future<void>? cancel}) async =>
      details[id] ?? jobs.firstWhere((r) => r.id == id);
  @override
  Future<PaperlessRun> start(
    String requestId,
    PaperlessConnection connection, {
    Future<void>? cancel,
  }) async {
    requestIds.add(requestId);
    tokens.add(connection.token);
    servers.add(connection.serverUrl);
    if (startFailure case final failure?) throw failure;
    final run = paperlessRun(id: requestId, serverUrl: connection.serverUrl);
    jobs = [run, ...jobs];
    return run;
  }

  @override
  Future<PaperlessRun> cancelRun(String id, {Future<void>? cancel}) async {
    cancellations.add(id);
    final run = paperlessRun(id: id, cancelRequested: true);
    jobs = [run];
    return run;
  }

  @override
  void cancelRequests() {
    cancelled = true;
  }
}

PaperlessRun paperlessRun({
  String id = '11111111-1111-4111-8111-111111111111',
  String state = 'queued',
  String serverUrl = 'https://paperless.example.test',
  bool cancelRequested = false,
  String? stage,
  int discovered = 0,
  int imported = 0,
  int duplicates = 0,
  int failed = 0,
  DateTime? createdAt,
  Iterable<PaperlessOutcome> outcomes = const [],
}) => PaperlessRun(
  id: id,
  serverUrl: serverUrl,
  state: state,
  stage: stage ?? (state == 'queued' ? 'queued' : 'complete'),
  discovered: discovered,
  imported: imported,
  duplicates: duplicates,
  failed: failed,
  cancelRequested: cancelRequested,
  createdAt: createdAt ?? DateTime.utc(2026, 9, 19),
  updatedAt: DateTime.utc(2026, 9, 19),
  outcomes: outcomes,
);
