import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    for (final dark in [false, true]) {
      testWidgets(
        'fixed panes retain independent scroll positions at $platform/$dark',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var page = 0;
          late StateSetter changePage;
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.dark() : AppTheme.light()).copyWith(
                platform: platform,
              ),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    changePage = setState;
                    return AppPage(
                      title: page == 0 ? 'History' : 'Details',
                      showHeading: page == 1,
                      actions: [
                        TextButton(
                          onPressed: () {},
                          child: const Text('Refresh'),
                        ),
                      ],
                      child: ListView.builder(
                        key: ValueKey('page-$page'),
                        itemCount: 100,
                        itemExtent: 80,
                        itemBuilder: (context, index) => Text('Record $index'),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          ScrollPosition position() => tester
              .state<ScrollableState>(
                find.descendant(
                  of: find.byKey(ValueKey('page-$page')),
                  matching: find.byType(Scrollable),
                ),
              )
              .position;
          Future<void> show(int value) async {
            changePage(() => page = value);
            await tester.pumpAndSettle();
          }

          final surface = tester.getRect(find.byKey(const Key('pageSurface')));
          final controls = tester.getRect(
            find.byKey(const Key('pageControls')),
          );
          expect(surface, const Rect.fromLTRB(8, 8, 382, 836));
          expect(find.text('History'), findsNothing);
          expect(find.byType(NestedScrollView), findsNothing);
          await tester.drag(
            find.byKey(const ValueKey('page-0')),
            const Offset(0, -800),
          );
          await tester.pumpAndSettle();
          final history = position().pixels;
          expect(history, greaterThan(0));
          expect(tester.getRect(find.byKey(const Key('pageSurface'))), surface);
          expect(
            tester.getRect(find.byKey(const Key('pageControls'))),
            controls,
          );

          await show(1);
          expect(position().pixels, 0);
          expect(find.text('Details').hitTestable(), findsOneWidget);
          await tester.drag(
            find.byKey(const ValueKey('page-1')),
            const Offset(0, -250),
          );
          await tester.pumpAndSettle();
          final details = position().pixels;
          expect(details, greaterThan(0));
          expect(find.text('Details').hitTestable(), findsOneWidget);
          await show(2);
          expect(position().pixels, 0);
          await show(0);
          expect(position().pixels, closeTo(history, .01));
          await show(1);
          expect(position().pixels, closeTo(details, .01));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
