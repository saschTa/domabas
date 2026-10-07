import 'workspace_actions.dart'
    show revealWorkspaceAction, revealWorkspaceHeader;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:domabas/app/http_client.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/presentation/document/widgets/processing_widgets.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:web/web.dart' as web;

import 'document_fixtures.dart';
import 'document_search.dart';
import 'document_processing.dart';
import 'email_ingestion.dart';

Future<void> exerciseDocumentWorkspace(
  WidgetTester tester, {
  required String sessionToken,
  required Future<void> Function() remount,
}) async {
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final transport = SessionClient(
    createHttpClient(),
    token: sessionToken,
    onUnauthorized: () {},
  );
  final generated = api.ApiClient(basePath: endpoint)..client.close();
  generated.client = transport;
  final documents = api.DocumentsApi(generated);
  addTearDown(transport.close);
  await _exercisePasswordPdf(tester, transport, endpoint, documents);
  web.window.performance.setResourceTimingBufferSize(10000);
  web.window.performance.clearResourceTimings();
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final title = 'Multipage PDF $suffix';
  final editedTitle = 'Reviewed PDF $suffix';
  final imageTitle = 'PNG fixture $suffix';
  final pdfId = await _upload(
    transport,
    endpoint,
    multipagePdf(),
    'pages.pdf',
    title,
    tags: ['alpha', 'bravo', 'charlie', 'delta'],
  );
  final imageId = await _upload(
    transport,
    endpoint,
    await pngFixture(),
    'image.png',
    imageTitle,
  );
  await _ready(documents, pdfId);
  await _ready(documents, imageId);
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await _until(
    tester,
    () => find.text(title).evaluate().isNotEmpty,
    'uploaded collection refreshed',
  );
  expect(find.text(title), findsOneWidget);
  expect(find.text('+1'), findsOneWidget);
  for (final id in [pdfId, imageId]) {
    await _until(
      tester,
      () => find
          .descendant(
            of: find.byKey(Key('document-$id')),
            matching: find.byWidgetPredicate(
              (widget) => widget is RawImage && widget.image != null,
            ),
          )
          .evaluate()
          .isNotEmpty,
      'automatic thumbnail becomes visible for $id',
      timeout: const Duration(minutes: 2),
    );
    final paths = _documentNetworkPaths(id);
    expect(paths, contains('/api/v1/documents/$id/thumbnail'));
    expect(paths, isNot(contains('/api/v1/documents/$id/content')));
    final descriptor = (await documents.getDocument(id))!.thumbnail!;
    expect(descriptor.width, lessThanOrEqualTo(256));
    expect(descriptor.height, lessThanOrEqualTo(360));
    expect(descriptor.size, lessThanOrEqualTo(256 * 1024));
  }
  await _exerciseThumbnailJobs(tester, documents, pdfId);
  expect(
    tester.getSize(find.byKey(Key('document-$pdfId'))).height,
    closeTo(tester.getSize(find.byKey(Key('document-$imageId'))).height, .001),
  );
  await tester.tap(find.byTooltip('List'));
  await tester.pumpAndSettle();
  expect(find.text(title), findsOneWidget);
  await tester.tap(find.byTooltip('Grid'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await _until(
    tester,
    () =>
        find.byKey(const Key('pdfPage')).evaluate().isNotEmpty &&
        tester.widget<TextField>(find.byKey(const Key('pdfPage'))).enabled ==
            true,
    'PDF viewer ready',
  );
  expect(find.text('of 2'), findsOneWidget);
  expect(
    _documentNetworkPaths(pdfId),
    contains('/api/v1/documents/$pdfId/content'),
  );
  expect(tester.takeException(), isNull);
  final initialController = tester
      .widget<PdfViewer>(find.byType(PdfViewer))
      .controller!;
  final initialPage = initialController.layout.pageLayouts.first;
  final visiblePage = MatrixUtils.transformRect(
    initialController.value,
    initialPage,
  );
  expect(visiblePage.left, greaterThanOrEqualTo(-1));
  expect(visiblePage.top, greaterThanOrEqualTo(-1));
  expect(
    visiblePage.right,
    lessThanOrEqualTo(initialController.viewSize.width + 1),
  );
  expect(
    visiblePage.bottom,
    lessThanOrEqualTo(initialController.viewSize.height + 1),
  );
  final controls = tester.getRect(
    find.byKey(const Key('documentCanvasControls')),
  );
  final viewport = tester.getRect(
    find.byKey(const Key('documentCanvasViewport')),
  );
  expect(controls.top, lessThan(viewport.bottom));
  expect(controls.bottom, lessThan(viewport.bottom));
  expect(visiblePage.bottom + viewport.top, lessThan(controls.top));
  expect(find.byKey(const Key('documentWindow')), findsOneWidget);
  await tester.tap(find.byTooltip('Next document page'));
  await tester.pumpAndSettle();
  expect(
    tester.widget<TextField>(find.byKey(const Key('pdfPage'))).controller!.text,
    '2',
  );
  await tester.tap(find.byTooltip('Zoom in'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fit'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Find in PDF'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('pdfSearch')), 'Orchard');
  await _until(
    tester,
    () => find.text('1 of 2 matches').evaluate().isNotEmpty,
    'native PDF search',
  );
  await tester.tap(find.byTooltip('Next PDF match'));
  await _until(
    tester,
    () => find.text('2 of 2 matches').evaluate().isNotEmpty,
    'next native PDF match',
  );
  expect(find.text('2 of 2 matches'), findsOneWidget);
  final pdfController = tester
      .widget<PdfViewer>(find.byType(PdfViewer))
      .controller;
  final searchController = tester
      .widget<TextField>(find.byKey(const Key('pdfSearch')))
      .controller;
  final currentPage = pdfController!.pageNumber;
  final currentZoom = pdfController.currentZoom;
  for (final mode in ['light', 'dark']) {
    await revealWorkspaceAction(tester, 'appearance-action');
    await tester.tap(
      find.byKey(const Key('appearance-action')).hitTestable().first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('appearance-$mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('closeAppearance')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PdfViewer>(find.byType(PdfViewer)).controller,
      same(pdfController),
    );
    expect(pdfController.pageNumber, currentPage);
    expect(pdfController.currentZoom, closeTo(currentZoom, .001));
    expect(
      tester.widget<TextField>(find.byKey(const Key('pdfSearch'))).controller,
      same(searchController),
    );
    expect(searchController!.text, 'Orchard');
    expect(find.text('2 of 2 matches'), findsOneWidget);
  }
  await tester.tap(find.byTooltip('Close PDF search'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Document details'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit properties'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('edit-title')), editedTitle);
  await tester.enterText(
    find.byKey(const Key('edit-tags')),
    'finance\nreviewed',
  );
  await tester.scrollUntilVisible(
    find.text('Save properties'),
    200,
    scrollable: find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save properties'));
  await _until(
    tester,
    () => find.text('Properties saved.').evaluate().isNotEmpty,
    'metadata save completed',
  );
  expect((await documents.getDocument(pdfId))!.title, editedTitle);
  expect((await documents.getDocument(pdfId))!.tags, ['finance', 'reviewed']);
  await tester.tap(find.text('Extracted text'));
  await tester.pumpAndSettle();
  await _until(
    tester,
    () => find
        .widgetWithText(OutlinedButton, 'Edit extracted text')
        .evaluate()
        .any((element) => (element.widget as OutlinedButton).onPressed != null),
    'extracted text loaded',
  );
  await tester.tap(find.text('Edit extracted text'));
  await tester.pumpAndSettle();
  final textField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == 'Extracted text',
  );
  const correction = '  İ Verified Orchard correction\nSecond line äö\n';
  await tester.enterText(textField, correction);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
  expect(find.text('Discard unsaved changes?'), findsOneWidget);
  await tester.tap(find.text('Keep editing'));
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(textField).controller!.text, correction);
  await tester.tap(find.text('Save extracted text'));
  await _until(
    tester,
    () => find.text('Extracted text saved.').evaluate().isNotEmpty,
    'extracted text save completed',
  );
  expect((await documents.getDocumentOCR(pdfId))!.text, correction);
  final ocrQuery = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Find in extracted text',
  );
  await tester.enterText(ocrQuery, 'Orchard');
  await tester.pumpAndSettle();
  expect(find.text('1 of 1 matches'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(textField)
        .controller!
        .selection
        .textInside(correction),
    'Orchard',
  );
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await remount();
  await _until(
    tester,
    () =>
        find.text(editedTitle).evaluate().isNotEmpty &&
        find.text(imageTitle).evaluate().isNotEmpty,
    'persisted library restored',
  );
  expect(find.text(editedTitle), findsOneWidget);
  expect((await documents.getDocumentOCR(pdfId))!.text, correction);
  await tester.tap(find.text(imageTitle));
  await tester.pumpAndSettle();
  await _until(
    tester,
    () => find.text('Page 1 of 1').evaluate().isNotEmpty,
    'PNG viewer ready',
  );
  expect(find.text('This image could not be opened.'), findsNothing);
  await tester.tap(find.byTooltip('Zoom in'));
  await tester.pumpAndSettle();
  expect(find.text('125%'), findsOneWidget);
  await tester.tap(find.text('Fit'));
  await tester.pumpAndSettle();
  expect(find.text('100%'), findsOneWidget);
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await exerciseDocumentProcessing(
    tester,
    documents: documents,
    correctedDocumentId: pdfId,
    correction: correction,
    imageId: imageId,
  );
  await tester.tap(find.text(editedTitle));
  await tester.pumpAndSettle();
  await _until(
    tester,
    () => find.byTooltip('Document actions').evaluate().isNotEmpty,
    'document actions loaded',
  );
  await tester.tap(find.byTooltip('Document actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete document'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete document'));
  await _until(
    tester,
    () => find.byKey(const Key('documentDetails')).evaluate().isEmpty,
    'document deletion completed',
  );
  expect(find.byKey(const Key('documentDetails')), findsNothing);
  expect(find.text(editedTitle), findsNothing);
  await expectLater(
    documents.getDocument(pdfId),
    throwsA(
      isA<api.ApiException>().having((error) => error.code, 'status', 404),
    ),
  );
  await remount();
  await _until(
    tester,
    () => find.text(imageTitle).evaluate().isNotEmpty,
    'library restored after deletion',
  );
  expect(find.text(editedTitle), findsNothing);
  expect(find.text(imageTitle), findsOneWidget);
  expect(tester.takeException(), isNull);
  await exerciseDocumentSearch(
    tester,
    documents: documents,
    transport: transport,
    endpoint: endpoint,
  );
  await exerciseEmailIngestion(tester, client: generated);
}

Future<String> _upload(
  http.Client client,
  String endpoint,
  Uint8List bytes,
  String filename,
  String title, {
  List<String> tags = const [],
}) async {
  final request =
      http.MultipartRequest(
          'POST',
          Uri.parse('$endpoint/api/v1/documents/upload'),
        )
        ..fields['metadata'] = jsonEncode({'title': title, 'tags': tags})
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        );
  final response = await http.Response.fromStream(await client.send(request));
  expect(response.statusCode, 202, reason: response.body);
  return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
}

Future<void> _ready(api.DocumentsApi documents, String id) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final processing = await documents.getDocumentProcessing(id);
    if (processing!.state.toString() == 'ready') return;
    expect(
      processing.state.toString(),
      isNot('failed'),
      reason: processing.failureCode,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Document processing did not complete before its deadline.');
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    for (final viewer in tester.widgetList<PdfViewer>(find.byType(PdfViewer))) {
      if (viewer.documentRef.resolveListenable().error case final error?) {
        fail('$reason: PDF renderer failed: $error');
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull, reason: reason);
  if (!ready()) {
    fail(
      '$reason; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).whereType<String>().join(' | ')}',
    );
  }
}

List<String> _documentNetworkPaths(String id) => web.window.performance
    .getEntriesByType('resource')
    .toDart
    .map((entry) => Uri.parse(entry.name).path)
    .where((path) => path.startsWith('/api/v1/documents/$id/'))
    .toList();

Future<void> _exerciseThumbnailJobs(
  WidgetTester tester,
  api.DocumentsApi documents,
  String documentId,
) async {
  final jobs = (await documents.listDocumentJobs(
    documentId: documentId,
    pipeline: 'thumbnail',
    status: 'succeeded',
  ))!;
  final job = jobs.items.single;
  expect(job.configuration, isNull);
  expect(job.rendererRevision, greaterThan(0));
  await revealWorkspaceAction(tester, 'processingNavigation');
  await tester.tap(find.byKey(const Key('processingNavigation')));
  await tester.pumpAndSettle();
  Future<void> reveal(Finder target) async {
    if (target.evaluate().isEmpty) {
      final scroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('processingPage')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(target, 180, scrollable: scroll);
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  final filter = find.byKey(const Key('pipeline-filter-thumbnail'));
  await reveal(filter);
  await tester.tap(filter);
  await tester.pumpAndSettle();
  final row = find.byKey(Key('job-${job.id}'));
  await reveal(row);
  await tester.tap(find.descendant(of: row, matching: find.text('Details')));
  await tester.pumpAndSettle();
  expect(find.text('Job details'), findsOneWidget);
  await tester.ensureVisible(find.byType(DocumentThumbnailPipelineDiagram));
  await tester.pumpAndSettle();
  expect(find.byType(DocumentThumbnailPipelineDiagram), findsOneWidget);
  expect(find.byType(ProcessingConfigurationDetails), findsNothing);
  expect(
    find.text('Thumbnail renderer revision ${job.rendererRevision}'),
    findsOneWidget,
  );
  final back = find.text('Back to jobs');
  await revealWorkspaceHeader(tester, back);
  await tester.tap(back);
  await tester.pumpAndSettle();
  await reveal(filter);
  expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
  final all = find.byKey(const Key('pipeline-filter-all'));
  await reveal(all);
  await tester.tap(all);
  await tester.pumpAndSettle();
  await revealWorkspaceAction(tester, 'documentsNavigation');
  await tester.tap(find.byKey(const Key('documentsNavigation')));
  await tester.pumpAndSettle();
}

Future<void> _exercisePasswordPdf(
  WidgetTester tester,
  http.Client transport,
  String endpoint,
  api.DocumentsApi documents,
) async {
  final id = await _upload(
    transport,
    endpoint,
    passwordPdf(),
    'protected.pdf',
    'Password protected fixture',
  );
  for (var attempt = 0; attempt < 120; attempt++) {
    final state = await documents.getDocumentProcessing(id);
    if (state?.failureCode?.toString() == 'encrypted_pdf') break;
    if (attempt == 119) fail('Password requirement was not detected');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await _until(
    tester,
    () => find.text('Password protected fixture').evaluate().isNotEmpty,
    'password PDF in collection',
  );
  expect(find.byTooltip('PDF password required'), findsOneWidget);
  await tester.tap(find.text('Password protected fixture'));
  await _until(
    tester,
    () => find.byKey(const Key('pdf-password')).evaluate().isNotEmpty,
    'password form',
  );
  await tester.enterText(find.byKey(const Key('pdf-password')), 'wrong');
  await tester.pump();
  await tester.tap(find.text('Unlock PDF'));
  await _until(
    tester,
    () => find
        .text('That PDF password is incorrect. Try again.')
        .evaluate()
        .isNotEmpty,
    'incorrect password feedback',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pdf-password')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('pdf-password')), ' test123 ');
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('pdf-password')))
        .controller!
        .text,
    ' test123 ',
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _until(
    tester,
    () =>
        find.byKey(const Key('pdfPage')).evaluate().isNotEmpty &&
        tester.widget<TextField>(find.byKey(const Key('pdfPage'))).enabled ==
            true,
    'unlocked PDF renders without another password',
  );
  expect(find.byKey(const Key('pdf-password')), findsNothing);
  expect(find.text('of 1'), findsOneWidget);
  await _ready(documents, id);
  final text = await documents.getDocumentOCR(id);
  expect(text?.text, contains('platypus'));
  await tester.tap(find.byKey(const Key('closeDocument')));
  await tester.pumpAndSettle();
  await documents.deleteDocument(id);
  await tester.tap(find.byKey(const Key('refreshDocuments')));
  await tester.pumpAndSettle();
}
