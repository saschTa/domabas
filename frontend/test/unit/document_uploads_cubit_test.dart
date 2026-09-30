import 'dart:async';

import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/interfaces/document_upload_scheduler.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Scheduler implements DocumentUploadScheduler {
  final events = StreamController<void>.broadcast(sync: true);
  bool occupied = false;
  @override
  bool get contentBusy => occupied;
  @override
  Stream<void> get changes => events.stream;
  @override
  bool start(Future<void> Function() operation) {
    if (occupied) return false;
    occupied = true;
    unawaited(
      operation().whenComplete(() {
        occupied = false;
        events.add(null);
      }),
    );
    return true;
  }
}

final class _Repository implements DocumentUploadRepository {
  final result = Completer<DocumentUploadResult>();
  final started = Completer<void>();
  void Function(Document)? accepted;
  void Function(String)? readFailure;
  int calls = 0;
  bool sending = true;
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) {
    calls++;
    accepted = onAccepted;
    readFailure = onReadFailure;
    if (sending) onSending();
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}

Document _document() => Document(
  id: 'accepted',
  title: 'Upload',
  description: '',
  createdAt: DateTime.utc(2026),
);
const _candidate = DocumentUploadCandidate(id: 'one', displayName: 'one.pdf');

void main() {
  test(
    'whole-batch capacity rejects 19 plus 2 without admitting a prefix',
    () async {
      final repository = _Repository();
      final scheduler = _Scheduler()..occupied = true;
      final cubit = DocumentUploadsCubit(
        repository: repository,
        scheduler: scheduler,
        libraryName: 'Library',
        canRead: false,
        allowed: true,
      );
      expect(cubit.reserveBatch(19), isTrue);
      cubit.receiveBatch(
        List.generate(
          19,
          (i) => DocumentUploadCandidate(id: '$i', displayName: '$i.pdf'),
        ),
      );
      expect(cubit.reserveBatch(2), isFalse);
      expect(cubit.state.pending, 19);
      expect(cubit.state.feedback, contains('None of this batch'));
      expect(repository.calls, 0);
      await cubit.close();
      await scheduler.events.close();
    },
  );

  test('late acceptance after failed switch survives Clear finished and invalidates only when usable', () async {
    final repository = _Repository();
    final scheduler = _Scheduler();
    final cubit = DocumentUploadsCubit(
      repository: repository,
      scheduler: scheduler,
      libraryName: 'Library',
      canRead: true,
      allowed: true,
    );
    var invalidated = 0;
    cubit.onAccepted = () => invalidated++;
    expect(cubit.reserveBatch(1), isTrue);
    cubit.receiveBatch([_candidate]);
    await repository.started.future;
    cubit.setGate(busy: true, visible: true);
    expect(cubit.state.rows.single.phase, DocumentUploadPhase.uncertain);
    expect(cubit.state.feedback, contains('1 unknown'));
    cubit.clearFinished();
    expect(cubit.state.rows, hasLength(1));
    repository.accepted!(_document());
    expect(cubit.state.rows.single.phase, DocumentUploadPhase.accepted);
    expect(invalidated, 0);
    cubit.setGate(busy: false, visible: true);
    expect(invalidated, 1);
    expect(repository.calls, 1);
    repository.result.complete(
      const DocumentUploadResult(
        outcome: DocumentUploadOutcome.uncertain,
        message: 'late uncertainty',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.rows.single.phase, DocumentUploadPhase.accepted);
    expect(scheduler.contentBusy, isFalse);
    await cubit.close();
    await scheduler.events.close();
  });

  test('logical read timeout retains physical lease and replacement scope cannot overtake it', () async {
    final first = _Repository()..sending = false;
    final second = _Repository();
    final scheduler = _Scheduler();
    final old = DocumentUploadsCubit(
      repository: first,
      scheduler: scheduler,
      libraryName: 'Old',
      canRead: true,
      allowed: true,
    );
    old.reserveBatch(1);
    old.receiveBatch([_candidate]);
    await first.started.future;
    first.readFailure!('The file read timed out.');
    expect(old.state.rows.single.phase, DocumentUploadPhase.rejected);
    expect(scheduler.contentBusy, isTrue);
    old.retire();
    final next = DocumentUploadsCubit(
      repository: second,
      scheduler: scheduler,
      libraryName: 'Next',
      canRead: true,
      allowed: true,
    );
    next.reserveBatch(1);
    next.receiveBatch([
      const DocumentUploadCandidate(id: 'two', displayName: 'two.pdf'),
    ]);
    expect(second.calls, 0);
    first.result.complete(
      const DocumentUploadResult(
        outcome: DocumentUploadOutcome.rejected,
        message: 'drained',
      ),
    );
    await second.started.future;
    expect(second.calls, 1);
    first.accepted!(_document());
    expect(next.state.accepted, 0);
    second.result.complete(
      const DocumentUploadResult(
        outcome: DocumentUploadOutcome.rejected,
        message: 'done',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await old.close();
    await next.close();
    await scheduler.events.close();
  });
}
