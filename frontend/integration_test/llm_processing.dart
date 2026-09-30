import 'dart:convert';

import 'package:domabas/app/http_client.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/presentation/document/widgets/document_properties_panel.dart';
import 'package:domabas/presentation/document/views/document_processing_settings_screen.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'document_fixtures.dart';

Future<void> exerciseLLMProcessing(
  WidgetTester tester, {
  required String sessionToken,
  required Future<void> Function(String) navigate,
}) async {
  const endpoint = String.fromEnvironment('API_BASE_URL');
  const fixtureUrl = String.fromEnvironment('LLM_FIXTURE_URL');
  const fixtureKey = String.fromEnvironment('LLM_FIXTURE_KEY');
  expect(
    fixtureUrl,
    isNotEmpty,
    reason: 'The LLM fixture URL must be supplied to browser E2E.',
  );
  expect(
    fixtureKey,
    isNotEmpty,
    reason: 'The LLM fixture credential must be supplied to browser E2E.',
  );
  final transport = SessionClient(
    createHttpClient(),
    token: sessionToken,
    onUnauthorized: () {},
  );
  final generated = api.ApiClient(basePath: endpoint)..client.close();
  generated.client = transport;
  final documents = api.DocumentsApi(generated);
  final system = api.SystemApi(generated);
  addTearDown(transport.close);

  debugPrint(
    'Property extraction E2E: configure provider, process original, preserve human metadata',
  );
  await navigate('manageDocumentProcessing');
  await _wait(
    tester,
    () => find.text('Installed pipeline').evaluate().isNotEmpty,
    'processing settings loaded',
  );
  expect(find.text('Document ingestion'), findsOneWidget);
  expect(find.text('AI processing'), findsOneWidget);
  final installed = (await documents.getDocumentProcessingConfiguration())!;
  expect(installed.llm!.enabled, isFalse);
  expect(installed.llm!.propertyThinkingEnabled, isFalse);
  expect(installed.llm!.invoiceThinkingEnabled, isFalse);
  expect(installed.llm!.lmStudioCompatibility, isFalse);
  expect(installed.llm!.contextLength, 32768);
  final workloads = (await system.getWorkloadSettings())!;
  final ollama = workloads.resources.singleWhere(
    (resource) => resource.id == 'ollama',
  );
  expect(ollama.limit, inInclusiveRange(1, workloads.ollamaQueueSize ~/ 2));
  expect(
    ollama.maximumLimit,
    lessThanOrEqualTo(workloads.ollamaQueueSize ~/ 2),
  );
  expect(
    workloads.pipelines
        .singleWhere((pipeline) => pipeline.id == 'document_ingestion')
        .resourceIds,
    unorderedEquals(['worker', 'ollama']),
  );
  expect(
    workloads.pipelines
        .singleWhere((pipeline) => pipeline.id == 'paperless')
        .resourceIds,
    ['worker'],
  );
  await _reveal(tester, find.text('Shared resource limits'));
  expect(find.text('Shared resource limits'), findsOneWidget);
  expect(find.byKey(const Key('processingConcurrencySummary')), findsNothing);
  await _reveal(tester, find.byKey(const Key('llmContextLength')));
  await tester.enterText(find.byKey(const Key('llmContextLength')), '16384');
  await _reveal(tester, find.byKey(const Key('llmEnabled')));
  await tester.tap(find.byKey(const Key('llmEnabled')));
  await _reveal(tester, find.byKey(const Key('propertyThinkingEnabled')));
  await tester.tap(find.byKey(const Key('propertyThinkingEnabled')));
  await _reveal(tester, find.byKey(const Key('llmProviderOpenAI')));
  await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
  await tester.pumpAndSettle();
  await _reveal(tester, find.byKey(const Key('llmBaseUrl')));
  await tester.enterText(find.byKey(const Key('llmBaseUrl')), fixtureUrl);
  await _reveal(tester, find.byKey(const Key('llmLMStudioCompatibility')));
  await tester.tap(find.byKey(const Key('llmLMStudioCompatibility')));
  await _reveal(tester, find.byKey(const Key('llmModel')));
  await tester.enterText(find.byKey(const Key('llmModel')), 'fixture-model');
  await _reveal(tester, find.byKey(const Key('llmApiKey')));
  await tester.enterText(find.byKey(const Key('llmApiKey')), fixtureKey);
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<DocumentProcessingSettingsScreen>(
          find.byType(DocumentProcessingSettingsScreen),
        )
        .cubit
        .state
        .llm
        .apiKey
        .isNotEmpty,
    isTrue,
    reason: 'Typing the API key updates the settings draft before scrolling.',
  );
  await _reveal(tester, find.byKey(const Key('saveLLMSettings')));
  final settings = tester
      .widget<DocumentProcessingSettingsScreen>(
        find.byType(DocumentProcessingSettingsScreen),
      )
      .cubit;
  expect(
    settings.state.llm.model,
    'fixture-model',
    reason: 'Entered model reaches the settings draft.',
  );
  expect(
    settings.state.llm.apiKey.isNotEmpty,
    isTrue,
    reason: 'Entered API key reaches the settings draft.',
  );
  expect(settings.state.llm.lmStudioCompatibility, isTrue);
  expect(settings.state.llm.propertyThinkingEnabled, isTrue);
  expect(settings.state.llm.invoiceThinkingEnabled, isFalse);
  expect(
    settings.canSave,
    isTrue,
    reason:
        'The complete external provider draft must be saveable. Error: ${settings.state.error}; valid: ${settings.state.llm.valid}; enabled: ${settings.state.llm.enabled}; provider: ${settings.state.llm.provider}; key present: ${settings.state.llm.apiKey.isNotEmpty}; busy: ${settings.state.loading || settings.state.saving}',
  );
  final saveControl = find.byKey(const Key('saveLLMSettings'));
  await Scrollable.ensureVisible(tester.element(saveControl), alignment: .5);
  await tester.pumpAndSettle();
  final saveBounds = tester.getRect(saveControl);
  await tester.tap(saveControl);
  await _wait(
    tester,
    () => !settings.state.saving,
    'external configuration save completed',
  );
  expect(
    settings.state.error,
    isNull,
    reason: 'External provider settings must be accepted.',
  );
  expect(settings.state.configuration!.llm.credentialConfigured, isTrue);
  expect(tester.getRect(saveControl), saveBounds);
  expect(saveControl.hitTestable(), findsOneWidget);
  expect(settings.state.configuration!.llm.lmStudioCompatibility, isTrue);
  expect(settings.state.configuration!.llm.propertyThinkingEnabled, isTrue);
  expect(settings.state.configuration!.llm.invoiceThinkingEnabled, isFalse);
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('llmApiKey')))
        .controller!
        .text,
    isEmpty,
  );
  await navigate('documentsNavigation');
  await navigate('manageDocumentProcessing');
  for (final choice in [
    ('propertyThinkingEnabled', true),
    ('invoiceThinkingEnabled', false),
  ]) {
    await _reveal(tester, find.byKey(Key(choice.$1)));
    expect(
      tester.widget<SwitchListTile>(find.byKey(Key(choice.$1))).value,
      choice.$2,
    );
  }
  await _reveal(tester, find.byKey(const Key('llmBaseUrl')));
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('llmBaseUrl')))
        .controller!
        .text,
    fixtureUrl,
  );
  await _reveal(tester, find.byKey(const Key('llmLMStudioCompatibility')));
  expect(
    tester
        .widget<SwitchListTile>(
          find.byKey(const Key('llmLMStudioCompatibility')),
        )
        .value,
    isTrue,
  );
  await _reveal(tester, find.byKey(const Key('llmModel')));
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('llmModel')))
        .controller!
        .text,
    'fixture-model',
  );
  await _reveal(tester, find.byKey(const Key('llmApiKey')));
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('llmApiKey')))
        .controller!
        .text,
    isEmpty,
  );
  final saved = (await documents.getDocumentProcessingConfiguration())!;
  expect(saved.llm!.enabled, isTrue);
  expect(saved.llm!.invoiceEnabled, isFalse);
  expect(saved.llm!.propertyThinkingEnabled, isTrue);
  expect(saved.llm!.invoiceThinkingEnabled, isFalse);
  expect(saved.llm!.lmStudioCompatibility, isTrue);
  expect(saved.llm!.credentialConfigured, isTrue);
  expect(saved.llm!.contextLength, 16384);
  expect(
    (await api.ChatApi(generated).getChatAdminConfiguration())!.contextLength,
    32768,
  );
  final configuredWorkloads = (await system.getWorkloadSettings())!;
  final aiResources = configuredWorkloads.pipelines
      .singleWhere((pipeline) => pipeline.id == 'document_ai')
      .resourceIds;
  expect(aiResources, contains('worker'));
  expect(aiResources, isNot(contains('ollama')));
  expect(aiResources, hasLength(2));
  final externalResource = configuredWorkloads.resources.singleWhere(
    (resource) =>
        resource.id == aiResources.singleWhere((id) => id != 'worker'),
  );
  expect(externalResource.label, contains(Uri.parse(fixtureUrl).host));
  await _finishReindex(tester, documents, saved.automaticBatchId);

  for (final invoiceOnly in [true, false]) {
    await _reveal(tester, find.byKey(const Key('invoiceLLMEnabled')));
    await tester.tap(find.byKey(const Key('invoiceLLMEnabled')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('llmEnabled')));
    await tester.tap(find.byKey(const Key('llmEnabled')));
    await tester.pumpAndSettle();
    for (final key in ['invoiceThinkingEnabled', 'propertyThinkingEnabled']) {
      await _reveal(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(settings.state.llm.invoiceEnabled, invoiceOnly);
    expect(settings.state.llm.enabled, !invoiceOnly);
    expect(settings.state.llm.invoiceThinkingEnabled, invoiceOnly);
    expect(settings.state.llm.propertyThinkingEnabled, !invoiceOnly);
    await _reveal(tester, find.byKey(const Key('saveLLMSettings')));
    await tester.tap(find.byKey(const Key('saveLLMSettings')));
    await _wait(
      tester,
      () => !settings.state.saving,
      'independent AI settings saved',
    );
    expect(settings.state.error, isNull);
    final independent = (await documents.getDocumentProcessingConfiguration())!;
    expect(independent.llm!.invoiceEnabled, invoiceOnly);
    expect(independent.llm!.enabled, !invoiceOnly);
    expect(independent.llm!.invoiceThinkingEnabled, invoiceOnly);
    expect(independent.llm!.propertyThinkingEnabled, !invoiceOnly);
    expect(independent.llm!.lmStudioCompatibility, isTrue);
    await _finishReindex(tester, documents, independent.automaticBatchId);
  }

  final title = 'Property extraction ${DateTime.now().microsecondsSinceEpoch}';
  final request =
      http.MultipartRequest(
          'POST',
          Uri.parse('$endpoint/api/v1/documents/upload'),
        )
        ..fields['metadata'] = jsonEncode({
          'title': title,
          'description': 'Written by a person',
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            multipagePdf(),
            filename: 'extraction.pdf',
          ),
        );
  final response = await http.Response.fromStream(
    await transport.send(request),
  );
  expect(response.statusCode, 202, reason: response.body);
  final id =
      (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final processing = (await documents.getDocumentProcessing(id))!;
    if (processing.state.toString() == 'ready') break;
    expect(
      processing.state.toString(),
      isNot('failed'),
      reason: processing.failureCode,
    );
    await tester.pump(const Duration(milliseconds: 500));
  }
  final document = (await documents.getDocument(id))!;
  expect(document.processing!.state.toString(), 'ready');
  await _waitAI(tester, documents, id, 'succeeded');
  final enriched = (await documents.getDocument(id))!;
  expect(enriched.title, title);
  expect(enriched.description, 'Written by a person');
  expect(enriched.sender, 'LLM fixture sender');
  expect(enriched.subject, 'LLM fixture subject');
  expect(enriched.tags, ['llm-extracted']);
  expect(enriched.documentDate, '2026-09-19');
  final jobs = (await documents.listDocumentJobs(documentId: id))!.items;
  final completed = jobs.singleWhere(
    (job) => job.isCurrent && job.pipeline.toString() == 'ingestion',
  );
  expect(completed.status.toString(), 'succeeded');
  expect(completed.configuration!.propertyExtractionEnabled, isTrue);
  expect(completed.configuration!.propertyExtractionModel, 'fixture-model');
  final completedAI = jobs.singleWhere(
    (job) => job.isCurrent && job.pipeline.toString() == 'ai',
  );
  expect(completedAI.status.toString(), 'succeeded');

  await navigate('processingNavigation');
  await _wait(
    tester,
    () => find.text('Shared resource limits').evaluate().isNotEmpty,
    'job scheduling loaded',
  );
  expect(find.text('Shared resource limits'), findsOneWidget);
  expect(find.byKey(const Key('processingConcurrencySummary')), findsNothing);
  await _reveal(tester, find.text('Document ingestion pipeline'));
  expect(find.text('Document ingestion pipeline'), findsOneWidget);
  await _reveal(tester, find.text('AI processing pipeline'));
  expect(find.text('AI processing pipeline'), findsOneWidget);
  await _reveal(tester, find.byKey(const Key('pipeline-filter-ai')));
  await tester.tap(find.byKey(const Key('pipeline-filter-ai')));
  await _wait(
    tester,
    () =>
        find.byKey(Key('job-${completedAI.id}')).evaluate().isNotEmpty &&
        find.byKey(Key('job-${completed.id}')).evaluate().isEmpty,
    'AI attempt appears under its own pipeline filter',
  );
  expect(find.byKey(Key('job-${completed.id}')), findsNothing);

  await navigate('documentsNavigation');
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await _wait(
    tester,
    () => find.text(title).evaluate().isNotEmpty,
    'enriched document visible',
  );
  await tester.tap(find.text(title));
  await _wait(
    tester,
    () => find.byTooltip('Document details').evaluate().isNotEmpty,
    'document viewer loaded',
  );
  await tester.tap(find.byTooltip('Document details'));
  await tester.pumpAndSettle();
  await _wait(
    tester,
    () => find
        .descendant(
          of: find.byType(DocumentPropertiesPanel),
          matching: find.byType(Scrollable),
        )
        .evaluate()
        .isNotEmpty,
    'document properties loaded',
  );
  final propertiesScroll = find
      .descendant(
        of: find.byType(DocumentPropertiesPanel),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text('LLM fixture sender'),
    120,
    scrollable: propertiesScroll,
  );
  expect(find.text('LLM fixture sender'), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text('LLM fixture subject'),
    120,
    scrollable: propertiesScroll,
  );
  expect(find.text('LLM fixture subject'), findsOneWidget);
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await documents.deleteDocument(id);

  final failedTitle = 'AI retry ${DateTime.now().microsecondsSinceEpoch}';
  final failedUpload =
      http.MultipartRequest(
          'POST',
          Uri.parse('$endpoint/api/v1/documents/upload'),
        )
        ..fields['metadata'] = jsonEncode({
          'title': failedTitle,
          'kind': 'email',
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            utf8.encode(
              'From: fixture@example.test\r\n'
              'To: user@example.test\r\n'
              'Subject: AI isolation retry fixture\r\n'
              'MIME-Version: 1.0\r\n'
              'Content-Type: text/plain; charset=utf-8\r\n\r\n'
              'AI isolation retry fixture. This document remains searchable.\r\n',
            ),
            filename: 'ai-isolation.eml',
          ),
        );
  final failedResponse = await http.Response.fromStream(
    await transport.send(failedUpload),
  );
  expect(failedResponse.statusCode, 202, reason: failedResponse.body);
  final failedID =
      (jsonDecode(failedResponse.body) as Map<String, dynamic>)['id'] as String;
  await _waitAI(tester, documents, failedID, 'failed');
  final beforeRetry = (await documents.getDocumentProcessing(failedID))!;
  expect(beforeRetry.state.toString(), 'ready');
  expect(beforeRetry.failureCode, isNull);
  await navigate('documentsNavigation');
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await _wait(
    tester,
    () => find.text(failedTitle).evaluate().isNotEmpty,
    'searchable document with failed AI visible',
  );
  await tester.tap(find.text(failedTitle));
  await _wait(
    tester,
    () => find.byTooltip('Document details').evaluate().isNotEmpty,
    'failed AI document opened',
  );
  await tester.tap(find.byTooltip('Document details'));
  await tester.pumpAndSettle();
  final retry = find.byKey(const Key('retryDocumentAI'));
  final retryScroll = find
      .descendant(
        of: find.byType(DocumentPropertiesPanel),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text('Searchable'),
    160,
    scrollable: retryScroll,
    maxScrolls: 100,
  );
  expect(find.text('Searchable'), findsOneWidget);
  await tester.scrollUntilVisible(
    retry,
    160,
    scrollable: retryScroll,
    maxScrolls: 100,
  );
  await tester.tap(retry);
  await _waitAI(
    tester,
    documents,
    failedID,
    'succeeded',
    afterAttempt: beforeRetry.ai!.attempt,
  );
  final afterRetry = (await documents.getDocumentProcessing(failedID))!;
  expect(afterRetry.state.toString(), 'ready');
  expect(afterRetry.generation, beforeRetry.generation);
  expect(afterRetry.ai!.attempt, greaterThan(beforeRetry.ai!.attempt));
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await documents.deleteDocument(failedID);

  await navigate('manageDocumentProcessing');
  await _wait(
    tester,
    () => settings.active && !settings.state.loading && !settings.state.saving,
    'saved extraction settings are ready to edit',
  );
  expect(settings.state.configuration!.llm.enabled, isTrue);
  await _reveal(tester, find.byKey(const Key('llmEnabled')));
  await tester.tap(find.byKey(const Key('llmEnabled')));
  await tester.pumpAndSettle();
  expect(
    settings.state.llm.enabled,
    isFalse,
    reason: 'The extraction toggle must update the draft before saving.',
  );
  for (final choice in [
    ('propertyThinkingEnabled', installed.llm!.propertyThinkingEnabled),
    ('invoiceThinkingEnabled', installed.llm!.invoiceThinkingEnabled),
  ]) {
    final toggle = find.byKey(Key(choice.$1));
    await _reveal(tester, toggle);
    if (tester.widget<SwitchListTile>(toggle).value != choice.$2) {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
  }
  await _reveal(tester, find.byKey(const Key('llmProviderOllama')));
  await tester.tap(find.byKey(const Key('llmProviderOllama')));
  await _reveal(tester, find.byKey(const Key('llmModel')));
  await tester.enterText(find.byKey(const Key('llmModel')), 'qwen3.5:4b');
  await _reveal(tester, find.byKey(const Key('saveLLMSettings')));
  expect(
    settings.canSave,
    isTrue,
    reason:
        'The disabled internal-provider draft must be saveable: ${settings.state.error}',
  );
  await tester.tap(find.byKey(const Key('saveLLMSettings')));
  await _wait(
    tester,
    () => !settings.state.saving,
    'optional extraction disable save completed',
  );
  expect(settings.state.error, isNull);
  expect(settings.state.configuration!.llm.enabled, isFalse);
  final disabled = (await documents.getDocumentProcessingConfiguration())!;
  expect(disabled.llm!.enabled, isFalse);
  expect(disabled.llm!.credentialConfigured, isFalse);
  expect(
    disabled.llm!.propertyThinkingEnabled,
    installed.llm!.propertyThinkingEnabled,
  );
  expect(
    disabled.llm!.invoiceThinkingEnabled,
    installed.llm!.invoiceThinkingEnabled,
  );
  await _finishReindex(tester, documents, disabled.automaticBatchId);
  await navigate('documentsNavigation');
  expect(tester.takeException(), isNull);
}

Future<void> _finishReindex(
  WidgetTester tester,
  api.DocumentsApi documents,
  String? batchId,
) async {
  if (batchId == null) return;
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  api.DocumentReindexBatch? batch;
  while (DateTime.now().isBefore(deadline)) {
    batch = await documents.getSystemDocumentReindexBatch(batchId);
    if (!{'enumerating', 'running'}.contains(batch!.status.toString())) break;
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(
    batch!.status.toString(),
    'succeeded',
    reason: 'Settings reindex finishes before the next browser scenario.',
  );
}

Future<void> _waitAI(
  WidgetTester tester,
  api.DocumentsApi documents,
  String id,
  String status, {
  int afterAttempt = 0,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  api.DocumentProcessing? processing;
  while (DateTime.now().isBefore(deadline)) {
    processing = (await documents.getDocumentProcessing(id))!;
    expect(
      processing.state.toString(),
      isNot('failed'),
      reason: processing.failureCode,
    );
    if ((processing.ai?.attempt ?? 0) <= afterAttempt) {
      await tester.pump(const Duration(milliseconds: 500));
      continue;
    }
    if (processing.ai?.status.toString() == status) break;
    if (status != 'failed') {
      expect(
        processing.ai?.status.toString(),
        isNot('failed'),
        reason: processing.ai?.failureCode,
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(processing!.state.toString(), 'ready');
  expect(processing.ai?.status.toString(), status);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    return;
  }
  final scroll = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: scroll,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}
