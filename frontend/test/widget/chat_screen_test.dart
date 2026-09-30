import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas/presentation/chat/widgets/chat_message_card.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/workspace_navigation.dart' show revealWorkspaceContent;

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 1440,
  double height = 1000,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'deletion failure remains visible after scrolling to older history',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeChatRepository()
        ..history = List.generate(45, (i) => chatConversation('$i'))
        ..deleteFailure = const ChatFailure('unavailable');
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await mount(
        tester,
        ChatScreen(cubit: cubit, libraryName: 'My library'),
        width: 390,
        height: 844,
      );
      await cubit.load(more: true);
      await cubit.load(more: true);
      await tester.tap(find.byKey(const Key('chatHistory')));
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Scrollable),
      );
      final delete = find.byKey(const Key('deleteChatConversation-0'));
      await tester.scrollUntilVisible(delete, 300, scrollable: scroll);
      expect(find.byKey(const Key('chatConversation-9')), findsNothing);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteChatConversation')));
      await tester.pumpAndSettle();
      expect(repository.deleteRequests, ['0']);
      expect(
        find.byKey(const Key('chatDeleteError')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.textContaining('Could not delete the conversation.').hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(delete, 100, scrollable: scroll.last);
      await tester.pumpAndSettle();
      expect(delete.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('chatDeleteError')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1440.0, 320.0]) {
    testWidgets(
      'history confirms deletion and supports retry at $width width',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final one = chatConversation('one');
        final repository = FakeChatRepository()
          ..history = [one]
          ..transcript['one'] = [
            chatMessage('answer', content: 'Saved answer'),
          ];
        final cubit = ChatCubit(repository, allowed: true)..setActive(true);
        addTearDown(cubit.close);
        await mount(
          tester,
          ChatScreen(cubit: cubit, libraryName: 'My library'),
          width: width,
          height: width < 600 ? 640 : 1000,
          scale: width < 600 ? 2 : 1,
        );
        await cubit.select(one);
        cubit.editDraft('My question');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'selected transcript');
        if (width < 600) {
          await tester.tap(find.byKey(const Key('chatHistory')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'history');
        }
        final delete = find.byKey(const Key('deleteChatConversation-one'));
        await tester.tap(delete);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'confirmation');
        expect(find.text('Delete conversation?'), findsOneWidget);
        expect(repository.deleteRequests, isEmpty);
        await tester.tap(find.byKey(const Key('cancelDeleteChatConversation')));
        await tester.pumpAndSettle();
        expect(repository.deleteRequests, isEmpty);
        expect(cubit.state.draft, 'My question');
        final pending = Completer<void>();
        repository.delayedDelete = pending;
        repository.deleteFailure = const ChatFailure('unavailable');
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirmDeleteChatConversation')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(cubit.state.deletingConversationId, 'one');
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(repository.deleteRequests, ['one']);
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'delete failure');
        expect(
          find.textContaining('Could not delete the conversation.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('chatConversation-one')), findsOneWidget);
        expect(cubit.state.draft, 'My question');
        repository.deleteFailure = null;
        await tester.ensureVisible(delete);
        await tester.tap(delete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirmDeleteChatConversation')),
        );
        await tester.pumpAndSettle();
        expect(repository.deleteRequests, ['one', 'one']);
        expect(find.byKey(const Key('chatConversation-one')), findsNothing);
        expect(cubit.state.messages, isEmpty);
        expect(cubit.state.draft, isEmpty);
        if (width < 600) {
          expect(find.byTooltip('Close history'), findsOneWidget);
          await tester.tap(find.byTooltip('Close history'));
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('chatMessage')))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'suggestion fills composer, sending preserves progress and Stop confirms cancellation',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeChatRepository();
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await mount(tester, ChatScreen(cubit: cubit, libraryName: 'My library'));
      await tester.tap(find.text('Find my latest electricity bill'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chatMessage')))
            .controller!
            .text,
        'Find my latest electricity bill',
      );
      await tester.enterText(
        find.byKey(const Key('chatMessage')),
        'Find my latest electricity bill and its amount',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('sendChatMessage')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('sendChatMessage')));
      await tester.pumpAndSettle();
      expect(find.text('Queued'), findsOneWidget);
      expect(
        find.text('Your message is saved and waiting to start.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('stopChatReply')));
      await tester.pumpAndSettle();
      expect(find.text('Reply stopped'), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in [
    (390.0, 844.0, 1.0, false),
    (320.0, 600.0, 2.0, true),
    (1440.0, 1000.0, 1.0, true),
  ]) {
    testWidgets('chat fits ${variant.$1} width at ${variant.$3} scale', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeChatRepository();
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await mount(
        tester,
        ChatScreen(cubit: cubit, libraryName: 'A library with a long name'),
        width: variant.$1,
        height: variant.$2,
        scale: variant.$3,
        dark: variant.$4,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('chatHistory')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatHistory')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'persisted progress has explicit labels and sources open trusted document IDs',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      for (final entry in {
        'queued': 'Queued',
        'waiting_for_ingestion': 'Waiting to start',
        'preparing': 'Preparing your reply',
        'generating': 'Thinking',
        'searching_documents': 'Searching your library',
        'reading_document': 'Reading documents',
        'future_stage': 'Working on your reply',
      }.entries) {
        await mount(
          tester,
          Center(
            child: ChatMessageCard(
              message: chatMessage(
                'answer',
                status: 'running',
                stage: entry.key,
              ),
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
      await mount(
        tester,
        Center(
          child: ChatMessageCard(
            message: chatMessage(
              'answer',
              content: 'Read the invoice.',
              sources: [
                const ChatSource(
                  documentId: 'verified-id',
                  title: 'An invoice',
                ),
              ],
            ),
            onOpenDocument: (id) async => opened = id,
          ),
        ),
      );
      await tester.tap(find.text('An invoice'));
      expect(opened, 'verified-id');
      expect(find.text('Documents consulted'), findsOneWidget);
    },
  );

  testWidgets(
    'admin separates provider fields, masks secret and clears it after saving',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeChatRepository();
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await mount(tester, ChatSettingsScreen(cubit: cubit));
      expect(find.byKey(const Key('chatBaseUrl')), findsNothing);
      await tester.tap(find.byKey(const Key('chatProviderOpenAI')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('chatBaseUrl')),
        'https://example.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('chatModel')),
        'separate-chat',
      );
      await tester.enterText(
        find.byKey(const Key('chatApiKey')),
        'private-key',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chatApiKey')))
            .obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('saveChatSettings')));
      await tester.tap(find.byKey(const Key('saveChatSettings')));
      await tester.pumpAndSettle();
      expect(repository.lastDraft!.apiKey, 'private-key');
      expect(cubit.state.draft.apiKey, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chatApiKey')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('API key stored'), findsOneWidget);
    },
  );

  testWidgets('admin form fits a narrow enlarged dark screen', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeChatRepository();
    final cubit = ChatSettingsCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await mount(
      tester,
      ChatSettingsScreen(cubit: cubit),
      width: 320,
      height: 640,
      scale: 2,
      dark: true,
    );
    expect(tester.takeException(), isNull);
    await revealWorkspaceContent(
      tester,
      find.byKey(const Key('chatProviderOpenAI')),
      scrollable: find.byKey(const Key('chatSettingsScroll')),
    );
    await tester.tap(find.byKey(const Key('chatProviderOpenAI')));
    await tester.pumpAndSettle();
    await revealWorkspaceContent(
      tester,
      find.byKey(const Key('saveChatSettings')),
      scrollable: find.byKey(const Key('chatSettingsScroll')),
    );
    expect(tester.takeException(), isNull);
  });
}
