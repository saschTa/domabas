import 'dart:typed_data';

import 'package:domabas/app/app_dependencies.dart';
import 'package:domabas/app/domabas_app.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_email.dart';
import 'package:domabas/domain/document/models/document_search.dart';
import 'package:domabas/domain/identity/models/identity.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_activity_repository.dart';
import '../support/fake_appearance_repository.dart';
import '../support/fake_document_repository.dart';
import '../support/fake_email_repository.dart';
import '../support/fake_identity_repository.dart';
import '../support/fake_processing_repository.dart';
import '../support/fake_realtime_repository.dart';

final class _Documents extends FakeDocumentRepository {
  final criteria = <DocumentSearchCriteria>[];
  int downloads = 0;

  @override
  Future<Uint8List> download(
    DocumentOriginalRef document, {
    Future<void>? cancel,
  }) {
    downloads++;
    return super.download(document, cancel: cancel);
  }

  @override
  Future<DocumentSearchPage> search(
    DocumentSearchCriteria value, {
    int limit = 12,
    String? cursor,
    Future<void>? cancel,
  }) async {
    criteria.add(value);
    final mail = records.first;
    return DocumentSearchPage(
      items: [
        DocumentSearchResult(
          id: mail.id,
          title: mail.title,
          kind: mail.kind,
          tags: [],
          createdAt: mail.createdAt,
          snippet: 'Search excerpt',
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<DocumentEmailLinks> emailLinks(
    String id, {
    String? cursor,
    Future<void>? cancel,
  }) async => DocumentEmailLinks(
    attachments: id == 'mail'
        ? const [
            DocumentEmailAttachment(
              part: '1',
              filename: 'Linked mail',
              status: 'accepted',
              document: DocumentLink(
                id: 'child',
                title: 'Linked mail',
                mediaType: 'message/rfc822',
              ),
            ),
          ]
        : const [],
  );
}

Document _mail(String id, String title) => Document(
  id: id,
  title: title,
  description: '',
  createdAt: DateTime.utc(2026),
  kind: 'email',
  file: DocumentFile(
    originalFilename: '$id.eml',
    mediaType: 'message/rfc822',
    size: 100,
    sha256: 'a' * 64,
    ingestedAt: DateTime.utc(2026),
    uploaderId: 'user',
  ),
);

void main() {
  late _Documents documents;
  late FakeAppearanceRepository appearance;
  late FakeRealtimeRepository realtime;
  var scopes = 0;
  var closes = 0;

  Future<void> mount(WidgetTester tester, {double width = 640}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    documents = _Documents()
      ..records = [_mail('mail', 'Main email'), _mail('child', 'Linked mail')]
      ..ocr['mail'] = const DocumentOcr(
        status: 'available',
        revision: 7,
        text: 'Original message body',
        origin: 'machine',
        reason: null,
        semanticIndexing: 'ready',
      );
    appearance = FakeAppearanceRepository();
    realtime = FakeRealtimeRepository();
    scopes = 0;
    closes = 0;
    final session = testSession(
      extraPermissions: [
        IdentityPermission.searchDocuments,
        IdentityPermission.updateDocuments,
        IdentityPermission.readDocumentOcr,
        IdentityPermission.updateDocumentOcr,
        IdentityPermission.connectRealtime,
      ],
    );
    await tester.pumpWidget(
      DomabasApp(
        auth: FakeAuthRepository()..saved = session,
        appearance: appearance,
        authenticate: (_, _) {
          scopes++;
          return AuthenticatedDependencies(
            documents: documents,
            identity: FakeIdentityRepository(),
            processing: FakeProcessingRepository(),
            email: FakeEmailRepository(),
            activity: FakeActivityRepository(),
            realtime: realtime,
            externalLinks: FakeExternalLinkLauncher(),
            close: () => closes++,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String id) async {
    final action = find.byKey(const Key('appearance-action')).last;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('appearance-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('closeAppearance')));
    await tester.pumpAndSettle();
  }

  Future<void> openMail(WidgetTester tester) async {
    final card = find.byKey(const Key('document-mail'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'narrow dirty OCR inspector keeps route, controller, selection and edit base through themes',
    (tester) async {
      await mount(tester);
      await openMail(tester);
      final viewer = tester.state(find.byType(DocumentDetailDialog));
      await tester.tap(find.byTooltip('Document details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extracted text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit extracted text'));
      await tester.pumpAndSettle();
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Extracted text',
      );
      await tester.enterText(editor, 'Copyable unsaved OCR draft');
      final controller = tester.widget<TextField>(editor).controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );
      final route = ModalRoute.of(tester.element(editor));
      final inspector = tester.element(find.text('Document details'));
      final connects = realtime.connectCalls;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(editor)).brightness, Brightness.dark);
      final sheetSurface = tester
          .widgetList<Material>(
            find.ancestor(of: editor, matching: find.byType(Material)),
          )
          .firstWhere((widget) => widget.color != null && widget.color!.a == 1);
      expect(sheetSurface.color, AppTheme.dark().colorScheme.surface);
      expect(ModalRoute.of(tester.element(editor)), same(route));
      expect(tester.element(find.text('Document details')), same(inspector));
      await choose(tester, 'light');
      expect(Theme.of(tester.element(editor)).brightness, Brightness.light);
      expect(tester.widget<TextField>(editor).controller, same(controller));
      expect(controller.text, 'Copyable unsaved OCR draft');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 8),
      );
      expect(
        tester.state(find.byType(DocumentDetailDialog, skipOffstage: false)),
        same(viewer),
      );
      expect(documents.ocr['mail']!.revision, 7);
      expect(documents.ocr['mail']!.text, 'Original message body');
      expect(documents.downloads, 0);
      expect(scopes, 1);
      expect(closes, 0);
      expect(realtime.connectCalls, connects);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'search result viewer preserves automatic search intent and dirty properties across appearance changes',
    (tester) async {
      await mount(tester, width: 1400);
      final search = find.byKey(const Key('documentSearchTerm'));
      await tester.enterText(search, 'applied words');
      await tester.tap(find.byKey(const Key('applyDocumentSearch')));
      await tester.pumpAndSettle();
      await tester.enterText(search, 'unsubmitted new words');
      final searchController = tester.widget<TextField>(search).controller!;
      await tester.tap(find.byKey(const Key('search-document-mail')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Document details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit properties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit properties'));
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('edit-title'));
      await tester.enterText(title, 'Unsaved metadata');
      final controller = tester.widget<TextFormField>(title).controller!;
      final viewer = tester.state(find.byType(DocumentDetailDialog));
      await choose(tester, 'dark');
      expect(tester.widget<TextFormField>(title).controller, same(controller));
      expect(controller.text, 'Unsaved metadata');
      expect(tester.state(find.byType(DocumentDetailDialog)), same(viewer));
      expect(documents.records.first.title, 'Main email');
      await tester.tap(find.byKey(const Key('closeDocument')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(search).controller,
        same(searchController),
      );
      expect(searchController.text, 'unsubmitted new words');
      expect(documents.criteria, isNotEmpty);
      expect(documents.criteria.map((value) => value.query), [
        'applied words',
        'unsubmitted new words',
      ]);
      expect(scopes, 1);
      expect(closes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'nested linked viewer receives the same appearance action and retains parent route',
    (tester) async {
      await mount(tester, width: 1400);
      await openMail(tester);
      final parent = tester.state(find.byType(DocumentDetailDialog));
      final attachment = find.descendant(
        of: find.byKey(const Key('documentInspectorPanel')),
        matching: find.byKey(const Key('email-attachment-1')),
      );
      await tester.ensureVisible(attachment);
      await tester.tap(attachment);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DocumentDetailDialog>(
              find.byType(DocumentDetailDialog).last,
            )
            .documentId,
        'child',
      );
      final child = tester.state(find.byType(DocumentDetailDialog).last);
      await choose(tester, 'dark');
      expect(tester.state(find.byType(DocumentDetailDialog).last), same(child));
      expect(
        Theme.of(tester.element(find.byType(DocumentDetailDialog).last))
            .brightness,
        Brightness.dark,
      );
      await tester.tap(find.byKey(const Key('closeDocument')).last);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(DocumentDetailDialog)), same(parent));
      expect(
        tester
            .widget<DocumentDetailDialog>(find.byType(DocumentDetailDialog))
            .documentId,
        'mail',
      );
      expect(
        Theme.of(tester.element(find.byType(DocumentDetailDialog))).brightness,
        Brightness.dark,
      );
      expect(documents.downloads, 0);
      expect(scopes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
