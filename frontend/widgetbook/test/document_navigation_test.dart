import 'package:domabas/ui/domabas_ui.dart';
import 'package:domabas_widgetbook/catalog/documents_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invoice details and original preserve the selected invoice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: documentsCases().firstWhere(
          (entry) => entry.id == 'invoice-collection',
        ),
        reduceMotion: true,
      ),
    );
    await tester.tap(find.byTooltip('Open invoice FS-2026-042'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GlacierInvoiceDetails>(find.byType(GlacierInvoiceDetails))
          .title,
      'Invoice FS-2026-042',
    );
    final sections = tester.widgetList<GlacierInvoiceSection>(
      find.byType(GlacierInvoiceSection),
    );
    expect(
      sections.any((section) => section.values['Name'] == 'Forma Studio'),
      isTrue,
    );
    expect(
      sections.any(
        (section) => section.values['Total including tax'] == '1,785.00 EUR',
      ),
      isTrue,
    );
    await tester.tap(find.text('Open original'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GlacierReader>(find.byType(GlacierReader)).title,
      'Design services · October',
    );
    expect(find.text('€1,785.00'), findsNWidgets(2));
    expect(find.textContaining('Invoice FS-2026-042 · Page 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a grid record preserves its identity in the reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: documentsCases().firstWhere(
            (entry) => entry.id == 'documents-grid',
          ),
          reduceMotion: true,
        ),
      );
      final openRecord = find.bySemanticsLabel(
        RegExp('Open Studio lease · 2026'),
      );
      expect(openRecord, findsOneWidget);
      await tester.tap(openRecord);
      await tester.pumpAndSettle();
      final reader = tester.widget<GlacierReader>(find.byType(GlacierReader));
      expect(reader.title, 'Studio lease · 2026');
      expect(reader.contextLabel, 'Personal library · PDF · 8 pages');
      final properties = tester.widgetList<GlacierPropertyGrid>(
        find.byType(GlacierPropertyGrid),
      );
      expect(
        properties.any(
          (grid) => grid.values['Sender'] == 'Nordhaus Immobilien',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close document'));
      await tester.pumpAndSettle();
      expect(find.byType(GlacierReader), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
