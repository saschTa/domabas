import 'dart:convert';

import 'package:domabas/app/http_client.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/presentation/chat/views/chat_screen.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pdf;

Future<void> exerciseAIChat(
  WidgetTester tester, {
  required String sessionToken,
  required Future<void> Function(String) navigate,
  required Future<void> Function() remount,
}) async {
  const endpoint = String.fromEnvironment('API_BASE_URL');
  const fixtureUrl = String.fromEnvironment('LLM_FIXTURE_URL');
  const fixtureKey = String.fromEnvironment('LLM_FIXTURE_KEY');
  expect(fixtureUrl, isNotEmpty);
  expect(fixtureKey, isNotEmpty);
  debugPrint('AI chat E2E: loading independent configuration');
  final transport = SessionClient(
    createHttpClient(),
    token: sessionToken,
    onUnauthorized: () {},
  );
  final generated = api.ApiClient(basePath: endpoint)..client.close();
  generated.client = transport;
  final documents = api.DocumentsApi(generated), chat = api.ChatApi(generated);
  addTearDown(transport.close);
  final original = (await chat.getChatAdminConfiguration())!;
  expect(original.contextLength, 32768);
  expect(original.thinkingEnabled, isFalse);
  expect(
    original.hasApiKey,
    isFalse,
    reason: 'The disposable chat fixture starts with the internal default.',
  );
  final processingBefore = (await documents
      .getDocumentProcessingConfiguration())!;
  final title = 'Chat evidence ${DateTime.now().microsecondsSinceEpoch}';
  debugPrint('AI chat E2E: uploading a two-page PDF');
  final evidence = pdf.Document()
    ..addPage(
      pdf.Page(
        build: (_) =>
            pdf.Text('Chat evidence: the reference amount is 42 euros.'),
      ),
    )
    ..addPage(
      pdf.Page(
        build: (_) =>
            pdf.Text('Supporting note: the amount includes delivery.'),
      ),
    );
  final upload =
      http.MultipartRequest(
          'POST',
          Uri.parse('$endpoint/api/v1/documents/upload'),
        )
        ..fields['metadata'] = jsonEncode({'title': title})
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            await evidence.save(),
            filename: 'chat-evidence.pdf',
          ),
        );
  final uploaded = await http.Response.fromStream(await transport.send(upload));
  expect(uploaded.statusCode, 202, reason: uploaded.body);
  final documentId =
      (jsonDecode(uploaded.body) as Map<String, dynamic>)['id'] as String;
  String? conversationId;
  final historyIds = <String>[];
  var configurationChanged = false;
  Object? failure;
  StackTrace? failureStack;
  try {
    debugPrint('AI chat E2E: waiting for document evidence ingestion');
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final state = (await documents.getDocumentProcessing(documentId))!;
      if (state.state.toString() == 'ready') break;
      expect(
        state.state.toString(),
        isNot('failed'),
        reason: 'Chat evidence ingestion failed: ${state.failureCode}',
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      (await documents.getDocumentProcessing(documentId))!.state.toString(),
      'ready',
      reason: 'Chat evidence was not searchable before the ingestion deadline.',
    );
    debugPrint(
      'AI chat E2E: independent provider settings, durable reply, document tools and saved history',
    );
    await navigate('manageChat');
    await _wait(
      tester,
      () => find.byKey(const Key('chatProviderOpenAI')).evaluate().isNotEmpty,
      'Chat settings loaded',
    );
    await _revealSetting(tester, 'chatThinkingEnabled');
    await tester.tap(find.byKey(const Key('chatThinkingEnabled')));
    await _revealSetting(tester, 'chatContextLength');
    await tester.enterText(find.byKey(const Key('chatContextLength')), '65536');
    await _revealSetting(tester, 'chatProviderOpenAI');
    await tester.tap(find.byKey(const Key('chatProviderOpenAI')));
    await tester.pumpAndSettle();
    for (final field in [
      ('chatBaseUrl', fixtureUrl),
      ('chatModel', 'chat-fixture-model'),
      ('chatApiKey', fixtureKey),
    ]) {
      await _revealSetting(tester, field.$1);
      await tester.enterText(find.byKey(Key(field.$1)), field.$2);
    }
    final settings = tester
        .widget<ChatSettingsScreen>(find.byType(ChatSettingsScreen))
        .cubit;
    await _revealSetting(tester, 'saveChatSettings');
    configurationChanged = true;
    await tester.tap(find.byKey(const Key('saveChatSettings')));
    await _wait(tester, () => !settings.state.saving, 'Chat settings saved');
    expect(settings.state.error, isNull);
    expect(settings.state.saved!.hasApiKey, isTrue);
    expect(settings.state.saved!.thinkingEnabled, isTrue);
    expect(settings.state.draft.apiKey, isEmpty);
    final saved = (await chat.getChatAdminConfiguration())!;
    expect(saved.contextLength, 65536);
    expect(saved.thinkingEnabled, isTrue);
    final processingAfter = (await documents
        .getDocumentProcessingConfiguration())!;
    expect(processingAfter.llm!.provider, processingBefore.llm!.provider);
    expect(processingAfter.llm!.model, processingBefore.llm!.model);
    expect(processingAfter.llm!.enabled, processingBefore.llm!.enabled);
    expect(
      processingAfter.llm!.propertyThinkingEnabled,
      processingBefore.llm!.propertyThinkingEnabled,
    );
    expect(
      processingAfter.llm!.invoiceThinkingEnabled,
      processingBefore.llm!.invoiceThinkingEnabled,
    );
    expect(
      processingAfter.llm!.contextLength,
      processingBefore.llm!.contextLength,
    );
    await navigate('chatNavigation');
    await _wait(
      tester,
      () =>
          find.byType(ChatScreen).evaluate().isNotEmpty &&
          tester
                  .widget<ChatScreen>(find.byType(ChatScreen))
                  .cubit
                  .state
                  .configuration !=
              null,
      'Chat workspace ready',
    );
    final cubit = tester.widget<ChatScreen>(find.byType(ChatScreen)).cubit;
    await tester.enterText(
      find.byKey(const Key('chatMessage')),
      'Find the Chat evidence document and tell me its reference amount.',
    );
    await tester.pumpAndSettle();
    expect(
      cubit.state.canSend,
      isTrue,
      reason:
          'The complete chat draft is ready to submit: ${cubit.state.error}',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('sendChatMessage')))
          .onPressed,
      isNotNull,
      reason: 'The send button reflects the entered draft before tapping.',
    );
    debugPrint('AI chat E2E: submitting a question');
    await tester.tap(find.byKey(const Key('sendChatMessage')));
    await _wait(
      tester,
      () =>
          cubit.state.messages.any((message) => message.role == 'assistant') ||
          (!cubit.state.sending && cubit.state.error != null),
      'Chat question accepted',
    );
    expect(
      cubit.state.error,
      isNull,
      reason: 'Chat submission must be accepted before waiting for an answer.',
    );
    debugPrint('AI chat E2E: waiting for the accepted durable reply');
    await _wait(
      tester,
      () => cubit.state.messages.any(
        (message) =>
            message.role == 'assistant' &&
            ['completed', 'failed'].contains(message.status),
      ),
      'Durable assistant reply completed',
    );
    final answer = cubit.state.messages.last;
    expect(answer.status, 'completed', reason: answer.failureCode);
    expect(answer.content, contains('42 euros'));
    expect(
      answer.sources.map((source) => source.documentId),
      contains(documentId),
    );
    conversationId = cubit.state.selected!.id;
    final citation = find.byKey(
      ValueKey('chatSource-${answer.id}-$documentId'),
    );
    await tester.ensureVisible(citation);
    await tester.tap(citation);
    await _wait(
      tester,
      () => find.byKey(const Key('documentDetails')).evaluate().isNotEmpty,
      'Source opened in document viewer',
    );
    await tester.tap(find.byKey(const Key('closeDocument')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    debugPrint('AI chat E2E: creating a second page of conversation history');
    final seed = DateTime.now().microsecondsSinceEpoch;
    for (var index = 0; index < 21; index++) {
      final suffix = (seed + index).toRadixString(16).padLeft(16, '0');
      final created = (await chat.createChatConversation(
        api.CreateChatConversationRequest(
          requestId:
              'c0ffee00-0000-4000-8000-${suffix.substring(suffix.length - 12)}',
        ),
      ))!;
      historyIds.add(created.id);
    }
    await remount();
    await navigate('chatNavigation');
    await _wait(
      tester,
      () =>
          find.byType(ChatScreen).evaluate().isNotEmpty &&
          tester.widget<ChatScreen>(find.byType(ChatScreen)).cubit.state.loaded,
      'Saved history loaded',
    );
    await tester.tap(find.byKey(const Key('chatHistory')));
    await tester.pumpAndSettle();
    final restored = tester.widget<ChatScreen>(find.byType(ChatScreen)).cubit;
    expect(restored.state.conversations.length, 20);
    expect(restored.state.conversationCursor, isNotNull);
    expect(
      restored.state.conversations.any((item) => item.id == conversationId),
      isFalse,
    );
    final historyScroll = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .last;
    final older = find.descendant(
      of: find.byType(Dialog),
      matching: find.byKey(const Key('olderChatConversations')),
    );
    await tester.scrollUntilVisible(older, 300, scrollable: historyScroll);
    await tester.pumpAndSettle();
    await tester.tap(older);
    await _wait(
      tester,
      () =>
          restored.state.conversations.any((item) => item.id == conversationId),
      'Older conversation page loaded',
    );
    final row = find.descendant(
      of: find.byType(Dialog),
      matching: find.byKey(ValueKey('chatConversation-$conversationId')),
    );
    await tester.scrollUntilVisible(row, 300, scrollable: historyScroll);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await _wait(
      tester,
      () => restored.state.messages.any((message) => message.id == answer.id),
      'Saved transcript restored',
    );
    expect(restored.state.messages.last.content, answer.content);
    await restored.load();
    expect(restored.state.conversations.length, 22);
    expect(restored.state.conversationCursor, isNull);
    debugPrint('AI chat E2E: deleting a saved conversation from history');
    await tester.tap(find.byKey(const Key('chatHistory')));
    await tester.pumpAndSettle();
    final delete = find.descendant(
      of: find.byType(Dialog),
      matching: find.byKey(ValueKey('deleteChatConversation-$conversationId')),
    );
    await tester.scrollUntilVisible(delete, 300, scrollable: historyScroll);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteChatConversation')));
    await _wait(
      tester,
      () => !restored.state.conversations.any(
        (item) => item.id == conversationId,
      ),
      'Deleted conversation removed from history',
    );
    expect(restored.state.selected, isNull);
    expect(restored.state.messages, isEmpty);
    final deleted = await chat.getChatConversationWithHttpInfo(conversationId);
    expect(deleted.statusCode, 404);
    conversationId = null;
    await tester.tap(find.byTooltip('Close history'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await navigate('documentsNavigation');
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    Future<void> cleanup(String name, Future<void> Function() work) async {
      try {
        await work();
      } catch (error, stack) {
        debugPrint(
          'AI chat E2E cleanup failed for $name: ${error.runtimeType}',
        );
        if (failure == null) {
          failure = error;
          failureStack = stack;
        }
      }
    }

    if (conversationId != null) {
      await cleanup(
        'conversation',
        () => chat.deleteChatConversation(conversationId!),
      );
    }
    for (final id in historyIds) {
      await cleanup(
        'history conversation',
        () => chat.deleteChatConversation(id),
      );
    }
    await cleanup(
      'document evidence',
      () => documents.deleteDocument(documentId),
    );
    if (configurationChanged) {
      await cleanup('chat configuration', () async {
        final current = (await chat.getChatAdminConfiguration())!;
        final restored = (await chat.updateChatConfiguration(
          api.UpdateChatConfigurationRequest(
            expectedRevision: current.revision,
            enabled: original.enabled,
            thinkingEnabled: original.thinkingEnabled,
            provider: original.provider.toString() == 'openai'
                ? api.UpdateChatConfigurationRequestProviderEnum.openai
                : api.UpdateChatConfigurationRequestProviderEnum.ollama,
            model: original.model,
            baseUrl: original.baseUrl,
            contextLength: original.contextLength,
            clearApiKey: true,
          ),
        ))!;
        expect(restored.thinkingEnabled, original.thinkingEnabled);
      });
    }
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
}

Future<void> _revealSetting(WidgetTester tester, String key) async {
  await Scrollable.ensureVisible(
    tester.element(find.byKey(Key(key))),
    alignment: .5,
  );
  await tester.pumpAndSettle();
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: reason);
  await tester.pump();
}
