import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/navigation_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadNavigationFonts();
  });
  final profiles = [
    GlacierNativeWindowState(platform: GlacierNativePlatform.macos),
    GlacierNativeWindowState(platform: GlacierNativePlatform.windows),
    GlacierNativeWindowState(platform: GlacierNativePlatform.linux),
    GlacierNativeWindowState(
      platform: GlacierNativePlatform.linux,
      controlLayout: GlacierNativeControlLayout.closeOnly,
    ),
    GlacierNativeWindowState(
      platform: GlacierNativePlatform.linux,
      controlLayout: GlacierNativeControlLayout.left,
    ),
    GlacierNativeWindowState(
      platform: GlacierNativePlatform.linux,
      decoration: GlacierNativeDecoration.host,
    ),
  ];
  for (var profile = 0; profile < profiles.length; profile++) {
    for (final width in [330.0, 800.0, 1440.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'single-row titlebar profile$profile width$width scale$scale',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 600));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            var exits = 0;
            final state = profiles[profile].copyWith(
              mode: GlacierNativeWindowMode.fullscreen,
              controlsRevealed: true,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: GlacierTheme.light(),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 600),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: GlacierNativeTitleBar(
                        state: state,
                        commands: GlacierNativeWindowCommands(
                          onClose: () {},
                          onMinimize: () {},
                          onMaximize: () {},
                          onExitFullscreen: () => exits++,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final bar = tester.getRect(find.byType(GlacierNativeTitleBar));
            expect(bar.height, scale == 2 ? 52 : 44);
            final identity = tester.widget<Text>(
              find.text('Domabas · Personal library'),
            );
            expect(identity.maxLines, 1);
            expect(identity.overflow, TextOverflow.ellipsis);
            expect(identity.semanticsLabel, 'Domabas · Personal library');
            final exit = width <= 760 || scale > 1
                ? find.byTooltip('Exit full screen').last
                : find.widgetWithText(TextButton, 'Exit full screen');
            final exitRect = tester.getRect(exit);
            if (width > 760 && scale == 1) {
              final label = tester.renderObject<RenderParagraph>(
                find.text('Exit full screen'),
              );
              expect(
                label
                    .getBoxesForSelection(
                      const TextSelection(baseOffset: 0, extentOffset: 16),
                    )
                    .map((box) => box.top)
                    .toSet(),
                hasLength(1),
              );
              expect(label.didExceedMaxLines, isFalse);
            }
            expect(exitRect.height, 44);
            expect(exitRect.top, greaterThanOrEqualTo(bar.top));
            expect(exitRect.bottom, lessThanOrEqualTo(bar.bottom));
            if (state.captionsVisible) {
              final captions = tester.getRect(
                find.byType(GlacierNativeCaptionControls),
              );
              expect(captions.top, greaterThanOrEqualTo(bar.top));
              expect(captions.bottom, lessThanOrEqualTo(bar.bottom));
              expect(captions.overlaps(exitRect), isFalse);
              if (state.platform != GlacierNativePlatform.macos) {
                expect(captions.height, 44);
              }
            }
            await tester.tap(exit);
            expect(exits, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
