import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in ['desktop', 'mobile', 'row']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$kind preview retry is an independent in-item action at $scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var opens = 0;
          var previews = 0;
          var processing = 0;
          var selections = 0;
          var failedPreview = false;
          late StateSetter update;
          const document = GlacierDocumentValue(
            id: 'example',
            title: 'Example.pdf',
            sender: 'Northstar',
            tags: ['Home'],
            failed: true,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: GlacierTheme.light(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        final VoidCallback? retry = failedPreview
                            ? () => previews++
                            : null;
                        return SizedBox(
                          width: kind == 'row'
                              ? 520
                              : kind == 'mobile'
                              ? 186
                              : 280,
                          child: switch (kind) {
                            'mobile' => GlacierMobileDocumentCard(
                              document: document,
                              preview: const ColoredBox(
                                color: Colors.transparent,
                              ),
                              selected: false,
                              onSelectionChanged: (_) => selections++,
                              onOpen: () => opens++,
                              onRetry: () => processing++,
                              onRetryPreview: retry,
                            ),
                            'row' => GlacierDocumentRow(
                              document: document,
                              preview: const ColoredBox(
                                color: Colors.transparent,
                              ),
                              onOpen: () => opens++,
                              onRetry: () => processing++,
                              onRetryPreview: retry,
                            ),
                            _ => GlacierDocumentCard(
                              document: document,
                              preview: const ColoredBox(
                                color: Colors.transparent,
                              ),
                              onOpen: () => opens++,
                              onRetry: () => processing++,
                              onRetryPreview: retry,
                            ),
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          final item = switch (kind) {
            'mobile' => find.byType(GlacierMobileDocumentCard),
            'row' => find.byType(GlacierDocumentRow),
            _ => find.byType(GlacierDocumentCard),
          };
          final before = tester.getRect(item);
          update(() => failedPreview = true);
          await tester.pump();
          final retry = find.byType(GlacierPreviewRetry);
          expect(tester.getRect(item), before);
          expect(before.contains(tester.getRect(retry).topLeft), isTrue);
          expect(before.contains(tester.getRect(retry).bottomRight), isTrue);
          expect(
            find.bySemanticsLabel('Retry preview Example.pdf'),
            findsOneWidget,
          );
          final process = find.byTooltip('Retry processing Example.pdf');
          expect(
            tester.getRect(retry).overlaps(tester.getRect(process)),
            isFalse,
          );
          if (kind == 'mobile') {
            expect(
              tester
                  .getRect(retry)
                  .overlaps(
                    tester.getRect(find.bySemanticsLabel('Select Example.pdf')),
                  ),
              isFalse,
            );
          }
          await tester.tap(retry);
          expect(previews, 1);
          expect(opens, 0);
          expect(processing, 0);
          expect(selections, 0);
          await tester.tap(process);
          expect(processing, 1);
          expect(previews, 1);
          for (var i = 0; i < 10; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            if (tester.binding.focusManager.primaryFocus?.context
                    ?.findAncestorWidgetOfExactType<GlacierPreviewRetry>() !=
                null) {
              break;
            }
          }
          expect(
            tester.binding.focusManager.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<GlacierPreviewRetry>(),
            isNotNull,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(previews, 2);
          expect(opens, 0);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
