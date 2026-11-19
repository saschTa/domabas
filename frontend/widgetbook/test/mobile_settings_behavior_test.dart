import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone workload navigation previews a saved Paperless download limit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: catalogCases().firstWhere(
            (entry) => entry.id == 'mobile-more-ready',
          ),
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      final destination = find.text('Workload limits');
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('flow-pipeline-picker'));
      expect(picker.hitTestable(), findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      final paperless = find.text('Paperless imports').last;
      await tester.ensureVisible(paperless);
      await tester.tap(paperless);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 total'), findsOneWidget);
      final field = find.descendant(
        of: find.widgetWithText(
          GlacierMobileField,
          'Paperless downloads maximum parallel',
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '11');
      await tester.pump();
      expect(find.text('Enter a whole number from 1 to 10.'), findsOneWidget);
      final save = find.widgetWithText(GlacierButton, 'Save limits');
      expect(tester.widget<GlacierButton>(save).onPressed, isNull);
      await tester.enterText(field, '3');
      await tester.pump();
      expect(find.text('2 of 2 total'), findsOneWidget);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.ensureVisible(picker);
      expect(tester.widget<DropdownButton<String>>(picker).value, 'paperless');
      expect(find.text('2 of 3 total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in ['conflict', 'uncertain']) {
    testWidgets(
      'settings $state checks saved value before enabling retained draft',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          CatalogPreview(
            entry: catalogCases().firstWhere(
              (entry) => entry.id == 'mobile-workload-$state',
            ),
            reduceMotion: true,
          ),
        );
        await tester.pumpAndSettle();
        final first = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        first.controller!.text = '7';
        var save = tester.widget<GlacierButton>(
          find.widgetWithText(GlacierButton, 'Save limits'),
        );
        expect(save.onPressed, isNull);
        await tester.tap(
          find.text(
            state == 'conflict' ? 'Reload saved value' : 'Check saved value',
          ),
        );
        await tester.pumpAndSettle();
        save = tester.widget<GlacierButton>(
          find.widgetWithText(GlacierButton, 'Save limits'),
        );
        expect(save.onPressed, isNotNull);
        expect(first.controller!.text, '7');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('registration toggle retains the email draft', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: catalogCases().firstWhere(
          (entry) => entry.id == 'mobile-signin-ready',
        ),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'retained@example.com',
    );
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('retained@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inherited permissions remain selected and disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: catalogCases().firstWhere(
          (entry) => entry.id == 'mobile-access-ready',
        ),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    final choice = tester.widget<GlacierMobilePermissionChoice>(
      find.widgetWithText(GlacierMobilePermissionChoice, 'Read documents'),
    );
    expect(choice.selected, isTrue);
    expect(choice.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('license search filters records without losing the query', (
    tester,
  ) async {
    await tester.pumpWidget(
      CatalogPreview(
        entry: catalogCases().firstWhere(
          (entry) => entry.id == 'mobile-licenses-ready',
        ),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'DM Sans');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(GlacierMobileRecordRow, 'DM Sans'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(GlacierMobileRecordRow, 'Flutter'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
