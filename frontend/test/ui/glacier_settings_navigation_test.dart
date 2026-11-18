import 'package:domabas/ui/glacier/glacier_settings.dart';
import 'package:domabas/ui/glacier/glacier_controls.dart';
import 'package:domabas/ui/glacier/glacier_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {double scale = 1, bool dark = false}) =>
      MaterialApp(
        theme: dark ? GlacierTheme.dark() : GlacierTheme.light(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: child,
          ),
        ),
      );

  testWidgets('overview activates exact destination with the keyboard', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      host(
        GlacierSettingsOverview(
          destinations: const [
            GlacierSettingsDestination(
              id: 'library-members',
              label: 'Members',
              description: 'Manage access to this library.',
              icon: Icons.people_outline,
            ),
          ],
          onSelected: selected.add,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['library-members']);
  });

  for (final width in [390.0, 800.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'section actions and parent navigation remain reachable at $width dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var back = 0;
          var saved = 0;
          await tester.pumpWidget(
            host(
              GlacierSettingsPage(
                header: GlacierSettingsHeader(
                  parentLabel: 'Admin settings',
                  title: 'Document processing and analysis',
                  onBack: () => back++,
                ),
                sections: [
                  GlacierSettingsSection(
                    title: 'Processing preferences',
                    description: 'Choose how new documents are indexed and analyzed in this library. Existing documents keep their current results.',
                    actions: [
                      GlacierButton(
                        label: 'Save preferences',
                        onPressed: () => saved++,
                      ),
                    ],
                    child: const GlacierField(
                      label: 'Maximum active background jobs',
                      error: 'Enter a whole number between one and twenty.',
                    ),
                  ),
                ],
              ),
              scale: 2,
              dark: dark,
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Admin settings'));
          expect(back, 1);
          await tester.scrollUntilVisible(
            find.text('Save preferences'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Save preferences'));
          expect(saved, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
