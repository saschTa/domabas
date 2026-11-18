import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const previewKey = ValueKey('preview-paint');

Widget previewHost({
  bool dark = false,
  bool reduced = false,
  bool enabled = true,
  Size size = const Size(260, 180),
}) => MaterialApp(
  theme: dark ? GlacierTheme.dark() : GlacierTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: enabled,
        child: Center(
          child: RepaintBoundary(
            key: previewKey,
            child: SizedBox.fromSize(
              size: size,
              child: const GlacierPreviewPlaceholder(),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(previewKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = Uint8List.fromList(bytes!.buffer.asUint8List());
    image.dispose();
    return result;
  }))!;
}

void main() {
  testWidgets('native reduced-motion changes suspend an existing shimmer', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(previewHost());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(await pixels(tester), orderedEquals(before));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(await pixels(tester), isNot(orderedEquals(before)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cached offscreen previews pause and resume when revealed', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 260,
              height: 200,
              child: ListView(
                controller: scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                children: const [
                  SizedBox(height: 400),
                  SizedBox(height: 180, child: GlacierPreviewPlaceholder()),
                  SizedBox(height: 400),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final placeholder = find.byType(
      GlacierPreviewPlaceholder,
      skipOffstage: false,
    );
    expect(placeholder, findsOneWidget);
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: placeholder,
            matching: find.byType(CustomPaint, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        .painter!;
    var repaints = 0;
    void repaint() => repaints++;
    painter.addListener(repaint);
    await tester.pump(const Duration(milliseconds: 900));
    expect(repaints, 0);
    scroll.jumpTo(400);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(repaints, greaterThan(0));
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump();
    repaints = 0;
    await tester.pump(const Duration(milliseconds: 900));
    expect(repaints, 0);
    painter.removeListener(repaint);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  testWidgets('initially inactive and runtime reduced motion stay static', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(previewHost());
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(previewHost(reduced: true));
    await tester.pump(const Duration(milliseconds: 400));
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(await pixels(tester), orderedEquals(before));
  });

  for (final dark in [false, true]) {
    testWidgets('shimmer repaints inside stable bounds dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(previewHost(dark: dark));
      await tester.pump();
      final bounds = tester.getRect(find.byType(GlacierPreviewPlaceholder));
      final before = await pixels(tester);
      await tester.pump(const Duration(milliseconds: 900));
      final after = await pixels(tester);
      expect(after, isNot(orderedEquals(before)));
      expect(tester.getRect(find.byType(GlacierPreviewPlaceholder)), bounds);
      expect(bounds.size, const Size(260, 180));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reduced motion is static at compact thumbnail size', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      previewHost(reduced: true, size: const Size(64, 64)),
    );
    await tester.pump();
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(await pixels(tester), orderedEquals(before));
    expect(find.bySemanticsLabel('Preparing preview'), findsOneWidget);
    expect(
      tester.getSize(find.byType(GlacierPreviewPlaceholder)),
      const Size(64, 64),
    );
    semantics.dispose();
  });

  testWidgets('disabled ticker pauses and resumes the shimmer', (tester) async {
    await tester.pumpWidget(previewHost(enabled: false));
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(await pixels(tester), orderedEquals(before));
    await tester.pumpWidget(previewHost());
    await tester.pump(const Duration(milliseconds: 900));
    expect(await pixels(tester), isNot(orderedEquals(before)));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inactive app uses a static placeholder and resumes cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(previewHost());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final before = await pixels(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(await pixels(tester), orderedEquals(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(await pixels(tester), isNot(orderedEquals(before)));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
