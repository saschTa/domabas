import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final exactRoute in [false, true]) {
    testWidgets(
      'glass dialog keeps live theme and draft exactRoute=$exactRoute',
      (tester) async {
        final dark = ValueNotifier(false);
        final draft = TextEditingController(text: 'Retained draft');
        addTearDown(dark.dispose);
        addTearDown(draft.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: dark,
            builder: (_, value, _) => MaterialApp(
              theme: GlacierTheme.light(),
              darkTheme: GlacierTheme.dark(),
              themeMode: value ? ThemeMode.dark : ThemeMode.light,
              home: Builder(
                builder: (context) => Theme(
                  data: glacierMobileTheme(Theme.of(context)),
                  child: Builder(
                    builder: (local) => Scaffold(
                      body: GlacierButton(
                        label: 'Open',
                        onPressed: () {
                          Widget body(BuildContext context) => GlacierDialog(
                            title: 'Retained record',
                            child: TextField(
                              key: const Key('retainedDraft'),
                              controller: draft,
                            ),
                          );
                          if (exactRoute) {
                            Navigator.of(local).push(
                              createGlacierDialogRoute<void>(
                                context: local,
                                builder: body,
                              ),
                            );
                          } else {
                            showGlacierDialog<void>(
                              context: local,
                              builder: body,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('retainedDraft'));
        await tester.enterText(field, 'Still unsaved');
        draft.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
        final route = ModalRoute.of(tester.element(field));
        dark.value = true;
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(field)).brightness, Brightness.dark);
        expect(ModalRoute.of(tester.element(field)), same(route));
        expect(tester.widget<TextField>(field).controller, same(draft));
        expect(draft.text, 'Still unsaved');
        expect(
          draft.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5),
        );
        dark.value = false;
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(field)).brightness, Brightness.light);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'narrow enlarged validation rules remain complete and actions reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const messages = [
        'Enter a valid email address.',
        'Use 8–128 characters for your password.',
        'Enter an account name of 1–100 characters.',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      for (final message in messages)
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Account field',
                            errorText: message,
                          ),
                        ),
                      GlacierButton(label: 'Submit', onPressed: () {}),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final message in messages) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(message),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: message);
      }
      await tester.ensureVisible(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Submit').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
