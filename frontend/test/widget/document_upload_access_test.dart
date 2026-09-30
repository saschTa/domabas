import '../support/workspace_navigation.dart';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/desktop_upload_bridge.dart';
import 'package:domabas/app/document_upload_coordinator.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/data/document/datasources/document_upload_acquisition.dart';
import 'package:domabas/domain/appearance/models/appearance_preference.dart';
import 'package:domabas/domain/document/interfaces/document_upload_repository.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_upload.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/document_uploads_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_appearance_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'all document actions remain usable at 320px and 200% in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = _Fixture(
          permissions: const [
            IdentityPermission.uploadDocuments,
            IdentityPermission.readDocuments,
            IdentityPermission.createDocuments,
          ],
          dark: dark,
        );
        addTearDown(fixture.coordinator.dispose);
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();

        for (final key in [
          'uploadFiles',
          'viewUploads',
          'scanDocument',
          'newDocument',
        ]) {
          await revealWorkspaceAction(tester, key);
          final action = find.byKey(Key(key));
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget, reason: key);
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(0), reason: key);
          expect(rect.right, lessThanOrEqualTo(320), reason: key);
        }
        expect(find.text('Upload files'), findsOneWidget);
        expect(find.text('View uploads'), findsOneWidget);
        expect(find.text('Create metadata'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byKey(const Key('uploadFiles'))))
              .brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);

        await _tapAction(tester, 'uploadFiles');
        expect(fixture.acquisition.choices, 1);
        await tester.pumpAndSettle();
        expect(fixture.transport.calls, 1);
        expect(fixture.uploads.state.accepted, 1);
        expect(find.byKey(const Key('documentTitle')), findsNothing);

        await _tapAction(tester, 'viewUploads');
        await tester.pumpAndSettle();
        expect(find.text('Uploaded original.pdf'), findsOneWidget);
        expect(find.text('Accepted — processing continues'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        await _tapAction(tester, 'scanDocument');
        await tester.pumpAndSettle();
        expect(find.text('Scan document'), findsOneWidget);
        expect(find.text('Mobile scanner unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();

        await _tapAction(tester, 'newDocument');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('documentTitle')), findsOneWidget);
        expect(fixture.acquisition.choices, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (permission, mustChangePassword) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    final allowed = permission && !mustChangePassword;
    testWidgets(
      'upload access=$permission initialPassword=$mustChangePassword works independently of document read/create',
      (tester) async {
        final fixture = _Fixture(
          permissions: permission
              ? const [IdentityPermission.uploadDocuments]
              : [],
          mustChangePassword: mustChangePassword,
        );
        addTearDown(fixture.coordinator.dispose);
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();

        if (!mustChangePassword &&
            find.byKey(const Key('workspaceMore')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('workspaceMore')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('newDocument')), findsNothing);
        for (final key in ['uploadFiles', 'viewUploads', 'scanDocument']) {
          expect(
            find.byKey(Key(key)),
            allowed ? findsOneWidget : findsNothing,
            reason: key,
          );
        }
        expect(fixture.documents.offsets, isEmpty);
        expect(fixture.documents.reads, 0);
        if (!mustChangePassword &&
            find.byKey(const Key('workspaceMore')).evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Close actions'));
          await tester.pumpAndSettle();
        }

        if (allowed) {
          expect(find.text('Library access is limited'), findsOneWidget);
          await tester.tap(find.byKey(const Key('uploadFiles')));
          expect(fixture.acquisition.choices, 1);
          await tester.pumpAndSettle();
          expect(fixture.transport.calls, 1);
          expect(fixture.uploads.state.accepted, 1);
          expect(find.byKey(const Key('documentTitle')), findsNothing);
          await _tapAction(tester, 'viewUploads');
          await tester.pumpAndSettle();
          expect(find.text('Uploaded original.pdf'), findsOneWidget);
          expect(
            find.textContaining('Ask someone with library access'),
            findsOneWidget,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 16));
          await tester.pumpAndSettle();
        } else {
          fixture.coordinator.choose(fixture.uploads);
          fixture.uploads.setHover(true);
          await tester.pumpAndSettle();
          expect(fixture.acquisition.choices, 0);
          expect(fixture.transport.calls, 0);
          expect(fixture.bridge.owner, isNull);
          expect(find.byKey(const Key('fileDropInvitation')), findsNothing);
          if (mustChangePassword) {
            expect(find.text('Change initial password'), findsOneWidget);
          }
        }

        expect(fixture.documents.offsets, isEmpty);
        expect(fixture.documents.reads, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _tapAction(WidgetTester tester, String key) async {
  await revealWorkspaceAction(tester, key);
  final action = find.byKey(Key(key));
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
}

final class _Fixture {
  _Fixture({
    required List<String> permissions,
    bool mustChangePassword = false,
    bool dark = false,
  }) {
    final session = AuthSession(
      token: 'fixture-token',
      expiresAt: DateTime.utc(2100),
      identity: Identity(
        userId: 'upload-user',
        email: 'upload@example.test',
        accountId: 'upload-library',
        accountName: 'Upload library',
        role: AccountRole.viewer,
        mustChangePassword: mustChangePassword,
        permissions: permissions,
      ),
    );
    coordinator = DocumentUploadCoordinator(
      acquisition: acquisition,
      desktopBridge: bridge,
    );
    uploads = DocumentUploadsCubit(
      repository: transport,
      scheduler: coordinator,
      libraryName: session.identity.accountName,
      canRead: session.identity.allows(IdentityPermission.readDocuments),
      allowed: session.identity.allows(IdentityPermission.uploadDocuments),
    );
    app = DomabasApp(
      auth: FakeAuthRepository()..saved = session,
      appearance: FakeAppearanceRepository()
        ..stored = dark
            ? AppearancePreference.dark
            : AppearancePreference.light,
      uploads: coordinator,
      authenticate: (_, _) => AuthenticatedDependencies(
        documents: documents,
        identity: FakeIdentityRepository(),
        processing: FakeProcessingRepository(),
        email: FakeEmailRepository(),
        activity: FakeActivityRepository(),
        realtime: FakeRealtimeRepository(),
        externalLinks: FakeExternalLinkLauncher(),
        uploads: uploads,
        close: () {},
      ),
    );
  }

  final acquisition = _Acquisition();
  final bridge = _Bridge();
  final transport = _Transport();
  final documents = FakeDocumentRepository();
  late final DocumentUploadCoordinator coordinator;
  late final DocumentUploadsCubit uploads;
  late final DomabasApp app;
}

final class _Acquisition extends DocumentUploadAcquisition {
  int choices = 0;

  @override
  Future<DocumentUploadSelection> choose({
    required bool Function(int) reserve,
  }) {
    choices++;
    return Future.value(
      capture(
        1,
        reserve: reserve,
        handleAt: (_) => const RejectedDocumentUploadHandle(
          'Uploaded original.pdf',
          'The transport fixture handles this selection without file I/O.',
        ),
      ),
    );
  }

  @override
  DocumentUploadSelection captureNativePaths(
    List<String> paths, {
    required bool Function(int) reserve,
  }) => throw StateError('No native paths are supplied by this widget test.');
}

final class _Bridge implements DesktopUploadBridge {
  Object? owner;
  @override
  bool get portalBusy => false;
  @override
  void bind(Object? owner, void Function(DesktopUploadEvent)? listener) {
    this.owner = owner;
  }

  @override
  Future<void> dispose() async {}
}

final class _Transport implements DocumentUploadRepository {
  int calls = 0;

  @override
  Future<DocumentUploadResult> upload(
    DocumentUploadCandidate candidate, {
    required Future<void> cancel,
    required void Function() onSending,
    void Function(Document)? onAccepted,
    void Function(String)? onReadFailure,
  }) async {
    calls++;
    onSending();
    final accepted = Document(
      id: 'accepted-original',
      title: 'Uploaded original',
      description: '',
      createdAt: DateTime.utc(2026),
    );
    onAccepted?.call(accepted);
    return DocumentUploadResult(
      outcome: DocumentUploadOutcome.accepted,
      message: 'The server accepted this original. Processing continues.',
      document: accepted,
    );
  }

  @override
  void release(Iterable<String> ids) {}
  @override
  void dispose() {}
}
