import '../support/fake_realtime_repository.dart';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/email/models/email.dart';
import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/presentation/email/widgets/email_provider_editor.dart';
import 'package:domabas/presentation/identity/cubits/personal_activity_cubit.dart';
import 'package:domabas/presentation/identity/widgets/personal_activity_action.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  for (final failure in [false, true]) {
    testWidgets(
      'connection feedback is visible below actions without scrolling back: $failure',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakeEmailRepository();
        if (failure) {
          repository.failure = const EmailFailure(EmailFailureKind.unavailable);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmailProviderEditor(
                repository: repository,
                provider: emailProvider(),
                capabilities: const EmailCapabilities(
                  credentialsAvailable: true,
                ),
                canImport: true,
                onClose: (_) {},
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.byKey(const Key('email-test')));
        await tester.tap(find.byKey(const Key('email-test')));
        await tester.pumpAndSettle();
        final feedback = failure
            ? find.text(
                const EmailFailure(EmailFailureKind.unavailable).message,
              )
            : find.byKey(const Key('email-test-result'));
        expect(feedback.hitTestable(), findsOneWidget);
        expect(
          tester.getTopLeft(feedback).dy,
          greaterThan(
            tester.getBottomLeft(find.byKey(const Key('email-test'))).dy,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final upload in [false, true]) {
    testWidgets(
      'email import needs upload permission, independently of create: $upload',
      (tester) async {
        final email = FakeEmailRepository()
          ..providers['provider'] = emailProvider();
        final dependencies = AuthenticatedDependencies(
          realtime: FakeRealtimeRepository(),
          email: email,
          activity: FakeActivityRepository(),
          documents: FakeDocumentRepository(),
          identity: FakeIdentityRepository(),
          processing: FakeProcessingRepository(),
          externalLinks: FakeExternalLinkLauncher(),
          close: () {},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AccountWorkspace(
              session: testSession(
                role: upload ? AccountRole.viewer : AccountRole.user,
                extraPermissions: [
                  IdentityPermission.manageEmail,
                  if (upload) IdentityPermission.uploadDocuments,
                ],
              ),
              dependencies: dependencies,
              onLogout: () {},
              onSessionEnded: (_) {},
              onSwitch: (_) async => null,
            ),
          ),
        );
        await navigateWorkspace(tester, 'emailNavigation');
        await tester.tap(find.byKey(const Key('email-provider-provider')));
        await tester.pumpAndSettle();
        expect(
          tester
                  .widget<FilledButton>(find.byKey(const Key('email-import')))
                  .onPressed !=
              null,
          upload,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        dependencies.dispose();
      },
    );
  }
  for (final size in [const Size(320, 320), const Size(1280, 900)]) {
    testWidgets('email editor scrolls at $size and 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: EmailProviderEditor(
              repository: FakeEmailRepository(),
              capabilities: const EmailCapabilities(credentialsAvailable: true),
              canImport: true,
              onClose: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('email-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('email-save')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'private jobs dialog fits short enlarged viewport and owns its route',
    (tester) async {
      tester.view.physicalSize = const Size(320, 320);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final cubit = PersonalActivityCubit(FakeActivityRepository())
        ..setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PersonalActivityAction(
              cubit: cubit,
              namespaceId: 'library',
              onOpen: (_) async {},
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('personal-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Your jobs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('EML body works without download permission or preview bytes', (
    tester,
  ) async {
    final repository = FakeDocumentRepository();
    final mail = Document(
      id: 'mail',
      title: 'Safe email',
      description: '',
      createdAt: DateTime.utc(2026),
      kind: 'email',
      sender: 'sender@example.test',
      file: DocumentFile(
        originalFilename: 'message.eml',
        mediaType: 'message/rfc822',
        size: 100,
        sha256: 'a' * 64,
        ingestedAt: DateTime.utc(2026),
        uploaderId: 'user',
      ),
    );
    repository.records.add(mail);
    repository.ocr['mail'] = const DocumentOcr(
      status: 'available',
      revision: 1,
      text: '<script>inert text</script>',
      origin: 'machine',
      reason: null,
      semanticIndexing: 'ready',
    );
    final cubit = DocumentsCubit(
      repository,
      capabilities: const DocumentCapabilities(read: true, readOcr: true),
    );
    expect(
      await cubit.previews.request(mail.thumbnailRef).result.future,
      isNull,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DocumentDetailDialog(documentId: 'mail', cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('email-document-view')), findsOneWidget);
    expect(find.text('<script>inert text</script>'), findsOneWidget);
    expect(
      find.textContaining('does not allow viewing the original'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}
