import 'dart:async';

import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    late DocumentsCubit cubit;

    setUp(() {
      cubit = DocumentsCubit(
        _FocusSearchRepository(),
        capabilities: const DocumentCapabilities(read: true, search: true),
      );
    });
    tearDown(() => cubit.close());

    Future<void> mount(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: platform),
          home: Scaffold(body: DocumentsScreen(cubit: cubit)),
        ),
      );
      await tester.pumpAndSettle();
    }

    final term = find.byKey(const Key('documentSearchTerm'));
    final collection = find.byKey(const Key('documentCollectionScroll'));

    EditableText editor(WidgetTester tester) => tester.widget<EditableText>(
      find.descendant(of: term, matching: find.byType(EditableText)),
    );

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(of: collection, matching: find.byType(Scrollable))
              .first,
        )
        .position;

    testWidgets(
      '$platform scroll-away stays unfocused and in place after refresh and a route returns',
      (tester) async {
        await mount(tester);
        await tester.enterText(term, 'invoice');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(cubit.state.criteria?.query, 'invoice');
        final focus = editor(tester).focusNode;
        expect(focus.hasFocus, isTrue);
        tester.testTextInput.hide();
        await tester.drag(collection, const Offset(0, -550));
        await tester.pumpAndSettle();
        final offset = position(tester).pixels;
        expect(offset, greaterThan(300));

        await cubit.load(automatic: true);
        await tester.pumpAndSettle();
        expect(position(tester).pixels, closeTo(offset, .01));
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.push<void>(
            DialogRoute<void>(
              context: navigator.context,
              builder: (_) => const AlertDialog(title: Text('Other action')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();

        expect(
          position(tester).pixels,
          closeTo(offset, .01),
          reason:
              'Search focus=${focus.hasFocus}, keyboard=${tester.testTextInput.isVisible}',
        );
        expect(focus.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(cubit.state.rawTerm, 'invoice');
      },
    );

    testWidgets('$platform touch Search dismisses editing', (tester) async {
      await mount(tester);
      await tester.enterText(term, 'invoice');
      await tester.tap(find.byKey(const Key('applyDocumentSearch')));
      await tester.pumpAndSettle();
      expect(cubit.state.criteria?.query, 'invoice');
      expect(editor(tester).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('$platform touch outside search dismisses editing', (
      tester,
    ) async {
      await mount(tester);
      await tester.enterText(term, 'invoice');
      await tester.pump();
      await tester.tapAt(
        tester.getTopLeft(find.byType(DocumentCollectionCard).first) -
            const Offset(4, 4),
      );
      await tester.pumpAndSettle();
      expect(editor(tester).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(editor(tester).controller.text, 'invoice');
    });

    testWidgets('$platform touch Search preserves unfinished composition', (
      tester,
    ) async {
      await mount(tester);
      await tester.showKeyboard(term);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'in',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('applyDocumentSearch')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(cubit.state.searching, isFalse);
      expect(editor(tester).focusNode.hasFocus, isTrue);
      expect(
        editor(tester).controller.value.composing,
        const TextRange(start: 0, end: 2),
      );
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('$platform refresh preserves active editing', (tester) async {
      await mount(tester);
      await tester.enterText(term, 'invoice');
      await tester.pumpAndSettle();
      final focus = editor(tester).focusNode;
      final value = editor(tester).controller.value;
      await cubit.load(automatic: true);
      await tester.pumpAndSettle();
      expect(editor(tester).focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(editor(tester).controller.value, value);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  }
}

final class _FocusSearchRepository extends FakeDocumentRepository {
  _FocusSearchRepository() {
    records = List.generate(
      48,
      (index) => Document(
        id: 'document-$index',
        title: 'Invoice $index',
        description: '',
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria criteria, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentSearchPage(
    items: records
        .take(limit)
        .map(
          (document) => DocumentSearchResult(
            id: document.id,
            title: document.title,
            kind: document.kind,
            tags: document.tags,
            createdAt: document.createdAt,
            snippet: 'An invoice matching the search.',
          ),
        ),
    total: records.length,
  );
}
