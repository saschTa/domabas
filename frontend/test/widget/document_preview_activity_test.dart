import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/job_activity_indicator.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';

void main() {
  testWidgets(
    'activity preparation updates retain collection and search draft state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      final job = testProcessingJob(pipeline: 'thumbnail');
      final documents = FakeDocumentRepository()
        ..records = [
          Document(
            id: job.documentId,
            title: 'Pending image',
            description: '',
            createdAt: DateTime.utc(2026),
            file: DocumentFile(
              originalFilename: 'image.png',
              mediaType: 'image/png',
              size: 100,
              sha256: 'a' * 64,
              ingestedAt: DateTime.utc(2026),
              uploaderId: 'owner',
            ),
          ),
        ];
      final processing = FakeProcessingRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: AccountWorkspace(
            session: testSession(
              extraPermissions: [
                IdentityPermission.readDocumentJobs,
                IdentityPermission.downloadDocuments,
                IdentityPermission.readDocumentThumbnails,
                IdentityPermission.searchDocuments,
              ],
            ),
            dependencies: AuthenticatedDependencies(
              documents: documents,
              processing: processing,
              realtime: FakeRealtimeRepository(),
              email: FakeEmailRepository(),
              activity: FakeActivityRepository(),
              identity: FakeIdentityRepository(),
              externalLinks: FakeExternalLinkLauncher(),
              close: () {},
            ),
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final screen = tester.state(find.byType(DocumentsScreen));
      final card = tester.state(find.byType(DocumentCollectionCard));
      final monitor = tester
          .widget<JobActivityIndicator>(find.byType(JobActivityIndicator))
          .cubit;
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('documentSearchTerm'));
      await tester.enterText(field, 'unapplied search draft');
      final controller = tester.widget<TextField>(field).controller;
      processing.jobs = [job];
      await monitor.refresh();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
      expect(tester.state(find.byType(DocumentsScreen)), same(screen));
      expect(tester.state(find.byType(DocumentCollectionCard)), same(card));
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(controller!.text, 'unapplied search draft');
      monitor.setRealtimeHealthy(false);
      await tester.pump();
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      expect(tester.state(find.byType(DocumentsScreen)), same(screen));
      expect(controller.text, 'unapplied search draft');
      expect(documents.thumbnailReads, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
