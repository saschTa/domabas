import 'package:domabas/app/account_workspace.dart';
import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_chat_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_invoice_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';
import '../support/workspace_navigation.dart';
import '../support/navigation_fonts.dart';

void main() {
  setUpAll(loadNavigationFonts);
  for (final permissions in [
    <String>[],
    [IdentityPermission.useChat],
    [IdentityPermission.manageChat],
    [
      IdentityPermission.useChat,
      IdentityPermission.manageChat,
      IdentityPermission.readInvoices,
      IdentityPermission.readDocumentJobs,
    ],
  ]) {
    testWidgets('chat workspace uses independent claims: $permissions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeChatRepository();
      final dependencies = AuthenticatedDependencies(
        documents: FakeDocumentRepository(),
        invoices: FakeInvoiceRepository(),
        chat: repository,
        identity: FakeIdentityRepository(),
        processing: FakeProcessingRepository(),
        email: FakeEmailRepository(),
        activity: FakeActivityRepository(),
        realtime: FakeRealtimeRepository(),
        externalLinks: FakeExternalLinkLauncher(),
        close: () {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AccountWorkspace(
            session: testSession(extraPermissions: permissions),
            dependencies: dependencies,
            onLogout: () {},
            onSessionEnded: (_) {},
            onSwitch: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final canChat = permissions.contains(IdentityPermission.useChat),
          canManage = permissions.contains(IdentityPermission.manageChat);
      expect(
        find.byKey(const Key('chatNavigation')),
        canChat ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(
          Key(
            permissions.length == 4
                ? 'navigation-more'
                : 'navigation-admin-settings',
          ),
        ),
        canManage ? findsOneWidget : findsNothing,
      );
      if (canChat) {
        await tester.ensureVisible(find.byKey(const Key('chatNavigation')));
        await tester.tap(find.byKey(const Key('chatNavigation')));
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        if (permissions.length == 4) {
          final conversation = chatConversation('mobile');
          repository.history.add(conversation);
          repository.transcript[conversation.id] = [
            chatMessage(
              'question',
              conversationId: conversation.id,
              role: 'user',
              content: 'What is the reference amount?',
            ),
            chatMessage(
              'answer',
              conversationId: conversation.id,
              sequence: 2,
              content: 'The reference amount is 42 euros.',
              sources: [
                const ChatSource(
                  documentId: 'evidence',
                  title: 'Reference document',
                ),
              ],
            ),
          ];
          final chat = tester.widget<ChatScreen>(find.byType(ChatScreen)).cubit;
          await chat.select(conversation);
          await tester.pumpAndSettle();
          final transcript = find.byKey(const Key('chatTranscript'));
          final navigationHeight = tester
              .getSize(find.byKey(const Key('workspaceBottomNavigation')))
              .height;
          expect(
            tester.getSize(transcript).height,
            greaterThanOrEqualTo(520 - navigationHeight),
          );
          expect(
            find.text('The reference amount is 42 euros.').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Reference document').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const Key('chatHistory')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('newChat')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.getBottomLeft(find.byKey(const Key('chatMessage'))).dy,
            lessThan(
              tester
                  .getTopLeft(
                    find.byKey(const Key('workspaceBottomNavigation')),
                  )
                  .dy,
            ),
          );
        }
        await tester.enterText(
          find.byKey(const Key('chatMessage')),
          'Keep this draft',
        );
        await navigateWorkspace(
          tester,
          'documentsNavigation',
          group: 'Workspace',
        );
        await navigateWorkspace(tester, 'chatNavigation', group: 'Workspace');
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('chatMessage')))
              .controller!
              .text,
          'Keep this draft',
        );
      }
      if (canManage) {
        await navigateWorkspace(tester, 'manageChat', group: 'Admin settings');
        expect(find.byType(ChatSettingsScreen), findsOneWidget);
      }
      if (permissions.length == 4) {
        expect(
          find.byKey(const Key('workspaceNotchedNavigation')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
      expect(repository.cancelled, isTrue);
    });
  }
}
