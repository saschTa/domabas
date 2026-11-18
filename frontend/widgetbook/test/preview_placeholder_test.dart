import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preparation gives way to ready and failure without changing card size',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        CatalogPreview(
          entry: catalogCases().singleWhere(
            (entry) => entry.id == 'document-preview-lifecycle',
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      final bounds = tester.getRect(find.byType(GlacierDocumentCard));
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
      await tester.tap(find.widgetWithText(GlacierButton, 'Preview ready'));
      await tester.pump();
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      expect(tester.getRect(find.byType(GlacierDocumentCard)), bounds);
      await tester.tap(
        find.widgetWithText(GlacierButton, 'Preview unavailable'),
      );
      await tester.pump();
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      expect(
        find.bySemanticsLabel('Retry preview Household insurance.pdf'),
        findsOneWidget,
      );
      final retry = find.byType(GlacierPreviewRetry);
      expect(bounds.contains(tester.getCenter(retry)), isTrue);
      await tester.tap(retry);
      await tester.pump();
      expect(find.byType(GlacierPreviewPlaceholder), findsOneWidget);
      await tester.tap(find.widgetWithText(GlacierButton, 'No preview'));
      await tester.pump();
      expect(find.byType(GlacierPreviewPlaceholder), findsNothing);
      expect(tester.getRect(find.byType(GlacierDocumentCard)), bounds);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
