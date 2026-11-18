import 'package:domabas/app/job_activity_cubit.dart';
import 'package:domabas/app/job_activity_indicator.dart';
import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/document/cubits/document_processing_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  testWidgets(
    'real job detail dialog closes before document handoff and dies with its owner',
    (tester) async {
      final repository = FakeProcessingRepository()
        ..jobs = [testProcessingJob(status: 'succeeded')];
      final cubit = DocumentProcessingCubit(
        repository,
        canReadJobs: true,
        canReindex: false,
      )..setActive(true);
      final opened = <String>[];
      BuildContext? ownerContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: Builder(
            builder: (context) {
              ownerContext = context;
              return Scaffold(
                body: DocumentProcessingScreen(
                  modalDetails: true,
                  cubit: cubit,
                  canReadDocuments: true,
                  onOpenDocument: (id) {
                    expect(Navigator.canPop(context), isFalse);
                    opened.add(id);
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await cubit.selectJob('job');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Job details'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('openJobDocument')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openJobDocument')));
      await tester.pumpAndSettle();
      expect(opened, [repository.jobs.first.documentId]);
      expect(cubit.state.selected, isNull);
      expect(Navigator.canPop(ownerContext!), isFalse);
      await cubit.selectJob('job');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(home: Text('Replacement library')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Job details'), findsNothing);
      expect(tester.takeException(), isNull);
      await cubit.close();
    },
  );

  for (final (size, scale) in [
    (const Size(800, 500), 1.0),
    (const Size(320, 320), 2.0),
  ]) {
    testWidgets(
      'real Chat Send and Stop remain pointer reachable beside activity at $size/$scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = FakeChatRepository();
        final chat = ChatCubit(repository, allowed: true)..setActive(true);
        final jobs = JobActivityCubit(
          processing: FakeProcessingRepository()..jobs = [testProcessingJob()],
          email: FakeEmailRepository(),
          canReadJobs: true,
          canReadBatches: false,
          canReadSystemBatches: false,
          canReadEmail: false,
          canReadPaperless: false,
        )..setActive(true);
        await tester.pumpWidget(
          MaterialApp(
            theme: GlacierTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: AppWorkspaceShell(
              glacier: true,
              libraryLabel: 'Real library',
              libraryPicker: const SizedBox.shrink(),
              accountLabel: 'reader@example.test',
              onLogout: () {},
              groups: [
                AppNavigationGroup(
                  id: 'chat',
                  label: 'Chat',
                  icon: Icons.chat,
                  items: const [
                    AppNavigationItem(
                      id: 'chat',
                      label: 'Chat',
                      icon: Icons.chat,
                    ),
                  ],
                ),
              ],
              selectedId: 'chat',
              onSelected: (_) {},
              activityIndicator: JobActivityIndicator(
                glacier: true,
                cubit: jobs,
                uploads: null,
                onOpen: (_) {},
              ),
              child: ChatScreen(cubit: chat, libraryName: 'Real library'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = find.byKey(const Key('chatMessage'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'Find my bill');
        await tester.pumpAndSettle();
        final send = find.byKey(const Key('sendChatMessage'));
        await Scrollable.ensureVisible(tester.element(send), alignment: .05);
        await tester.pumpAndSettle();
        expect(send.hitTestable(), findsOneWidget);
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(repository.sendRequests, hasLength(1));
        final stop = find.byKey(const Key('stopChatReply'));
        await Scrollable.ensureVisible(tester.element(stop), alignment: .05);
        await tester.pumpAndSettle();
        expect(stop.hitTestable(), findsOneWidget);
        await tester.tap(stop);
        await tester.pumpAndSettle();
        expect(chat.state.hasActiveTurn, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await jobs.close();
        await chat.close();
      },
    );
  }
}
