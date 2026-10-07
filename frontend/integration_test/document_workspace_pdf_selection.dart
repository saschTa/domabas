import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> exercisePdfTouchSelection(
  WidgetTester tester,
  PdfViewerController controller, {
  Offset wordPoint = const Offset(55, 43),
  String word = 'Orchard',
}) async {
  final previousPlatform = debugDefaultTargetPlatformOverride;
  try {
    if (kIsWeb) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
    }
    await _exercisePdfTouchSelection(tester, controller, wordPoint, word);
  } finally {
    if (kIsWeb) {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
    }
  }
}

Future<void> _exercisePdfTouchSelection(
  WidgetTester tester,
  PdfViewerController controller,
  Offset wordPoint,
  String word,
) async {
  expect(
    Theme.of(tester.element(find.byType(PdfViewer))).platform,
    TargetPlatform.iOS,
  );
  final canvas = tester.getRect(
    find.byKey(const Key('documentCanvasViewport')),
  );
  final wordPosition =
      canvas.topLeft +
      MatrixUtils.transformPoint(
        controller.value,
        controller.layout.pageLayouts.first.topLeft + wordPoint,
      );
  await tester.longPressAt(wordPosition);
  await tester.pumpAndSettle();
  final selection = controller.textSelectionDelegate;
  expect(await selection.getSelectedText(), word);
  final handle = find.byKey(const Key('anchorB'));
  expect(handle.hitTestable(), findsOneWidget);
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveBy(const Offset(24, 0));
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byKey(const Key('magnifier')), findsNothing);
  expect(find.byKey(const Key('pdfrxMagnifierPositioned')), findsNothing);
  await gesture.up();
  await tester.pumpAndSettle();
  expect(selection.hasSelectedText, isTrue);
  expect(selection.isCopyAllowed, isTrue);
  expect(find.text('Copy'), findsOneWidget);
  expect(await selection.getSelectedText(), contains(word));
  await selection.clearTextSelection();
  await tester.pumpAndSettle();
}
