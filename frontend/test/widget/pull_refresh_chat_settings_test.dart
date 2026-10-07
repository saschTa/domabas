import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas/presentation/paperless/cubits/paperless_settings_cubit.dart';
import 'package:domabas/presentation/paperless/views/paperless_settings_screen.dart';
import 'package:domabas/presentation/workload/cubits/workload_settings_cubit.dart';
import 'package:domabas/presentation/workload/views/workload_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_paperless_settings_repository.dart';
import '../support/fake_workload_settings_repository.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pull(WidgetTester tester, String key) async {
  await tester.pumpAndSettle();
  final list = find.byKey(Key(key));
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      )
      .position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  await tester.dragFrom(
    tester.getTopLeft(list) + const Offset(12, 24),
    const Offset(0, 500),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'pulling a short chat preserves the composer and awaits refresh at $width',
      (tester) async {
        final repository = FakeChatRepository();
        final cubit = ChatCubit(repository, allowed: true)..setActive(true);
        addTearDown(cubit.close);
        await _mount(
          tester,
          ChatScreen(cubit: cubit, libraryName: 'Personal'),
          width: width,
        );
        final composer = find.byKey(const Key('chatMessage'));
        await tester.enterText(composer, 'Keep this question');
        final controller = tester.widget<TextField>(composer).controller;
        final pending = repository.delayedHistory = Completer();
        final reads = repository.historyCursors.length;
        await _pull(tester, 'chatTranscript');
        expect(repository.historyCursors.length, reads + 1);
        expect(cubit.state.loading, isTrue);
        expect(tester.widget<TextField>(composer).controller, same(controller));
        expect(controller!.text, 'Keep this question');
        expect(find.byKey(const Key('refreshChat')), findsNothing);
        pending.complete(ChatPage(items: [chatConversation('new')]));
        await tester.pumpAndSettle();
        expect(cubit.state.loading, isFalse);
        expect(cubit.state.conversations.single.id, 'new');
        expect(cubit.state.draft, 'Keep this question');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'pulling chat history preserves loaded pages and draft at $width',
      (tester) async {
        final repository = FakeChatRepository()
          ..history = List.generate(25, (index) => chatConversation('$index'));
        final cubit = ChatCubit(repository, allowed: true)..setActive(true);
        addTearDown(cubit.close);
        await _mount(
          tester,
          ChatScreen(cubit: cubit, libraryName: 'Personal'),
          width: width,
        );
        await cubit.load(more: true);
        cubit.editDraft('Unsent question');
        await tester.pumpAndSettle();
        if (width < 850) {
          await tester.tap(find.byKey(const Key('chatHistory')));
          await tester.pumpAndSettle();
        }
        repository.history.insert(0, chatConversation('new'));
        final reads = repository.historyCursors.length;
        await _pull(tester, 'chatHistoryList');
        await tester.pumpAndSettle();
        expect(repository.historyCursors.length, reads + 1);
        expect(cubit.state.conversations, hasLength(26));
        expect(
          cubit.state.conversations.any((item) => item.id == '24'),
          isTrue,
        );
        expect(cubit.state.draft, 'Unsent question');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pulling chat settings updates saved data and keeps the edited model',
    (tester) async {
      final repository = FakeChatRepository();
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await _mount(tester, ChatSettingsScreen(cubit: cubit));
      final field = find.byKey(const Key('chatModel'));
      await tester.enterText(field, 'draft-model');
      final controller = tester.widget<TextField>(field).controller;
      repository.saved = const ChatConfiguration(
        enabled: true,
        provider: 'ollama',
        model: 'new-saved-model',
        revision: 2,
      );
      await _pull(tester, 'chatSettingsScroll');
      await tester.pumpAndSettle();
      expect(cubit.state.saved!.revision, 2);
      expect(cubit.state.draft.model, 'draft-model');
      expect(tester.widget<TextField>(field).controller, same(controller));
      expect(find.byKey(const Key('refreshChatSettings')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pulling workload limits preserves the edited field', (
    tester,
  ) async {
    final repository = FakeWorkloadSettingsRepository();
    final cubit = WorkloadSettingsCubit(repository, allowed: true)
      ..setActive(true);
    addTearDown(cubit.close);
    await _mount(tester, WorkloadSettingsScreen(cubit: cubit));
    await tester.enterText(
      find.byKey(const ValueKey('workloadLimit-worker-input')),
      '7',
    );
    repository.current = testWorkloadSettings(
      revision: 2,
      workerLimit: 5,
      ollamaLimit: 12,
    );
    final reads = repository.reads;
    await _pull(tester, 'workloadSettingsScroll');
    await tester.pumpAndSettle();
    expect(repository.reads, reads + 1);
    expect(cubit.state.settings!.revision, 2);
    expect(cubit.state.drafts['worker'], '7');
    expect(cubit.state.drafts['ollama'], '12');
    expect(find.byKey(const Key('refreshWorkloadSettings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pulling Paperless settings preserves the parallelism draft', (
    tester,
  ) async {
    final repository = FakePaperlessSettingsRepository();
    final cubit = PaperlessSettingsCubit(repository, allowed: true)
      ..setActive(true);
    addTearDown(cubit.close);
    await _mount(tester, PaperlessSettingsScreen(cubit: cubit));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    repository.current = testPaperlessSettings(concurrency: 2, revision: 2);
    final reads = repository.reads;
    await _pull(tester, 'paperlessSettingsScroll');
    await tester.pumpAndSettle();
    expect(repository.reads, reads + 1);
    expect(cubit.state.settings!.revision, 2);
    expect(cubit.state.retrievalConcurrency, 4);
    expect(find.byKey(const Key('refreshPaperlessSettings')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
