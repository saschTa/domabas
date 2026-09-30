import 'dart:async';

import 'package:domabas/domain/chat/models/chat.dart';
import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/domain/workload/models/workload_settings.dart';
import 'package:domabas/presentation/chat/cubits/chat_settings_cubit.dart';
import 'package:domabas/presentation/chat/views/chat_settings_screen.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_settings_screen.dart';
import 'package:domabas/presentation/workload/cubits/workload_settings_cubit.dart';
import 'package:domabas/presentation/workload/views/workload_settings_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_chat_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_workload_settings_repository.dart';
import '../support/workspace_navigation.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);

  Future<void> mount(WidgetTester tester, double width, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
          child: child!,
        ),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder pageScroll() => find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> reveal(WidgetTester tester, Finder target) async {
    tester.state<ScrollableState>(pageScroll()).position.jumpTo(0);
    await tester.pumpAndSettle();
    await revealWorkspaceContent(tester, target, scrollable: pageScroll());
  }

  Future<void> saveWithoutMovement(
    WidgetTester tester,
    String key,
    VoidCallback finish, {
    bool dialog = false,
  }) async {
    final button = dialog
        ? find.descendant(
            of: find.byType(AppDialog),
            matching: find.byKey(Key(key)),
          )
        : find.byKey(Key(key));
    if (dialog) {
      await tester.ensureVisible(button);
    } else {
      await reveal(tester, button);
    }
    await Scrollable.ensureVisible(tester.element(button), alignment: .5);
    await tester.pumpAndSettle();
    final before = tester.getRect(button);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.getRect(button),
      before,
      reason: 'Save start moved the controls',
    );
    finish();
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(
      tester.getRect(button),
      before,
      reason: 'Save result moved the controls',
    );
    expect(button.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  void dismissNotice(WidgetTester tester, Type screen) =>
      ScaffoldMessenger.of(tester.element(find.byType(screen)))
          .removeCurrentSnackBar();

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final kind in [
      'invoice',
      'property',
      'model',
      'long-model',
      'context',
      'provider',
      'credentials',
      'remove',
      'url',
      'compatibility',
      'ocr',
    ]) {
      testWidgets('processing $kind saves keep controls in place at $width', (
        tester,
      ) async {
        final repository = FakeProcessingRepository();
        if (kind == 'long-model') {
          repository.pipeline = testPipeline(
            propertyExtractionEnabled: true,
            propertyExtractionModel: 'short-model',
            invoiceExtractionEnabled: true,
            invoiceExtractionModel: 'short-model',
          );
          repository.systemConfiguration = DocumentProcessingConfiguration(
            pipeline: repository.pipeline,
            llm: const DocumentLLMConfiguration(
              enabled: true,
              invoiceEnabled: true,
              model: 'short-model',
            ),
          );
        }
        if (['credentials', 'remove', 'url', 'compatibility'].contains(kind)) {
          repository.systemConfiguration = DocumentProcessingConfiguration(
            pipeline: repository.pipeline,
            llm: DocumentLLMConfiguration(
              provider: 'openai',
              baseUrl: 'https://example.test/v1',
              credentialConfigured: kind == 'remove' || kind == 'url',
            ),
          );
        }
        final cubit = DocumentProcessingSettingsCubit(
          repository,
          FakeExternalLinkLauncher(),
          allowed: true,
        )..setActive(true);
        addTearDown(cubit.close);
        await mount(
          tester,
          width,
          DocumentProcessingSettingsScreen(cubit: cubit),
        );
        if (kind == 'long-model') {
          final details = find.text('Configuration 1');
          await reveal(tester, details);
          await tester.tap(details);
          await tester.pumpAndSettle();
          expect(find.text('Configuration fingerprint'), findsOneWidget);
        }
        for (var attempt = 0; attempt < 2; attempt++) {
          switch (kind) {
            case 'invoice':
              cubit.editLLM(invoiceEnabled: attempt == 0);
            case 'property':
              cubit.editLLM(enabled: attempt == 0);
            case 'model':
            case 'long-model':
              final input = find.byKey(const Key('llmModel'));
              await reveal(tester, input);
              await tester.enterText(
                input,
                kind == 'long-model' && attempt == 0
                    ? 'organization-name/${'large-document-extraction-model-' * 3}Q4_K_M:latest'
                    : 'model-$attempt',
              );
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: input,
                        matching: find.byType(EditableText),
                      ),
                    )
                    .focusNode
                    .hasFocus,
                isTrue,
              );
            case 'context':
              cubit.editLLM(contextLength: attempt == 0 ? '65536' : '32768');
            case 'provider':
              cubit.editLLM(
                provider: attempt == 0 ? 'openai' : 'ollama',
                baseUrl: 'https://example.test/v1',
              );
            case 'credentials':
              cubit.editLLM(apiKey: 'test-key-$attempt');
            case 'remove':
              cubit.editLLM(
                clearApiKey: attempt == 0,
                apiKey: attempt == 0 ? '' : 'replacement-key',
              );
            case 'url':
              cubit.editLLM(baseUrl: 'https://service-$attempt.test/v1');
            case 'compatibility':
              cubit.editLLM(lmStudioCompatibility: attempt == 0);
            case 'ocr':
              cubit.edit(language: attempt == 0 ? 'deu' : 'eng');
          }
          await tester.pumpAndSettle();
          expect(cubit.canSave, isTrue);
          final pending = repository.delayedSettingsSave = Completer<void>();
          await saveWithoutMovement(
            tester,
            kind == 'ocr' ? 'saveProcessingSettings' : 'saveLLMSettings',
            pending.complete,
          );
          expect(cubit.state.dirty, isFalse);
          if (kind == 'long-model') {
            expect(
              repository.pipeline.configuration.propertyExtractionEnabled,
              isTrue,
            );
            expect(
              repository.pipeline.configuration.invoiceExtractionEnabled,
              isTrue,
            );
            expect(
              repository.pipeline.configuration.propertyExtractionModel,
              cubit.state.llm.model,
            );
            expect(
              repository.pipeline.configuration.invoiceExtractionModel,
              cubit.state.llm.model,
            );
          }
          expect(find.byType(SnackBar), findsOneWidget);
          dismissNotice(tester, DocumentProcessingSettingsScreen);
          await tester.pumpAndSettle();
        }
        expect(repository.llmUpdates, hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets(
      'workload draining and repeated saves stay in place at $width',
      (tester) async {
        final repository = FakeWorkloadSettingsRepository()
          ..current = testWorkloadSettings(activeOllama: 10);
        final cubit = WorkloadSettingsCubit(repository, allowed: true)
          ..setActive(true);
        addTearDown(cubit.close);
        await mount(tester, width, WorkloadSettingsScreen(cubit: cubit));
        for (final limit in [12, 2]) {
          final input = find.byKey(const Key('workloadLimit-ollama-input'));
          await reveal(tester, input);
          await tester.enterText(input, '$limit');
          await tester.pumpAndSettle();
          final pending = Completer<WorkloadSettings>();
          repository.onWrite = () => pending.future;
          await saveWithoutMovement(
            tester,
            'saveWorkloadSettings',
            () => pending.complete(
              testWorkloadSettings(
                revision: cubit.state.settings!.revision + 1,
                ollamaLimit: limit,
                activeOllama: 10,
              ),
            ),
          );
          expect(cubit.state.dirty, isFalse);
          dismissNotice(tester, WorkloadSettingsScreen);
          await tester.pumpAndSettle();
        }
        expect(repository.writes, hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'extraction dialog saves keep one fixed success notice at $width',
      (tester) async {
        final repository = FakeProcessingRepository();
        final cubit = DocumentProcessingSettingsCubit(
          repository,
          FakeExternalLinkLauncher(),
          allowed: true,
        )..setActive(true);
        addTearDown(cubit.close);
        await mount(
          tester,
          width,
          DocumentProcessingSettingsScreen(cubit: cubit),
        );
        final open = find.text('Edit property extraction');
        await reveal(tester, open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        final dialog = find.byType(AppDialog);
        for (var attempt = 0; attempt < 2; attempt++) {
          final input = find.descendant(
            of: dialog,
            matching: find.byKey(const Key('llmModel')),
          );
          await tester.ensureVisible(input);
          await tester.enterText(input, 'dialog-model-$attempt');
          await tester.pumpAndSettle();
          final closeBefore = tester.getRect(
            find.widgetWithText(TextButton, 'Close'),
          );
          final pending = repository.delayedSettingsSave = Completer<void>();
          await saveWithoutMovement(
            tester,
            'saveLLMSettings',
            pending.complete,
            dialog: true,
          );
          expect(
            tester.getRect(find.widgetWithText(TextButton, 'Close')),
            closeBefore,
          );
          expect(find.text('Settings saved').hitTestable(), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
        }
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        await reveal(tester, open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        await cubit.load(poll: true);
        await tester.pumpAndSettle();
        expect(find.text('Settings saved').hitTestable(), findsNothing);
        await cubit.requestReindex();
        await tester.pumpAndSettle();
        expect(find.text('Settings saved').hitTestable(), findsNothing);
        final pending = repository.delayedSettingsSave = Completer<void>();
        cubit.editLLM(model: 'reopened-dialog-model');
        await tester.pumpAndSettle();
        await saveWithoutMovement(
          tester,
          'saveLLMSettings',
          pending.complete,
          dialog: true,
        );
        expect(find.text('Settings saved').hitTestable(), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await cubit.requestReindex();
        await tester.pumpAndSettle();
        expect(find.text('Settings saved').hitTestable(), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final kind in [
      'model',
      'context',
      'provider',
      'credentials',
      'remove',
      'url',
    ]) {
      testWidgets('chat repeated $kind saves stay in place at $width', (
        tester,
      ) async {
        final repository = FakeChatRepository();
        if (['credentials', 'remove', 'url'].contains(kind)) {
          repository.saved = ChatConfiguration(
            enabled: true,
            provider: 'openai',
            model: 'model',
            baseUrl: 'https://example.test/v1',
            revision: 1,
            hasApiKey: kind != 'credentials',
          );
        }
        final cubit = ChatSettingsCubit(repository, allowed: true)
          ..setActive(true);
        addTearDown(cubit.close);
        await mount(tester, width, ChatSettingsScreen(cubit: cubit));
        for (var attempt = 0; attempt < 2; attempt++) {
          switch (kind) {
            case 'model':
              final input = find.byKey(const Key('chatModel'));
              await reveal(tester, input);
              await tester.enterText(input, 'model-$attempt');
            case 'context':
              cubit.edit(contextLength: attempt == 0 ? '65536' : '32768');
            case 'provider':
              cubit.edit(
                provider: attempt == 0 ? 'openai' : 'ollama',
                baseUrl: 'https://example.test/v1',
              );
            case 'credentials':
              cubit.edit(apiKey: 'key-$attempt');
            case 'remove':
              cubit.edit(
                clearApiKey: attempt == 0,
                apiKey: attempt == 0 ? '' : 'new-key',
              );
            case 'url':
              cubit.edit(baseUrl: 'https://service-$attempt.test/v1');
          }
          await tester.pumpAndSettle();
          final pending = repository.delayedSave =
              Completer<ChatConfiguration>();
          final draft = cubit.state.draft;
          await saveWithoutMovement(
            tester,
            'saveChatSettings',
            () => pending.complete(
              ChatConfiguration(
                enabled: draft.enabled,
                provider: draft.provider,
                model: draft.model,
                baseUrl: draft.provider == 'ollama' ? '' : draft.baseUrl,
                contextLength: draft.contextLengthValue ?? 32768,
                hasApiKey:
                    !draft.clearApiKey &&
                    (draft.apiKey.isNotEmpty ||
                        (cubit.state.saved!.hasApiKey &&
                            cubit.state.saved!.baseUrl == draft.baseUrl)),
                revision: attempt + 2,
              ),
            ),
          );
          expect(cubit.state.dirty, isFalse);
          dismissNotice(tester, ChatSettingsScreen);
          await tester.pumpAndSettle();
        }
        expect(repository.saveCount, 2);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('extraction dialog acknowledges a save confirmed by refresh', (
    tester,
  ) async {
    final repository = FakeProcessingRepository();
    final cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    )..setActive(true);
    addTearDown(cubit.close);
    await mount(tester, 1280, DocumentProcessingSettingsScreen(cubit: cubit));
    final open = find.text('Edit property extraction');
    await reveal(tester, open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    cubit.editLLM(model: 'confirmed-model');
    repository.onUpdate = (language, segmentation, revision) async {
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: testPipeline(
          revision: revision! + 1,
          language: language,
          segmentation: segmentation,
        ),
        llm: const DocumentLLMConfiguration(model: 'confirmed-model'),
      );
      throw const DocumentProcessingFailure(
        DocumentProcessingFailureKind.unavailable,
      );
    };
    await cubit.save();
    await tester.pumpAndSettle();
    expect(cubit.state.reconcileRequired, isTrue);
    expect(find.text('Settings saved').hitTestable(), findsNothing);
    await cubit.load();
    await tester.pumpAndSettle();
    expect(cubit.state.reconcileRequired, isFalse);
    expect(cubit.state.error, isNull);
    expect(find.text('Settings saved').hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'chat does not replay a retained success notice on model discovery',
    (tester) async {
      final repository = FakeChatRepository();
      final cubit = ChatSettingsCubit(repository, allowed: true)
        ..setActive(true);
      addTearDown(cubit.close);
      await mount(tester, 1280, ChatSettingsScreen(cubit: cubit));
      cubit.edit(model: 'saved-model');
      await cubit.save();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, 1280, ChatSettingsScreen(cubit: cubit));
      await cubit.checkModelContext();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
