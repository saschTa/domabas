import 'dart:async';

import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('short content pulls once and awaits refresh on $platform', (
      tester,
    ) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: AppPage(
              title: 'Empty collection',
              onRefresh: () {
                calls++;
                return pending.future;
              },
              child: ListView(children: const [Text('No records')]),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      final progress = find.byType(
        platform == TargetPlatform.iOS
            ? CupertinoActivityIndicator
            : RefreshProgressIndicator,
      );
      expect(progress, findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(progress, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'keyboard refresh retains draft, focus and scroll when disabled',
    (tester) async {
      final scroll = ScrollController();
      final text = TextEditingController(text: 'unsaved draft');
      final focus = FocusNode();
      addTearDown(scroll.dispose);
      addTearDown(text.dispose);
      addTearDown(focus.dispose);
      final pending = Completer<void>();
      var calls = 0;
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return AppPage(
                  title: 'Settings',
                  onRefresh: enabled
                      ? () {
                          calls++;
                          rebuild(() => enabled = false);
                          return pending.future;
                        }
                      : null,
                  child: ListView(
                    controller: scroll,
                    children: [
                      const SizedBox(height: 700),
                      TextField(controller: text, focusNode: focus),
                      const SizedBox(height: 900),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      scroll.jumpTo(600);
      focus.requestFocus();
      await tester.pumpAndSettle();
      final editor = tester.element(find.byType(EditableText));
      final offset = scroll.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(tester.element(find.byType(EditableText)), same(editor));
      expect(text.text, 'unsaved draft');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, offset);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested scrolling does not refresh the page', (tester) async {
    var calls = 0;
    const nested = Key('nested');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPage(
            title: 'Nested content',
            onRefresh: () async => calls++,
            child: ListView(
              children: [
                SizedBox(
                  height: 300,
                  child: ListView(
                    key: nested,
                    primary: false,
                    children: const [Text('Short nested editor')],
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byKey(nested), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
