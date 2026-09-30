import 'dart:async';

import 'package:bloc/bloc.dart';

import '../domain/document/interfaces/document_processing_repository.dart';
import '../domain/document/models/document_processing.dart';
import '../domain/email/interfaces/email_repository.dart';
import '../domain/email/models/email.dart';
import '../domain/paperless/interfaces/paperless_repository.dart';
import '../domain/paperless/models/paperless.dart';
import '../scheduling/automatic_refresh.dart';
import '../domain/realtime/models/realtime.dart';

enum JobActivityKind { document, ai, thumbnail, email, paperless, reindex }

final class JobActivityItem {
  const JobActivityItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.stage,
    required this.createdAt,
    this.batch,
  });
  final String id, title, status, stage;
  final JobActivityKind kind;
  final DateTime createdAt;
  final DocumentReindexBatch? batch;
  bool get active =>
      const {'queued', 'running', 'enumerating'}.contains(status);
  bool get running => status == 'running' || status == 'enumerating';
}

final class JobActivityState {
  JobActivityState({
    Iterable<JobActivityItem> items = const [],
    this.runningCount,
    this.queuedCount,
    this.batchCount,
    this.discovering = false,
    this.stale = false,
    this.loading = false,
    this.hasMore = false,
  }) : items = List.unmodifiable(items);
  final List<JobActivityItem> items;
  final int? runningCount, queuedCount, batchCount;
  final bool discovering, stale, loading, hasMore;
}

final class JobActivityCubit extends Cubit<JobActivityState> {
  JobActivityCubit({
    required DocumentProcessingRepository processing,
    required EmailRepository email,
    PaperlessRepository? paperless,
    required bool canReadJobs,
    required bool canReadBatches,
    required bool canReadSystemBatches,
    required bool canReadEmail,
    required bool canReadPaperless,
  }) : super(JobActivityState()) {
    if (canReadJobs) {
      _addFeed(RealtimeTopic.processing, (cursor, cancel) async {
        final page = await processing.listJobs(
          activeOnly: true,
          cursor: cursor,
          cancel: cancel,
        );
        final counts = page.counts;
        return _JobActivityPage(
          page.items.map(_document),
          page.nextCursor,
          counts == null
              ? null
              : {
                  for (final status in ['queued', 'running'])
                    status: counts.entries
                        .where((entry) => entry.key.$2 == status)
                        .fold<int>(0, (sum, entry) => sum + entry.value),
                },
        );
      });
    }
    for (final system in [false, true]) {
      if (system ? !canReadSystemBatches : !canReadBatches) continue;
      _addFeed(
        system
            ? RealtimeTopic.processingConfiguration
            : RealtimeTopic.processing,
        (cursor, cancel) async {
          final page = system
              ? await processing.listSystemBatches(
                  activeOnly: true,
                  cursor: cursor,
                  cancel: cancel,
                )
              : await processing.listNamespaceBatches(
                  activeOnly: true,
                  cursor: cursor,
                  cancel: cancel,
                );
          return _JobActivityPage(
            page.items.map(_batch),
            page.nextCursor,
            page.counts,
          );
        },
        batches: true,
      );
    }
    if (canReadEmail) {
      _addFeed(RealtimeTopic.email, (cursor, cancel) async {
        final page = await email.listRuns(
          null,
          activeOnly: true,
          cursor: cursor,
          cancel: cancel,
        );
        return _JobActivityPage(
          page.items.map(_email),
          page.nextCursor,
          page.counts,
        );
      });
    }
    if (canReadPaperless && paperless != null) {
      _addFeed(RealtimeTopic.paperless, (cursor, cancel) async {
        final page = await paperless.runs(
          activeOnly: true,
          cursor: cursor,
          cancel: cancel,
        );
        return _JobActivityPage(
          page.items.map(_paperless),
          page.nextCursor,
          page.counts,
        );
      });
    }
  }

  final List<_JobActivityFeed> _feeds = [];
  bool _active = false, _healthy = true;

  void _addFeed(
    RealtimeTopic topic,
    Future<_JobActivityPage> Function(String?, Future<void>) page, {
    bool batches = false,
  }) {
    _feeds.add(
      _JobActivityFeed(
        topic: topic,
        page: page,
        batches: batches,
        changed: _publish,
      ),
    );
  }

  void invalidate([Set<RealtimeTopic>? topics]) {
    for (final feed in _feeds) {
      if (topics == null || topics.contains(feed.topic)) feed.invalidate();
    }
  }

  void setRealtimeHealthy(bool value) {
    if (isClosed || value == _healthy) return;
    _healthy = value;
    _publish();
  }

  void setActive(bool value) {
    if (isClosed || value == _active) return;
    _active = value;
    for (final feed in _feeds) {
      feed.setActive(value);
    }
    _publish();
  }

  Future<void> refresh() => Future.wait(_feeds.map((feed) => feed.refresh()));
  Future<void> loadMore() => Future.wait(
    _feeds
        .where((feed) => feed.cursor != null)
        .map((feed) => feed.refresh(more: true)),
  );

  int? _total(bool batches, Set<String> statuses) {
    var total = 0;
    for (final feed in _feeds.where((feed) => feed.batches == batches)) {
      final counts = feed.counts;
      if (counts == null) return null;
      for (final status in statuses) {
        total += counts[status] ?? 0;
      }
    }
    return total;
  }

  void _publish() {
    if (isClosed) return;
    final items = _feeds.expand((feed) => feed.items).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    emit(
      JobActivityState(
        items: items,
        runningCount: _total(false, {'running'}),
        queuedCount: _total(false, {'queued'}),
        batchCount: _total(true, {'queued', 'running', 'enumerating'}),
        discovering: _feeds.any((feed) => feed.counts == null),
        stale: !_healthy || _feeds.any((feed) => feed.stale),
        loading: _feeds.any((feed) => feed.loading),
        hasMore: _feeds.any((feed) => feed.cursor != null),
      ),
    );
  }

  @override
  Future<void> close() {
    for (final feed in _feeds) {
      feed.dispose();
    }
    return super.close();
  }

  static JobActivityItem _document(DocumentProcessingJob job) =>
      JobActivityItem(
        id: job.id,
        kind: job.isAI
            ? JobActivityKind.ai
            : job.isThumbnail
            ? JobActivityKind.thumbnail
            : JobActivityKind.document,
        title: job.label,
        status: job.status,
        stage: job.stage,
        createdAt: job.createdAt,
      );
  static JobActivityItem _batch(DocumentReindexBatch batch) => JobActivityItem(
    id: batch.id,
    kind: JobActivityKind.reindex,
    title: batch.scope == 'system'
        ? 'Reindex · All libraries'
        : 'Reindex · Current library',
    status: batch.status,
    stage: batch.status,
    createdAt: batch.createdAt,
    batch: batch,
  );
  static JobActivityItem _email(EmailRun run) => JobActivityItem(
    id: run.id,
    kind: JobActivityKind.email,
    title: 'Email import',
    status: run.status,
    stage: run.stage,
    createdAt: run.createdAt,
  );
  static JobActivityItem _paperless(PaperlessRun run) => JobActivityItem(
    id: run.id,
    kind: JobActivityKind.paperless,
    title: 'Paperless import',
    status: run.state,
    stage: run.stage,
    createdAt: run.createdAt,
  );
}

final class _JobActivityPage {
  _JobActivityPage(Iterable<JobActivityItem> items, this.cursor, this.counts)
    : items = items.toList();
  final List<JobActivityItem> items;
  final String? cursor;
  final Map<String, int>? counts;
}

final class _JobActivityFeed {
  _JobActivityFeed({
    required this.topic,
    required this.page,
    required this.batches,
    required this.changed,
  });
  final RealtimeTopic topic;
  final bool batches;
  final void Function() changed;
  final Future<_JobActivityPage> Function(String?, Future<void>) page;
  List<JobActivityItem> items = [];
  Map<String, int>? counts;
  String? cursor;
  int _pages = 1, _epoch = 0;
  bool _active = false, loading = false, stale = false;
  Completer<void>? _cancel;
  late final _refresh = AutomaticRefresh(read: refresh, busy: () => loading);

  void invalidate() => _refresh.invalidate();

  void setActive(bool value) {
    _active = value;
    _epoch++;
    if (_cancel case final cancel? when !cancel.isCompleted) cancel.complete();
    loading = false;
    _refresh.setActive(value);
    if (value) unawaited(refresh());
  }

  Future<void> refresh({bool more = false}) async {
    if (!_active || loading || (more && cursor == null)) return;
    final epoch = _epoch;
    final cancel = _cancel = Completer<void>();
    bool current() => _active && epoch == _epoch;
    loading = true;
    changed();
    try {
      final updated = <String, JobActivityItem>{
        if (more)
          for (final item in items) item.id: item,
      };
      var next = more ? cursor : null;
      Map<String, int>? totals;
      var pages = 0;
      final seen = <String>{};
      do {
        final result = await page(next, cancel.future);
        if (!current()) return;
        totals ??= result.counts;
        for (final item in result.items) {
          if (item.active) updated[item.id] = item;
        }
        next = result.cursor;
        if (next != null && !seen.add(next)) {
          throw const FormatException('Repeated activity cursor');
        }
        pages++;
      } while (!more && next != null && pages < _pages);
      items = updated.values.toList();
      counts = totals;
      cursor = next;
      _pages = more ? _pages + 1 : pages;
      stale = false;
    } on DocumentProcessingFailure {
      if (current()) stale = true;
    } on EmailFailure {
      if (current()) stale = true;
    } on PaperlessFailure {
      if (current()) stale = true;
    } on FormatException {
      if (current()) stale = true;
    } finally {
      if (current()) {
        loading = false;
        changed();
      }
    }
  }

  void dispose() {
    setActive(false);
    _refresh.dispose();
  }
}
