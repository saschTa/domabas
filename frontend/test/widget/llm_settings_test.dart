import 'dart:async';

import 'package:domabas/domain/document/models/document_processing.dart';
import 'package:domabas/presentation/document/cubits/document_processing_settings_cubit.dart';
import 'package:domabas/presentation/document/views/document_processing_settings_screen.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas/presentation/document/widgets/property_extraction_settings.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_processing_repository.dart';

void main() {
  late FakeProcessingRepository repository;
  late DocumentProcessingSettingsCubit cubit;
  setUp(() {
    repository = FakeProcessingRepository();
    cubit = DocumentProcessingSettingsCubit(
      repository,
      FakeExternalLinkLauncher(),
      allowed: true,
    );
    cubit.setActive(true);
  });
  tearDown(() => cubit.close());

  Future<void> mount(
    WidgetTester tester, {
    double width = 800,
    double scale = 1,
    bool dark = false,
    bool screen = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: screen
              ? DocumentProcessingSettingsScreen(cubit: cubit)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child:
                      BlocBuilder<
                        DocumentProcessingSettingsCubit,
                        DocumentProcessingSettingsState
                      >(
                        bloc: cubit,
                        builder: (context, state) => state.configuration == null
                            ? const SizedBox.shrink()
                            : AppSurface(
                                child: PropertyExtractionSettings(
                                  cubit: cubit,
                                  state: state,
                                ),
                              ),
                      ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'LM Studio compatibility appears for external services and saves explicitly',
    (tester) async {
      await mount(tester);
      final toggle = find.byKey(const Key('llmLMStudioCompatibility'));
      expect(toggle, findsNothing);
      await reveal(tester, 'llmProviderOpenAI');
      await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
      await tester.pumpAndSettle();
      await reveal(tester, 'llmBaseUrl');
      await tester.enterText(
        find.byKey(const Key('llmBaseUrl')),
        'http://127.0.0.1:1234/v1',
      );
      await reveal(tester, 'llmLMStudioCompatibility');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        tester.getTopLeft(find.byKey(const Key('llmBaseUrl'))).dy,
        lessThan(tester.getTopLeft(toggle).dy),
      );
      expect(
        tester.getTopLeft(toggle).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('llmModel'))).dy),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.llmUpdates, isEmpty);
      expect(cubit.state.dirty, isTrue);
      await cubit.load(poll: true);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await reveal(tester, 'llmProviderOllama');
      await tester.tap(find.byKey(const Key('llmProviderOllama')));
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await reveal(tester, 'saveLLMSettings');
      await tester.tap(find.byKey(const Key('saveLLMSettings')));
      await tester.pumpAndSettle();
      expect(repository.llmUpdates.single!.lmStudioCompatibility, isTrue);
      expect(cubit.state.dirty, isFalse);
      await reveal(tester, 'llmLMStudioCompatibility');
      await tester.tap(toggle);
      await reveal(tester, 'resetLLMSettings');
      await tester.tap(find.byKey(const Key('resetLLMSettings')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(cubit.state.dirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('AI settings remain editable and save during pipeline refresh', (
    tester,
  ) async {
    await mount(tester);
    final previous = cubit.state.configuration!;
    final pending = Completer<DocumentProcessingConfiguration>();
    repository.onConfiguration = () => pending.future;
    final refresh = cubit.load(poll: true);
    await tester.pump();
    await reveal(tester, 'invoiceLLMEnabled');
    await tester.tap(find.byKey(const Key('invoiceLLMEnabled')));
    await reveal(tester, 'llmModel');
    await tester.enterText(
      find.byKey(const Key('llmModel')),
      'replacement-model',
    );
    await reveal(tester, 'llmContextLength');
    await tester.enterText(find.byKey(const Key('llmContextLength')), '65536');
    await reveal(tester, 'saveLLMSettings');
    expect(cubit.state.loading, isFalse);
    expect(cubit.canSave, isTrue);
    repository.onConfiguration = null;
    await tester.tap(find.byKey(const Key('saveLLMSettings')));
    await tester.pumpAndSettle();
    pending.complete(previous);
    await refresh;
    await tester.pumpAndSettle();
    expect(repository.llmUpdates.single!.invoiceEnabled, isTrue);
    expect(repository.llmUpdates.single!.model, 'replacement-model');
    expect(repository.llmUpdates.single!.contextLength, '65536');
    expect(cubit.state.configuration!.llm.invoiceEnabled, isTrue);
    expect(cubit.state.configuration!.llm.model, 'replacement-model');
    expect(cubit.state.configuration!.llm.contextLength, 65536);
    expect(cubit.state.dirty, isFalse);
    await reveal(tester, 'invoiceLLMEnabled');
    await tester.tap(find.byKey(const Key('invoiceLLMEnabled')));
    await reveal(tester, 'saveLLMSettings');
    await tester.tap(find.byKey(const Key('saveLLMSettings')));
    await tester.pumpAndSettle();
    expect(cubit.state.configuration!.llm.invoiceEnabled, isFalse);
    expect(cubit.state.configuration!.llm.model, 'replacement-model');
    expect(cubit.state.configuration!.llm.contextLength, 65536);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('model field semantics keep a distinct field label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, screen: true, width: 1440);
    await tester.scrollUntilVisible(
      find.byKey(const Key('llmModel')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await reveal(tester, 'llmModel');
    final node = tester.getSemantics(
      find.descendant(
        of: find.byKey(const Key('llmModel')),
        matching: find.byType(EditableText),
      ),
    );
    expect(node.label, 'Model');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'scrolling between lazy settings fields preserves every pending edit',
    (tester) async {
      await mount(tester, width: 800, screen: true);
      Future<void> scrollTo(String key) async {
        final scroll = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(Key(key)),
          160,
          scrollable: scroll,
          maxScrolls: 100,
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(Key(key))),
          alignment: .5,
        );
        await tester.pumpAndSettle();
      }

      await scrollTo('llmEnabled');
      await tester.tap(find.byKey(const Key('llmEnabled')));
      await scrollTo('llmProviderOpenAI');
      await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
      await tester.pumpAndSettle();
      await scrollTo('llmBaseUrl');
      await tester.enterText(
        find.byKey(const Key('llmBaseUrl')),
        'http://127.0.0.1:1234/v1',
      );
      await scrollTo('llmModel');
      await tester.enterText(
        find.byKey(const Key('llmModel')),
        'fixture-model',
      );
      await scrollTo('llmApiKey');
      await tester.enterText(find.byKey(const Key('llmApiKey')), 'fixture-key');
      await scrollTo('saveLLMSettings');
      expect(cubit.state.llm.model, 'fixture-model');
      expect(cubit.state.llm.apiKey, 'fixture-key');
      await tester.tap(find.byKey(const Key('saveLLMSettings')));
      await tester.pumpAndSettle();
      expect(repository.llmUpdates.single!.model, 'fixture-model');
      expect(repository.llmUpdates.single!.apiKey, 'fixture-key');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'external settings save explicitly, preserve focus on refresh and clear the submitted key',
    (tester) async {
      await mount(tester);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('llmEnabled')))
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('llmModel')))
            .controller!
            .text,
        'qwen3.5:4b',
      );
      await tester.tap(find.byKey(const Key('llmEnabled')));
      expect(repository.llmUpdates, isEmpty);
      await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('llmBaseUrl')),
        'https://models.example/v1',
      );
      await tester.enterText(
        find.byKey(const Key('llmModel')),
        'external-model',
      );
      await reveal(tester, 'llmApiKey');
      await tester.enterText(
        find.byKey(const Key('llmApiKey')),
        'private-replacement',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('llmApiKey')))
            .obscureText,
        isTrue,
      );
      final controller = tester
          .widget<TextField>(find.byKey(const Key('llmApiKey')))
          .controller;
      final focus = FocusManager.instance.primaryFocus;
      await cubit.load(poll: true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('llmApiKey'))).controller,
        same(controller),
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(controller!.text, 'private-replacement');
      await reveal(tester, 'saveLLMSettings');
      await tester.tap(find.byKey(const Key('saveLLMSettings')));
      await tester.pumpAndSettle();
      expect(repository.llmUpdates.single!.apiKey, 'private-replacement');
      expect(controller.text, isEmpty);
      expect(find.text('API key stored'), findsOneWidget);
      expect(cubit.state.configuration!.llm.enabled, isTrue);
      expect(cubit.state.configuration!.llm.invoiceEnabled, isFalse);
      expect(find.text('Unsaved changes').hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'removing a stored key is explicit and reversible before saving',
    (tester) async {
      await tester.pump();
      repository.systemConfiguration = DocumentProcessingConfiguration(
        pipeline: repository.pipeline,
        llm: const DocumentLLMConfiguration(
          provider: 'openai',
          baseUrl: 'https://models.example/v1',
          credentialConfigured: true,
        ),
      );
      await cubit.load();
      await mount(tester);
      await reveal(tester, 'llmClearApiKey');
      await tester.tap(find.byKey(const Key('llmClearApiKey')));
      await tester.pumpAndSettle();
      expect(find.text('Keep stored key'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('llmApiKey'))).enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('llmClearApiKey')));
      await tester.pumpAndSettle();
      expect(cubit.state.llm.clearApiKey, isFalse);
      expect(repository.llmUpdates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'graph edit opens the same settings with keyboard-accessible controls',
    (tester) async {
      await mount(tester, width: 1440, screen: true);
      final action = find.text('Edit property extraction');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      final dialog = find.byType(AppDialog);
      final control = find.descendant(
        of: dialog,
        matching: find.byKey(const Key('llmEnabled')),
      );
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(cubit.state.llm.enabled, isTrue);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(cubit.state.dirty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('invoice settings action opens independent AI controls', (
    tester,
  ) async {
    await mount(tester, width: 1440, screen: true);
    final action = find.text('Edit invoice extraction');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    final invoice = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byKey(const Key('invoiceLLMEnabled')),
    );
    await tester.ensureVisible(invoice);
    await tester.tap(invoice);
    await tester.pumpAndSettle();
    expect(cubit.state.llm.invoiceEnabled, isTrue);
    expect(cubit.state.llm.enabled, isFalse);
    expect(find.text('Shared model connection'), findsWidgets);
    final thinking = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byKey(const Key('invoiceThinkingEnabled')),
    );
    await tester.ensureVisible(thinking);
    await tester.tap(thinking);
    await tester.pumpAndSettle();
    expect(cubit.state.llm.invoiceThinkingEnabled, isTrue);
    expect(cubit.state.llm.propertyThinkingEnabled, isFalse);
    final save = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byKey(const Key('saveLLMSettings')),
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.llmUpdates.single!.invoiceEnabled, isTrue);
    expect(repository.llmUpdates.single!.enabled, isFalse);
    expect(repository.llmUpdates.single!.invoiceThinkingEnabled, isTrue);
    expect(repository.llmUpdates.single!.propertyThinkingEnabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pipeline distinguishes invoice AI from property AI', (
    tester,
  ) async {
    for (final choices in [
      (false, true),
      (true, false),
      (false, false),
      (true, true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocumentAIPipelineDiagram(
                configuration: testPipelineConfiguration(
                  propertyExtractionEnabled: choices.$1,
                  invoiceExtractionEnabled: choices.$2,
                  propertyExtractionModel: 'shared-model',
                  invoiceExtractionModel: 'shared-model',
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('without AI; invoice AI is off'),
        choices.$2 ? findsNothing : findsOneWidget,
      );
      expect(
        find.textContaining('AI off · document properties'),
        choices.$1 ? findsNothing : findsOneWidget,
      );
      expect(
        find.textContaining('AI enabled · shared-model'),
        findsNWidgets((choices.$1 ? 1 : 0) + (choices.$2 ? 1 : 0)),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 390.0, 800.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'extraction fields and actions fit width $width, dark $dark, 200% text',
        (tester) async {
          await mount(tester, width: width, dark: dark, scale: 2);
          await reveal(tester, 'llmProviderOpenAI');
          await tester.tap(find.byKey(const Key('llmProviderOpenAI')));
          await tester.pumpAndSettle();
          await reveal(tester, 'llmLMStudioCompatibility');
          await tester.tap(find.byKey(const Key('llmLMStudioCompatibility')));
          await tester.pumpAndSettle();
          expect(cubit.state.llm.lmStudioCompatibility, isTrue);
          await reveal(tester, 'llmBaseUrl');
          await tester.enterText(
            find.byKey(const Key('llmBaseUrl')),
            'not a URL',
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Enter an HTTP or HTTPS base URL'),
            findsOneWidget,
          );
          await reveal(tester, 'saveLLMSettings');
          expect(
            find.byKey(const Key('saveLLMSettings')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('saveLLMSettings')))
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'retained combined pipeline preserves its recorded enrichment stages',
    (tester) async {
      Future<void> show(DocumentProcessingJob job) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PipelineDiagram(
                configuration: job.configuration!,
                job: job,
              ),
            ),
          ),
        ),
      );
      await show(
        testProcessingJob(
          pipelineVersion: 1,
          stage: 'enriching',
          propertyExtractionEnabled: true,
        ),
      );
      var steps = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(steps[2].title, 'Invoice extraction');
      expect(steps[2].status, 'Not recorded');
      expect(steps[3].title, 'Property extraction');
      expect(steps[3].current, isTrue);
      expect(steps[4].status, 'Waiting');
      await show(
        testProcessingJob(
          pipelineVersion: 1,
          status: 'succeeded',
          propertyExtractionEnabled: true,
        ),
      );
      steps = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(steps[3].status, 'Configured');
      expect(steps[3].icon, Icons.auto_awesome_outlined);
      await show(
        testProcessingJob(
          pipelineVersion: 1,
          status: 'succeeded',
          propertyExtractionEnabled: false,
        ),
      );
      steps = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(steps[3].status, 'Off for this attempt');
      await show(testProcessingJob(pipelineVersion: 1, status: 'succeeded'));
      steps = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(steps[3].status, 'Not recorded');
      await show(testProcessingJob(pipelineVersion: 1, stage: 'invoicing'));
      steps = tester
          .widget<AppPipelineDiagram>(find.byType(AppPipelineDiagram))
          .steps;
      expect(steps[2].current, isTrue);
      expect(steps[2].status, 'In progress');
      expect(find.text('Edit property extraction'), findsNothing);
    },
  );
}
