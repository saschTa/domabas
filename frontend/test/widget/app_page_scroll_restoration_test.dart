import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page heading and body positions restore independently', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var page = 0;
    late StateSetter changePage;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              changePage = setState;
              return AppPage(
                title: page == 0 ? 'History' : 'Details',
                description: 'Read and manage records in this library.',
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
    NestedScrollViewState scroll() =>
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    Future<void> show(int value) async {
      changePage(() => page = value);
      await tester.pumpAndSettle();
    }

    await tester.drag(
      find.byKey(const ValueKey('page-0')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    final history = scroll().innerController.offset;
    expect(history, greaterThan(0));
    expect(find.text('History').hitTestable(), findsNothing);

    await show(1);
    expect(scroll().innerController.offset, 0);
    expect(scroll().outerController.offset, 0);
    expect(find.text('Details').hitTestable(), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('page-1')),
      const Offset(0, -55),
    );
    await tester.pumpAndSettle();
    final heading = scroll().outerController.offset;
    expect(heading, greaterThan(0));
    expect(
      heading,
      lessThan(scroll().outerController.position.maxScrollExtent),
    );
    expect(scroll().innerController.offset, 0);

    await show(2);
    expect(scroll().outerController.offset, 0);
    expect(scroll().innerController.offset, 0);
    await show(0);
    expect(scroll().innerController.offset, closeTo(history, .01));
    expect(find.text('History').hitTestable(), findsNothing);
    await show(1);
    expect(scroll().outerController.offset, closeTo(heading, .01));
    expect(scroll().innerController.offset, 0);
    expect(tester.takeException(), isNull);
  });
}
