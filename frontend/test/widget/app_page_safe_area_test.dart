import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final keyboard in [false, true]) {
    testWidgets('page corners clear iPhone safe area with keyboard $keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      MediaQueryData? bodyMedia;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              padding: EdgeInsets.only(bottom: keyboard ? 0 : 130),
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: EdgeInsets.only(bottom: keyboard ? 300 : 0),
            ),
            child: AppPage(
              title: 'Documents',
              insetBody: false,
              child: Builder(
                builder: (context) {
                  bodyMedia = MediaQuery.of(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      final surface = tester.getRect(find.byKey(const Key('pageSurface')));
      expect(surface.left, 8);
      expect(surface.right, 382);
      expect(surface.top, 8);
      expect(surface.bottom, keyboard ? 836 : 802);
      expect(bodyMedia!.padding.bottom, keyboard ? 0 : 96);
      expect(bodyMedia!.viewPadding.bottom, keyboard ? 34 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
