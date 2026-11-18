import 'package:domabas/ui/domabas_ui.dart';
import 'package:domabas_widgetbook/catalog/documents_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final state in ['conflict', 'uncertain']) {
    testWidgets('$state requires checking the record and retains the draft', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: documentsCases().firstWhere(
            (entry) => entry.id == 'document-editor-$state',
          ),
          reduceMotion: true,
        ),
      );
      final save = find.widgetWithText(GlacierButton, 'Save changes');
      expect(tester.widget<GlacierButton>(save).onPressed, isNull);
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(title, 'My retained draft');
      await tester.tap(
        find.text(
          state == 'conflict' ? 'Reload saved record' : 'Check saved value',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(title).controller!.text,
        'My retained draft',
      );
      expect(
        find.textContaining('Sample saved record checked:'),
        findsOneWidget,
      );
      expect(find.text('Saved'), findsNothing);
      expect(tester.widget<GlacierButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
