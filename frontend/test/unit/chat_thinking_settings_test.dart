import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';

void main() {
  test(
    'chat thinking defaults off and saves independently while chat is disabled',
    () async {
      final repository = FakeChatRepository()
        ..saved = const ChatConfiguration(
          enabled: false,
          provider: 'ollama',
          model: 'qwen3.5:4b',
          revision: 1,
        );
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.draft.thinkingEnabled, isFalse);
      for (final enabled in [true, false]) {
        cubit.edit(thinkingEnabled: enabled);
        await cubit.load();
        expect(cubit.state.draft.thinkingEnabled, enabled);
        expect(cubit.state.draft.enabled, isFalse);
        expect(cubit.state.canSave, isTrue);
        await cubit.save();
        expect(repository.lastDraft!.thinkingEnabled, enabled);
        expect(repository.saved.thinkingEnabled, enabled);
        expect(cubit.state.dirty, isFalse);
      }
    },
  );

  test(
    'chat thinking survives provider changes and resets to saved choice',
    () async {
      final repository = FakeChatRepository();
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      cubit.edit(thinkingEnabled: true);
      await cubit.save();
      cubit.edit(
        thinkingEnabled: false,
        provider: 'openai',
        baseUrl: 'https://models.example/v1',
      );
      await cubit.load();
      cubit.edit(provider: 'ollama', baseUrl: '');
      expect(cubit.state.draft.thinkingEnabled, isFalse);
      cubit.reset();
      expect(cubit.state.draft.thinkingEnabled, isTrue);
      expect(cubit.state.dirty, isFalse);
    },
  );
}
