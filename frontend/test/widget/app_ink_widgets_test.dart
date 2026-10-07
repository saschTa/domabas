import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  bool dark = false,
  bool reduced = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Directionality(
      textDirection: direction,
      child: Center(child: SizedBox(width: 100, child: child)),
    ),
  ),
);

Future<ByteData> _pixels(
  WidgetTester tester,
  Finder owner, {
  double height = 10,
}) async {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: owner, matching: find.byType(CustomPaint)),
  );
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3);
    paint.painter!.paint(canvas, Size(100, height));
    final picture = recorder.endRecording();
    final image = await picture.toImage(300, (height * 3).round());
    final bytes = await image.toByteData();
    image.dispose();
    picture.dispose();
    return bytes!;
  }))!;
}

int _pixelOffset(int x, int y) => ((y * 3 + 1) * 300 + x * 3 + 1) * 4;

int _alpha(ByteData bytes, int x, int y) =>
    bytes.getUint8(_pixelOffset(x, y) + 3);

void main() {
  for (final dark in [false, true]) {
    testWidgets('section dividers paint one fine solid rule dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const AppStripedDivider(thickness: 11), dark: dark),
      );
      final pixels = await _pixels(
        tester,
        find.byType(AppStripedDivider),
        height: 11,
      );
      final row = List.generate(80, (i) => _alpha(pixels, i + 10, 5));
      expect(row, everyElement(255));
      for (var x = 0; x < 100; x++) {
        expect(_alpha(pixels, x, 3), 0);
        expect(_alpha(pixels, x, 6), 0);
      }
      expect(_alpha(pixels, 0, 0), 0);
      final x = 10 + row.indexOf(255);
      final ink = (dark ? AppTheme.dark() : AppTheme.light())
          .colorScheme
          .outlineVariant;
      expect(pixels.getUint8(_pixelOffset(x, 5)), (ink.r * 255).round());
      expect(pixels.getUint8(_pixelOffset(x, 5) + 1), (ink.g * 255).round());
      expect(pixels.getUint8(_pixelOffset(x, 5) + 2), (ink.b * 255).round());
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('progress fills the leading fraction for $direction', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const AppStripedProgressIndicator(
            value: .25,
            minHeight: 10,
            semanticsLabel: 'Uploading',
          ),
          direction: direction,
        ),
      );
      expect(
        tester.getSemantics(find.byType(AppStripedProgressIndicator)),
        matchesSemantics(label: 'Uploading', value: '25%'),
      );
      final pixels = await _pixels(
        tester,
        find.byType(AppStripedProgressIndicator),
      );
      for (var x = 0; x < 100; x++) {
        final outside = direction == TextDirection.ltr ? x >= 25 : x < 75;
        if (outside) {
          for (var y = 0; y < 10; y++) {
            expect(_alpha(pixels, x, y), 0);
          }
        }
      }
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      semantics.dispose();
    });
  }

  for (final platform in [false, true]) {
    testWidgets('indeterminate motion stops at runtime platform=$platform', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const indicator = AppStripedProgressIndicator(
        minHeight: 10,
        semanticsLabel: 'Loading',
      );
      await tester.pumpWidget(_app(indicator));
      await tester.pump(const Duration(milliseconds: 200));
      final movingPixels = await _pixels(
        tester,
        find.byType(AppStripedProgressIndicator),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final nextPixels = await _pixels(
        tester,
        find.byType(AppStripedProgressIndicator),
      );
      expect(
        movingPixels.buffer.asUint8List(),
        isNot(nextPixels.buffer.asUint8List()),
      );
      expect(tester.binding.hasScheduledFrame, isTrue);
      if (platform) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      } else {
        await tester.pumpWidget(_app(indicator, reduced: true));
      }
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.getSemantics(find.byType(AppStripedProgressIndicator)),
        matchesSemantics(label: 'Loading', value: 'In progress'),
      );
      final pixels = await _pixels(
        tester,
        find.byType(AppStripedProgressIndicator),
      );
      for (var x = 0; x < 100; x++) {
        if (x < 36 || x >= 64) expect(_alpha(pixels, x, 5), 0);
      }
      expect(
        List.generate(
          28,
          (i) => _alpha(pixels, 36 + i, 5),
        ).where((alpha) => alpha > 0),
        isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('inactive refresh preserves height and active state is unknown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const AppProgressSlot(active: false)));
    expect(tester.getSize(find.byType(AppProgressSlot)).height, 4);
    await tester.pumpWidget(
      _app(const AppProgressSlot(active: true), reduced: true),
    );
    expect(tester.getSize(find.byType(AppProgressSlot)).height, 4);
    expect(
      tester.getSemantics(find.byType(AppStripedProgressIndicator)),
      matchesSemantics(label: 'Loading', value: 'In progress'),
    );
    semantics.dispose();
  });
}
