import 'dart:ui' as ui;

import 'package:domabas/ui/app_paper_canvas.dart';
import 'package:domabas/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('${theme.brightness} canvas paints dots with plain gaps', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Center(
            child: AppPaperCanvas(child: SizedBox(width: 40, height: 40)),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(AppPaperCanvas),
          matching: find.byType(CustomPaint),
        ),
      );
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(40, 40));
      final picture = recorder.endRecording();
      final pixels = await tester.runAsync(() async {
        final image = await picture.toImage(40, 40);
        final data = await image.toByteData();
        image.dispose();
        return data!;
      });
      picture.dispose();
      int pixel(int x, int y) => pixels!.getUint32((y * 40 + x) * 4);
      final canvasArgb = theme.scaffoldBackgroundColor.toARGB32();
      final canvasRgba = ((canvasArgb & 0xffffff) << 8) | 0xff;
      expect(pixel(0, 0), canvasRgba);
      expect(pixel(20, 20), canvasRgba);
      expect(pixel(10, 10), isNot(canvasRgba));
      expect(pixel(10, 10), pixel(30, 30));
      expect(tester.getSize(find.byType(AppPaperCanvas)), const Size(40, 40));
      expect(paint.painter!.hitTest(Offset.zero), isFalse);
    });
  }

  testWidgets('canvas leaves child interaction and empty hit regions intact', (
    tester,
  ) async {
    var backgroundTaps = 0;
    var childTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => backgroundTaps++,
                  ),
                ),
                AppPaperCanvas(
                  child: SizedBox(
                    width: 200,
                    height: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => childTaps++,
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    expect(childTaps, 1);
    expect(backgroundTaps, 0);
    await tester.tapAt(
      tester.getTopLeft(find.byType(AppPaperCanvas)) + const Offset(180, 50),
    );
    expect(childTaps, 1);
    expect(backgroundTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
