import 'package:domabas/app/native_desktop_frame.dart';
import 'package:domabas/app/platform/desktop_window_controller.dart';
import 'package:domabas/ui/glacier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/desktop_window_controller_test.dart' show WindowPortFake;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'native app navigator has exactly one title inset at scale $scale',
      (tester) async {
        final port = WindowPortFake();
        final controller = DesktopWindowController(port);
        final navigator = GlobalKey<NavigatorState>();
        final observer = DesktopWindowRouteObserver();
        final anchor = GlobalKey();
        await tester.pumpWidget(
          NativeDesktopHost(
            controller: controller,
            child: MaterialApp(
              navigatorKey: navigator,
              navigatorObservers: [observer],
              theme: GlacierTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: NativeDesktopFrame(
                  navigatorKey: navigator,
                  observer: observer,
                  child: child!,
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      SizedBox(key: anchor, height: 10),
                      TextButton(
                        onPressed: () => showGlacierDialog<void>(
                          context: context,
                          builder: (_) => const GlacierDialog(
                            title: 'Native dialog',
                            child: Text('Content'),
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GlacierNativeFrame), findsOneWidget);
        expect(tester.getTopLeft(find.byKey(anchor)).dy, scale == 1 ? 44 : 52);
        final bodyContext = tester.element(find.byKey(anchor));
        expect(
          GlacierNativePresentationScope.maybeOf(bodyContext)!.titlebarHeight,
          0,
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Native dialog'), findsOneWidget);
        final dialogContext = tester.element(find.text('Native dialog'));
        expect(
          GlacierNativePresentationScope.maybeOf(dialogContext)!.titlebarHeight,
          0,
        );
        expect(
          tester.getTopLeft(find.byType(Navigator).last).dy,
          scale == 1 ? 44 : 52,
        );
        expect(find.byTooltip('Close window'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controller.close);
        observer.dispose();
      },
    );
  }
  testWidgets(
    'server/session subtree replacement retains the native controller',
    (tester) async {
      final port = WindowPortFake();
      final controller = DesktopWindowController(port);
      final selected = ValueNotifier(0);
      await tester.pumpWidget(
        NativeDesktopHost(
          controller: controller,
          child: ValueListenableBuilder(
            valueListenable: selected,
            builder: (_, value, _) =>
                MaterialApp(key: ValueKey(value), home: const SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      selected.value = 1;
      await tester.pumpAndSettle();
      expect(port.calls.where((value) => value == 'initialize'), hasLength(1));
      expect(port.disposed, false);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.close);
      selected.dispose();
    },
  );
  testWidgets(
    'fullscreen recovery keeps real Exit and F11 until the host confirms restored chrome',
    (tester) async {
      final port = WindowPortFake()..pendingFullscreenRecovery = true;
      final controller = DesktopWindowController(port);
      final navigator = GlobalKey<NavigatorState>();
      final observer = DesktopWindowRouteObserver();
      await tester.pumpWidget(
        NativeDesktopHost(
          controller: controller,
          child: MaterialApp(
            theme: GlacierTheme.light(),
            navigatorKey: navigator,
            navigatorObservers: [observer],
            builder: (context, child) => NativeDesktopFrame(
              navigatorKey: navigator,
              observer: observer,
              child: child!,
            ),
            home: const Scaffold(body: Text('Library')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      port.events.add(
        port.snapshot(client: true, mode: GlacierNativeWindowMode.fullscreen),
      );
      await tester.pumpAndSettle();
      port.failLayout = true;
      port.events.add(
        port.snapshot(client: true, mode: GlacierNativeWindowMode.fullscreen),
      );
      await tester.pumpAndSettle();
      expect(controller.recovering, true);
      expect(find.byType(GlacierNativeFrame), findsOneWidget);
      final before = port.calls
          .where((call) => call == 'decoration:false')
          .length;
      await tester.tap(find.byTooltip('Exit full screen'));
      await tester.pumpAndSettle();
      expect(
        port.calls.where((call) => call == 'decoration:false').length,
        before + 1,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(
        port.calls.where((call) => call == 'decoration:false').length,
        before + 2,
      );
      port.events.add(port.snapshot(client: false));
      await tester.pumpAndSettle();
      expect(find.byType(GlacierNativeFrame), findsNothing);
      expect(find.text('Library'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.close);
      observer.dispose();
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'leading Close-only remains left with typed bounds at text scale $scale',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = const Size(330, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        GlacierNativeWindowLayout? measured;
        var closed = 0;
        final state = GlacierNativeWindowState(
          platform: GlacierNativePlatform.linux,
          controlLayout: GlacierNativeControlLayout.closeOnlyLeft,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: GlacierTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(330, 740),
                textScaler: TextScaler.linear(scale),
              ),
              child: GlacierNativeFrame(
                state: state,
                commands: GlacierNativeWindowCommands(
                  onClose: () => closed++,
                  onLayoutChanged: (layout) => measured = layout,
                ),
                child: const SizedBox(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close window'), findsOneWidget);
        expect(find.byTooltip('Minimize window'), findsNothing);
        expect(find.byTooltip('Maximize window'), findsNothing);
        expect(measured!.captionBounds.keys, [GlacierNativeCommand.close]);
        final bounds = measured!.captionBounds[GlacierNativeCommand.close]!;
        expect(bounds.left, 16);
        expect(bounds.width, 46);
        expect(bounds.right, lessThan(78));
        final identity = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.semanticsLabel == 'Domabas · Personal library',
          ),
        );
        expect(identity.left, greaterThanOrEqualTo(bounds.right + 16));
        await tester.tap(find.byTooltip('Close window'));
        expect(closed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
