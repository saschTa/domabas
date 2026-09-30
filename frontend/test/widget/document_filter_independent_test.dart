import 'dart:ui' show CheckedState;

import 'package:domabas/domain/document/models/document_vocabulary.dart';
import 'package:domabas/presentation/document/cubits/document_vocabulary_cubit.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_filter_dialog.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';
import '../support/fake_document_vocabulary_repository.dart';

void main() {
  late DocumentsCubit documents;
  late FakeDocumentVocabularyRepository repository;
  late ValueNotifier<double> scale;
  setUp(() {
    documents = DocumentsCubit(
      FakeDocumentRepository(),
      capabilities: allDocumentCapabilities,
    );
    repository = FakeDocumentVocabularyRepository(count: 520);
    scale = ValueNotifier(1);
  });
  tearDown(() async {
    await documents.close();
    scale.dispose();
  });
  Future<void> mount(
    WidgetTester tester, {
    double width = 800,
    double height = 700,
    bool Function()? current,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder(
          valueListenable: scale,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(value)),
            child: DocumentFilterDialog(
              documents: documents,
              repository: repository,
              isCurrent: current ?? () => true,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  DocumentVocabularyCubit lookup(WidgetTester tester) => tester
      .widget<BlocConsumer<DocumentVocabularyCubit, DocumentVocabularyState>>(
        find.byType(
          BlocConsumer<DocumentVocabularyCubit, DocumentVocabularyState>,
        ),
      )
      .bloc!;
  Finder scroll() => find
      .descendant(
        of: find.byKey(const Key('documentVocabularyScroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(scroll()).position;
  (String, double) anchor(WidgetTester tester) {
    final top = tester.getRect(scroll()).top;
    for (final option in lookup(tester).state.items) {
      final row = find.byKey(ValueKey(option.key));
      if (row.evaluate().isEmpty) continue;
      final rect = tester.getRect(row);
      if (rect.top <= top + .01 && rect.bottom > top + .01) {
        return (option.key, (top - rect.top) / rect.height);
      }
    }
    fail('No visible option anchor at ${position(tester).pixels}');
  }

  void sameAnchor(WidgetTester tester, (String, double) before) {
    final after = anchor(tester);
    expect(after.$1, before.$1);
    expect(after.$2, closeTo(before.$2, .001));
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'mounted platform reduce-motion immediately replaces the lookup spinner with static progress',
    (tester) async {
      repository.automatic = false;
      await mount(tester, settle: false);
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .animate,
        isTrue,
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .animate,
        isFalse,
      );
      expect(
        tester
            .widget<AppStripedProgressIndicator>(
              find.byType(AppStripedProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(lookup(tester).state.loading, isTrue);
      repository.calls.single.response.complete(
        DocumentVocabularyPage(items: []),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'selecting a twenty-first tag keeps selections and exposes visible limit feedback at the current viewport',
    (tester) async {
      for (var index = 0; index < 20; index++) {
        await documents.selectOption(
          DocumentVocabularyField.tag,
          vocabularyOption(index),
        );
      }
      await mount(tester);
      final extra = find.byKey(ValueKey(vocabularyOption(20).key));
      await tester.scrollUntilVisible(
        extra,
        300,
        scrollable: scroll(),
        maxScrolls: 50,
      );
      await tester.ensureVisible(extra);
      await tester.pumpAndSettle();
      await tester.tap(extra);
      await tester.pump();
      expect(documents.state.selectedTags, hasLength(20));
      expect(find.text('20 tags max').hitTestable(), findsOneWidget);
      expect(
        find.bySemanticsLabel('You can select up to 20 tags.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'selection header, width-only resize and text scaling preserve visible key and fraction in the first painted frame',
    (tester) async {
      await mount(tester);
      for (var index = 0; index < 3; index++) {
        position(tester).jumpTo(position(tester).maxScrollExtent);
        await tester.pumpAndSettle();
      }
      position(tester).jumpTo(position(tester).pixels - 250);
      await tester.pumpAndSettle();
      final before = anchor(tester);
      await documents.selectOption(
        DocumentVocabularyField.tag,
        vocabularyOption(900, value: 'abcdefgh ' * 7),
      );
      await tester.pump();
      sameAnchor(tester, before);
      tester.view.physicalSize = const Size(490, 700);
      await tester.pump();
      sameAnchor(tester, before);
      scale.value = 2;
      await tester.pump();
      sameAnchor(tester, before);
    },
  );

  testWidgets(
    'pending continuation plus eviction and metric change preserve the current anchor with at most 400 options',
    (tester) async {
      await mount(tester);
      for (
        var index = 0;
        lookup(tester).state.items.length < 400 && index < 12;
        index++
      ) {
        position(tester).jumpTo(position(tester).maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(lookup(tester).state.items, hasLength(400));
      repository.automatic = false;
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      expect(repository.calls.last.cursor, '400');
      final before = anchor(tester);
      repository.calls.last.response.complete(
        DocumentVocabularyPage(
          items: List.generate(40, (index) => vocabularyOption(400 + index)),
          nextCursor: '440',
        ),
      );
      scale.value = 1.7;
      tester.view.physicalSize = const Size(470, 700);
      await tester.pump();
      sameAnchor(tester, before);
      expect(lookup(tester).state.items, hasLength(400));
      expect(lookup(tester).state.items.first.key, vocabularyOption(40).key);
      expect(lookup(tester).state.released, isTrue);
    },
  );

  testWidgets(
    '400-row continuation error exposes reachable trailing Retry and has no automatic retry loop',
    (tester) async {
      await mount(tester);
      for (
        var index = 0;
        lookup(tester).state.items.length < 400 && index < 12;
        index++
      ) {
        position(tester).jumpTo(position(tester).maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(lookup(tester).state.items, hasLength(400));
      repository.automatic = false;
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      final call = repository.calls.last;
      call.response.complete(
        DocumentVocabularyPage(items: [], nextCursor: 'invalid-no-progress'),
      );
      await tester.pumpAndSettle();
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      final retry = find.widgetWithText(TextButton, 'Retry').hitTestable();
      expect(retry, findsOneWidget);
      final count = repository.calls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.calls, hasLength(count));
      await tester.tap(retry);
      await tester.pump();
      expect(repository.calls, hasLength(count + 1));
      expect(repository.calls.last.cursor, call.cursor);
      repository.calls.last.response.complete(
        DocumentVocabularyPage(items: [vocabularyOption(99)]),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'maximum selections fit a 320 square at 200 percent with a keyboard and fixed 48-pixel close',
    (tester) async {
      for (var index = 0; index < 20; index++) {
        await documents.selectOption(
          DocumentVocabularyField.tag,
          vocabularyOption(
            index,
            value: '${index.toString().padLeft(2, '0')}${'x' * 62}',
          ),
        );
      }
      await documents.selectOption(
        DocumentVocabularyField.sender,
        vocabularyOption(100, value: '😀' * 320),
      );
      await documents.selectOption(
        DocumentVocabularyField.recipient,
        vocabularyOption(101, value: 'r' * 320),
      );
      scale.value = 2;
      await mount(tester, width: 320, height: 320);
      tester.view.viewInsets = const FakeViewPadding(bottom: 100);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final close = find.byKey(const Key('closeDocumentFilters'));
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
      expect(position(tester).maxScrollExtent, greaterThan(1000));
      await tester.ensureVisible(
        find.byKey(const Key('documentVocabularyQuery')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('documentVocabularyQuery')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checkbox and radio semantics retain full values; covered-route callbacks cannot mutate or launch lookup',
    (tester) async {
      var current = true;
      await mount(tester, current: () => current);
      final field = tester.widget<ChoiceChip>(
        find.byKey(const Key('documentFilter-sender')),
      );
      final query = tester.widget<TextField>(
        find.byKey(const Key('documentVocabularyQuery')),
      );
      final option = find.byKey(ValueKey(vocabularyOption(0).key));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      final semantics = tester.getSemantics(option);
      expect(semantics.label, 'option-0000');
      expect(semantics.flagsCollection.isChecked, CheckedState.isFalse);
      final row = tester.widget<InkWell>(
        find.descendant(of: option, matching: find.byType(InkWell)),
      );
      current = false;
      row.onTap!();
      field.onSelected!(true);
      query.onSubmitted!('late');
      query.controller!.text = 'late';
      await tester.pump(const Duration(seconds: 1));
      expect(documents.state.desiredCriteria.filterCount, 0);
      expect(repository.calls, hasLength(1));
      current = true;
      field.onSelected!(true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey(vocabularyOption(0).key)));
      await tester.pumpAndSettle();
      final radio = tester.getSemantics(
        find.byKey(ValueKey(vocabularyOption(0).key)),
      );
      expect(radio.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(radio.label, 'option-0000');
    },
  );
}
