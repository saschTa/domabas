import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large collections build one page and navigate both directions', (
    tester,
  ) async {
    final built = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppPagedList(
              itemCount: 10000,
              itemBuilder: (_, i) {
                built.add(i);
                return Text('Record $i');
              },
            ),
          ),
        ),
      ),
    );
    expect(built, List.generate(20, (i) => i));
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Record 0'), findsNothing);
    expect(find.text('Record 20'), findsOneWidget);
    expect(find.text('Record 40'), findsNothing);
    await tester.tap(find.text('Previous'));
    await tester.pump();
    expect(find.text('Record 0'), findsOneWidget);
  });

  testWidgets(
    'failed page requests retain rows and retry reaches the final page',
    (tester) async {
      final data = ValueNotifier((count: 20, more: true, loading: false));
      addTearDown(data.dispose);
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: data,
                builder: (context, value, _) => AppPagedList(
                  key: const Key('pages'),
                  itemCount: value.count,
                  hasMore: value.more,
                  loading: value.loading,
                  onLoadMore: () {
                    reads++;
                    data.value = (count: 20, more: true, loading: true);
                  },
                  itemBuilder: (_, i) => Text('Record $i'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(reads, 1);
      data.value = (count: 20, more: true, loading: false);
      await tester.pump();
      expect(find.text('Record 0'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pump();
      data.value = (count: 25, more: false, loading: false);
      await tester.pump();
      expect(find.text('Record 0'), findsNothing);
      expect(find.text('Record 24'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Load more'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Previous'));
      await tester.pump();
      expect(find.text('Record 0'), findsOneWidget);
      expect(reads, 2);
    },
  );
}
