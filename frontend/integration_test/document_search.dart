import 'dart:convert';

import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/views/documents_screen.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Future<void> exerciseDocumentSearch(
  WidgetTester tester, {
  required api.DocumentsApi documents,
  required http.Client transport,
  required String endpoint,
}) async {
  final prefix = 'Searchacceptance ${DateTime.now().microsecondsSinceEpoch}';
  final ids = <String>[];
  for (var index = 0; index <= DocumentsCubit.pageSize; index++) {
    final document = (await documents.createDocument(
      api.CreateDocument(
        title: '$prefix ${index.toString().padLeft(2, '0')}',
        description: 'Cursor search acceptance',
      ),
    ))!;
    ids.add(document.id);
    final recipient = ['recipients', 'cc', 'bcc'][index % 3];
    final response = await transport.patch(
      Uri.parse('$endpoint/api/v1/documents/${document.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'kind': ['document', 'letter', 'email'][index % 3],
        'tags': [
          'searchacceptance',
          'work',
          for (var value = 0; value < 8; value++)
            'aaa17-${((index % 13) * 8 + value).toString().padLeft(3, '0')}',
        ],
        'sender': 'Sender%_Literal',
        recipient: ['Recipient%_Literal'],
      }),
    );
    expect(response.statusCode, 200, reason: response.body);
  }

  Finder scroll() => find
      .descendant(
        of: find.byKey(const Key('documentCollectionScroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(Finder target, String stage) async {
    debugPrint('Document search E2E: $stage');
    final position = tester.state<ScrollableState>(scroll()).position;
    if (target.evaluate().isEmpty) {
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < DocumentsCubit.pageSize * 4 && target.evaluate().isEmpty;
        attempt++
      ) {
        final before = position.pixels;
        await tester.drag(
          scroll(),
          Offset(
            0,
            -(position.viewportDimension * .7).clamp(80, 300).toDouble(),
          ),
        );
        await tester.pumpAndSettle();
        if (position.pixels == before &&
            position.pixels >= position.maxScrollExtent) {
          break;
        }
      }
    }
    expect(
      target,
      findsOneWidget,
      reason:
          '$stage: missing $target at offset ${position.pixels}, range ${position.minScrollExtent}..${position.maxScrollExtent}, viewport ${position.viewportDimension}',
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 40 && target.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      final viewport = tester.getRect(scroll());
      final bounds = tester.getRect(target);
      await tester.drag(
        scroll(),
        Offset(0, bounds.center.dy > viewport.center.dy ? -150 : 150),
      );
      await tester.pumpAndSettle();
    }
    expect(
      target.hitTestable(),
      findsOneWidget,
      reason:
          '$stage: $target is not hit-testable; target ${tester.getRect(target)}, viewport ${tester.getRect(scroll())}, offset ${position.pixels}',
    );
  }

  Future<void> waitFor(bool Function() ready, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: label);
    await tester.pumpAndSettle();
  }

  DocumentsState collection() =>
      tester.widget<DocumentsScreen>(find.byType(DocumentsScreen)).cubit.state;

  final typoTitle =
      'Maintenance invoice ${DateTime.now().microsecondsSinceEpoch}';
  final typoDocument = (await documents.createDocument(
    api.CreateDocument(title: typoTitle),
  ))!;
  await reveal(
    find.byKey(const Key('documentSearchTerm')),
    'enter misspelling',
  );
  await tester.enterText(
    find.byKey(const Key('documentSearchTerm')),
    typoTitle.replaceFirst('Maintenance', 'Maintenence'),
  );
  await waitFor(
    () => find
        .byKey(Key('search-document-${typoDocument.id}'))
        .evaluate()
        .isNotEmpty,
    'combined search finds a misspelled title through the real API',
  );
  await documents.deleteDocument(typoDocument.id);

  await reveal(find.byKey(const Key('documentSearchTerm')), 'enter term');
  await tester.enterText(find.byKey(const Key('documentSearchTerm')), prefix);
  await waitFor(
    () =>
        collection().criteria?.query == prefix &&
        !collection().showLoading &&
        collection().results.length == DocumentsCubit.pageSize &&
        collection().nextCursor != null &&
        !collection().totalKnown,
    'typing searches matching documents and provides continuation without a total',
  );
  await reveal(find.byKey(const Key('documentFilters')), 'open filters');
  await tester.tap(find.byKey(const Key('documentFilters')));
  await tester.pumpAndSettle();
  Finder optionsScroll() => find
      .descendant(
        of: find.byKey(const Key('documentVocabularyScroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> choose(String value) async {
    final target = find.byTooltip(value);
    for (
      var attempt = 0;
      attempt < 120 && target.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(optionsScroll(), const Offset(0, -350));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(target, findsOneWidget, reason: 'existing vocabulary option $value');
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  await choose('searchacceptance');
  await choose('work');
  for (final (field, value) in [
    ('sender', 'Sender%_Literal'),
    ('recipient', 'Recipient%_Literal'),
  ]) {
    tester.state<ScrollableState>(optionsScroll()).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('documentFilter-$field')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('documentVocabularyQuery')),
    );
    await tester.enterText(
      find.byKey(const Key('documentVocabularyQuery')),
      '%_literal',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await choose(value);
  }
  await tester.tap(find.byKey(const Key('closeDocumentFilters')));
  await tester.pumpAndSettle();
  expect(
    tester.widget<Text>(find.byKey(const Key('documentCount'))).data,
    'Search results',
  );
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('documentSearchTerm')))
        .controller!
        .text,
    prefix,
  );
  Future<void> selectType(
    String kind,
    int total,
    Set<String> expectedKinds,
  ) async {
    final chip = find.byKey(Key('documentType-$kind'));
    await reveal(chip, 'select $kind type');
    await tester.tap(chip);
    await waitFor(
      () =>
          !collection().showLoading &&
          collection().results.length ==
              (total > DocumentsCubit.pageSize
                  ? DocumentsCubit.pageSize
                  : total) &&
          collection().results.every(
            (result) => expectedKinds.contains(result.kind),
          ) &&
          (collection().nextCursor != null) ==
              (total > DocumentsCubit.pageSize) &&
          !collection().totalKnown,
      'type selection shows matching cards and the correct continuation',
    );
  }

  final allCount = DocumentsCubit.pageSize + 1;
  final emailCount = allCount ~/ 3;
  final documentCount = (allCount + 2) ~/ 3;
  const allKinds = {'document', 'letter', 'email'};
  await selectType('email', emailCount, {'email'});
  await selectType('all', allCount, allKinds);
  await selectType('document', documentCount, {'document'});
  await selectType('letter', allCount - emailCount, {'document', 'letter'});
  await selectType('all', allCount, allKinds);
  await reveal(find.byKey(const Key('sortDocuments')), 'open sort menu');
  await tester.tap(find.byKey(const Key('sortDocuments')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Title A–Z'));
  await tester.pumpAndSettle();
  await reveal(find.text('$prefix 00'), 'first result in title order');
  expect(find.text('$prefix 00'), findsOneWidget);
  await reveal(find.widgetWithText(TextButton, 'Next'), 'next cursor page');
  await waitFor(
    () => tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Next'))
        .enabled,
    'sorted search response enables the next cursor page',
  );
  await tester.tap(find.widgetWithText(TextButton, 'Next'));
  await waitFor(
    () => find.text('Page 2').evaluate().isNotEmpty,
    'next cursor response displays page two',
  );
  await reveal(
    find.byKey(Key('search-document-${ids.last}')),
    'open page-two result',
  );
  expect(
    find.text('$prefix ${DocumentsCubit.pageSize.toString().padLeft(2, '0')}'),
    findsOneWidget,
  );
  await tester.tap(find.byKey(Key('search-document-${ids.last}')));
  await waitFor(
    () => find.byKey(const Key('documentDetails')).evaluate().isNotEmpty,
    'search result opened',
  );
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await reveal(find.text('Page 2'), 'no-edit return preserves page two');
  expect(find.text('Page 2'), findsOneWidget);
  await reveal(
    find.byKey(Key('search-document-${ids.last}')),
    'reopen page-two result',
  );
  await tester.tap(find.byKey(Key('search-document-${ids.last}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Document details'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit properties'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('edit-tags')));
  await tester.enterText(find.byKey(const Key('edit-tags')), 'reviewed');
  await tester.scrollUntilVisible(
    find.text('Save properties'),
    200,
    scrollable: find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save properties'));
  await waitFor(
    () => find.text('Properties saved.').evaluate().isNotEmpty,
    'search result metadata saved',
  );
  expect((await documents.getDocument(ids.last))!.tags, ['reviewed']);
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await reveal(
    find.text('Search results'),
    'mutation refreshes matching results',
  );
  await waitFor(
    () => find.text('Results updated.').evaluate().isNotEmpty,
    'mutation reconciliation completed',
  );
  expect(find.text('Results updated.'), findsOneWidget);
  expect(
    tester.widget<Text>(find.byKey(const Key('documentCount'))).data,
    'Search results',
  );
  expect(collection().results.length, DocumentsCubit.pageSize);
  expect(collection().nextCursor, isNull);
  expect(collection().totalKnown, isFalse);
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('documentSearchTerm')))
        .controller!
        .text,
    prefix,
  );
  expect(
    find.text('$prefix ${DocumentsCubit.pageSize.toString().padLeft(2, '0')}'),
    findsNothing,
  );
  await reveal(find.text('Page 1'), 'mutation resets cursor page');
  expect(find.text('Page 1'), findsOneWidget);
  await reveal(
    find.byKey(const Key('clearDocumentSearch')),
    'return from pagination to Clear',
  );
  await tester.tap(find.byKey(const Key('clearDocumentSearch')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('documentSearchTerm')))
        .controller!
        .text,
    '',
  );
  expect(tester.takeException(), isNull);
}
