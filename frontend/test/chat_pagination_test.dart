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
    'a locally created conversation cannot mask a gap in refreshed history',
    () async {
      final repository = FakeChatRepository()
        ..history = List.generate(45, (i) => chatConversation('old-$i'));
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.load(more: true);
      expect(cubit.state.conversationCursor, '40');
      repository.history.insertAll(0, [
        chatConversation('created'),
        ...List.generate(45, (i) => chatConversation('new-$i')),
      ]);
      cubit.editDraft('A new question');
      await cubit.send();
      expect(cubit.state.selected?.id, 'created');
      await cubit.load();
      expect(cubit.state.conversationCursor, '20');
      for (var i = 0; i < 4; i++) {
        await cubit.load(more: true);
      }
      expect(cubit.state.conversations, hasLength(91));
      expect(cubit.state.conversationCursor, isNull);
    },
  );

  test(
    'newly accepted messages cannot mask a gap in refreshed transcript',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [one]
        ..transcript['one'] = List.generate(
          45,
          (i) => chatMessage('$i', sequence: i),
        );
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.select(one);
      await cubit.earlierMessages();
      expect(cubit.state.messageCursor, '40');
      repository.transcript['one']!.addAll(
        List.generate(25, (i) => chatMessage('${i + 45}', sequence: i + 45)),
      );
      cubit.editDraft('A new question');
      await cubit.send();
      expect(cubit.state.messageCursor, '20');
      for (var i = 0; i < 3; i++) {
        await cubit.earlierMessages();
      }
      expect(cubit.state.messages, hasLength(72));
      expect(cubit.state.messageCursor, isNull);
    },
  );

  test(
    'history uses bounded pages and keeps cursors through refresh and failure',
    () async {
      final repository = FakeChatRepository()
        ..history = List.generate(45, (i) => chatConversation('$i'));
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      expect(cubit.state.conversations, hasLength(20));
      expect(cubit.state.conversationCursor, '20');
      await cubit.load(more: true);
      expect(cubit.state.conversations, hasLength(40));
      expect(cubit.state.conversationCursor, '40');
      await cubit.load();
      expect(cubit.state.conversations, hasLength(40));
      expect(cubit.state.conversationCursor, '40');
      repository.historyFailure = const ChatFailure('unavailable');
      await cubit.load(more: true);
      expect(cubit.state.conversations, hasLength(40));
      expect(cubit.state.conversationCursor, '40');
      expect(cubit.state.error, isNotNull);
      repository.historyFailure = null;
      await cubit.load(more: true);
      expect(cubit.state.conversations, hasLength(45));
      expect(cubit.state.conversationCursor, isNull);
      await cubit.load();
      expect(cubit.state.conversations, hasLength(45));
      expect(cubit.state.conversationCursor, isNull);
      expect(repository.historyCursors, [null, '20', null, '40', '40', null]);
    },
  );

  test(
    'empty loaded history discovers a new continuation on refresh',
    () async {
      final repository = FakeChatRepository();
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.conversationCursor, isNull);
      repository.history = List.generate(45, (i) => chatConversation('$i'));
      await cubit.load();
      expect(cubit.state.conversationCursor, isNotNull);
      await cubit.load(more: true);
      await cubit.load(more: true);
      expect(cubit.state.conversations, hasLength(45));
      expect(cubit.state.conversationCursor, isNull);
    },
  );

  test(
    'a full page of new history cannot hide the gap before loaded history',
    () async {
      final repository = FakeChatRepository()
        ..history = List.generate(45, (i) => chatConversation('old-$i'));
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.load(more: true);
      expect(cubit.state.conversationCursor, '40');
      repository.history.insertAll(
        0,
        List.generate(45, (i) => chatConversation('new-$i')),
      );
      await cubit.load();
      expect(cubit.state.conversations, hasLength(60));
      expect(cubit.state.conversationCursor, '20');
      for (var i = 0; i < 4; i++) {
        await cubit.load(more: true);
      }
      expect(cubit.state.conversations, hasLength(90));
      expect(cubit.state.conversationCursor, isNull);
    },
  );

  test(
    'message pages and newest-page gaps retain every loaded message and draft',
    () async {
      final one = chatConversation('one');
      final repository = FakeChatRepository()
        ..history = [one]
        ..transcript['one'] = List.generate(
          45,
          (i) => chatMessage('$i', sequence: i),
        );
      final cubit = ChatCubit(repository, allowed: true)..setActive(true);
      addTearDown(cubit.close);
      await settle();
      await cubit.select(one);
      expect(cubit.state.messages, hasLength(20));
      await cubit.earlierMessages();
      expect(cubit.state.messages, hasLength(40));
      expect(cubit.state.messageCursor, '40');
      cubit.editDraft('Retain question');
      await cubit.refreshMessages();
      expect(cubit.state.messageCursor, '40');
      repository.transcript['one']!.addAll(
        List.generate(25, (i) => chatMessage('${i + 45}', sequence: i + 45)),
      );
      await cubit.refreshMessages();
      expect(cubit.state.messages, hasLength(60));
      expect(cubit.state.messageCursor, '20');
      for (var i = 0; i < 3; i++) {
        await cubit.earlierMessages();
      }
      expect(cubit.state.messages, hasLength(70));
      expect(cubit.state.messageCursor, isNull);
      expect(cubit.state.draft, 'Retain question');
      await cubit.refreshMessages();
      expect(cubit.state.messageCursor, isNull);
    },
  );
}
