import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/document_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_ocr_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

void main() {
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
            widget.decoration?.labelText == 'Find in extracted text',
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
  );
}
