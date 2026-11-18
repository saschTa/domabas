import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: GlacierTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('failed card retry does not open the document', (tester) async {
    var opens = 0, retries = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 280,
          child: GlacierDocumentCard(
            document: const GlacierDocumentValue(
              id: 'one',
              title: 'Electricity',
              failed: true,
              tags: ['Home'],
            ),
            preview: const ColoredBox(color: Colors.white),
            onOpen: () => opens++,
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Retry processing Electricity'));
    expect(retries, 1);
    expect(opens, 0);
    await tester.tap(find.text('Electricity'));
    expect(opens, 1);
  });

  testWidgets(
    'reader actions and related documents stay reachable at desktop and narrow widths',
    (tester) async {
      for (final width in [1440.0, 800.0, 390.0]) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        await tester.pumpWidget(
          _app(
            GlacierReader(
              title: 'A long electricity document title',
              contextLabel: 'Personal library · PDF',
              original: const Center(child: Text('Original')),
              toolbar: const SizedBox.shrink(),
              inspector: const GlacierRelatedDocuments(
                documents: [
                  GlacierRelatedDocument(
                    title: 'Source message',
                    relationship: 'Source email',
                  ),
                ],
              ),
              onEdit: () {},
              onResync: () {},
              onDelete: () {},
              onDownload: () {},
              onClose: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Delete document'), findsOneWidget);
        expect(find.text('Related documents'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('reader find shortcut and Escape route to find ownership', (
    tester,
  ) async {
    var opened = 0, closed = 0;
    final controller = TextEditingController();
    await tester.pumpWidget(
      _app(
        GlacierReader(
          title: 'Document',
          contextLabel: 'Personal',
          original: const SizedBox(),
          inspector: const SizedBox(),
          toolbar: const SizedBox(),
          onFind: () => opened++,
          onCloseFind: () => closed++,
          find: GlacierFindBar(controller: controller, resultLabel: '1 / 2'),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(opened, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('search commits once and Escape clears draft', (tester) async {
    var commits = 0, clears = 0;
    final controller = TextEditingController(text: 'electricity');
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            width: 600,
            height: 400,
            child: GlacierSearchDialog(
              controller: controller,
              filters: const Text('Document types'),
              onApply: () => commits++,
              onClear: () {
                clears++;
                controller.clear();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(commits, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(clears, 1);
    expect(controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'invoice keeps exact decimal text and pagination exposes older line items',
    (tester) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Column(
              children: [
                const GlacierInvoiceRow(
                  invoice: GlacierInvoiceValue(
                    number: 'CN-1',
                    supplier: 'Energy',
                    amount: '-123456789012345678901234.123456789012',
                    currency: 'EUR',
                  ),
                ),
                GlacierInvoiceRecords(
                  title: 'Line items',
                  pageSize: 1,
                  records: const [
                    GlacierInvoiceDetailRecord(
                      title: 'First',
                      values: {'Amount': '0.10 EUR'},
                    ),
                    GlacierInvoiceDetailRecord(
                      title: 'Second',
                      values: {'Amount': '0.20 EUR'},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text('-123456789012345678901234.123456789012 EUR'),
        findsOneWidget,
      );
      expect(find.text('Second'), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'waiting status has written meaning and reduced motion stays static',
    (tester) async {
      await tester.pumpWidget(
        _app(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Column(
              children: [
                SizedBox(
                  width: 280,
                  child: GlacierDocumentCard(
                    document: const GlacierDocumentValue(
                      id: 'one',
                      title: 'Electricity',
                      status: 'Waiting to start',
                      statusIcon: Icons.schedule,
                    ),
                    preview: const ColoredBox(color: Colors.white),
                  ),
                ),
                const GlacierDocumentRow(
                  document: GlacierDocumentValue(
                    id: 'two',
                    title: 'Insurance',
                    busy: true,
                    status: 'Processing',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byTooltip('Waiting to start'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'page entry is named, validates bounds, and disables without callback',
    (tester) async {
      var page = 1;
      await tester.pumpWidget(
        _app(
          GlacierPdfToolbar(
            page: 1,
            pageCount: 6,
            zoomLabel: '100%',
            onPageChanged: (value) => page = value,
          ),
        ),
      );
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).decoration?.hintText, 'Page');
      await tester.enterText(field, '99');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(find.text('Choose 1–6'), findsOneWidget);
      expect(page, 1);
      await tester.enterText(field, '3');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(page, 3);
      expect(find.text('Choose 1–6'), findsNothing);
      await tester.pumpWidget(
        _app(const GlacierPdfToolbar(page: 1, pageCount: 6, zoomLabel: '100%')),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    },
  );
}
