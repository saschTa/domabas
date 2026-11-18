import 'package:domabas/ui/glacier/glacier_controls.dart';
import 'package:domabas/ui/glacier/glacier_settings.dart';
import 'package:domabas/ui/glacier/glacier_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: GlacierTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('provider and model fields align at text scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlacierModelConnection(
                provider: 'external',
                onProviderChanged: (_) {},
                modelField: const GlacierField(label: 'Model'),
                contextField: const SizedBox.shrink(),
                credentialField: const SizedBox.shrink(),
                endpointField: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(DropdownButtonFormField<String>)).dy,
        tester.getTopLeft(find.byType(GlacierField)).dy,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'inherited permissions cannot be revoked while explicit grants remain editable',
    (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          GlacierPermissionGroup(
            title: 'Documents',
            permissions: const [
              GlacierPermission(
                id: 'read',
                label: 'Read documents',
                inherited: true,
              ),
              GlacierPermission(id: 'delete', label: 'Delete documents'),
            ],
            onChanged: (id, selected) => changes.add('$id:$selected'),
          ),
        ),
      );
      await tester.tap(find.text('Read documents'));
      await tester.tap(find.text('Delete documents'));
      expect(changes, ['delete:true']);
      expect(find.text('Included in this role'), findsOneWidget);
    },
  );

  testWidgets(
    'removing a stored credential disables replacement without losing its draft',
    (tester) async {
      final controller = TextEditingController(text: 'fictional replacement');
      addTearDown(controller.dispose);
      var remove = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => GlacierCredentialField(
              label: 'API key',
              controller: controller,
              configured: true,
              removeStored: remove,
              onRemoveChanged: (value) => setState(() => remove = value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Remove stored credential'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(controller.text, 'fictional replacement');
      await tester.tap(find.text('Remove stored credential'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(controller.text, 'fictional replacement');
    },
  );

  testWidgets(
    'hosted server is read-only and cannot start a replacement connection',
    (tester) async {
      final controller = TextEditingController(text: 'https://example.test');
      addTearDown(controller.dispose);
      var connected = false;
      await tester.pumpWidget(
        host(
          GlacierServerForm(
            address: controller,
            hosted: true,
            onConnect: () => connected = true,
          ),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Connect'), findsNothing);
      expect(connected, isFalse);
    },
  );

  testWidgets('settings actions remain reachable while long content scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.dark(),
        home: Scaffold(
          body: GlacierSettingsPage(
            sections: [
              for (var i = 0; i < 20; i++)
                Text(
                  'Setting $i with a longer description for a household archive',
                ),
            ],
            actions: [
              GlacierButton(
                label: 'Save changes',
                onPressed: () => saved = true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Save changes'));
    expect(saved, isTrue);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save changes').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'appearance uses caller-owned choices and opaque mode disables blur adjustment',
    (tester) async {
      String? changed;
      await tester.pumpWidget(
        host(
          GlacierAppearancePreferences(
            value: const GlacierAppearanceValue(reduceTransparency: true),
            onModeChanged: (value) => changed = value,
            onBackgroundChanged: (_) {},
            onPatternChanged: (_) {},
            onSoftnessChanged: (_) {},
            onTransparencyChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark').last);
      await tester.pumpAndSettle();
      expect(changed, 'dark');
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
