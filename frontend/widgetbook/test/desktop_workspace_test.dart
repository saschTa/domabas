import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/desktop_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop utilities open modals over the retained workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: desktopCases().singleWhere(
          (entry) => entry.id == 'desktop-workspace',
        ),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Invoices').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI chat').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Appearance').first);
    await tester.pumpAndSettle();
    expect(find.byType(GlacierDialog), findsOneWidget);
    expect(find.byType(GlacierWorkspace), findsOneWidget);
    expect(find.byType(GlacierAppearancePreferences), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GlacierDialog), findsNothing);
    await tester.tap(find.byTooltip('Select library').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to Family library'));
    await tester.pumpAndSettle();
    expect(find.text('Family library'), findsWidgets);
    expect(find.byType(GlacierDialog), findsNothing);
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    expect(find.byType(GlacierSearchDialog), findsOneWidget);
    expect(find.byType(GlacierWorkspace), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GlacierSearchDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
