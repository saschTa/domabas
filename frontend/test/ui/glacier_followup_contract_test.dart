import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleFollowupFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump();
}

Widget followupNativeHost({
  required GlacierNativeWindowState state,
  required GlacierNativeWindowCommands commands,
  required double scale,
  Widget child = const SizedBox.expand(),
}) => MaterialApp(
  theme: GlacierTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(330, 740),
      textScaler: TextScaler.linear(scale),
      disableAnimations: true,
    ),
    child: Scaffold(
      body: GlacierNativeFrame(state: state, commands: commands, child: child),
    ),
  ),
);

void main() {
  for (final platform in GlacierNativePlatform.values) {
    for (final variant in [
      (scale: 1.0, fullscreen: false, height: 44.0),
      (scale: 2.0, fullscreen: false, height: 52.0),
      (scale: 1.0, fullscreen: true, height: 44.0),
      (scale: 2.0, fullscreen: true, height: 52.0),
    ]) {
      testWidgets(
        '$platform dedicated bar ${variant.height} fullscreen=${variant.fullscreen} owns drag geometry',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await tester.binding.setSurfaceSize(const Size(330, 740));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            GlacierNativeWindowLayout? layout;
            await tester.pumpWidget(
              followupNativeHost(
                state: GlacierNativeWindowState(
                  platform: platform,
                  mode: variant.fullscreen
                      ? GlacierNativeWindowMode.fullscreen
                      : GlacierNativeWindowMode.restored,
                  controlsRevealed: variant.fullscreen,
                  reduceMotion: true,
                ),
                scale: variant.scale,
                commands: GlacierNativeWindowCommands(
                  onClose: () {},
                  onMinimize: () {},
                  onMaximize: () {},
                  onEnterFullscreen: () {},
                  onExitFullscreen: () {},
                  onLayoutChanged: (value) => layout = value,
                ),
              ),
            );
            await settleFollowupFrame(tester);
            final bar = tester.getRect(find.byType(GlacierNativeTitleBar));
            expect(bar, Rect.fromLTWH(0, 0, 330, variant.height));
            final identity = find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.semanticsLabel == 'Domabas · Personal library',
            );
            expect(identity, findsOneWidget);
            expect(tester.widget<Text>(identity).maxLines, 1);
            expect(
              find.bySemanticsLabel('Domabas · Personal library'),
              findsOneWidget,
            );
            expect(layout, isNotNull);
            expect(layout!.titlebar, bar);
            expect(layout!.viewport, const Size(330, 740));
            expect(layout!.candidateDragRegions, [bar]);
            final dragX = platform == GlacierNativePlatform.macos
                ? 165.0
                : 20.0;
            expect(
              layout!.canDragAt(Offset(dragX, variant.height - 2)),
              isTrue,
            );
            expect(layout!.canDragAt(Offset(165, variant.height + 1)), isFalse);
            for (final reservation in layout!.nativeControlReservations) {
              expect(reservation.left, greaterThanOrEqualTo(bar.left));
              expect(reservation.right, lessThanOrEqualTo(bar.right));
              expect(reservation.top, greaterThanOrEqualTo(bar.top));
              expect(reservation.bottom, lessThanOrEqualTo(bar.bottom));
              expect(layout!.canDragAt(reservation.center), isFalse);
            }
            if (!variant.fullscreen) {
              expect(layout!.canDragAt(const Offset(4, 20)), isFalse);
            }
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final variant in [
    (scale: 1.0, fullscreen: false, height: 44.0),
    (scale: 2.0, fullscreen: false, height: 52.0),
    (scale: 1.0, fullscreen: true, height: 44.0),
    (scale: 2.0, fullscreen: true, height: 52.0),
  ]) {
    testWidgets(
      'modal applies titlebar ${variant.height} fullscreen=${variant.fullscreen} inset exactly once',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(330, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var closes = 0;
        await tester.pumpWidget(
          followupNativeHost(
            state: GlacierNativeWindowState(
              platform: GlacierNativePlatform.windows,
              mode: variant.fullscreen
                  ? GlacierNativeWindowMode.fullscreen
                  : GlacierNativeWindowMode.restored,
              controlsRevealed: variant.fullscreen,
              reduceMotion: true,
            ),
            scale: variant.scale,
            commands: GlacierNativeWindowCommands(onClose: () => closes++),
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showGlacierDialog<void>(
                    context: context,
                    builder: (_) => const SizedBox.expand(
                      key: ValueKey('native-modal-area'),
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
                  child: const Text('Open task'),
                ),
              ),
            ),
          ),
        );
        await settleFollowupFrame(tester);
        await tester.tap(find.text('Open task'));
        await settleFollowupFrame(tester);
        expect(
          tester.getRect(find.byKey(const ValueKey('native-modal-area'))),
          Rect.fromLTWH(0, variant.height, 330, 740 - variant.height),
        );
        await tester.tap(find.byTooltip('Close window'));
        await tester.pump();
        expect(closes, 1);
        expect(find.byKey(const ValueKey('native-modal-area')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'open modal retains the slim inset through fullscreen without reopening',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(330, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.windows,
        reduceMotion: true,
      );
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) => followupNativeHost(
            state: state,
            scale: 2,
            commands: GlacierNativeWindowCommands(
              onEnterFullscreen: () => update(() {
                state = state.copyWith(
                  mode: GlacierNativeWindowMode.fullscreen,
                  controlsRevealed: true,
                );
              }),
              onExitFullscreen: () => update(() {
                state = state.copyWith(mode: GlacierNativeWindowMode.restored);
              }),
            ),
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showGlacierDialog<void>(
                    context: context,
                    builder: (_) => const SizedBox.expand(
                      key: ValueKey('resizing-modal-area'),
                      child: Material(child: TextField(autofocus: true)),
                    ),
                  ),
                  child: const Text('Open task'),
                ),
              ),
            ),
          ),
        ),
      );
      await settleFollowupFrame(tester);
      await tester.tap(find.text('Open task'));
      await settleFollowupFrame(tester);
      final field = find.byType(TextField);
      await tester.enterText(field, 'Keep this draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await settleFollowupFrame(tester);
      expect(state.mode, GlacierNativeWindowMode.fullscreen);
      expect(tester.getRect(find.byType(GlacierNativeTitleBar)).height, 52);
      expect(
        tester.getRect(find.byKey(const ValueKey('resizing-modal-area'))).top,
        52,
      );
      expect(find.text('Keep this draft'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit full screen'));
      await settleFollowupFrame(tester);
      expect(state.mode, GlacierNativeWindowMode.restored);
      expect(tester.getRect(find.byType(GlacierNativeTitleBar)).height, 52);
      expect(
        tester.getRect(find.byKey(const ValueKey('resizing-modal-area'))).top,
        52,
      );
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
