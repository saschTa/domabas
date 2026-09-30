import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_processing_repository.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'requested context has independent defaults and bounded integer validation',
    () {
      expect(const ChatConfigurationDraft().contextLength, '32768');
      expect(const DocumentLLMSettingsDraft().contextLength, '32768');
      for (final invalid in ['', '0', '1023', '1048577', '1.5', '32k']) {
        expect(ChatConfigurationDraft(contextLength: invalid).error, isNotNull);
        expect(DocumentLLMSettingsDraft(contextLength: invalid).valid, isFalse);
      }
      for (final valid in ['1024', '32768', '1048576']) {
        expect(ChatConfigurationDraft(contextLength: valid).error, isNull);
        expect(DocumentLLMSettingsDraft(contextLength: valid).valid, isTrue);
      }
    },
  );

  test(
    'chat preserves invalid refresh drafts, saves requested value and resets',
    () async {
      final repository = FakeChatRepository();
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await settle();
      cubit.edit(contextLength: '');
      await cubit.load();
      expect(cubit.state.draft.contextLength, isEmpty);
      expect(cubit.state.canSave, isFalse);
      cubit.edit(contextLength: '65536');
      await cubit.checkModelContext();
      expect(cubit.state.modelContext!.maxContextLength, 131072);
      await cubit.save();
      expect(repository.saved.contextLength, 65536);
      cubit.edit(contextLength: '32768');
      cubit.reset();
      expect(cubit.state.draft.contextLength, '65536');
    },
  );

  test(
    'chat ignores old model lookups and permits saving during lookup failure',
    () async {
      final pending = Completer<ChatModelContext>();
      final repository = FakeChatRepository()
        ..onModelContext = (_) => pending.future;
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await settle();
      final lookup = cubit.checkModelContext();
      cubit.edit(model: 'new-model', contextLength: '65536');
      pending.complete(
        const ChatModelContext(model: 'qwen3.5:4b', maxContextLength: 8192),
      );
      await lookup;
      expect(cubit.state.modelContext, isNull);
      expect(cubit.state.loadingModelContext, isFalse);
      repository.onModelContext = (_) async =>
          throw const ChatFailure('unavailable');
      await cubit.checkModelContext();
      expect(cubit.state.modelContextError, isNotNull);
      expect(cubit.state.error, isNull);
      expect(cubit.state.canSave, isTrue);
      await cubit.save();
      expect(repository.saved.contextLength, 65536);
    },
  );

  test('chat provider changes and closure fence context responses', () async {
    final pending = Completer<ChatModelContext>();
    final repository = FakeChatRepository()
      ..onModelContext = (_) => pending.future;
    final cubit = ChatSettingsCubit(repository, allowed: true)..setActive(true);
    await settle();
    cubit.edit(contextLength: '65536');
    final lookup = cubit.checkModelContext();
    cubit.edit(provider: 'openai', baseUrl: 'https://example.com/v1');
    expect(cubit.state.draft.contextLength, '65536');
    await cubit.close();
    pending.complete(
      const ChatModelContext(model: 'qwen3.5:4b', maxContextLength: 8192),
    );
    await lookup;
    expect(cubit.state.modelContext, isNull);
  });

  test('pipeline preserves invalid drafts, independent saved context and requested value above maximum', () async {
    final repository = FakeProcessingRepository()
      ..onModelContext = (model) async =>
          DocumentModelContext(model: model, maxContextLength: 8192);
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    )..setActive(true);
    addTearDown(cubit.close);
    await settle();
    cubit.editLLM(contextLength: '');
    await cubit.load();
    expect(cubit.state.llm.contextLength, isEmpty);
    expect(cubit.canSave, isFalse);
    cubit.editLLM(contextLength: '16384');
    await cubit.checkModelContext();
    expect(cubit.state.modelContext!.maxContextLength, 8192);
    expect(cubit.canSave, isTrue);
    await cubit.save();
    expect(repository.systemConfiguration!.llm.contextLength, 16384);
    cubit.editLLM(contextLength: '32768');
    cubit.resetDraft();
    expect(cubit.state.llm.contextLength, '16384');
  });

  test('pipeline ignores stale lookups, keeps errors separate and saves without discovery', () async {
    final pending = Completer<DocumentModelContext>();
    final repository = FakeProcessingRepository()
      ..onModelContext = (_) => pending.future;
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    )..setActive(true);
    addTearDown(cubit.close);
    await settle();
    final lookup = cubit.checkModelContext();
    cubit.editLLM(model: 'new-model', contextLength: '65536');
    pending.complete(
      const DocumentModelContext(model: 'qwen3.5:4b', maxContextLength: 8192),
    );
    await lookup;
    expect(cubit.state.modelContext, isNull);
    expect(cubit.state.loadingModelContext, isFalse);
    repository.onModelContext = (_) async =>
        throw const DocumentProcessingFailure(
          DocumentProcessingFailureKind.unavailable,
        );
    await cubit.checkModelContext();
    expect(cubit.state.modelContextError, isNotNull);
    expect(cubit.state.error, isNull);
    expect(cubit.canSave, isTrue);
    cubit.editLLM(provider: 'openai', baseUrl: 'https://example.com/v1');
    expect(cubit.state.modelContextError, isNull);
    expect(cubit.state.llm.contextLength, '65536');
    await cubit.save();
    expect(repository.systemConfiguration!.llm.contextLength, 65536);
  });
}
