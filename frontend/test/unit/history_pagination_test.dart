import 'dart:async';

import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/domain/identity/models/personal_activity.dart';
import 'package:domabas/domain/paperless/models/paperless.dart';
import 'package:domabas/presentation/email/cubits/email_providers_cubit.dart';
import 'package:domabas/presentation/identity/cubits/personal_activity_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_import_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_jobs_cubit.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_outcomes_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/mock_paperless_repository.dart';

final class PagedProviders extends FakeEmailRepository {
  @override
  Future<EmailProviderPage> listProviders({
    int limit = 20,
    String? cursor,
    Future<void>? cancel,
  }) async {
    final offset = int.parse(cursor ?? '0');
    return EmailProviderPage(
      items: providers.values.skip(offset).take(limit),
      nextCursor: offset + limit < providers.length
          ? (offset + limit).toString()
          : null,
    );
  }
}

final class PagedActivity extends FakeActivityRepository {
  final requests = <(String?, String?)>[];
  bool fail = false;
  @override
  Future<PersonalActivity> getActivity({
    String? activeCursor,
    String? finishedCursor,
    Future<void>? cancel,
  }) async {
    requests.add((activeCursor, finishedCursor));
    if (fail) throw const ActivityFailure(ActivityFailureKind.unavailable);
    return PersonalActivity(
      active: const [],
      finished: const [],
      activeTruncated: activeCursor == null,
      generatedAt: DateTime.utc(2026),
      activeNextCursor: activeCursor == null ? 'active-2' : null,
      finishedNextCursor: finishedCursor == null ? 'finished-2' : null,
    );
  }
}

void main() {
  test('outcome filters reset history and fence pending responses', () async {
    final repository = MockPaperlessRepository()
      ..jobs = [
        paperlessRun(
          id: 'run',
          outcomes: List.generate(
            70,
            (i) => PaperlessOutcome(
              sourceId: 70 - i,
              title: 'Result',
              status: i < 25 ? 'imported' : 'failed',
            ),
          ),
        ),
      ];
    final cubit = PaperlessOutcomesCubit(repository, 'run');
    addTearDown(cubit.close);
    await cubit.load();
    expect(
      cubit.state.items.every((item) => item.status == 'imported'),
      isTrue,
    );
    final pending = Completer<PaperlessOutcomePage>();
    repository.pendingOutcomes = pending.future;
    final olderPage = cubit.load(more: true);
    final cancelled = repository.outcomeCancel;
    repository.pendingOutcomes = null;
    await cubit.setStatus('failed');
    await expectLater(cancelled, completes);
    pending.complete(PaperlessOutcomePage([]));
    await olderPage;
    expect(cubit.state.status, 'failed');
    expect(repository.outcomeRequests.last, (null, 'failed'));
    expect(cubit.state.items.length, 20);
    expect(cubit.state.items.first.sourceId, 45);
    repository.pendingOutcomes = Future.error(
      const PaperlessFailure('unavailable'),
    );
    await cubit.load(more: true);
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.status, 'failed');
    expect(cubit.state.cursor, '20');
    repository.pendingOutcomes = null;
    await cubit.load(more: true);
    expect(repository.outcomeRequests.last, ('20', 'failed'));
    expect(cubit.state.items.length, 40);
    await cubit.load(automatic: true);
    expect(cubit.state.items.length, 40);
    await cubit.load();
    expect(repository.outcomeRequests.last, (null, 'failed'));
    await cubit.setStatus('duplicate');
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.cursor, isNull);
    await cubit.setStatus(null);
    expect(cubit.state.items.first.sourceId, 70);
  });

  test('outcome navigation supersedes a silent background refresh', () async {
    final repository = MockPaperlessRepository()
      ..jobs = [
        paperlessRun(
          id: 'run',
          outcomes: List.generate(
            25,
            (i) => PaperlessOutcome(
              sourceId: 25 - i,
              title: 'Result',
              status: 'failed',
            ),
          ),
        ),
      ];
    final cubit = PaperlessOutcomesCubit(repository, 'run');
    addTearDown(cubit.close);
    await cubit.load();
    final pending = Completer<PaperlessOutcomePage>();
    repository.pendingOutcomes = pending.future;
    final background = cubit.load(automatic: true);
    expect(cubit.state.loading, isFalse);
    final cancelled = repository.outcomeCancel;
    repository.pendingOutcomes = null;
    await cubit.load(more: true);
    await expectLater(cancelled, completes);
    pending.complete(PaperlessOutcomePage([]));
    await background;
    expect(cubit.state.items.length, 25);
    expect(cubit.state.cursor, isNull);
  });
  test(
    'Paperless jobs retain every page and retry a failed continuation',
    () async {
      final repository = MockPaperlessRepository()
        ..jobs = List.generate(
          45,
          (i) => paperlessRun(id: 'run-$i', state: 'succeeded'),
        );
      final cubit = PaperlessJobsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.runs.length, 20);
      await cubit.load(more: true);
      expect(cubit.state.runs.length, 40);
      final before = cubit.state.runs.map((r) => r.id).toList();
      repository.jobs.insert(0, paperlessRun(id: 'new', state: 'succeeded'));
      await cubit.load(poll: true);
      expect(cubit.state.runs.map((r) => r.id), before);
      expect(cubit.state.cursor, '40');
      repository.pendingList = Future.error(
        const PaperlessFailure('unavailable'),
      );
      await cubit.load(more: true);
      expect(cubit.state.runs.map((r) => r.id), before);
      expect(cubit.state.cursor, '40');
      expect(cubit.state.error, isNotNull);
      repository.pendingList = null;
      await cubit.load(more: true);
      expect(cubit.state.runs.length, 45);
      expect(cubit.state.cursor, isNull);
      expect(cubit.state.runs.map((r) => r.id).toSet().length, 45);
      final reads = repository.lists;
      await cubit.load(more: true);
      expect(repository.lists, reads);
    },
  );

  test('Paperless settings retain older imports during polling', () async {
    final repository = MockPaperlessRepository()
      ..jobs = List.generate(
        25,
        (i) => paperlessRun(id: 'run-$i', state: 'succeeded'),
      );
    final cubit = PaperlessImportCubit(repository);
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.load(more: true);
    expect(cubit.state.runs.length, 25);
    repository.jobs.insert(0, paperlessRun(id: 'new', state: 'succeeded'));
    await cubit.load(poll: true);
    expect(cubit.state.runs.length, 25);
    expect(cubit.state.runs.first.id, 'run-0');
    expect(cubit.state.cursor, isNull);
    await cubit.load();
    expect(cubit.state.runs.first.id, 'new');
    expect(cubit.state.runs.length, 20);
  });

  test('Paperless outcomes continue beyond 100 and automatic refresh preserves history', () async {
    final repository = MockPaperlessRepository()
      ..jobs = [
        paperlessRun(
          id: 'run',
          outcomes: List.generate(
            115,
            (i) => PaperlessOutcome(
              sourceId: 115 - i,
              title: 'Result',
              status: 'failed',
            ),
          ),
        ),
      ];
    final cubit = PaperlessOutcomesCubit(repository, 'run');
    addTearDown(cubit.close);
    await cubit.load();
    while (cubit.state.cursor != null) {
      await cubit.load(more: true);
    }
    expect(cubit.state.items.length, 115);
    expect(cubit.state.items.last.sourceId, 1);
    repository.jobs = [
      paperlessRun(
        id: 'run',
        outcomes: List.generate(
          115,
          (i) => PaperlessOutcome(
            sourceId: 115 - i,
            title: 'Updated result',
            status: 'imported',
          ),
        ),
      ),
    ];
    await cubit.load(automatic: true);
    expect(cubit.state.items.length, 115);
    expect(cubit.state.items.last.status, 'imported');
    expect(cubit.state.cursor, isNull);
    await cubit.load();
    expect(cubit.state.items.length, 20);
  });

  testWidgets(
    'outcome events received during a read refresh after it completes',
    (tester) async {
      final pending = Completer<PaperlessOutcomePage>();
      final repository = MockPaperlessRepository()
        ..pendingOutcomes = pending.future
        ..jobs = [
          paperlessRun(
            id: 'run',
            outcomes: [
              const PaperlessOutcome(
                sourceId: 1,
                title: 'Done',
                status: 'imported',
              ),
            ],
          ),
        ];
      final cubit = PaperlessOutcomesCubit(repository, 'run');
      addTearDown(cubit.close);
      final initial = cubit.load();
      cubit.invalidate();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.outcomeRequests.length, 1);
      repository.pendingOutcomes = null;
      pending.complete(PaperlessOutcomePage([]));
      await initial;
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.outcomeRequests.length, 2);
      expect(cubit.state.items.single.status, 'imported');
      await tester.pump(const Duration(minutes: 5));
      expect(repository.outcomeRequests.length, 2);
    },
  );

  test(
    'email provider polling and returning from details preserve loaded pages',
    () async {
      final repository = PagedProviders();
      for (var i = 0; i < 25; i++) {
        repository.providers['provider-$i'] = emailProvider(id: 'provider-$i');
      }
      final cubit = EmailProvidersCubit(
        repository,
        allowed: true,
        canImport: true,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.load(more: true);
      await cubit.load(poll: true);
      expect(cubit.state.providers.length, 25);
      expect(cubit.state.providerCursor, isNull);
      await cubit.select('provider-24');
      await cubit.back();
      expect(cubit.state.providers.length, 25);
      repository.providers.remove('provider-24');
      for (var i = 0; i < 3; i++) {
        await cubit.load(poll: true);
      }
      expect(cubit.state.providers.length, 24);
    },
  );

  test(
    'activity pages are independent and failed navigation is retryable',
    () async {
      final repository = PagedActivity();
      final cubit = PersonalActivityCubit(repository)..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      await cubit.refresh(moreActive: true);
      expect(cubit.state.activePage, 2);
      expect(cubit.state.finishedPage, 1);
      await cubit.refresh(moreFinished: true);
      expect(repository.requests.last, ('active-2', 'finished-2'));
      await cubit.refresh(automatic: true);
      expect(repository.requests.last, ('active-2', 'finished-2'));
      repository.fail = true;
      await cubit.refresh(previousActive: true);
      expect(cubit.state.activePage, 2);
      expect(cubit.state.finishedPage, 2);
      repository.fail = false;
      await cubit.refresh(previousActive: true);
      expect(repository.requests.last, (null, 'finished-2'));
      expect(cubit.state.activePage, 1);
      await cubit.refresh();
      expect(repository.requests.last, (null, null));
      expect(cubit.state.finishedPage, 1);
    },
  );
}
