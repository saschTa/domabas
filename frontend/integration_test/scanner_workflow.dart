import 'workspace_actions.dart' show revealWorkspaceAction;

import 'dart:async';
import 'dart:typed_data';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/http_client.dart';
import 'package:domabas/app/scanner_scope.dart';
import 'package:domabas/app/session_client.dart';
import 'package:domabas/data/document/datasources/document_upload_remote_data_source.dart';
import 'package:domabas/data/scanner/datasources/scan_pdf_document.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas_api/api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scanner_fixtures.dart';

AuthenticatedDependencies withScannerFixture(
  AuthenticatedDependencies real,
  AuthSession session,
  void Function(BrowserScannerFixture) active,
) {
  final scanner = BrowserScannerFixture(session.token);
  active(scanner);
  return AuthenticatedDependencies(
    documents: real.documents,
    invoices: real.invoices,
    chat: real.chat,
    vocabulary: real.vocabulary,
    identity: real.identity,
    processing: real.processing,
    email: real.email,
    paperless: real.paperless,
    paperlessSettings: real.paperlessSettings,
    workloadSettings: real.workloadSettings,
    activity: real.activity,
    realtime: real.realtime,
    externalLinks: real.externalLinks,
    uploads: real.uploads,
    scanner: scanner,
    close: () {
      scanner.dispose();
      real.dispose();
    },
  );
}

final class BrowserScannerFixture implements ScannerScopeFactory {
  BrowserScannerFixture(String token) {
    client = api.ApiClient(
      basePath: const String.fromEnvironment('API_BASE_URL'),
    )..client.close();
    client.client = SessionClient(
      createHttpClient(),
      token: token,
      onUnauthorized: () {},
    );
    repository = BrowserScanDraftFixture(
      DocumentUploadRemoteDataSource(client),
    );
  }
  late final api.ApiClient client;
  late final BrowserScanDraftFixture repository;
  final scopes = <_BrowserScope>[];
  @override
  Future<ScannerScope> open() async {
    final scope = _BrowserScope(repository);
    scopes.add(scope);
    return scope;
  }

  @override
  void cancelNewOperations() {
    for (final scope in scopes) {
      scope.cancelNewOperations();
    }
  }

  @override
  Future<void> close() async {
    for (final scope in scopes) {
      await scope.close();
    }
  }

  void dispose() {
    cancelNewOperations();
    client.client.close();
  }
}

final class _BrowserScope implements ScannerScope {
  _BrowserScope(this.repository);
  @override
  final BrowserScanDraftFixture repository;
  @override
  final camera = _BrowserCamera();
  @override
  WidgetBuilder get previewBuilder =>
      (_) => const ColoredBox(
        color: Color(0xffd9e6e1),
        child: Center(child: Text('Camera fixture')),
      );
  @override
  void cancelNewOperations() {
    camera.cancelNewOperations();
  }

  @override
  Future<void> close() => camera.close();
}

final class _BrowserCamera extends FixtureScannerCamera {
  @override
  Future<ScanCapture> capture() async {
    captures++;
    final width = captures == 3 ? 400 : 200, height = captures == 3 ? 200 : 300;
    return ScanCapture(
      id: 'browser-page-$captures',
      width: width,
      height: height,
      corners: ScanCorners.fullImage(),
      preview: scanJpeg(
        width,
        height,
        red: captures == 1 ? 230 : 20,
        green: captures == 3 ? 230 : 30,
      ),
    );
  }
}

final class BrowserScanDraftFixture extends FixtureScanRepository {
  BrowserScanDraftFixture(this.upload);
  final DocumentUploadRemoteDataSource upload;
  Document? accepted;
  Uint8List? sentPdf;
  @override
  Future<ScanSubmission> submit() async {
    submissions++;
    final pdf = await encodeScanPdf(
      draft.pages
          .map((page) => ScanPdfImage(page.thumbnail, page.width, page.height))
          .toList(),
    );
    sentPdf = pdf;
    final document = await upload.send(
      pdf,
      upload.prepare(draft.properties),
      'scan-browser-fixture.pdf',
      Completer<void>().future,
    );
    accepted = document;
    draft = ScanDraft(
      id: draft.id,
      revision: draft.revision + 1,
      properties: draft.properties,
      status: ScanDraftStatus.accepted,
      acceptedDocumentId: document.id,
    );
    return ScanSubmission(draft, document: document);
  }
}

Future<void> exerciseScannerWorkflow(
  WidgetTester tester,
  BrowserScannerFixture Function() current,
) async {
  debugPrint(
    'Scanner E2E: capture fixtures through real UI, encode PDF and persist Unicode metadata through API upload',
  );
  final title = 'Mobile scan Grüße 世界 ${DateTime.now().microsecondsSinceEpoch}';
  Future<void> tap(Key key) async {
    if (key == const Key('scanDocument')) {
      await revealWorkspaceAction(tester, 'scanDocument');
    }
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  await tap(const Key('documentsNavigation'));
  await tap(const Key('scanDocument'));
  for (var index = 0; index < 3; index++) {
    await tap(const Key('addScanPage'));
    await tap(const Key('captureScanPage'));
    await tap(const Key('keepScanPage'));
  }
  expect(current().repository.submissions, 0);
  await tap(const Key('removeScanPage-1'));
  expect(current().repository.draft.pages.map((page) => page.id), [
    'browser-page-1',
    'browser-page-3',
  ]);
  await tap(const Key('moveScanPageEarlier-1'));
  expect(current().repository.draft.pages.map((page) => page.id), [
    'browser-page-3',
    'browser-page-1',
  ]);
  final inputs = <String, String>{
    'title': title,
    'description': 'Scanner round-trip Grüße\nExact description 世界',
    'tags': 'Reviewed\nscanner',
    'documentDate': '2026-09-18',
    'sender': 'Scanner Sender',
    'recipients': 'First recipient\nSecond recipient',
    'cc': 'Copy recipient',
    'bcc': 'Hidden recipient',
    'subject': 'Scanned letter subject • 四月',
    'messageId': '<scanner-fixture@example.test>',
  };
  for (final entry in inputs.entries) {
    final finder = find.byKey(Key('scan-${entry.key}'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, entry.value);
    await tester.pumpAndSettle();
  }
  await tap(const Key('scan-kind'));
  await tester.tap(find.text('Letter').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('appearance-action')).last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('appearance-light')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('closeAppearance')));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('scan-title')))
        .controller!
        .text,
    title,
  );
  await tester.ensureVisible(find.text('Save and close'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save and close'));
  await tester.pumpAndSettle();
  await tap(const Key('scanDocument'));
  expect(
    tester
        .widget<TextField>(find.byKey(const Key('scan-title')))
        .controller!
        .text,
    title,
  );
  expect(current().repository.draft.pages.map((page) => page.id), [
    'browser-page-3',
    'browser-page-1',
  ]);
  await tap(const Key('uploadScan'));
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (find.text('Scan uploaded').evaluate().isEmpty &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(find.text('Scan uploaded'), findsOneWidget);
  final fixture = current();
  expect(fixture.repository.submissions, 1);
  final id = fixture.repository.accepted!.id;
  final documents = api.DocumentsApi(fixture.client);
  final saved = (await documents.getDocument(id))!;
  expect(saved.title, title);
  expect(saved.description, inputs['description']);
  expect(saved.tags, ['reviewed', 'scanner']);
  expect(saved.kind.toString(), 'letter');
  expect(saved.sender, inputs['sender']);
  expect(saved.recipients, ['First recipient', 'Second recipient']);
  expect(saved.cc, ['Copy recipient']);
  expect(saved.bcc, ['Hidden recipient']);
  expect(saved.documentDate, inputs['documentDate']);
  expect(saved.subject, inputs['subject']);
  expect(saved.messageId, inputs['messageId']);
  final original = await documents.downloadDocumentWithHttpInfo(id);
  expect(original.statusCode, 200);
  expect(original.bodyBytes, fixture.repository.sentPdf);
  expect(saved.file!.size, fixture.repository.sentPdf!.length);
  await tester.tap(find.text('Done'));
  final collectionDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (find.text(title).evaluate().isEmpty &&
      DateTime.now().isBefore(collectionDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text(title), findsOneWidget);
  expect(tester.takeException(), isNull);
}
