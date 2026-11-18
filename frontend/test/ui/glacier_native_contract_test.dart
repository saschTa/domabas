import 'package:domabas/ui/glacier/glacier_native_frame.dart';
import 'package:domabas/ui/glacier/glacier_native_values.dart';
import 'package:domabas/ui/glacier/glacier_surfaces.dart';
import 'package:domabas/ui/glacier/glacier_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/navigation_fonts.dart';

Widget nativeHost({
  required GlacierNativeWindowState state,
  GlacierNativeWindowCommands commands = const GlacierNativeWindowCommands(),
  Widget child = const SizedBox.expand(),
}) => MaterialApp(
  theme: GlacierTheme.light(),
  home: Scaffold(
    body: GlacierNativeFrame(state: state, commands: commands, child: child),
  ),
);

void main() {
  setUpAll(loadNavigationFonts);

  test(
    'host capabilities and layout collections are defensive immutable values',
    () {
      final capabilities = {GlacierNativeCommand.close};
      final state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.windows,
        supportedCommands: capabilities,
      );
      capabilities.add(GlacierNativeCommand.maximize);
      expect(state.supportedCommands, {GlacierNativeCommand.close});
      expect(
        () => state.supportedCommands.add(GlacierNativeCommand.restore),
        throwsUnsupportedError,
      );
      final areas = [const Rect.fromLTWH(0, 0, 800, 64)];
      final exclusions = [const Rect.fromLTWH(100, 8, 48, 48)];
      final reservations = [const Rect.fromLTWH(630, 8, 138, 44)];
      final layout = GlacierNativeWindowLayout(
        viewport: const Size(800, 600),
        titlebar: areas.single,
        candidateDragRegions: areas,
        interactiveExclusions: exclusions,
        nativeControlReservations: reservations,
        devicePixelRatio: 2,
      );
      areas.clear();
      exclusions.clear();
      reservations.clear();
      expect(layout.candidateDragRegions, hasLength(1));
      expect(layout.interactiveExclusions, hasLength(1));
      expect(layout.nativeControlReservations, hasLength(1));
      for (final collection in [
        layout.candidateDragRegions,
        layout.interactiveExclusions,
        layout.nativeControlReservations,
      ]) {
        expect(collection.clear, throwsUnsupportedError);
      }
      expect(layout.viewport, const Size(800, 600));
      expect(layout.devicePixelRatio, 2);
      expect(layout.canDragAt(const Offset(200, 12)), isTrue);
      expect(layout.canDragAt(const Offset(4, 12)), isFalse);
      expect(layout.canDragAt(const Offset(110, 12)), isFalse);
      expect(layout.canDragAt(const Offset(650, 12)), isFalse);
      expect(layout.canDragAt(const Offset(200, 90)), isFalse);
    },
  );

  test(
    'host-published mode controls caption intent without mutating input',
    () {
      final state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.windows,
      );
      expect(state.captionCommands, contains(GlacierNativeCommand.maximize));
      final maximized = state.copyWith(mode: GlacierNativeWindowMode.maximized);
      expect(maximized.captionCommands, contains(GlacierNativeCommand.restore));
      expect(state.mode, GlacierNativeWindowMode.restored);
      expect(() => state.captionCommands.clear(), throwsUnsupportedError);
      final mac = state.copyWith(platform: GlacierNativePlatform.macos);
      expect(
        mac.captionCommands,
        contains(GlacierNativeCommand.enterFullscreen),
      );
      expect(
        mac.copyWith(mode: GlacierNativeWindowMode.fullscreen).captionCommands,
        contains(GlacierNativeCommand.exitFullscreen),
      );
    },
  );

  testWidgets('caption actions request host intent and obey capabilities', (
    tester,
  ) async {
    var closes = 0;
    var maximizes = 0;
    final state = GlacierNativeWindowState(
      platform: GlacierNativePlatform.windows,
      supportedCommands: {GlacierNativeCommand.close},
    );
    await tester.pumpWidget(
      nativeHost(
        state: state,
        commands: GlacierNativeWindowCommands(
          onClose: () => closes++,
          onMaximize: () => maximizes++,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close window'));
    await tester.tap(find.byTooltip('Maximize window'));
    await tester.pump();
    expect(closes, 1);
    expect(maximizes, 0);
    expect(state.mode, GlacierNativeWindowMode.restored);
    expect(find.byType(GlacierNativeFrame), findsOneWidget);
    for (final label in ['Minimize window', 'Maximize window']) {
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byTooltip(label),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, .42);
    }
    expect(
      tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byTooltip('Close window'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      1,
    );
  });

  testWidgets('supported caption without a callback is visibly disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      nativeHost(
        state: GlacierNativeWindowState(platform: GlacierNativePlatform.macos),
      ),
    );
    for (final label in [
      'Close window',
      'Minimize window',
      'Enter full screen',
    ]) {
      final control = find.byTooltip(label);
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(of: control, matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        .42,
      );
      expect(
        tester
            .widget<TextButton>(
              find.descendant(of: control, matching: find.byType(TextButton)),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('disabled fullscreen capability also disables the F11 shortcut', (
    tester,
  ) async {
    var enters = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      nativeHost(
        state: GlacierNativeWindowState(
          platform: GlacierNativePlatform.windows,
          supportedCommands: {},
        ),
        commands: GlacierNativeWindowCommands(
          onEnterFullscreen: () => enters++,
        ),
        child: Focus(focusNode: focus, child: const SizedBox.expand()),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(enters, 0);
  });

  testWidgets('frame reports a usable blank drag area in logical coordinates', (
    tester,
  ) async {
    GlacierNativeWindowLayout? reported;
    await tester.pumpWidget(
      nativeHost(
        state: GlacierNativeWindowState(
          platform: GlacierNativePlatform.windows,
          devicePixelRatio: 2,
        ),
        commands: GlacierNativeWindowCommands(
          onSystemMenu: () {},
          onTitlebarDoubleClick: () {},
          onLayoutChanged: (value) => reported = value,
        ),
      ),
    );
    await tester.pump();
    expect(reported, isNotNull);
    expect(reported!.viewport, const Size(800, 600));
    expect(reported!.devicePixelRatio, 2);
    expect(reported!.canDragAt(const Offset(400, 12)), isTrue);
    expect(reported!.canDragAt(const Offset(400, 4)), isFalse);
    expect(reported!.nativeControlReservations, isNotEmpty);
    expect(
      reported!.canDragAt(reported!.nativeControlReservations.single.center),
      isFalse,
    );
  });

  testWidgets(
    'changing workspace content does not require changing host state',
    (tester) async {
      final state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.macos,
      );
      await tester.pumpWidget(
        nativeHost(state: state, child: const Text('Documents destination')),
      );
      await tester.pump();
      expect(find.text('Documents destination'), findsOneWidget);
      await tester.pumpWidget(
        nativeHost(state: state, child: const Text('Settings destination')),
      );
      await tester.pump();
      expect(find.text('Settings destination'), findsOneWidget);
      expect(find.text('Documents destination'), findsNothing);
    },
  );

  testWidgets(
    'native dialog preserves caption access and blocks background actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var backgroundActions = 0;
        var closeRequests = 0;
        final backgroundFocus = FocusNode(debugLabel: 'Blocked app action');
        addTearDown(backgroundFocus.dispose);
        await tester.pumpWidget(
          nativeHost(
            state: GlacierNativeWindowState(
              platform: GlacierNativePlatform.windows,
            ),
            commands: GlacierNativeWindowCommands(
              onClose: () => closeRequests++,
              onMinimize: () {},
              onMaximize: () {},
            ),
            child: Builder(
              builder: (context) => Stack(
                children: [
                  Positioned(
                    top: 120,
                    left: 20,
                    child: TextButton(
                      key: const ValueKey('open-native-dialog'),
                      onPressed: () => showGlacierDialog<void>(
                        context: context,
                        builder: (context) => GlacierDialog(
                          title: 'Retained document task',
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Done'),
                            ),
                          ],
                          child: const TextField(
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Document title',
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Open document task'),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: TextButton(
                      key: const ValueKey('background-action'),
                      focusNode: backgroundFocus,
                      onPressed: () => backgroundActions++,
                      child: const Text('Underlying app action'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final backgroundPoint = tester.getCenter(
          find.byKey(const ValueKey('background-action')),
        );
        await tester.tap(find.byKey(const ValueKey('open-native-dialog')));
        await tester.pumpAndSettle();
        expect(find.text('Retained document task'), findsOneWidget);
        expect(
          tester.semantics.simulatedAccessibilityTraversal().map(
            (node) => node.getSemanticsData().label,
          ),
          isNot(contains('Underlying app action')),
        );
        expect(
          tester.getTopLeft(find.byType(GlacierDialog)).dy,
          greaterThanOrEqualTo(44),
        );
        var reachedCaption = false;
        for (var index = 0; index < 12; index++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(backgroundFocus.hasFocus, isFalse);
          final focusContext = FocusManager.instance.primaryFocus?.context;
          reachedCaption |=
              focusContext
                  ?.findAncestorWidgetOfExactType<
                    GlacierNativeCaptionControls
                  >() !=
              null;
        }
        expect(reachedCaption, isTrue);
        await tester.tap(find.byTooltip('Close window'));
        await tester.pump();
        expect(closeRequests, 1);
        expect(find.text('Retained document task'), findsOneWidget);
        await tester.tapAt(backgroundPoint);
        await tester.pumpAndSettle();
        expect(backgroundActions, 0);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'fullscreen focus moves to the visible exit and back to the caption',
    (tester) async {
      var state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.macos,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: GlacierTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: GlacierNativeFrame(
                state: state,
                commands: GlacierNativeWindowCommands(
                  onEnterFullscreen: () => setState(
                    () => state = state.copyWith(
                      mode: GlacierNativeWindowMode.fullscreen,
                    ),
                  ),
                  onExitFullscreen: () => setState(
                    () => state = state.copyWith(
                      mode: GlacierNativeWindowMode.restored,
                    ),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Enter full screen'),
          matching: find.byType(TextButton),
        ),
      );
      entry.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(state.fullscreen, isTrue);
      expect(find.text('Exit full screen'), findsOneWidget);
      final exit = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Exit full screen'),
      );
      expect(exit.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(state.fullscreen, isFalse);
      final returned = tester.widget<TextButton>(
        find.descendant(
          of: find.byTooltip('Enter full screen'),
          matching: find.byType(TextButton),
        ),
      );
      expect(returned.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'host decoration omits simulated captions and retains fullscreen exit',
    (tester) async {
      final state = GlacierNativeWindowState(
        platform: GlacierNativePlatform.linux,
        decoration: GlacierNativeDecoration.host,
      );
      await tester.pumpWidget(nativeHost(state: state));
      await tester.pump();
      expect(find.byType(GlacierNativeCaptionControls), findsNothing);
      await tester.pumpWidget(
        nativeHost(
          state: state.copyWith(mode: GlacierNativeWindowMode.fullscreen),
          commands: GlacierNativeWindowCommands(onExitFullscreen: () {}),
        ),
      );
      await tester.pump();
      expect(find.byType(GlacierNativeCaptionControls), findsNothing);
      expect(find.text('Exit full screen'), findsOneWidget);
    },
  );

  for (final platform in GlacierNativePlatform.values) {
    testWidgets('frame publishes the $platform Flutter platform context', (
      tester,
    ) async {
      TargetPlatform? actual;
      await tester.pumpWidget(
        nativeHost(
          state: GlacierNativeWindowState(platform: platform),
          child: Builder(
            builder: (context) {
              actual = Theme.of(context).platform;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      expect(actual, switch (platform) {
        GlacierNativePlatform.macos => TargetPlatform.macOS,
        GlacierNativePlatform.windows => TargetPlatform.windows,
        GlacierNativePlatform.linux => TargetPlatform.linux,
      });
    });
  }
}
