import 'dart:async';

import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';

void main() {
  late FakeProcessingRepository repository;
  late DocumentProcessingSettingsCubit cubit;

  setUp(() async {
    repository = FakeProcessingRepository();
    cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    );
    cubit.setActive(true);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => cubit.close());

  test('defaults are off and OCR-only saves omit extraction updates', () async {
    expect(cubit.state.llm.enabled, isFalse);
    expect(cubit.state.llm.invoiceEnabled, isFalse);
    expect(cubit.state.llm.propertyThinkingEnabled, isFalse);
    expect(cubit.state.llm.invoiceThinkingEnabled, isFalse);
    expect(cubit.state.llm.lmStudioCompatibility, isFalse);
    expect(cubit.state.llm.model, 'qwen3.5:4b');
    expect(cubit.canSave, isFalse);
    cubit.edit(language: 'eng');
    await cubit.save();
    expect(repository.llmUpdates.single, isNull);
  });

  test(
    'thinking choices save independently while extraction is disabled',
    () async {
      for (final choices in [
        (true, false),
        (false, true),
        (true, true),
        (false, false),
      ]) {
        cubit.editLLM(
          propertyThinkingEnabled: choices.$1,
          invoiceThinkingEnabled: choices.$2,
        );
        await cubit.load(poll: true);
        expect(cubit.state.llm.propertyThinkingEnabled, choices.$1);
        expect(cubit.state.llm.invoiceThinkingEnabled, choices.$2);
        expect(cubit.state.llm.enabled, isFalse);
        expect(cubit.state.llm.invoiceEnabled, isFalse);
        expect(cubit.canSave, isTrue);
        await cubit.save();
        expect(repository.llmUpdates.last!.propertyThinkingEnabled, choices.$1);
        expect(repository.llmUpdates.last!.invoiceThinkingEnabled, choices.$2);
        expect(
          cubit.state.configuration!.llm.propertyThinkingEnabled,
          choices.$1,
        );
        expect(
          cubit.state.configuration!.llm.invoiceThinkingEnabled,
          choices.$2,
        );
        expect(cubit.state.dirty, isFalse);
      }
    },
  );

  test(
    'thinking choices survive provider changes and reset to saved values',
    () async {
      cubit.editLLM(propertyThinkingEnabled: true);
      await cubit.save();
      cubit.editLLM(
        propertyThinkingEnabled: false,
        invoiceThinkingEnabled: true,
        provider: 'openai',
        baseUrl: 'https://models.example/v1',
      );
      await cubit.load(poll: true);
      cubit.editLLM(provider: 'ollama');
      expect(cubit.state.llm.propertyThinkingEnabled, isFalse);
      expect(cubit.state.llm.invoiceThinkingEnabled, isTrue);
      cubit.resetDraft();
      expect(cubit.state.llm.propertyThinkingEnabled, isTrue);
      expect(cubit.state.llm.invoiceThinkingEnabled, isFalse);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'LM Studio compatibility alone saves, resets and survives provider changes',
    () async {
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: repository.pipeline,
        llm: const DocumentLLMConfiguration(
          provider: 'openai',
          baseUrl: 'http://127.0.0.1:1234/v1',
        ),
      );
      await cubit.load();
      cubit.editLLM(lmStudioCompatibility: true);
      await cubit.load(poll: true);
      expect(cubit.state.llm.lmStudioCompatibility, isTrue);
      expect(cubit.canSave, isTrue);
      cubit.resetDraft();
      expect(cubit.state.llm.lmStudioCompatibility, isFalse);
      expect(cubit.state.dirty, isFalse);
      cubit.editLLM(lmStudioCompatibility: true);
      await cubit.save();
      expect(repository.llmUpdates.single!.lmStudioCompatibility, isTrue);
      expect(cubit.state.configuration!.llm.lmStudioCompatibility, isTrue);
      expect(cubit.state.dirty, isFalse);
      cubit.editLLM(provider: 'ollama');
      await cubit.save();
      expect(cubit.state.configuration!.llm.lmStudioCompatibility, isTrue);
      cubit.editLLM(provider: 'openai', baseUrl: 'http://127.0.0.1:1234/v1');
      expect(cubit.state.llm.lmStudioCompatibility, isTrue);
    },
  );

  test(
    'uncertain compatibility writes require the saved choice to match',
    () async {
      repository.onUpdate = (_, _, _) async =>
          throw const DocumentProcessingFailure(
            DocumentProcessingFailureKind.unavailable,
          );
      cubit.editLLM(lmStudioCompatibility: true);
      await cubit.save();
      expect(cubit.state.reconcileRequired, isTrue);
      await cubit.load();
      expect(cubit.state.error, contains('differ from your draft'));
      expect(cubit.state.notice, isNull);
      expect(cubit.state.llm.lmStudioCompatibility, isTrue);
      expect(cubit.canSave, isTrue);
      await cubit.save();
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: testPipeline(revision: 2),
        llm: const DocumentLLMConfiguration(lmStudioCompatibility: true),
      );
      await cubit.load();
      expect(cubit.state.notice, contains('Settings confirmed'));
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'invoice and property switches save independently and survive refresh',
    () async {
      for (final choices in [
        (false, true),
        (true, false),
        (true, true),
        (false, false),
      ]) {
        cubit.editLLM(enabled: choices.$1, invoiceEnabled: choices.$2);
        await cubit.load(poll: true);
        expect(cubit.state.llm.enabled, choices.$1);
        expect(cubit.state.llm.invoiceEnabled, choices.$2);
        expect(cubit.canSave, isTrue);
        await cubit.save();
        expect(repository.llmUpdates.last!.enabled, choices.$1);
        expect(repository.llmUpdates.last!.invoiceEnabled, choices.$2);
        expect(cubit.state.configuration!.llm.enabled, choices.$1);
        expect(cubit.state.configuration!.llm.invoiceEnabled, choices.$2);
        expect(cubit.state.dirty, isFalse);
      }
    },
  );

  test('external URL validation prevents unsafe or incomplete submission', () {
    cubit.editLLM(enabled: true, provider: 'openai');
    expect(cubit.canSave, isFalse);
    for (final value in [
      'file:///tmp/model',
      'https://key@host/v1',
      'https://host/v1?key=secret',
      'https://host/#token',
      'https://host:99999/v1',
    ]) {
      cubit.editLLM(baseUrl: value);
      expect(cubit.canSave, isFalse, reason: value);
    }
    cubit.editLLM(baseUrl: 'https://models.example/v1', model: 'local-model');
    expect(cubit.canSave, isTrue);
    cubit.editLLM(model: '');
    expect(cubit.canSave, isFalse);
    cubit.editLLM(model: 'm' * 129);
    expect(cubit.canSave, isFalse);
  });

  test(
    'background refresh preserves draft and key; accepted save clears key',
    () async {
      cubit.editLLM(
        enabled: true,
        provider: 'openai',
        baseUrl: 'https://models.example/v1',
        model: 'custom',
        apiKey: 'private-key',
      );
      await cubit.load(poll: true);
      expect(cubit.state.llm.model, 'custom');
      expect(cubit.state.llm.apiKey, 'private-key');
      await cubit.save();
      expect(repository.llmUpdates.single!.apiKey, 'private-key');
      expect(cubit.state.configuration!.llm.credentialConfigured, isTrue);
      expect(cubit.state.llm.apiKey, isEmpty);
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.notice, contains('Settings saved'));
    },
  );

  test(
    'stored credentials support explicit removal and destination changes',
    () async {
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: repository.pipeline,
        llm: const DocumentLLMConfiguration(
          enabled: true,
          provider: 'openai',
          model: 'custom',
          baseUrl: 'https://models.example/v1',
          credentialConfigured: true,
        ),
      );
      await cubit.load();
      expect(cubit.state.llm.apiKey, isEmpty);
      cubit.editLLM(apiKey: 'replacement');
      cubit.editLLM(clearApiKey: true);
      expect(cubit.state.llm.apiKey, isEmpty);
      await cubit.save();
      expect(repository.llmUpdates.last!.clearApiKey, isTrue);
      expect(cubit.state.configuration!.llm.credentialConfigured, isFalse);
      cubit.editLLM(apiKey: 'new-key');
      await cubit.save();
      cubit.editLLM(baseUrl: 'https://another.example/v1');
      await cubit.save();
      expect(cubit.state.configuration!.llm.credentialConfigured, isFalse);
    },
  );

  test('an uncertain credential write requires refresh without claiming key verification', () async {
    repository.onUpdate = (_, _, _) async =>
        throw const DocumentProcessingFailure(
          DocumentProcessingFailureKind.unavailable,
        );
    cubit.editLLM(
      enabled: true,
      provider: 'openai',
      baseUrl: 'https://models.example/v1',
      apiKey: 'secret',
    );
    await cubit.save();
    expect(cubit.state.reconcileRequired, isTrue);
    expect(cubit.canSave, isFalse);
    repository.systemConfiguration = DocumentProcessingConfiguration(
      pipeline: testPipeline(revision: 2),
      llm: const DocumentLLMConfiguration(
        enabled: true,
        provider: 'openai',
        baseUrl: 'https://models.example/v1',
        credentialConfigured: true,
      ),
    );
    await cubit.load();
    expect(cubit.state.reconcileRequired, isFalse);
    expect(cubit.state.llm.apiKey, isEmpty);
    expect(cubit.state.notice, isNull);
    expect(cubit.state.error, contains('cannot be checked'));
  });

  test('conflicting refresh retains the draft revision until reset', () async {
    cubit.editLLM(enabled: true, model: 'custom');
    repository.pipeline = testPipeline(revision: 2);
    await cubit.load();
    expect(cubit.state.draftRevision, 1);
    expect(cubit.state.llm.model, 'custom');
    cubit.resetDraft();
    expect(cubit.state.draftRevision, isNull);
    expect(cubit.state.llm.model, 'qwen3.5:4b');
  });

  test('refresh cannot confirm a failed credential removal while a key remains stored', () async {
    repository.systemConfiguration = DocumentProcessingConfiguration(
      pipeline: repository.pipeline,
      llm: const DocumentLLMConfiguration(
        provider: 'openai',
        baseUrl: 'https://models.example/v1',
        credentialConfigured: true,
      ),
    );
    await cubit.load();
    repository.onUpdate = (_, _, _) async =>
        throw const DocumentProcessingFailure(
          DocumentProcessingFailureKind.unavailable,
        );
    cubit.editLLM(clearApiKey: true);
    await cubit.save();
    await cubit.load();
    expect(cubit.state.error, contains('differ from your draft'));
    expect(cubit.state.notice, isNull);
    expect(cubit.state.llm.clearApiKey, isTrue);
    expect(cubit.canSave, isTrue);
  });

  test(
    'inactive and unauthorized scopes cannot alter or save settings',
    () async {
      cubit.setActive(false);
      cubit.editLLM(enabled: true);
      await cubit.save();
      expect(repository.llmUpdates, isEmpty);
      final unauthorized = DocumentProcessingSettingsCubit(
        repository,
        FakeExternalLinkLauncher(),
        allowed: false,
      );
      unauthorized.setActive(true);
      final reads = repository.systemReads;
      unauthorized.editLLM(enabled: true);
      await unauthorized.load();
      await unauthorized.save();
      expect(repository.systemReads, reads);
      expect(repository.llmUpdates, isEmpty);
      await unauthorized.close();
    },
  );

  test('retired scope ignores an in-flight save completion', () async {
    final response = Completer<DocumentProcessingConfiguration>();
    repository.onUpdate = (_, _, _) => response.future;
    cubit.editLLM(enabled: true);
    final pending = cubit.save();
    cubit.setActive(false);
    response.complete(
      DocumentProcessingConfiguration(
        pipeline: testPipeline(revision: 2),
        llm: const DocumentLLMConfiguration(enabled: true),
      ),
    );
    await pending;
    expect(cubit.state.configuration!.llm.enabled, isFalse);
    expect(cubit.state.notice, isNull);
  });
}
