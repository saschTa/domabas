import 'dart:typed_data';

import 'package:domabas/domain/document/interfaces/document_file_saver.dart';
import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  testWidgets('rounded download action saves an email original at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = FakeDocumentRepository()
      ..records = [
        Document(
          id: 'email',
          title: 'A long email document title',
          description: '',
          createdAt: DateTime.utc(2026),
          file: DocumentFile(
            originalFilename: 'email.eml',
            mediaType: 'message/rfc822',
            size: 3,
            sha256: 'a' * 64,
            ingestedAt: DateTime.utc(2026),
            uploaderId: 'user',
          ),
        ),
      ]
      ..originals['email'] = Uint8List.fromList([1, 2, 3]);
    final saver = _AccessibleDocumentFileSaver();
    final collection = DocumentsCubit(
      repository,
      capabilities: const DocumentCapabilities(read: true, download: true),
      fileSaver: saver,
    );
    addTearDown(collection.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DocumentDetailDialog(documentId: 'email', cubit: collection),
      ),
    );
    await tester.pumpAndSettle();
    final download = find.byTooltip('Download original');
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(tester.getSize(download).width, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(saver.filename, 'email.eml');
    expect(saver.bytes, [1, 2, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('document inspector remains usable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = FakeDocumentRepository()
      ..records = [
        Document(
          id: 'letter',
          title: 'A long document title for accessible reading',
          description: 'Letter details',
          createdAt: DateTime.utc(2026),
          file: DocumentFile(
            originalFilename: 'letter.pdf',
            mediaType: 'application/pdf',
            size: 200,
            sha256: 'a' * 64,
            ingestedAt: DateTime.utc(2026),
            uploaderId: 'user',
          ),
        ),
      ]
      ..ocr['letter'] = const DocumentOcr(
        status: 'available',
        revision: 1,
        text: 'Readable extracted letter text',
        origin: 'machine',
        reason: null,
        semanticIndexing: 'ready',
      );
    final collection = DocumentsCubit(
      repository,
      capabilities: const DocumentCapabilities(
        read: true,
        update: true,
        readOcr: true,
        updateOcr: true,
        delete: true,
      ),
    );
    addTearDown(collection.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => DocumentDetailDialog.open(
                context,
                documentId: 'letter',
                cubit: collection,
              ),
              child: const Text('Open letter'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open letter'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.byKey(const Key('documentDetails'))).dx, 8);
    expect(find.byKey(const Key('downloadDocument')), findsNothing);
    await tester.tap(find.byTooltip('Document details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('documentInspectorWindow')), findsOneWidget);
    await tester.tap(find.text('Edit properties'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-title')),
      'Revised title',
    );
    await tester.scrollUntilVisible(
      find.text('Save properties'),
      200,
      scrollable: find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save properties'));
    await tester.pumpAndSettle();
    expect(repository.records.single.title, 'Revised title');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Extracted text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit extracted text'));
    await tester.pumpAndSettle();
    final editor = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Extracted text',
    );
    final ocrScroll = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(editor, 200, scrollable: ocrScroll);
    await tester.pumpAndSettle();
    expect(tester.getSize(editor).height, greaterThan(0));
    await tester.enterText(editor, 'Unsaved correction');
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(editor).controller!.text,
      'Unsaved correction',
    );
    await tester.scrollUntilVisible(
      find.text('Save extracted text'),
      -200,
      scrollable: ocrScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save extracted text'));
    await tester.pumpAndSettle();
    expect(repository.ocr['letter']!.text, 'Unsaved correction');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('closeDocument')));
    await tester.pumpAndSettle();
    expect(find.text('Open letter'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'wide window shows details beside the document and protects drafts',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeDocumentRepository()
        ..records = [
          Document(
            id: 'letter',
            title: 'Letter',
            description: 'Letter details',
            createdAt: DateTime.utc(2026),
          ),
        ];
      final collection = DocumentsCubit(
        repository,
        capabilities: const DocumentCapabilities(read: true, update: true),
      );
      addTearDown(collection.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => DocumentDetailDialog.open(
                  context,
                  documentId: 'letter',
                  cubit: collection,
                ),
                child: const Text('Open letter'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open letter'));
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('documentInspectorPanel'));
      expect(panel, findsOneWidget);
      expect(
        tester.getTopLeft(panel).dx,
        greaterThan(tester.getBottomRight(find.text('No original file')).dx),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('documentDetails'))).dx,
        24,
      );
      await tester.tap(find.text('Edit properties'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit-title')),
        'Draft title',
      );
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('edit-title')))
            .controller!
            .text,
        'Draft title',
      );
      await tester.tap(find.byKey(const Key('closeDocument')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Open letter'), findsOneWidget);
      expect(repository.records.single.title, 'Letter');
      expect(tester.takeException(), isNull);
    },
  );
}

final class _AccessibleDocumentFileSaver implements DocumentFileSaver {
  String? filename;
  Uint8List? bytes;

  @override
  Future<void> save(DocumentFile file, Uint8List bytes) async {
    filename = file.originalFilename;
    this.bytes = bytes;
  }
}
