import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_processing_repository.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final chat in [true, false]) {
      testWidgets(
        '${chat ? 'chat' : 'extraction'} thinking settings work at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final chatRepository = FakeChatRepository()
            ..saved = const ChatConfiguration(
              enabled: false,
              provider: 'ollama',
              model: 'qwen3.5:4b',
              revision: 1,
            );
          final documentRepository = FakeProcessingRepository();
          final chatCubit = ChatSettingsCubit(chatRepository, allowed: true)
            ..setActive(chat);
          final documentCubit = DocumentProcessingSettingsCubit(
            documentRepository,
            FakeExternalLinkLauncher(),
            allowed: true,
          )..setActive(!chat);
          addTearDown(chatCubit.close);
          addTearDown(documentCubit.close);
          await tester.pumpWidget(
            MaterialApp(
              theme: width == 320 ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
                child: child!,
              ),
              home: Scaffold(
                body: chat
                    ? ChatSettingsScreen(cubit: chatCubit)
                    : DocumentProcessingSettingsScreen(cubit: documentCubit),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first;
          Future<void> reveal(String key) async {
            tester.state<ScrollableState>(scrollable).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(Key(key)),
              350,
              scrollable: scrollable,
            );
            await Scrollable.ensureVisible(
              tester.element(find.byKey(Key(key))),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
          }

          Future<void> tap(String key) async {
            await reveal(key);
            await tester.tap(find.byKey(Key(key)));
            await tester.pumpAndSettle();
          }

          final keys = chat
              ? ['chatThinkingEnabled']
              : ['invoiceThinkingEnabled', 'propertyThinkingEnabled'];
          for (final key in keys) {
            await reveal(key);
            final toggle = tester.widget<SwitchListTile>(find.byKey(Key(key)));
            expect(toggle.value, isFalse);
            expect(toggle.onChanged, isNotNull);
          }
          await tap(keys.first);
          expect(chatRepository.saveCount, 0);
          expect(documentRepository.llmUpdates, isEmpty);
          if (!chat) {
            expect(documentCubit.state.llm.invoiceThinkingEnabled, isTrue);
            expect(documentCubit.state.llm.propertyThinkingEnabled, isFalse);
          }
          await tap(chat ? 'chatProviderOpenAI' : 'llmProviderOpenAI');
          for (final key in keys) {
            await reveal(key);
            expect(
              tester.widget<SwitchListTile>(find.byKey(Key(key))).value,
              key == keys.first,
            );
          }
          await tap(chat ? 'chatProviderOllama' : 'llmProviderOllama');
          await tap(chat ? 'saveChatSettings' : 'saveLLMSettings');
          expect(
            chat
                ? chatRepository.saved.thinkingEnabled
                : documentRepository
                      .systemConfiguration!
                      .llm
                      .invoiceThinkingEnabled,
            isTrue,
          );
          await tap(keys.first);
          await tap(chat ? 'resetChatSettings' : 'resetLLMSettings');
          await reveal(keys.first);
          expect(
            tester.widget<SwitchListTile>(find.byKey(Key(keys.first))).value,
            isTrue,
          );
          if (!chat) {
            await tap('propertyThinkingEnabled');
            await tap('saveLLMSettings');
            expect(
              documentRepository
                  .systemConfiguration!
                  .llm
                  .propertyThinkingEnabled,
              isTrue,
            );
            expect(
              documentRepository
                  .systemConfiguration!
                  .llm
                  .invoiceThinkingEnabled,
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
