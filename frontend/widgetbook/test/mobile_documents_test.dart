import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/mobile_documents_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = mobileDocumentsCases();
  test('A owns57 frozen screen states and18 isolated public widgets', () {
    expect(cases.where((entry) => entry.referenceScreen != null).length, 57);
    expect(cases.where((entry) => entry.referenceComponent != null).length, 18);
    expect(cases.map((entry) => entry.id).toSet().length, cases.length);
  });

  for (final entry in cases) {
    for (final configuration in const [
      (Size(320, 740), 1.0, false),
      (Size(390, 844), 1.0, true),
      (Size(768, 1024), 1.0, false),
      (Size(320, 740), 2.0, false),
    ]) {
      testWidgets(
        '${entry.id} ${configuration.$1.width} text${configuration.$2} ${configuration.$3}',
        (tester) async {
          await tester.binding.setSurfaceSize(configuration.$1);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            CatalogPreview(
              entry: entry,
              dark: configuration.$3,
              textScale: configuration.$2,
              reduceMotion: true,
              keyboard: entry.referenceState == 'keyboard',
              platform: configuration.$3
                  ? TargetPlatform.android
                  : TargetPlatform.iOS,
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull, reason: entry.id);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  Future<void> pumpCase(WidgetTester tester, String id) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CatalogPreview(
        entry: cases.firstWhere((entry) => entry.id == id),
        reduceMotion: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('retry and selection have separate card callbacks and48targets', (
    tester,
  ) async {
    var opened = 0, retried = 0, selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: glacierMobileTheme(GlacierTheme.light()),
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: GlacierMobileDocumentCard(
              document: const GlacierDocumentValue(
                id: 'test',
                title: 'Energy',
                failed: true,
              ),
              preview: const SizedBox(),
              selected: false,
              onOpen: () => opened++,
              onRetry: () => retried++,
              onSelectionChanged: (_) => selected++,
            ),
          ),
        ),
      ),
    );
    final retry = find.byTooltip('Retry processing Energy');
    expect(tester.getSize(retry).width, greaterThanOrEqualTo(48));
    await tester.tap(retry);
    expect(retried, 1);
    expect(opened, 0);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Select Energy',
      ),
    );
    expect(selected, 1);
    expect(opened, 0);
  });

  testWidgets(
    'iOS extension exposes close without application back navigation',
    (tester) async {
      await pumpCase(tester, 'mobile-share-ios-ready');
      expect(find.byTooltip('Back'), findsNothing);
      expect(find.byTooltip('Close extension'), findsOneWidget);
      expect(find.byType(GlacierMobileNavigation), findsNothing);
      await tester.tap(find.byTooltip('Close extension'));
      await tester.pump();
      expect(
        find.text('Preview: extension closes without uploading'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'search commits query and filters together and returns retained results',
    (tester) async {
      await pumpCase(tester, 'mobile-documents-ready');
      await tester.tap(find.text('Find a document'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'Energy');
      await tester.tap(find.text('Home').last);
      await tester.tap(find.text('Apply search'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Energy statement'), findsNWidgets(2));
      expect(find.text('Forma Studio'), findsNothing);
      await tester.tap(find.text('Energy statement').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('€142.80'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Energy statement'), findsNWidgets(2));
      expect(find.text('Forma Studio'), findsNothing);
    },
  );

  testWidgets('IME Enter does not apply and Escape clears before closing', (
    tester,
  ) async {
    await pumpCase(tester, 'mobile-search-ready');
    final query = find.byType(TextField).first;
    await tester.tap(query);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Home',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(GlacierMobileSearchFilters), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Home',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(GlacierMobileSearchFilters), findsOneWidget);
    expect(tester.widget<TextField>(query).controller!.text, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(GlacierMobileSearchFilters), findsNothing);
  });

  testWidgets('draft removal and keep confirmation preserve page count', (
    tester,
  ) async {
    await pumpCase(tester, 'mobile-scan-review-ready');
    await tester.tap(find.byTooltip('Remove page 1'));
    await tester.pump();
    expect(find.text('2 of 20'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Keep draft'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 of 20'), findsOneWidget);
  });

  testWidgets('pending scan blocks acquisition and submission', (tester) async {
    await pumpCase(tester, 'mobile-scan-review-pending');
    final buttons = tester
        .widgetList<GlacierButton>(find.byType(GlacierButton))
        .toList();
    expect(buttons.firstWhere((b) => b.label == 'Add page').onPressed, isNull);
    expect(
      buttons.firstWhere((b) => b.label == 'Upload 3-page PDF').onPressed,
      isNull,
    );
  });

  testWidgets('uncertain metadata requires check and retains draft', (
    tester,
  ) async {
    await pumpCase(tester, 'mobile-properties-uncertain');
    final properties = find.byType(GlacierMobileDocumentProperties);
    expect(properties, findsOneWidget);
    var save = tester
        .widgetList<GlacierButton>(find.byType(GlacierButton))
        .firstWhere((b) => b.label == 'Save properties');
    expect(save.onPressed, isNull);
    await tester.tap(find.text('Check saved value'));
    await tester.pump();
    save = tester
        .widgetList<GlacierButton>(find.byType(GlacierButton))
        .firstWhere((b) => b.label == 'Save properties');
    expect(save.onPressed, isNotNull);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .controller!
          .text,
      'Forma Studio',
    );
  });

  testWidgets('unknown upload has no automatic retry callback', (tester) async {
    await pumpCase(tester, 'mobile-upload-uncertain');
    expect(
      tester
          .widget<GlacierMobileUploadOutcome>(
            find.byType(GlacierMobileUploadOutcome),
          )
          .onRetryExact,
      isNull,
    );
    await tester.ensureVisible(find.text('Check receipt'));
    await tester.tap(find.text('Check receipt'));
    await tester.pump();
    expect(find.text('Original accepted'), findsOneWidget);
    expect(find.textContaining('indexing continue'), findsOneWidget);
  });

  testWidgets('property draft survives reader roundtrip before save', (
    tester,
  ) async {
    await pumpCase(tester, 'mobile-properties-ready');
    await tester.enterText(
      find.byType(TextField).first,
      'My retained document title',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Properties'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'My retained document title',
    );
  });
}
