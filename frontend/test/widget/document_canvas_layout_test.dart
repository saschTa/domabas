import 'package:domabas/presentation/document/widgets/document_canvas_layout.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(1440, 900),
    const Size(320, 568),
    const Size(844, 320),
  ]) {
    testWidgets('floating controls overlay the full canvas at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var canvasTaps = 0;
      var controlTaps = 0;
      var controlsHeight = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DocumentCanvasLayout(
              onControlsHeight: (height) => controlsHeight = height,
              canvas: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => canvasTaps++,
                child: const ColoredBox(color: Colors.green),
              ),
              controls: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final label in [
                    'Previous page',
                    'Next page',
                    'Zoom out',
                    'Zoom in',
                    'Fit',
                    'Find in PDF',
                  ])
                    TextButton(
                      onPressed: () => controlTaps++,
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const Key('documentCanvasViewport')),
      );
      final controls = tester.getRect(
        find.byKey(const Key('documentCanvasControls')),
      );
      expect(viewport.size, size);
      expect(controls.top, lessThan(viewport.bottom));
      expect(controls.bottom, lessThan(viewport.bottom));
      expect(controls.left, greaterThan(viewport.left));
      expect(controls.right, lessThan(viewport.right));
      expect(controlsHeight, greaterThan(controls.height));
      await tester.tapAt(Offset(2, controls.center.dy));
      expect(canvasTaps, 1);
      await tester.ensureVisible(find.text('Find in PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find in PDF'));
      expect(controlTaps, 1);
      expect(canvasTaps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
