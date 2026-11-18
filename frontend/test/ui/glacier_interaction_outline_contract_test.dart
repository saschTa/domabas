import 'dart:ui' as ui;

import 'package:domabas/ui/glacier.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _targetKey = ValueKey('outline-contract-target');
const _captureKey = ValueKey('outline-contract-capture');
const _paintKey = ValueKey('glacier-interaction-outline');

class _GlacierOutlinePixels {
  const _GlacierOutlinePixels(this.width, this.bytes);
  final int width;
  final Uint8List bytes;
  Color at(Offset point) {
    final index = (point.dy.floor() * width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes[index + 3],
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
    );
  }
}

Future<_GlacierOutlinePixels> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = _GlacierOutlinePixels(
      image.width,
      Uint8List.fromList(data!.buffer.asUint8List()),
    );
    image.dispose();
    return result;
  }))!;
}

Finder _paintFor(Finder target) =>
    find.descendant(of: target, matching: find.byKey(_paintKey));

int _activeOutlines(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byKey(_paintKey))
    .where((paint) => paint.foregroundPainter != null)
    .length;

Future<void> _host(
  WidgetTester tester, {
  required bool dark,
  required WidgetBuilder control,
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = (dark ? GlacierTheme.dark() : GlacierTheme.light()).copyWith(
    platform: platform,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: RepaintBoundary(
          key: _captureKey,
          child: Material(
            color: theme.extension<GlacierTokens>()!.canvas,
            child: Center(
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(onPressed: () {}, child: const Text('Before')),
                    Builder(builder: control),
                    TextButton(onPressed: () {}, child: const Text('After')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tabToTarget(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

Future<void> _expectPaintedKeyboardRing(
  WidgetTester tester,
  Finder target,
  Color accent,
) async {
  final paint = _paintFor(target).first;
  await _expectPaintedOutline(tester, paint, accent);
}

Future<void> _expectPaintedOutline(
  WidgetTester tester,
  Finder paint,
  Color accent,
) async {
  expect(tester.widget<CustomPaint>(paint).foregroundPainter, isNotNull);
  final rect = tester.getRect(paint);
  final pixels = await _capture(tester);
  expect(pixels.at(Offset(rect.left - 4, rect.center.dy)), accent);
  expect(pixels.at(Offset(rect.right + 3, rect.center.dy)), accent);
  expect(pixels.at(Offset(rect.left - 7, rect.center.dy)), isNot(accent));
}

void main() {
  for (final dark in [false, true]) {
    final tokens = dark ? GlacierTokens.dark : GlacierTokens.light;
    for (final kind in [...GlacierButtonKind.values, null]) {
      testWidgets(
        'keyboard-only ring preserves button geometry $kind dark=$dark',
        (tester) async {
          var presses = 0;
          await _host(
            tester,
            dark: dark,
            control: (_) => kind == null
                ? GlacierIconButton(
                    key: _targetKey,
                    label: 'Action',
                    icon: Icons.add,
                    onPressed: () => presses++,
                  )
                : GlacierButton(
                    key: _targetKey,
                    label: 'Action',
                    kind: kind,
                    onPressed: () => presses++,
                  ),
          );
          final target = find.byKey(_targetKey);
          final initial = tester.getRect(target);
          final semantics = tester.ensureSemantics();
          try {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: const Offset(1, 1));
            addTearDown(mouse.removePointer);
            await mouse.moveTo(tester.getCenter(target));
            await tester.pumpAndSettle();
            expect(_activeOutlines(tester), 0);
            await mouse.down(tester.getCenter(target));
            await mouse.up();
            await tester.pumpAndSettle();
            expect(presses, 1);
            expect(_activeOutlines(tester), 0);
            await mouse.moveTo(const Offset(1, 1));
            await _tabToTarget(tester);
            expect(_activeOutlines(tester), 1);
            await _expectPaintedKeyboardRing(tester, target, tokens.accent);
            expect(tester.getRect(target), initial);
            final actions = tester.semantics
                .simulatedAccessibilityTraversal()
                .map((node) => node.getSemanticsData())
                .where((data) => data.hasAction(ui.SemanticsAction.tap))
                .toList();
            expect(actions, hasLength(3));
            expect(
              actions.where(
                (data) => data.label == 'Action' || data.tooltip == 'Action',
              ),
              hasLength(1),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(presses, 2);
            final semanticAction = tester.semantics
                .simulatedAccessibilityTraversal()
                .singleWhere((node) {
                  final data = node.getSemanticsData();
                  return data.hasAction(ui.SemanticsAction.tap) &&
                      (data.label == 'Action' || data.tooltip == 'Action');
                });
            semanticAction.owner!.performAction(
              semanticAction.id,
              ui.SemanticsAction.tap,
            );
            await tester.pumpAndSettle();
            expect(presses, 3);
            expect(_activeOutlines(tester), 1);
            await tester.tapAt(const Offset(20, 20));
            await tester.pumpAndSettle();
            expect(_activeOutlines(tester), 0);
            await tester.tap(target, kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(presses, 4);
            expect(_activeOutlines(tester), 0);
            await _tabToTarget(tester);
            expect(_activeOutlines(tester), 1);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(_activeOutlines(tester), 0);
            expect(
              FocusManager.instance.primaryFocus!.context!
                  .findAncestorWidgetOfExactType<TextButton>()!
                  .child,
              isA<Text>().having((text) => text.data, 'label', 'After'),
            );
            expect(tester.getRect(target), initial);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    _selectionCases(dark, tokens);
    _documentCase(dark, tokens);
    _sidebarCase(dark, tokens);
  }
  _touchCase();
}

void _selectionCases(bool dark, GlacierTokens tokens) {
  for (final toggle in [false, true]) {
    testWidgets('selection hover disabled keyboard toggle=$toggle dark=$dark', (
      tester,
    ) async {
      bool? selected = false;
      var enabled = true;
      var changes = 0;
      late StateSetter update;
      await _host(
        tester,
        dark: dark,
        control: (_) => StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return toggle
                ? GlacierSwitchRow(
                    key: _targetKey,
                    label: 'Permission',
                    value: selected == true,
                    onChanged: enabled
                        ? (value) => update(() {
                            selected = value;
                            changes++;
                          })
                        : null,
                  )
                : GlacierChoice(
                    key: _targetKey,
                    label: 'Permission',
                    compact: true,
                    selected: selected,
                    onChanged: enabled
                        ? (value) => update(() {
                            selected = value;
                            changes++;
                          })
                        : null,
                  );
          },
        ),
      );
      final target = find.byKey(_targetKey);
      final initial = tester.getRect(target);
      BorderSide edge() {
        final shape = toggle
            ? tester
                  .widget<SwitchListTile>(
                    find.descendant(
                      of: target,
                      matching: find.byType(SwitchListTile),
                    ),
                  )
                  .shape
            : tester
                  .widget<Material>(
                    find
                        .descendant(of: target, matching: find.byType(Material))
                        .first,
                  )
                  .shape;
        return (shape! as OutlinedBorder).side;
      }

      expect(
        edge().color,
        toggle
            ? Colors.transparent
            : Color.lerp(tokens.solid, tokens.muted, .42),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(edge().width, 1);
      expect(edge().color, tokens.accent);
      expect(_activeOutlines(tester), 0);
      await tester.tap(target, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(changes, 1);
      expect(edge().color, tokens.accent);
      expect(_activeOutlines(tester), 0);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(edge().color, Color.lerp(tokens.solid, tokens.accent, .55));
      final semantics = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('Permission'), findsOneWidget);
        if (!toggle) {
          update(() => selected = null);
          await tester.pumpAndSettle();
          expect(edge().color, Color.lerp(tokens.solid, tokens.accent, .55));
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('Permission'))
                .getSemanticsData()
                .flagsCollection
                .isChecked,
            ui.CheckedState.mixed,
          );
          update(() => selected = true);
          await tester.pumpAndSettle();
        }
        await _tabToTarget(tester);
        expect(_activeOutlines(tester), 1);
        await _expectPaintedKeyboardRing(tester, target, tokens.accent);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selected, isFalse);
        expect(changes, 2);
        expect(tester.getRect(target), initial);
        update(() => enabled = false);
        await tester.pumpAndSettle();
        expect(_activeOutlines(tester), 0);
        expect(edge().color, Colors.transparent);
        await mouse.moveTo(tester.getCenter(target));
        await tester.pumpAndSettle();
        expect(edge().color, Colors.transparent);
        await tester.tap(target, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(changes, 2);
        update(() => enabled = true);
        await tester.pumpAndSettle();
        expect(edge().color, tokens.accent);
        update(() => enabled = false);
        await tester.pumpAndSettle();
        await _tabToTarget(tester);
        expect(_activeOutlines(tester), 0);
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<TextButton>()!
              .child,
          isA<Text>().having((text) => text.data, 'label', 'After'),
        );
        expect(tester.getRect(target), initial);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

void _documentCase(bool dark, GlacierTokens tokens) {
  testWidgets(
    'document hover and Retry keep separate focus targets dark=$dark',
    (tester) async {
      var opens = 0;
      var retries = 0;
      await _host(
        tester,
        dark: dark,
        control: (_) => GlacierDocumentCard(
          key: _targetKey,
          document: const GlacierDocumentValue(
            id: 'lease',
            title: 'Lease',
            failed: true,
            status: 'Processing failed',
          ),
          preview: const ColoredBox(color: Colors.white),
          onOpen: () => opens++,
          onRetry: () => retries++,
        ),
      );
      final target = find.byKey(_targetKey);
      final initial = tester.getRect(target);
      final surface = find.descendant(
        of: target,
        matching: find.byType(GlacierSurface),
      );
      expect(
        tester.widget<GlacierSurface>(surface).borderColor,
        isNot(tokens.accent),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      expect(tester.widget<GlacierSurface>(surface).borderColor, tokens.accent);
      expect(tester.getRect(target), initial);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GlacierSurface>(surface).borderColor,
        isNot(tokens.accent),
      );
      await _tabToTarget(tester);
      expect(_activeOutlines(tester), 1);
      await _expectPaintedKeyboardRing(tester, target, tokens.accent);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_activeOutlines(tester), 1);
      final paints = tester.widgetList<CustomPaint>(_paintFor(target)).toList();
      expect(paints.first.foregroundPainter, isNull);
      expect(paints.last.foregroundPainter, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(opens, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_activeOutlines(tester), 0);
      expect(tester.getRect(target), initial);
      expect(tester.takeException(), isNull);
    },
  );
}

void _touchCase() {
  testWidgets('touch choice never retains hover or keyboard outlines', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final routesBefore =
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
    var selected = false;
    await _host(
      tester,
      dark: false,
      platform: TargetPlatform.android,
      control: (_) => StatefulBuilder(
        builder: (_, update) => GlacierChoice(
          key: _targetKey,
          label: 'Touch choice',
          compact: true,
          selected: selected,
          onChanged: (value) => update(() => selected = value!),
        ),
      ),
    );
    final target = find.byKey(_targetKey);
    final initial = tester.getRect(target);
    await tester.tap(target, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(_activeOutlines(tester), 0);
    final ink = tester.widget<InkWell>(
      find.descendant(of: target, matching: find.byType(InkWell)),
    );
    expect(ink.statesController!.value, isNot(contains(WidgetState.hovered)));
    expect(tester.getRect(target), initial);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(
      GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
      routesBefore,
    );
    expect(tester.takeException(), isNull);
  });
}

void _sidebarCase(bool dark, GlacierTokens tokens) {
  testWidgets(
    'sidebar search inset and navigation focus stay distinct dark=$dark',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = 'documents';
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? GlacierTheme.dark() : GlacierTheme.light(),
          home: RepaintBoundary(
            key: _captureKey,
            child: StatefulBuilder(
              builder: (_, update) => GlacierWorkspace(
                destinations: const [
                  GlacierDestination(
                    id: 'documents',
                    label: 'Documents',
                    icon: Icons.description_outlined,
                  ),
                  GlacierDestination(
                    id: 'invoices',
                    label: 'Invoices',
                    icon: Icons.receipt_outlined,
                  ),
                ],
                selected: selected,
                onSelected: (value) => update(() => selected = value),
                onSearch: () {},
                libraryLabel: 'Personal library',
                accountLabel: 'Alex',
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.widgetWithText(OutlinedButton, 'Search');
      final navigation = find.byKey(
        const ValueKey('navigation-trigger-documents'),
      );
      final searchRect = tester.getRect(search);
      final navigationRect = tester.getRect(navigation);
      final searchPaint = find
          .ancestor(of: search, matching: find.byKey(_paintKey))
          .first;
      final navigationPaint = find
          .ancestor(of: navigation, matching: find.byKey(_paintKey))
          .first;
      Future<void> tabTo(Finder paint) async {
        for (var count = 0; count < 16; count++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          if (tester.widget<CustomPaint>(paint).foregroundPainter != null) {
            return;
          }
        }
        fail('Keyboard traversal did not reach the sidebar target.');
      }

      await tabTo(searchPaint);
      expect(_activeOutlines(tester), 1);
      final pixels = await _capture(tester);
      expect(
        pixels.at(Offset(searchRect.left + 1, searchRect.center.dy)),
        tokens.accent,
      );
      expect(
        pixels.at(Offset(searchRect.left - 3, searchRect.center.dy)),
        isNot(tokens.accent),
      );
      await tabTo(navigationPaint);
      expect(_activeOutlines(tester), 1);
      await _expectPaintedOutline(tester, navigationPaint, tokens.accent);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 'documents');
      expect(tester.getRect(search), searchRect);
      expect(tester.getRect(navigation), navigationRect);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(navigation));
      await tester.tap(navigation, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(_activeOutlines(tester), 0);
      expect(tester.getRect(navigation), navigationRect);
      expect(tester.takeException(), isNull);
    },
  );
}
