import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'selected deletion fences history and transcript reads and clears drafts',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [one, chatConversation('two')]
        ..transcript['one'] = [chatMessage('answer', content: 'Old answer')];
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      cubit.editDraft('Unused new conversation draft');
      await cubit.select(one);
      cubit.editDraft('Private question');
      final history = Completer<ChatPage<ChatConversation>>();
      final messages = Completer<ChatPage<ChatMessage>>();
      repository.delayedHistory = history;
      repository.delayedMessages = messages;
      final refreshHistory = cubit.load();
      final refreshMessages = cubit.refreshMessages();
      await settle();
      await cubit.deleteConversation(one);
      history.complete(ChatPage(items: [one]));
      messages.complete(ChatPage(items: [chatMessage('stale')]));
      await Future.wait([refreshHistory, refreshMessages]);
      expect(cubit.state.conversations.map((item) => item.id), ['two']);
      expect(cubit.state.selected, isNull);
      expect(cubit.state.messages, isEmpty);
      expect(cubit.state.draft, isEmpty);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.loadingMessages, isFalse);
      expect(cubit.state.deletingConversationId, isNull);
      cubit.newConversation();
      expect(cubit.state.draft, isEmpty);
    },
  );

  test(
    'unselected deletion retains selection, transcript, draft and continuation',
    () async {
      final repository = FakeChatRepository()
        ..history = List.generate(45, (i) => chatConversation('$i'))
        ..transcript['0'] = List.generate(
          45,
          (i) => chatMessage('$i', conversationId: '0', sequence: i),
        );
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.load(more: true);
      final deleted = repository.history[39];
      await cubit.select(deleted);
      cubit.editDraft('Deleted draft');
      await cubit.select(repository.history.first);
      await cubit.earlierMessages();
      cubit.editDraft('Keep this question');
      final conversationCursor = cubit.state.conversationCursor;
      final messageCursor = cubit.state.messageCursor;
      await cubit.deleteConversation(deleted);
      expect(cubit.state.selected?.id, '0');
      expect(cubit.state.messages, hasLength(40));
      expect(cubit.state.draft, 'Keep this question');
      expect(cubit.state.conversations, hasLength(39));
      expect(cubit.state.conversationCursor, conversationCursor);
      expect(cubit.state.messageCursor, messageCursor);
      repository.history.add(deleted);
      await cubit.select(deleted);
      expect(cubit.state.draft, isEmpty);
    },
  );

  test('pending deletion blocks writes and selection; failure retains state for retry', () async {
    final one = chatConversation('one');
    final two = chatConversation('two');
    final deletion = Completer<void>();
    final repository = FakeChatRepository()
      ..history = [one, two]
      ..transcript['one'] = [chatMessage('answer', content: 'Saved answer')]
      ..delayedDelete = deletion
      ..deleteFailure = const ChatFailure('unavailable');
    final cubit = ChatCubit(repository, allowed: true)..setActive(true);
    addTearDown(cubit.close);
    await settle();
    await cubit.select(one);
    cubit.editDraft('Keep question on failure');
    final pending = cubit.deleteConversation(one);
    expect(cubit.state.deletingConversationId, 'one');
    expect(cubit.state.canSend, isFalse);
    expect(cubit.state.canManageConversations, isFalse);
    await cubit.send();
    await cubit.select(two);
    await cubit.deleteConversation(two);
    cubit.newConversation();
    cubit.editDraft('Other question');
    expect(repository.sendRequests, isEmpty);
    expect(repository.deleteRequests, ['one']);
    expect(cubit.state.selected?.id, 'one');
    expect(cubit.state.draft, 'Keep question on failure');
    deletion.complete();
    await pending;
    expect(cubit.state.deletingConversationId, isNull);
    expect(cubit.state.deleteError, contains('Could not delete'));
    expect(cubit.state.messages.single.content, 'Saved answer');
    expect(cubit.state.draft, 'Keep question on failure');
    expect(cubit.state.canSend, isTrue);
    repository.deleteFailure = null;
    await cubit.deleteConversation(one);
    expect(repository.deleteRequests, ['one', 'one']);
    expect(cubit.state.deleteError, isNull);
    expect(cubit.state.selected, isNull);
  });

  test(
    'already deleted conversation reconciles an uncertain delete retry',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [one]
        ..deleteFailure = const ChatFailure('not_found');
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.select(one);
      await cubit.deleteConversation(one);
      expect(cubit.state.conversations, isEmpty);
      expect(cubit.state.selected, isNull);
      expect(cubit.state.deleteError, isNull);
    },
  );

  test(
    'uncertain send must be reconciled before deleting any conversation',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [one]
        ..sendFailure = const ChatFailure('unavailable');
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.select(one);
      cubit.editDraft('Uncertain question');
      await cubit.send();
      await cubit.deleteConversation(one);
      expect(repository.deleteRequests, isEmpty);
      expect(cubit.state.uncertain, isTrue);
      expect(cubit.state.draft, 'Uncertain question');
    },
  );

  test(
    'closed and unauthorized cubits cannot publish or request deletion',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()..history = [one];
      final forbidden = ChatCubit(repository, allowed: false)..setActive(true);
      await forbidden.deleteConversation(one);
      expect(repository.deleteRequests, isEmpty);
      await forbidden.close();
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      await settle();
      final deletion = Completer<void>();
      repository.delayedDelete = deletion;
      final pending = cubit.deleteConversation(one);
      await cubit.close();
      deletion.complete();
      await pending;
      expect(cubit.isClosed, isTrue);
    },
  );
}
