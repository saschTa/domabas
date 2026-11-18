import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
