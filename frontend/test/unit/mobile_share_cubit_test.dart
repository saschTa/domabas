import 'dart:async';

import 'package:domabas/app/document_upload_coordinator.dart';
import 'package:domabas/app/mobile_share_cubit.dart';
import 'package:domabas/app/mobile_share_host.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition_native.dart';
import 'package:domabas/data/document/datasources/mobile_share_data_source.dart';
import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ShareSource extends MobileShareDataSource {
  MobileShareBatch? batch;
  Completer<MobileShareBatch?>? delayed;
  final released = <String>[];
  final contexts = <Map<String, String>?>[];
  void Function()? changed;
  bool disposed = false;
  @override
  void listen(void Function() changed) => this.changed = changed;
  @override
  Future<MobileShareBatch?> pending() async =>
      delayed == null ? batch : delayed!.future;
  @override
  Future<void> release(String id) async {
    released.add(id);
    if (batch?.id == id) batch = null;
  }

  @override
  Future<void> setSession(Map<String, String>? context) async =>
      contexts.add(context);
  @override
  void dispose() => disposed = true;
}

final class _UploadRepository implements DocumentUploadRepository {
  int calls = 0;
  final result = Completer<DocumentUploadResult>();
  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) {
    calls++;
    onSending();
    return result.future;
  }

  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}

AuthSession _session({String account = 'Library', bool allowed = true}) =>
    AuthSession(
      token: 'session-$account',
      expiresAt: null,
      identity: Identity(
        userId: 'user',
        email: 'user@example.com',
        accountId: account,
        accountName: account,
        role: AccountRole.user,
        mustChangePassword: false,
        permissions: allowed ? [IdentityPermission.uploadDocuments] : [],
      ),
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DocumentUploadCoordinator uploads;
  late _UploadRepository repository;
  late DocumentUploadsCubit target;
  late _ShareSource source;
  late MobileShareCubit shares;

  setUp(() {
    uploads = DocumentUploadCoordinator(
      acquisition: NativeDocumentUploadAcquisition(),
    );
    repository = _UploadRepository();
    target = DocumentUploadsCubit(
      repository: repository,
      scheduler: uploads,
      libraryName: 'Library',
      canRead: false,
      allowed: true,
    );
    source = _ShareSource();
    shares = MobileShareCubit(
      endpoint: 'https://example.com/domabas',
      uploads: uploads,
      source: source,
      platform: TargetPlatform.android,
    );
  });
  tearDown(() async {
    if (!repository.result.isCompleted) {
      repository.result.complete(
        const DocumentUploadResult(
          outcome: DocumentUploadOutcome.rejected,
          message: 'Stopped',
        ),
      );
    }
    await shares.close();
    await target.close();
    uploads.dispose();
    await _settle();
  });

  test('cold share waits for sign-in and explicit confirmation; releases only after upload', () async {
    await _settle();
    source.batch = MobileShareBatch(id: 'cold', paths: ['/cache/receipt.pdf']);
    source.changed!();
    await _settle();
    expect(shares.state.batch?.id, 'cold');
    expect(shares.state.canUpload, isFalse);
    shares.confirm();
    expect(repository.calls, 0);
    uploads.attach(target, busy: false);
    shares.attach(_session(), target, busy: false);
    expect(shares.state.canUpload, isTrue);
    shares.confirm();
    shares.confirm();
    await _settle();
    expect(repository.calls, 1);
    expect(shares.state.batch, isNull);
    expect(source.released, isEmpty);
    source.changed!();
    await _settle();
    expect(shares.state.batch, isNull);
    repository.result.complete(
      const DocumentUploadResult(
        outcome: DocumentUploadOutcome.uncertain,
        message: 'Check library',
      ),
    );
    await _settle();
    expect(source.released, ['cold']);
    expect(target.state.rows.single.phase, DocumentUploadPhase.uncertain);
    expect(repository.calls, 1);
  });

  test('scope replacement and logout discard a pending batch', () async {
    uploads.attach(target, busy: false);
    final session = _session();
    shares.attach(session, target, busy: false);
    await _settle();
    source.batch = MobileShareBatch(id: 'old', paths: ['/cache/a.pdf']);
    source.changed!();
    await _settle();
    shares.attach(_session(account: 'Other'), target, busy: false);
    await _settle();
    expect(shares.state.batch, isNull);
    expect(source.released, ['old']);
    expect(repository.calls, 0);
  });

  test('late platform read cannot enter a replacement session', () async {
    uploads.attach(target, busy: false);
    shares.attach(_session(), target, busy: false);
    await _settle();
    source.delayed = Completer<MobileShareBatch?>();
    shares.refresh();
    shares.attach(_session(account: 'Other'), target, busy: false);
    source.delayed!.complete(
      MobileShareBatch(id: 'late', paths: ['/cache/a.pdf']),
    );
    await _settle();
    expect(shares.state.batch, isNull);
    expect(source.released, ['late']);
  });

  test('busy or forbidden scopes cannot confirm, and batches above queue capacity remain visible', () async {
    uploads.attach(target, busy: true);
    shares.attach(_session(), target, busy: true);
    await _settle();
    source.batch = MobileShareBatch(
      id: 'large',
      paths: List.filled(21, '/cache/a.pdf'),
    );
    source.changed!();
    await _settle();
    shares.confirm();
    expect(repository.calls, 0);
    uploads.attach(target, busy: false);
    shares.attach(_session(), target, busy: false);
    await _settle();
    source.batch = MobileShareBatch(
      id: 'large-again',
      paths: List.filled(21, '/cache/a.pdf'),
    );
    source.changed!();
    await _settle();
    shares.confirm();
    expect(repository.calls, 0);
    expect(shares.state.batch?.id, 'large-again');
    shares.discard();
    expect(source.released, contains('large-again'));
  });

  test('iOS context contains a token fingerprint, clears on busy/logout, and preserves endpoint scope', () async {
    await shares.close();
    shares = MobileShareCubit(
      endpoint: 'https://example.com/domabas',
      uploads: uploads,
      source: source,
      platform: TargetPlatform.iOS,
    );
    final session = _session();
    shares.attach(session, target, busy: false);
    final context = source.contexts.last!;
    expect(context['endpoint'], 'https://example.com/domabas');
    expect(context['credentialKey'], startsWith('domabas.session.v1.'));
    expect(context['tokenHash'], matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(context.values, isNot(contains(session.token)));
    shares.attach(session, target, busy: true);
    expect(source.contexts.last, isNull);
    shares.attach(_session(allowed: false), target, busy: false);
    expect(source.contexts.last, isNull);
    shares.attach(null, null, busy: false);
    expect(source.contexts.last, isNull);
  });

  testWidgets(
    'confirmation names the library, never auto uploads, and allows discard',
    (tester) async {
      uploads.attach(target, busy: false);
      shares.attach(_session(), target, busy: false);
      await tester.pump();
      source.batch = MobileShareBatch(id: 'ui', paths: ['/cache/a.pdf']);
      source.changed!();
      await tester.pumpWidget(
        MaterialApp(
          home: MobileShareHost(
            shares: shares,
            child: const Scaffold(body: Text('Documents')),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Upload 1 file to Library?'), findsOneWidget);
      expect(repository.calls, 0);
      await tester.tap(find.text('Discard'));
      await tester.pump();
      expect(find.text('Shared with Domabas'), findsNothing);
      expect(source.released, contains('ui'));
      expect(tester.takeException(), isNull);
    },
  );
}
