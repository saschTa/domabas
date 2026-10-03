import 'dart:async';

import 'package:domabas/domain/scanner/models/scan.dart';
import 'package:domabas/presentation/scanner/cubits/scanner_cubit.dart';
import 'package:domabas/presentation/scanner/views/scanner_screen.dart';
import 'package:domabas/presentation/scanner/widgets/scan_frame.dart';
import 'package:domabas/ui/domabas_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scanner_fixtures.dart';

void main() {
  for (final layout in [
    (const Size(800, 1280), 1200, 1600),
    (const Size(1280, 800), 1600, 1200),
  ]) {
    testWidgets('tablet preview fills its contained viewport at ${layout.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = layout.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final camera = FixtureScannerCamera();
      final cubit = ScannerCubit(
        camera: camera,
        repository: FixtureScanRepository(),
        allowed: true,
      );
      addTearDown(camera.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ScannerScreen(
            cubit: cubit,
            previewBuilder: (_) => const ColoredBox(
              key: Key('actualCameraImage'),
              color: Colors.blue,
            ),
            canReadDocuments: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addScanPage')));
      await tester.pumpAndSettle();
      camera.publish(
        ScanCameraState(
          status: ScanCameraStatus.ready,
          width: layout.$2,
          height: layout.$3,
          corners: ScanCorners.fullImage(),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const Key('scanCameraViewport')),
      );
      final image = tester.getRect(find.byKey(const Key('actualCameraImage')));
      final expected = applyBoxFit(
        BoxFit.contain,
        Size(layout.$2.toDouble(), layout.$3.toDouble()),
        viewport.size,
      ).destination;
      expect(viewport.width, layout.$1.width);
      expect(image.width, closeTo(expected.width, .001));
      expect(image.height, closeTo(expected.height, .001));
      expect(image.center, viewport.center);
      expect(image.width, greaterThan(760));
      expect(image.height, greaterThan(420));
      expect(
        find.byKey(const Key('captureScanPage')).hitTestable(),
        findsOneWidget,
      );
      camera.captureGate = Completer<ScanCapture>();
      final taking = cubit.capture();
      await tester.pump();
      expect(cubit.state.busy, isTrue);
      expect(tester.getRect(find.byKey(const Key('actualCameraImage'))), image);
      for (final phase in [
        ScanCameraStatus.capturing,
        ScanCameraStatus.processing,
      ]) {
        camera.publish(
          ScanCameraState(status: phase, width: layout.$2, height: layout.$3),
        );
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const Key('actualCameraImage'))),
          image,
        );
        expect(
          find.text(
            phase == ScanCameraStatus.capturing
                ? 'Capturing… Hold steady.'
                : 'Photo captured. Preparing page…',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('captureScanPage')))
              .onPressed,
          isNull,
        );
      }
      camera.captureGate!.complete(
        ScanCapture(
          id: 'tablet',
          width: layout.$2,
          height: layout.$3,
          corners: ScanCorners.fullImage(),
          preview: scanJpeg(20, 30),
        ),
      );
      await taking;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'page order controls remain accessible at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final camera = FixtureScannerCamera();
      final repository = FixtureScanRepository(
        initial: ScanDraft(
          id: 'reorder',
          revision: 3,
          properties: scanProperties(),
          pages: [
            for (final id in ['one', 'two', 'three'])
              ScanPage(
                id: id,
                width: 20,
                height: 30,
                thumbnail: scanJpeg(20, 30),
              ),
          ],
        ),
      );
      final cubit = ScannerCubit(
        camera: camera,
        repository: repository,
        allowed: true,
      );
      addTearDown(camera.close);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ScannerScreen(
            cubit: cubit,
            previewBuilder: (_) => const SizedBox(),
            canReadDocuments: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final earlier = find.byKey(const Key('moveScanPageEarlier-0'));
      await tester.ensureVisible(earlier);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(earlier).onPressed, isNull);
      expect(
        tester.getSemantics(earlier).getSemanticsData().tooltip,
        'Move page 1 earlier',
      );
      final later = find.byKey(const Key('moveScanPageLater-0'));
      expect(tester.getSize(later).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(later).height, greaterThanOrEqualTo(48));
      repository.moveGate = Completer<void>();
      await tester.tap(later);
      await tester.pump();
      expect(tester.widget<IconButton>(later).onPressed, isNull);
      expect(repository.draft.pages.first.id, 'one');
      repository.moveGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.draft.pages.map((page) => page.id), [
        'two',
        'one',
        'three',
      ]);
      final finalLater = find.byKey(const Key('moveScanPageLater-2'));
      await tester.ensureVisible(finalLater);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(finalLater).onPressed, isNull);
      final finalEarlier = find.byKey(const Key('moveScanPageEarlier-2'));
      expect(
        tester.getSemantics(finalEarlier).getSemanticsData().tooltip,
        'Move page 3 earlier',
      );
      await tester.tap(finalEarlier);
      await tester.pumpAndSettle();
      expect(repository.draft.pages.map((page) => page.id), [
        'two',
        'three',
        'one',
      ]);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'save and close targets scanner route when appearance dialog opens during save',
    (tester) async {
      final camera = FixtureScannerCamera();
      final repository = FixtureScanRepository()..saveGate = Completer<void>();
      final cubit = ScannerCubit(
        camera: camera,
        repository: repository,
        allowed: true,
      );
      addTearDown(camera.close);
      ScannerExit? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ScannerExit>(
                    MaterialPageRoute(
                      builder: (scannerContext) => ScannerScreen(
                        cubit: cubit,
                        previewBuilder: (_) => const SizedBox(),
                        canReadDocuments: true,
                        appearanceAction: IconButton(
                          key: const Key('openScannerModal'),
                          icon: const Icon(Icons.palette),
                          onPressed: () {
                            unawaited(
                              showDialog<void>(
                                context: scannerContext,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Appearance modal'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('Close modal'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open fixture scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open fixture scanner'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-title')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scan-title')),
        'Persist before leaving',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('closeScanner')));
      await tester.pump();
      expect(repository.saves, 1);
      await tester.tap(find.byKey(const Key('openScannerModal')));
      await tester.pumpAndSettle();
      repository.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Appearance modal'), findsOneWidget);
      expect(result, ScannerExit.saved);
      expect(repository.draft.properties.title, 'Persist before leaving');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close modal'));
      await tester.pumpAndSettle();
      expect(find.text('Open fixture scanner'), findsOneWidget);
    },
  );
  test('contain geometry and inverse pointer mapping preserve portrait/landscape proportions', () {
    for (final size in [const Size(320, 320), const Size(844, 390)]) {
      for (final dimensions in [(200, 300), (400, 200)]) {
        final geometry = ScanFrameGeometry.contain(
          size,
          dimensions.$1,
          dimensions.$2,
        );
        expect(
          geometry.rect.width / geometry.rect.height,
          closeTo(dimensions.$1 / dimensions.$2, 1e-9),
        );
        for (final point in [
          const ScanPoint(0, 0),
          const ScanPoint(.2, .7),
          const ScanPoint(1, 1),
        ]) {
          final roundtrip = geometry.pointAt(geometry.position(point));
          expect(roundtrip.x, closeTo(point.x, 1e-9));
          expect(roundtrip.y, closeTo(point.y, 1e-9));
        }
        expect(geometry.pointAt(const Offset(-100, -100)).x, 0);
      }
    }
    expect(
      ScanCorners([
        const ScanPoint(0, 0),
        const ScanPoint(1, 1),
        const ScanPoint(1, 0),
        const ScanPoint(0, 1),
      ]).validFor(200, 300),
      isFalse,
    );
    expect(
      ScanCorners([
        const ScanPoint(double.nan, 0),
        const ScanPoint(1, 0),
        const ScanPoint(1, 1),
        const ScanPoint(0, 1),
      ]).validFor(200, 300),
      isFalse,
    );
  });
  testWidgets(
    'drag updates accumulate without a pumped frame and dark corner labels use readable foreground',
    (tester) async {
      final moved = <ScanPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 320,
              child: ScanFrame(
                width: 200,
                height: 200,
                corners: ScanCorners([
                  const ScanPoint(.2, .2),
                  const ScanPoint(.8, .2),
                  const ScanPoint(.8, .8),
                  const ScanPoint(.2, .8),
                ]),
                onMove: (_, point) => moved.add(point),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      );
      final label = tester.widget<Text>(find.text('1'));
      expect(label.style!.color, AppTheme.dark().colorScheme.onPrimary);
      final start = tester.getCenter(find.byKey(const Key('scan-corner-0')));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      expect(moved.length, greaterThanOrEqualTo(2));
      expect(moved.last.x, closeTo(.2 + 65 / 272, 1e-9));
      expect(moved.last.y, closeTo(.2, 1e-9));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'correction edges and corners drag without scrolling and stay in sync with sliders',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final camera = FixtureScannerCamera();
      final repository = FixtureScanRepository();
      final cubit = ScannerCubit(
        camera: camera,
        repository: repository,
        allowed: true,
      );
      addTearDown(camera.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ScannerScreen(
            cubit: cubit,
            previewBuilder: (_) => const SizedBox(),
            canReadDocuments: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await cubit.addPage();
      await cubit.capture();
      await tester.pumpAndSettle();
      final frame = find.byType(ScanFrame);
      final geometry = ScanFrameGeometry.contain(
        tester.getSize(frame),
        200,
        300,
      );
      final origin = tester.getTopLeft(frame);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      final scrollOffset = scrollable.position.pixels;
      final top = origin + geometry.position(const ScanPoint(.3, 0));
      final edge = await tester.startGesture(top + const Offset(0, 8));
      await edge.moveBy(const Offset(0, 25));
      await tester.pump();
      await edge.moveBy(const Offset(0, 15));
      await edge.up();
      await tester.pump();
      final y = 40 / geometry.rect.height;
      expect(cubit.state.corners!.points[0].y, closeTo(y, 1e-9));
      expect(cubit.state.corners!.points[1].y, closeTo(y, 1e-9));
      expect(cubit.state.corners!.points[2].y, 1);
      expect(scrollable.position.pixels, scrollOffset);
      expect(
        tester
            .widget<Slider>(find.byKey(const Key('scanCornerVertical')))
            .value,
        closeTo(y, 1e-9),
      );

      final cornerStart = tester.getCenter(
        find.byKey(const Key('scan-corner-0')),
      );
      final corner = await tester.startGesture(
        cornerStart + const Offset(8, 6),
      );
      await corner.moveBy(const Offset(25, 15));
      await tester.pump();
      await corner.moveBy(const Offset(10, 10));
      await corner.up();
      await tester.pump();
      expect(
        cubit.state.corners!.points[0].x,
        closeTo(35 / geometry.rect.width, 1e-9),
      );
      expect(
        cubit.state.corners!.points[0].y,
        closeTo(65 / geometry.rect.height, 1e-9),
      );
      expect(cubit.state.corners!.points[1].x, 1);
      expect(cubit.state.corners!.points[1].y, closeTo(y, 1e-9));
      expect(scrollable.position.pixels, scrollOffset);

      final beforeScroll = cubit.state.corners;
      await tester.dragFrom(
        origin + geometry.rect.center,
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(scrollOffset));
      expect(cubit.state.corners, same(beforeScroll));
      await tester.ensureVisible(find.byKey(const Key('scanCornerHorizontal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanCornerHorizontal')));
      await tester.pumpAndSettle();
      expect(cubit.state.corners!.points[0].x, closeTo(.5, .02));
      expect(cubit.state.corners!.points[1].x, 1);

      cubit.moveEdge(0, const ScanPoint(.5, 1));
      await tester.pumpAndSettle();
      expect(cubit.state.validCorners, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('keepScanPage')))
            .onPressed,
        isNull,
      );
      cubit.resetCorners();
      await tester.pumpAndSettle();
      repository.saveGate = Completer<void>();
      cubit.setProperties(scanProperties({'title': 'Adjusted page'}));
      final keeping = cubit.keepPage();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scan-edge-0')), findsNothing);
      expect(find.byKey(const Key('scan-corner-0')), findsNothing);
      expect(
        tester
            .widget<Slider>(find.byKey(const Key('scanCornerHorizontal')))
            .onChanged,
        isNull,
      );
      repository.saveGate!.complete();
      await keeping;
      await tester.pumpAndSettle();
      expect(cubit.state.draft!.pages, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final size in [const Size(320, 320), const Size(844, 390)]) {
    testWidgets(
      'capture and correction remain reachable at $size with enlarged text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final camera = FixtureScannerCamera();
        final repository = FixtureScanRepository();
        final cubit = ScannerCubit(
          camera: camera,
          repository: repository,
          allowed: true,
        );
        addTearDown(camera.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ScannerScreen(
              cubit: cubit,
              previewBuilder: (_) => const ColoredBox(color: Colors.black),
              canReadDocuments: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('addScanPage')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('addScanPage')));
        await tester.pumpAndSettle();
        final capture = find.byKey(const Key('captureScanPage'));
        expect(capture.hitTestable(), findsOneWidget);
        await tester.tap(capture);
        await tester.pumpAndSettle();
        final keep = find.byKey(const Key('keepScanPage'));
        expect(keep.hitTestable(), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('scanCornerHorizontal')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('scanCornerHorizontal')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(keep);
        await tester.pumpAndSettle();
        expect(cubit.state.draft!.pages, hasLength(1));
        expect(repository.submissions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'permission denial preserves draft; raw fields persist through theme rebuild; invalid submit reveals title',
    (tester) async {
      final camera = FixtureScannerCamera()..denied = true;
      final repository = FixtureScanRepository(
        initial: ScanDraft(
          id: 'saved',
          revision: 1,
          properties: scanProperties(),
          pages: [
            ScanPage(
              id: 'one',
              width: 200,
              height: 300,
              thumbnail: scanJpeg(200, 300),
            ),
          ],
        ),
      );
      final cubit = ScannerCubit(
        camera: camera,
        repository: repository,
        allowed: true,
      );
      addTearDown(camera.close);
      Widget app(ThemeData theme) => MaterialApp(
        theme: theme,
        home: ScannerScreen(
          cubit: cubit,
          previewBuilder: (_) => const SizedBox(),
          canReadDocuments: false,
        ),
      );
      await tester.pumpWidget(app(AppTheme.light()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addScanPage')));
      await tester.pumpAndSettle();
      expect(find.text('Camera permission needed'), findsOneWidget);
      expect(cubit.state.draft!.pages, hasLength(1));
      await tester.tap(find.text('Review scan'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('scan-tags')));
      await tester.enterText(
        find.byKey(const Key('scan-tags')),
        ' Raw \n\nDUP',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.draft.properties.tags, [' Raw ', '', 'DUP']);
      await tester.pumpWidget(app(AppTheme.dark()));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('scan-tags')))
            .controller!
            .text,
        ' Raw \n\nDUP',
      );
      expect(repository.restores, 1);
      await tester.ensureVisible(find.byKey(const Key('scan-title')));
      await tester.enterText(find.byKey(const Key('scan-title')), '');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('uploadScan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uploadScan')));
      await tester.pumpAndSettle();
      final title = tester.widget<TextField>(
        find.byKey(const Key('scan-title')),
      );
      expect(title.focusNode!.hasFocus, isTrue);
      expect(find.byKey(const Key('scan-title')).hitTestable(), findsOneWidget);
      expect(repository.submissions, 0);
      expect(find.text('Enter a document title.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
