import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('new chat drafts use Qwen and saved drafts retain their model', () {
    expect(const ChatConfigurationDraft().model, 'qwen3.5:4b');
    final saved = ChatConfigurationDraft.saved(
      const ChatConfiguration(
        enabled: true,
        provider: 'ollama',
        model: 'gemma3:4b',
        revision: 1,
      ),
    );
    expect(saved.model, 'gemma3:4b');
  });

  test('uncertain acceptance reuses IDs, retains the draft and blocks duplicate sends', () async {
    final repository = FakeChatRepository()
      ..sendFailure = const ChatFailure('unavailable');
    final cubit = ChatCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await settle();
    cubit.editDraft('Find my invoice');
    await cubit.send();
    expect(cubit.state.uncertain, isTrue);
    expect(cubit.state.draft, 'Find my invoice');
    cubit.editDraft('different');
    expect(cubit.state.draft, 'Find my invoice');
    await cubit.send();
    expect(repository.sendRequests, hasLength(1));
    repository.sendFailure = null;
    await cubit.send(reconcile: true);
    expect(repository.createRequests, hasLength(1));
    expect(
      repository.sendRequests[0].requestId,
      repository.sendRequests[1].requestId,
    );
    expect(cubit.state.messages, hasLength(2));
    expect(cubit.state.draft, isEmpty);
    expect(cubit.state.uncertain, isFalse);
    await cubit.stop();
    expect(cubit.state.messages.last.status, 'cancelled');
    cubit.sendAgain(cubit.state.messages.last);
    expect(cubit.state.draft, 'Find my invoice');
    await cubit.send();
    expect(
      repository.sendRequests.last.requestId,
      isNot(repository.sendRequests.first.requestId),
    );
    expect(cubit.state.messages, hasLength(4));
  });

  test(
    'history and transcript continuation survive refresh and draft edits',
    () async {
      final repository = FakeChatRepository()
        ..history = List.generate(25, (i) => chatConversation('$i'));
      repository.transcript['0'] = List.generate(
        25,
        (i) => chatMessage('$i', conversationId: '0', sequence: i),
      );
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.load(more: true);
      expect(cubit.state.conversations, hasLength(25));
      await cubit.select(repository.history.first);
      expect(cubit.state.messages, hasLength(20));
      await cubit.earlierMessages();
      expect(cubit.state.messages, hasLength(25));
      cubit.editDraft('Keep my question');
      await cubit.load();
      expect(cubit.state.conversations, hasLength(25));
      expect(cubit.state.messages, hasLength(25));
      expect(cubit.state.messageCursor, isNull);
      expect(cubit.state.draft, 'Keep my question');
      await cubit.select(repository.history[1]);
      cubit.editDraft('Second question');
      await cubit.select(repository.history.first);
      expect(cubit.state.draft, 'Keep my question');
    },
  );

  test('late conversation reads cannot overwrite a new selection', () async {
    final repository = FakeChatRepository()
      ..history = [chatConversation('one'), chatConversation('two')];
    final cubit = ChatCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await settle();
    final delayed = Completer<ChatPage<ChatMessage>>();
    repository.delayedMessages = delayed;
    final first = cubit.select(repository.history.first);
    await settle();
    await cubit.select(repository.history.last);
    delayed.complete(ChatPage(items: [chatMessage('private-first')]));
    await first;
    expect(cubit.state.selected!.id, 'two');
    expect(cubit.state.messages, isEmpty);
    expect(cubit.state.loadingMessages, isFalse);
  });

  test(
    'push refresh pauses in background and does not poll terminal replies',
    () async {
      final repository = FakeChatRepository()
        ..history = [chatConversation('one')];
      repository.transcript['one'] = [
        chatMessage(
          'answer',
          status: 'running',
          stage: 'waiting_for_ingestion',
        ),
      ];
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.select(repository.history.first);
      final baseline = repository.readCount;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(repository.readCount, baseline);
      cubit.invalidate();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repository.readCount, greaterThan(baseline));
      cubit.setActive(false);
      final count = repository.readCount;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repository.readCount, count);
      repository.transcript['one'] = [
        chatMessage('answer', content: 'Finished'),
      ];
      cubit.setActive(true);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final terminalCount = repository.readCount;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repository.readCount, terminalCount);
    },
  );

  test('settings conflict preserves draft, refresh reconciles, successful save clears secret', () async {
    final repository = FakeChatRepository();
    final cubit = ChatSettingsCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await settle();
    cubit.edit(
      provider: 'openai',
      model: 'chat-model',
      baseUrl: 'https://example.com/v1',
      apiKey: 'private-key',
    );
    repository.saveFailure = const ChatFailure('conflict');
    await cubit.save();
    expect(cubit.state.requiresRefresh, isTrue);
    expect(cubit.state.draft.apiKey, 'private-key');
    expect(cubit.state.canSave, isFalse);
    repository.saved = const ChatConfiguration(
      enabled: true,
      provider: 'ollama',
      model: 'updated',
      revision: 2,
    );
    await cubit.load();
    expect(cubit.state.draft.model, 'chat-model');
    expect(cubit.state.saved!.revision, 2);
    repository.saveFailure = null;
    await cubit.save();
    expect(cubit.state.draft.apiKey, isEmpty);
    expect(cubit.state.saved!.hasApiKey, isTrue);
    expect(cubit.state.saved!.revision, 3);
    expect(cubit.state.notice, contains('saved'));
  });

  test(
    'catalog failure does not erase settings; continuation appends models',
    () async {
      final repository = FakeChatRepository()
        ..modelFailure = const ChatFailure('unavailable');
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await settle();
      expect(cubit.state.saved!.model, 'qwen3.5:4b');
      expect(cubit.state.modelsError, isNotNull);
      repository.modelFailure = null;
      await cubit.loadModels();
      await cubit.loadModels(more: true);
      expect(cubit.state.models, ['qwen3.5:4b', 'qwen3:8b']);
      expect(cubit.state.nextModelOffset, isNull);
    },
  );

  test('forbidden scopes never read and closed reads never emit', () async {
    final repository = FakeChatRepository();
    final forbidden = ChatCubit(repository, allowed: false)..setActive(true);
    await settle();
    expect(repository.historyCursors, isEmpty);
    await forbidden.close();
    final cubit = ChatCubit(repository, allowed: true)..setActive(true);
    await settle();
    repository.history.add(chatConversation('one'));
    final delayed = Completer<ChatPage<ChatMessage>>();
    repository.delayedMessages = delayed;
    final pending = cubit.select(repository.history.first);
    await settle();
    await cubit.close();
    delayed.complete(ChatPage(items: []));
    await pending;
    expect(cubit.isClosed, isTrue);
  });
}
