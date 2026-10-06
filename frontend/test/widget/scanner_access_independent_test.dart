import 'dart:async';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/app/scanner_scope.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/ui/app_navigation_button.dart';
import 'package:domabas/ui/app_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';
import '../support/fake_activity_repository.dart';
import '../support/fake_appearance_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  for (final (permission, native, mustChangePassword) in [
    (true, true, false),
    (false, true, false),
    (true, false, false),
    (false, false, false),
    (true, true, true),
  ]) {
    testWidgets(
      'mobile Scanner upload=$permission native=$native initialPassword=$mustChangePassword',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final factory = _Factory();
        final documents = FakeDocumentRepository();
        final auth = FakeAuthRepository()
          ..saved = AuthSession(
            token: 'fixture-token',
            expiresAt: DateTime.utc(2100),
            identity: Identity(
              userId: 'u',
              email: 'upload@example.test',
              accountId: 'namespace',
              accountName: 'Upload library',
              role: AccountRole.viewer,
              mustChangePassword: mustChangePassword,
              permissions: [
                IdentityPermission.readDocumentJobs,
                if (permission) IdentityPermission.uploadDocuments,
              ],
            ),
          );
        addTearDown(factory.scope.camera.close);
        await tester.pumpWidget(
          DomabasApp(
            appearance: FakeAppearanceRepository(),
            auth: auth,
            authenticate: (_, _) => AuthenticatedDependencies(
              documents: documents,
              identity: FakeIdentityRepository(),
              processing: FakeProcessingRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              realtime: FakeRealtimeRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              scanner: native ? factory : null,
              close: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final allowed = permission && native && !mustChangePassword;
        final scanner = find.byKey(const Key('scannerNavigation'));
        expect(scanner, allowed ? findsOneWidget : findsNothing);
        expect(factory.opens, 0);
        if (!mustChangePassword) {
          expect(find.byKey(const Key('processingNavigation')), findsNothing);
          await navigateWorkspace(tester, 'processingNavigation');
          expect(
            tester
                .widget<AppNavigationButton>(
                  find.byKey(const Key('navigation-more')),
                )
                .selected,
            isTrue,
          );
          final shell = tester.widget<AppWorkspaceShell>(
            find.byType(AppWorkspaceShell),
          );
          expect(shell.selectedId, 'jobs');
          if (allowed) {
            factory.wait = Completer<ScannerScope>();
            await tester.tap(scanner);
            await tester.pump();
            shell.onSelected('scanner');
            expect(factory.opens, 1);
            expect(
              tester
                  .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
                  .selectedId,
              'jobs',
            );
            factory.wait!.complete(factory.scope);
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('addScanPage')), findsOneWidget);
            await tester.tap(find.byKey(const Key('closeScanner')));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('addScanPage')), findsNothing);
            expect(
              tester
                  .widget<AppWorkspaceShell>(find.byType(AppWorkspaceShell))
                  .selectedId,
              'jobs',
            );
          } else {
            shell.onSelected('scanner');
            await tester.pumpAndSettle();
            expect(factory.opens, 0);
          }
        }
        expect(documents.offsets, isEmpty);
        expect(documents.reads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final access in [(true, false), (false, false), (true, true)]) {
    final permission = access.$1, mustChangePassword = access.$2;
    final allowed = permission && !mustChangePassword;
    testWidgets(
      'scanner entry upload=$permission initialPassword=$mustChangePassword without read/create',
      (tester) async {
        final auth = FakeAuthRepository()
          ..saved = AuthSession(
            token: 'fixture-token',
            expiresAt: DateTime.utc(2100),
            identity: Identity(
              userId: 'u',
              email: 'upload@example.test',
              accountId: 'namespace',
              accountName: 'Upload library',
              role: AccountRole.viewer,
              mustChangePassword: mustChangePassword,
              permissions: permission
                  ? [IdentityPermission.uploadDocuments]
                  : [],
            ),
          );
        final factory = _Factory();
        final documents = FakeDocumentRepository();
        addTearDown(factory.scope.camera.close);
        await tester.pumpWidget(
          DomabasApp(
            appearance: FakeAppearanceRepository(),
            auth: auth,
            authenticate: (_, _) => AuthenticatedDependencies(
              documents: documents,
              identity: FakeIdentityRepository(),
              processing: FakeProcessingRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              realtime: FakeRealtimeRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              scanner: factory,
              close: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!mustChangePassword &&
            find.byKey(const Key('workspaceMore')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('workspaceMore')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('newDocument')), findsNothing);
        expect(
          find.byKey(const Key('scanDocument')),
          allowed ? findsOneWidget : findsNothing,
        );
        if (allowed) {
          factory.wait = Completer<ScannerScope>();
          await tester.tap(find.byKey(const Key('scanDocument')));
          await tester.pump();
          expect(
            find.text('Opening scanner… Finishing any previous scan first.'),
            findsOneWidget,
          );
          factory.wait!.complete(factory.scope);
          await tester.pumpAndSettle();
          expect(find.text('Scan document'), findsOneWidget);
          expect(factory.scope.repository.restores, 1);
          expect(find.byKey(const Key('addScanPage')), findsOneWidget);
        } else {
          expect(factory.opens, 0);
        }
        expect(documents.offsets, isEmpty);
        expect(documents.reads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final class _Factory implements ScannerScopeFactory {
  final scope = _Scope();
  Completer<ScannerScope>? wait;
  int opens = 0;
  @override
  Future<ScannerScope> open() async {
    opens++;
    return wait == null ? scope : wait!.future;
  }

  @override
  void cancelNewOperations() {}
  @override
  Future<void> close() => scope.close();
}

final class _Scope implements ScannerScope {
  @override
  final camera = FixtureScannerCamera();
  @override
  final FixtureScanRepository repository = FixtureScanRepository();
  @override
  WidgetBuilder get previewBuilder =>
      (_) => const SizedBox();
  @override
  void cancelNewOperations() {
    camera.cancelNewOperations();
    repository.cancelNewOperations();
  }

  @override
  Future<void> close() async {}
}
