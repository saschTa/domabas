import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/settings_cases.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'appearance opens above the retained workspace and closes back to it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      GlacierAppearanceValue? changed;
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const Text('Retained document workspace'),
                  TextButton(
                    onPressed: () => showGlacierDialog<void>(
                      context: context,
                      builder: (_) => settingsDialog(
                        'appearance',
                        onAppearanceChanged: (value) => changed = value,
                      ),
                    ),
                    child: const Text('Appearance'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.byType(GlacierDialog), findsOneWidget);
      expect(find.text('Appearance and background'), findsOneWidget);
      expect(find.text('Retained document workspace'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(changed?.mode, 'dark');
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byType(GlacierDialog),
                    matching: find.byType(GlacierSurface),
                  )
                  .first,
            )
            .width,
        lessThanOrEqualTo(620),
      );
      await tester.tap(find.text('Back to the workspace'));
      await tester.pumpAndSettle();
      expect(find.byType(GlacierDialog), findsNothing);
      expect(
        find.text('Retained document workspace').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
