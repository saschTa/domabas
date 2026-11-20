import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_ocr_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
  testWidgets(
    'Android reads long OCR text with a single touch scroll',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lines = List.generate(2000, (index) => 'Document line $index');
      final content = lines.join('\r\n');
      final repository = FakeDocumentRepository()
        ..records = [
          Document(
            id: 'long',
            title: 'Long document',
            description: '',
            createdAt: DateTime.utc(2026),
          ),
        ]
        ..ocr['long'] = DocumentOcr(
          status: 'available',
          revision: 1,
          text: content,
          origin: 'machine',
          reason: null,
          semanticIndexing: 'ready',
        );
      final cubit = DocumentCubit(
        repository,
        id: 'long',
        capabilities: const DocumentCapabilities(read: true, readOcr: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentOcrPanel(cubit: cubit, onCancel: () {}),
          ),
        ),
      );

      final body = find.text(content);
      final position = Scrollable.of(tester.element(body)).position;
      final start =
          tester.getRect(find.byType(CustomScrollView)).bottomCenter -
          const Offset(0, 40);
      expect(tester.getRect(body).contains(start), isTrue);
      await tester.flingFrom(start, const Offset(0, -180), 1000);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(180));
      await tester.flingFrom(start, const Offset(0, 240), 2200);
      await tester.pumpAndSettle();
      expect(position.pixels, 0);

      await tester.enterText(find.byKey(const Key('ocrSearch')), lines.last);
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 matches'), findsOneWidget);
      final editor = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Extracted text',
        ),
      );
      expect(
        editor.controller!.selection.textInside(editor.controller!.text),
        lines.last,
      );
    },
    skip: kIsWeb,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'OCR search selects original Unicode ranges and literal queries',
    (tester) async {
      const content = 'İ Orchard\nİ ORCHARD\nLiteral [a+b] and another [a+b]';
      final repository = FakeDocumentRepository()
        ..records = [
          Document(
            id: 'letter',
            title: 'Letter',
            description: '',
            createdAt: DateTime.utc(2026),
          ),
        ]
        ..ocr['letter'] = const DocumentOcr(
          status: 'available',
          revision: 1,
          text: content,
          origin: 'manual',
          reason: null,
          semanticIndexing: 'ready',
        );
      final cubit = DocumentCubit(
        repository,
        id: 'letter',
        capabilities: const DocumentCapabilities(read: true, readOcr: true),
        onUpdated: (_) {},
        onDeleted: (_) async {},
      );
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentOcrPanel(cubit: cubit, onCancel: () {}),
          ),
        ),
      );
      final query = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Find in extracted text',
      );
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Extracted text',
      );
      await tester.enterText(query, 'orchard');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(editor).controller!;
      expect(find.text('1 of 2 matches'), findsOneWidget);
      expect(controller.selection.textInside(content), 'Orchard');
      expect(controller.selection.start, content.indexOf('Orchard'));
      await tester.tap(find.byTooltip('Next text match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 matches'), findsOneWidget);
      expect(controller.selection.textInside(content), 'ORCHARD');
      await tester.enterText(query, '[a+b]');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 matches'), findsOneWidget);
      expect(controller.selection.textInside(content), '[a+b]');
      await tester.tap(find.byTooltip('Previous text match'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 matches'), findsOneWidget);
      expect(controller.selection.start, content.lastIndexOf('[a+b]'));
      await tester.enterText(query, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );
}
