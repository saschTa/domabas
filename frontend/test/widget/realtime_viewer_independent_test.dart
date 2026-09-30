import 'package:domabas/domain/document/models/document.dart';
import 'package:domabas/domain/document/models/document_capabilities.dart';
import 'package:domabas/presentation/document/cubits/documents_cubit.dart';
import 'package:domabas/presentation/document/widgets/document_detail_dialog.dart';
import 'package:domabas/presentation/document/widgets/document_route_scope.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_document_repository.dart';

DocumentOcr _text(String text, int revision) => DocumentOcr(
  status: 'available',
  revision: revision,
  text: text,
  origin: 'manual',
  reason: null,
  semanticIndexing: 'ready',
);

void main() {
  testWidgets(
    'narrow owned inspector receives remote conflicts and deletion preserves selectable draft',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeDocumentRepository()
        ..records = [
          Document(
            id: 'mail',
            title: 'Mail',
            description: '',
            createdAt: DateTime.utc(2026),
            kind: 'email',
            file: DocumentFile(
              originalFilename: 'mail.eml',
              mediaType: 'message/rfc822',
              size: 100,
              sha256: 'a' * 64,
              ingestedAt: DateTime.utc(2026),
              uploaderId: 'user',
            ),
          ),
        ]
        ..ocr['mail'] = _text('Initial body', 1);
      final cubit = DocumentsCubit(
        repository,
        capabilities: const DocumentCapabilities(
          read: true,
          readOcr: true,
          updateOcr: true,
          update: true,
        ),
      );
      cubit.setActive(true);
      final observer = RouteObserver<ModalRoute<void>>();
      await tester.pumpWidget(
        DocumentRouteScope(
          observer: observer,
          child: MaterialApp(
            theme: AppTheme.light(),
            navigatorObservers: [observer],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => DocumentDetailDialog(
                        documentId: 'mail',
                        cubit: cubit,
                      ),
                    ),
                  ),
                  child: const Text('Open mail'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open mail'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Document details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extracted text'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit extracted text'));
      await tester.tap(find.text('Edit extracted text'));
      await tester.pumpAndSettle();
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Extracted text',
      );
      await tester.enterText(editor, 'My draft survives');
      await tester.pump();
      repository.ocr['mail'] = _text('Remote body', 2);
      cubit.invalidate();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(editor).controller!.text,
        'My draft survives',
      );
      expect(
        find.textContaining('Extracted text changed elsewhere'),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save extracted text'),
            )
            .onPressed,
        isNull,
      );
      repository.records.clear();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      cubit.invalidate();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentDetailDialog), findsOneWidget);
      expect(
        find.text(
          'This document was deleted. Copy any unsaved text before leaving.',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText && widget.data == 'My draft survives',
        ),
        findsWidgets,
      );
      expect(
        find.widgetWithText(FilledButton, 'Save extracted text'),
        findsNothing,
      );
      expect(find.byKey(const Key('email-body')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
