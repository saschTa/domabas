import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
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
  for (final layout in [
    (width: 320.0, scale: 2.0, dark: true),
    (width: 390.0, scale: 1.0, dark: false),
    (width: 1280.0, scale: 1.0, dark: false),
  ]) {
    for (final chat in [true, false]) {
      testWidgets(
        '${chat ? 'chat' : 'pipeline'} context form at ${layout.width}, scale ${layout.scale}',
        (tester) async {
          tester.view.physicalSize = Size(layout.width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final chatRepository = FakeChatRepository()
            ..onModelContext = (model) async =>
                ChatModelContext(model: model, maxContextLength: 8192);
          final documentRepository = FakeProcessingRepository()
            ..onModelContext = (model) async =>
                DocumentModelContext(model: model, maxContextLength: 8192);
          final chatCubit = ChatSettingsCubit(chatRepository, allowed: true)
            ..setActive(chat);
          final documentCubit = DocumentProcessingSettingsCubit(
            documentRepository,
            FakeExternalLinkLauncher(),
            allowed: true,
          )..setActive(!chat);
          final fieldKey = Key(chat ? 'chatContextLength' : 'llmContextLength');
          final checkKey = Key(
            chat ? 'checkChatModelContext' : 'checkLLMModelContext',
          );
          final defaultKey = Key(
            chat ? 'resetChatContextLength' : 'resetLLMContextLength',
          );
          final saveKey = Key(chat ? 'saveChatSettings' : 'saveLLMSettings');
          await tester.pumpWidget(
            MaterialApp(
              theme: layout.dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.scale)),
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
          Future<void> reveal(Key key) async {
            final finder = find.byKey(key);
            tester.state<ScrollableState>(scrollable).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              finder,
              350,
              scrollable: scrollable,
            );
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
          }

          await reveal(fieldKey);
          expect(
            tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
            '32768',
          );
          await reveal(checkKey);
          await tester.tap(find.byKey(checkKey));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Model maximum: 8,192 tokens. Effective context: 8,192 tokens.',
            ),
            findsOneWidget,
          );
          await reveal(fieldKey);
          await tester.enterText(find.byKey(fieldKey), '65536');
          await tester.pumpAndSettle();
          await reveal(saveKey);
          await tester.tap(find.byKey(saveKey));
          await tester.pumpAndSettle();
          expect(
            chat
                ? chatRepository.saved.contextLength
                : documentRepository.systemConfiguration!.llm.contextLength,
            65536,
          );
          await reveal(defaultKey);
          await tester.tap(find.byKey(defaultKey));
          await tester.pumpAndSettle();
          await reveal(fieldKey);
          expect(
            tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
            '32768',
          );
          if (layout.width == 390) {
            await tester.enterText(find.byKey(fieldKey), '');
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextField>(find.byKey(fieldKey))
                  .decoration!
                  .errorText,
              'Enter a whole number from 1,024 to 1,048,576 tokens.',
            );
            await reveal(saveKey);
            expect(
              tester.widget<FilledButton>(find.byKey(saveKey)).onPressed,
              isNull,
            );
            final externalKey = Key(
              chat ? 'chatProviderOpenAI' : 'llmProviderOpenAI',
            );
            await reveal(externalKey);
            await tester.tap(find.byKey(externalKey));
            await tester.pumpAndSettle();
            expect(find.byKey(fieldKey), findsNothing);
            expect(
              find.textContaining(
                'Context length is managed by the external service.',
              ),
              findsOneWidget,
            );
            final ollamaKey = Key(
              chat ? 'chatProviderOllama' : 'llmProviderOllama',
            );
            await reveal(ollamaKey);
            await tester.tap(find.byKey(ollamaKey));
            await tester.pumpAndSettle();
            await reveal(fieldKey);
            expect(
              tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
              isEmpty,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await chatCubit.close();
          await documentCubit.close();
        },
      );
    }
  }
}
