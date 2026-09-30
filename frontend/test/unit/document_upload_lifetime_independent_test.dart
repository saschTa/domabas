import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/app/desktop_upload_bridge.dart';
import 'package:domabas/app/document_upload_coordinator.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition.dart';
import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Acquisition extends DocumentUploadAcquisition {
  late Future<DocumentUploadSelection> Function(bool Function(int)) opening;
  int opened = 0;
  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) {
    opened++;
    return opening(reserve);
  }

  DocumentUploadSelection batch(int count, bool Function(int) reserve) =>
      capture(
        count,
        reserve: reserve,
        handleAt: (_) =>
            const RejectedDocumentUploadHandle('file.pdf', 'fixture'),
      );

  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => batch(paths.length, reserve);
}

final class _Bridge implements DesktopUploadBridge {
  @override
  bool get portalBusy => false;
  @override
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener) {}
  @override
  Future<void> dispose() async {}
}

final class _Repository implements DocumentUploadRepository {
  final pending = Completer<DocumentUploadResult>();
  final released = <String>[];
  int calls = 0;
  void Function(Document)? accept;
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) {
    calls++;
    accept = onAccepted;
    onSending();
    return pending.future;
  }

  @override
  void release(Iterable<String> ids) => released.addAll(ids);
  @override
  void dispose() {}
}

final class _Fixture {
  _Fixture() {
    coordinator = DocumentUploadCoordinator(
      acquisition: acquisition,
      desktopBridge: _Bridge(),
    );
    cubit = scope(repository);
    coordinator.attach(cubit, busy: false);
  }
  final acquisition = _Acquisition();
  final repository = _Repository();
  late final DocumentUploadCoordinator coordinator;
  late final DocumentUploadsCubit cubit;
  DocumentUploadsCubit scope(_Repository source) => DocumentUploadsCubit(
    repository: source,
    scheduler: coordinator,
    libraryName: 'Independent library',
    canRead: true,
    allowed: true,
  );
  Future<void> close() async {
    if (!repository.pending.isCompleted) {
      repository.pending.complete(
        const DocumentUploadResult(
          outcome: DocumentUploadOutcome.rejected,
          message: 'Fixture drained',
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    coordinator.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final synchronous in [true, false]) {
    test(
      '${synchronous ? 'synchronous' : 'asynchronous'} chooser failure rolls back reserved capacity and permits another selection',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.close);
        fixture.acquisition.opening = (reserve) {
          expect(reserve(20), isTrue);
          if (synchronous) throw StateError('Platform chooser failed');
          return Future.error(StateError('Platform chooser failed'));
        };
        fixture.coordinator.choose(fixture.cubit);
        expect(fixture.acquisition.opened, 1);
        await Future<void>.delayed(Duration.zero);
        expect(fixture.cubit.freePlaces, 20);
        expect(fixture.coordinator.canAcquire, isTrue);
        expect(fixture.cubit.state.feedback, 'No files could be received.');
        fixture.acquisition.opening = (_) async =>
            DocumentUploadSelection(cancelled: true);
        fixture.coordinator.choose(fixture.cubit);
        await Future<void>.delayed(Duration.zero);
        expect(fixture.acquisition.opened, 2);
        expect(fixture.repository.calls, 0);
        expect(fixture.cubit.state.rows, isEmpty);
      },
    );
  }

  test('opening is synchronous; hidden chooser completion waits and cannot admit a second chooser', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final completion = Completer<DocumentUploadSelection>();
    late bool Function(int) reserve;
    fixture.acquisition.opening = (admit) {
      reserve = admit;
      return completion.future;
    };
    fixture.coordinator.choose(fixture.cubit);
    expect(fixture.acquisition.opened, 1);
    fixture.coordinator.lifecycleChanged(AppLifecycleState.hidden);
    fixture.coordinator.choose(fixture.cubit);
    expect(fixture.acquisition.opened, 1);
    completion.complete(fixture.acquisition.batch(1, reserve));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.cubit.state.pending, 1);
    expect(fixture.repository.calls, 0);
    fixture.coordinator.lifecycleChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.repository.calls, 1);
  });

  test('late chooser cannot target replacement scope and keeps global lease until it settles', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final completion = Completer<DocumentUploadSelection>();
    late bool Function(int) reserve;
    fixture.acquisition.opening = (admit) {
      reserve = admit;
      return completion.future;
    };
    fixture.coordinator.choose(fixture.cubit);
    final selected = fixture.acquisition.batch(1, reserve);
    fixture.cubit.retire();
    final nextRepository = _Repository();
    final next = fixture.scope(nextRepository);
    fixture.coordinator.attach(next, busy: false);
    expect(fixture.coordinator.canAcquire, isFalse);
    fixture.coordinator.choose(next);
    expect(fixture.acquisition.opened, 1);
    completion.complete(selected);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.coordinator.canAcquire, isTrue);
    expect(next.state.rows, isEmpty);
    expect(nextRepository.calls, 0);
    await expectLater(
      fixture.acquisition.read(
        selected.candidates.single.id,
        Completer<void>().future,
      ),
      throwsA(
        isA<DocumentUploadReadException>().having(
          (error) => error.message,
          'reason',
          'This file selection has ended.',
        ),
      ),
    );
    await next.close();
  });

  test('failed switch invalidates late chooser result without restarting its queue', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final completion = Completer<DocumentUploadSelection>();
    late bool Function(int) reserve;
    fixture.acquisition.opening = (admit) {
      reserve = admit;
      return completion.future;
    };
    fixture.coordinator.choose(fixture.cubit);
    fixture.coordinator.attach(fixture.cubit, busy: true);
    fixture.coordinator.attach(fixture.cubit, busy: false);
    expect(reserve(1), isFalse);
    completion.complete(DocumentUploadSelection(cancelled: true));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.coordinator.canAcquire, isTrue);
    expect(fixture.repository.calls, 0);
    expect(fixture.cubit.freePlaces, 20);
  });

  test('retired physical handle rejects 20 atomically without reservation leak, then admits 19', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final drain = Completer<Uint8List>();
    final old = fixture.acquisition.capture(
      1,
      reserve: (_) => true,
      handleAt: (_) => _DrainingHandle(drain),
    );
    final reading = fixture.acquisition.read(
      old.candidates.single.id,
      Completer<void>().future,
    );
    var reserves = 0;
    final rejected = fixture.acquisition.batch(20, (count) {
      reserves++;
      return fixture.cubit.reserveBatch(count);
    });
    expect(rejected.candidates, isEmpty);
    expect(rejected.rejection, isNotNull);
    expect(reserves, 0);
    expect(fixture.cubit.freePlaces, 20);
    final smaller = fixture.acquisition.batch(19, fixture.cubit.reserveBatch);
    expect(smaller.candidates, hasLength(19));
    expect(fixture.cubit.freePlaces, 1);
    drain.complete(Uint8List(1));
    await reading;
    fixture.acquisition.release(
      [
        ...old.candidates,
        ...smaller.candidates,
      ].map((candidate) => candidate.id),
    );
    fixture.cubit.releaseReservation(19);
    expect(fixture.cubit.freePlaces, 20);
  });

  test(
    'terminal feedback retains eight visible seconds across hidden time',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);
      fixture.cubit.reject('Nothing was uploaded.');
      await Future<void>.delayed(const Duration(seconds: 4));
      fixture.coordinator.lifecycleChanged(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(fixture.cubit.state.showFeedback, isTrue);
      fixture.coordinator.lifecycleChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(fixture.cubit.state.showFeedback, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(fixture.cubit.state.showFeedback, isFalse);
    },
  );
}

final class _DrainingHandle implements DocumentUploadHandle {
  _DrainingHandle(this.completion);
  final Completer<Uint8List> completion;
  @override
  String get displayName => 'old.pdf';
  @override
  Future<Uint8List> read(
    Future<void> cancel, {
    void Function(String)? onReadFailure,
  }) => completion.future;
}
