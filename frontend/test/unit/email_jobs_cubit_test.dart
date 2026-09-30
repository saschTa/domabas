import 'dart:async';

import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/presentation/email/cubits/email_jobs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_email_repository.dart';

final class JobsRepository extends FakeEmailRepository {
  Completer<EmailRunPage>? pending;
  bool aborted = false;
  int reads = 0;
  final requests = <(String?, String?)>[];
  @override
  Future<EmailRunPage> listRuns(
    String? providerId, {
    bool activeOnly = false,
    int limit = 20,
    String? cursor,
    String? status,
    Future<void>? cancel,
  }) async {
    reads++;
    requests.add((cursor, status));
    expect(providerId, isNull);
    unawaited(cancel?.then((_) => aborted = true));
    return pending?.future ??
        super.listRuns(
          providerId,
          limit: limit,
          cursor: cursor,
          status: status,
          cancel: cancel,
        );
  }
}

EmailRun emailJob(String status) => EmailRun(
  id: 'run',
  providerId: 'provider',
  namespaceId: 'library',
  reason: 'scheduled',
  status: status,
  stage: status == 'running' ? 'discovering' : 'complete',
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'status changes cancel pending history and start a fresh filtered page',
    () async {
      final repository = JobsRepository()..runs['run'] = emailJob('failed');
      final cubit = EmailJobsCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      final pending = repository.pending = Completer<EmailRunPage>();
      final oldRead = cubit.load();
      repository.pending = null;
      cubit.filter('failed');
      await Future<void>.delayed(Duration.zero);
      expect(repository.aborted, isTrue);
      expect(repository.requests.last, (null, 'failed'));
      expect(cubit.state.runs.single.status, 'failed');
      pending.complete(
        EmailRunPage(items: [emailJob('queued')], nextCursor: 'stale'),
      );
      await oldRead;
      expect(cubit.state.runs.single.status, 'failed');
      expect(cubit.state.cursor, isNull);
      expect(cubit.state.browsingHistory, isFalse);
      cubit.filter('succeeded');
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests.last, (null, 'succeeded'));
      expect(cubit.state.runs, isEmpty);
    },
  );

  test(
    'hidden and closed jobs ignore late reads, and permissions prevent reads',
    () async {
      final repository = JobsRepository()..pending = Completer<EmailRunPage>();
      final denied = EmailJobsCubit(repository, allowed: false)
        ..setActive(true);
      await denied.load();
      expect(repository.reads, 0);
      await denied.close();
      final cubit = EmailJobsCubit(repository, allowed: true)..setActive(true);
      await Future<void>.delayed(Duration.zero);
      cubit.setActive(false);
      repository.pending!.complete(EmailRunPage(items: [emailJob('running')]));
      await Future<void>.delayed(Duration.zero);
      expect(repository.aborted, isTrue);
      expect(cubit.state.runs, isEmpty);
      await cubit.close();
    },
  );

  test(
    'selected email details refresh even after leaving the newest history page',
    () async {
      final repository = JobsRepository()..runs['run'] = emailJob('running');
      final cubit = EmailJobsCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.selectJob(emailJob('running'));
      await Future<void>.delayed(Duration.zero);
      repository.runs['run'] = emailJob('succeeded');
      repository.pending = Completer<EmailRunPage>()
        ..complete(EmailRunPage(items: []));
      await cubit.load(poll: true);
      expect(cubit.state.runs, isEmpty);
      expect(cubit.state.selected?.status, 'succeeded');
      cubit.clearSelection();
      expect(cubit.state.selected, isNull);
    },
  );
}
