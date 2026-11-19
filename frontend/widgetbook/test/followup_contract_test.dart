import 'dart:io';

import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog_case.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/catalog/desktop_cases.dart';
import 'package:domabas_widgetbook/catalog/native_reference_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleFollowup(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> openDesktopFollowup(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  double textScale = 1,
  bool reduced = true,
  String destination = 'documents-grid',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    CatalogPreview(
      entry: CatalogCase(
        id: 'followup-workspace',
        domain: 'Follow-up validation',
        component: 'Real workspace',
        name: destination,
        widgetType: 'GlacierWorkspace',
        builder: (_) => desktopWorkspace(initialSelected: destination),
      ),
      textScale: textScale,
      reduceMotion: reduced,
    ),
  );
  await settleFollowup(tester);
  expect(tester.takeException(), isNull);
}

Finder get followupToken => find.byKey(const ValueKey('activity-dock-token'));
Finder get followupPanel => find.ancestor(
  of: find.widgetWithText(GlacierButton, 'View all activity'),
  matching: find.byType(GlacierSurface),
);
Finder get documentScroller => find.descendant(
  of: find.byType(GlacierDocumentCollection),
  matching: find.byType(CustomScrollView),
);

ScrollPosition followupPosition(WidgetTester tester, Finder scroller) => tester
    .state<ScrollableState>(
      find.descendant(of: scroller, matching: find.byType(Scrollable)).first,
    )
    .position;

Future<void> endFollowupScroll(WidgetTester tester, Finder scroller) async {
  final position = followupPosition(tester, scroller);
  position.jumpTo(position.maxScrollExtent);
  await settleFollowup(tester);
}

Future<void> exerciseFollowupActivity(WidgetTester tester) async {
  await tester.tap(followupToken);
  await settleFollowup(tester);
  if (find.byType(GlacierDialog).evaluate().isNotEmpty) {
    expect(find.text('Your activity'), findsOneWidget);
    expect(followupPanel, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleFollowup(tester);
    expect(find.byType(GlacierDialog), findsNothing);
    expect(tester.widget<InkWell>(followupToken).focusNode!.hasFocus, isTrue);
  } else {
    expect(followupPanel, findsOneWidget);
  }
}

void expectClearOfFollowupActivity(WidgetTester tester, Rect bounds) {
  expect(bounds.overlaps(tester.getRect(followupToken)), isFalse);
  if (followupPanel.evaluate().isNotEmpty) {
    expect(bounds.overlaps(tester.getRect(followupPanel)), isFalse);
  }
}

void main() {
  test('follow-up public additions preserve all existing catalog coverage', () {
    final widgets = <String>{};
    for (final file in Directory(
      '../lib/ui/glacier',
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      widgets.addAll(
        RegExp(
          r'class\s+(Glacier\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|InheritedWidget)',
        ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!),
      );
    }
    final cases = catalogCases();
    expect(widgets, hasLength(140));
    expect(
      widgets.difference(cases.map((entry) => entry.widgetType).toSet()),
      isEmpty,
    );
    expect(cases.where((entry) => entry.nativeCase != null), hasLength(72));
    expect(cases.where((entry) => entry.nativeComponent != null), hasLength(6));
    expect(
      cases.where((entry) => entry.nativeInteraction != null),
      hasLength(3),
    );
    expect(
      cases.where((entry) => entry.mobile && entry.referenceScreen != null),
      hasLength(176),
    );
    for (final name in ['GlacierNativeTitleBar', 'GlacierWorkspaceGeometry']) {
      expect(cases.where((entry) => entry.widgetType == name), isNotEmpty);
    }
  });

  for (final spec in nativeReferenceCases) {
    final id = spec['id']! as String;
    testWidgets('$id has a separate titlebar and bounded content', (
      tester,
    ) async {
      final width = (spec['width']! as num).toDouble();
      final height = (spec['height']! as num).toDouble();
      final query = spec['query']! as Map;
      final large = query['textScale'] == '2';
      final expectedHeight = large ? 52.0 : 44.0;
      await tester.binding.setSurfaceSize(Size(width, height));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: catalogCases().singleWhere((entry) => entry.id == id),
          reduceMotion: true,
        ),
      );
      await settleFollowup(tester);
      final bar = tester.getRect(find.byType(GlacierNativeTitleBar));
      expect(bar, Rect.fromLTWH(0, 0, width, expectedHeight));
      final captions = find.byType(GlacierNativeCaptionControls);
      if (captions.evaluate().isNotEmpty) {
        final rect = tester.getRect(captions);
        expect(rect.top, greaterThanOrEqualTo(bar.top));
        expect(rect.bottom, lessThanOrEqualTo(bar.bottom));
      }
      for (final toolbar in find.byType(GlacierToolbar).evaluate()) {
        final box = toolbar.findRenderObject()! as RenderBox;
        expect(
          box.localToGlobal(Offset.zero).dy,
          greaterThanOrEqualTo(bar.bottom),
        );
      }
      if (find.byType(GlacierDocumentCollection).evaluate().isNotEmpty) {
        final viewport = tester.getRect(documentScroller);
        expect(viewport.top, greaterThan(bar.bottom));
        expect(viewport.bottom, closeTo(height - (width <= 760 ? 12 : 16), 1));
        expect(viewport.height, greaterThan(0));
      }
      for (final type in [GlacierSearchDialog, GlacierReader]) {
        final dialog = find.byType(type);
        if (dialog.evaluate().isNotEmpty) {
          expect(
            tester.getRect(dialog).top,
            greaterThanOrEqualTo(bar.bottom + 8),
          );
          expect(tester.getRect(dialog).bottom, lessThanOrEqualTo(height - 16));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(1440, 900), const Size(800, 800)]) {
    testWidgets('right activity preserves document viewport at $size', (
      tester,
    ) async {
      await openDesktopFollowup(tester, size: size);
      final viewport = tester.getRect(documentScroller);
      final firstCard = tester.getRect(find.byType(GlacierDocumentCard).first);
      final token = tester.getRect(find.byType(GlacierActivityDock));
      final compactExtent = followupPosition(
        tester,
        documentScroller,
      ).maxScrollExtent;
      final compactTail = tester
          .widget<GlacierWorkspaceGeometry>(
            find.byType(GlacierWorkspaceGeometry).first,
          )
          .trailingExtent;
      expect(viewport.bottom, closeTo(size.height - 16, 1));
      expect(token.right, closeTo(viewport.right - 20, 1));
      expect(token.bottom, closeTo(viewport.bottom - 16, 1));
      await tester.tap(followupToken);
      await settleFollowup(tester);
      final panel = tester.getRect(followupPanel);
      final expandedTail = tester
          .widget<GlacierWorkspaceGeometry>(
            find.byType(GlacierWorkspaceGeometry).first,
          )
          .trailingExtent;
      expect(tester.getRect(documentScroller), viewport);
      expect(tester.getRect(find.byType(GlacierDocumentCard).first), firstCard);
      expect(tester.getRect(find.byType(GlacierActivityDock)), token);
      expect(panel.right, closeTo(token.right, 1));
      expect(token.top - panel.bottom, closeTo(8, 1));
      expect(
        expandedTail,
        greaterThanOrEqualTo(viewport.bottom - panel.top + 16),
      );
      expect(expandedTail - compactTail, closeTo(panel.height + 8, 2));
      expect(
        followupPosition(tester, documentScroller).maxScrollExtent -
            compactExtent,
        closeTo(expandedTail - compactTail, 2),
      );
      await endFollowupScroll(tester, documentScroller);
      final next = find.widgetWithText(GlacierButton, 'Next');
      expect(tester.getRect(next).bottom, lessThanOrEqualTo(panel.top - 15));
      await tester.tap(next);
      await settleFollowup(tester);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('12 sample documents · 9–12 shown'), findsOneWidget);
      expect(
        tester
            .widget<GlacierDocumentCollection>(
              find.byType(GlacierDocumentCollection),
            )
            .documents,
        hasLength(4),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'activity resize never feeds its trailing space into viewport size',
    (tester) async {
      await openDesktopFollowup(tester);
      final initialViewport = tester.getRect(documentScroller);
      final initialCard = tester.getRect(
        find.byType(GlacierDocumentCard).first,
      );
      await tester.tap(followupToken);
      await settleFollowup(tester);
      for (var cycle = 0; cycle < 2; cycle++) {
        for (final width in [700.0, 800.0, 1440.0]) {
          await tester.binding.setSurfaceSize(Size(width, 900));
          await settleFollowup(tester);
          final viewport = tester.getRect(documentScroller);
          expect(viewport.bottom, closeTo(884, 1));
          expect(viewport.height, greaterThan(0));
          expect(viewport.height, lessThan(900));
          expect(tester.takeException(), isNull);
        }
        expect(tester.getRect(documentScroller), initialViewport);
        expect(
          tester.getRect(find.byType(GlacierDocumentCard).first),
          initialCard,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFollowup(tester);
      expect(followupPanel, findsNothing);
      expect(tester.getRect(documentScroller), initialViewport);
      expect(tester.widget<InkWell>(followupToken).focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'native resize closes an unusable panel without opening a dialog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: catalogCases().singleWhere(
            (entry) => entry.id == 'native-windows-documents-light',
          ),
          reduceMotion: true,
        ),
      );
      await settleFollowup(tester);
      final initialViewport = tester.getRect(documentScroller);
      final initialCard = tester.getRect(
        find.byType(GlacierDocumentCard).first,
      );
      await tester.tap(followupToken);
      await settleFollowup(tester);
      expect(followupPanel, findsOneWidget);
      final initialTail = tester
          .widget<GlacierWorkspaceGeometry>(
            find.byType(GlacierWorkspaceGeometry).first,
          )
          .trailingExtent;
      await tester.binding.setSurfaceSize(const Size(800, 500));
      await settleFollowup(tester);
      expect(followupPanel, findsNothing);
      expect(find.byType(GlacierDialog), findsNothing);
      expect(tester.getRect(documentScroller).bottom, closeTo(484, 1));
      final constrainedTail = tester
          .widget<GlacierWorkspaceGeometry>(
            find.byType(GlacierWorkspaceGeometry).first,
          )
          .trailingExtent;
      expect(constrainedTail, lessThan(initialTail));
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await settleFollowup(tester);
      expect(find.byType(GlacierDialog), findsNothing);
      expect(followupPanel, findsNothing);
      expect(tester.getRect(documentScroller), initialViewport);
      expect(
        tester.getRect(find.byType(GlacierDocumentCard).first),
        initialCard,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'activity hover and reduced-motion keyboard dismissal retain focus',
    (tester) async {
      await openDesktopFollowup(tester, reduced: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(followupToken));
      await settleFollowup(tester);
      expect(followupPanel, findsOneWidget);
      final visibleTail = tester
          .widget<GlacierWorkspaceGeometry>(
            find.byType(GlacierWorkspaceGeometry).first,
          )
          .trailingExtent;
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      expect(followupPanel, findsOneWidget);
      expect(
        tester
            .widget<GlacierWorkspaceGeometry>(
              find.byType(GlacierWorkspaceGeometry).first,
            )
            .trailingExtent,
        visibleTail,
      );
      await settleFollowup(tester);
      expect(followupPanel, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await openDesktopFollowup(tester);
      tester.widget<InkWell>(followupToken).focusNode!.requestFocus();
      await settleFollowup(tester);
      expect(followupPanel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFollowup(tester);
      expect(followupPanel, findsNothing);
      expect(tester.widget<InkWell>(followupToken).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('right activity leaves workload Save pointer-reachable', (
    tester,
  ) async {
    await openDesktopFollowup(
      tester,
      size: const Size(800, 800),
      textScale: 2,
      destination: 'settings-workload',
    );
    final page = find.byType(GlacierSettingsPage);
    final scroller = find
        .descendant(of: page, matching: find.byType(SingleChildScrollView))
        .first;
    final viewport = tester.getRect(scroller);
    await exerciseFollowupActivity(tester);
    expect(tester.getRect(scroller), viewport);
    await endFollowupScroll(tester, scroller);
    final save = find.widgetWithText(GlacierButton, 'Save changes');
    expect(viewport.contains(tester.getCenter(save)), isTrue);
    expectClearOfFollowupActivity(tester, tester.getRect(save));
    await tester.tap(save);
    await settleFollowup(tester);
    expect(
      find.text('Sample settings saved. No server configuration changed.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final native in [false, true]) {
    testWidgets('right activity preserves Chat Send and Stop, native=$native', (
      tester,
    ) async {
      if (native) {
        await tester.binding.setSurfaceSize(const Size(1024, 768));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          CatalogPreview(
            entry: catalogCases().singleWhere(
              (entry) => entry.id == 'native-windows-chat',
            ),
            textScale: 2,
            reduceMotion: true,
          ),
        );
        await settleFollowup(tester);
      } else {
        await openDesktopFollowup(
          tester,
          size: const Size(1024, 768),
          textScale: 2,
          destination: 'chat-conversation',
        );
      }
      final chat = find.byType(GlacierChatScreen);
      final outer = find
          .descendant(of: chat, matching: find.byType(SingleChildScrollView))
          .first;
      final composer = find.byType(GlacierChatComposer);
      final input = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Find the renewal date');
      await settleFollowup(tester);
      final viewport = tester.getRect(outer);
      await exerciseFollowupActivity(tester);
      expect(tester.getRect(outer), viewport);
      final inner = find
          .ancestor(of: composer, matching: find.byType(SingleChildScrollView))
          .first;
      await endFollowupScroll(tester, inner);
      await endFollowupScroll(tester, outer);
      final send = find.widgetWithText(GlacierButton, 'Send');
      await Scrollable.ensureVisible(tester.element(send), alignment: .5);
      await settleFollowup(tester);
      final sendBounds = tester.getRect(send);
      expect(
        viewport.contains(sendBounds.center),
        isTrue,
        reason:
            'viewport=$viewport send=$sendBounds outer=${followupPosition(tester, outer).pixels}/${followupPosition(tester, outer).maxScrollExtent} inner=${followupPosition(tester, inner).pixels}/${followupPosition(tester, inner).maxScrollExtent} same=${identical(followupPosition(tester, outer), followupPosition(tester, inner))}',
      );
      expectClearOfFollowupActivity(tester, sendBounds);
      await tester.tap(send);
      await settleFollowup(tester);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(
        tester
            .widget<GlacierChatScreen>(chat)
            .messages
            .whereType<GlacierChatMessage>()
            .any((message) => message.text == 'Find the renewal date'),
        isTrue,
      );
      final stop = find.widgetWithText(GlacierButton, 'Stop reply');
      await endFollowupScroll(tester, inner);
      await endFollowupScroll(tester, outer);
      await Scrollable.ensureVisible(tester.element(stop), alignment: .5);
      await settleFollowup(tester);
      expect(viewport.contains(tester.getCenter(stop)), isTrue);
      await tester.tap(stop);
      await settleFollowup(tester);
      expect(find.widgetWithText(GlacierButton, 'Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (size: const Size(1440, 900), scale: 1.0),
    (size: const Size(800, 800), scale: 2.0),
    (size: const Size(800, 500), scale: 1.0),
  ]) {
    testWidgets('native activity retains pagination at $scenario', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(scenario.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CatalogPreview(
          entry: catalogCases().singleWhere(
            (entry) => entry.id == 'native-windows-documents-light',
          ),
          textScale: scenario.scale,
          reduceMotion: true,
        ),
      );
      await settleFollowup(tester);
      final viewport = tester.getRect(documentScroller);
      final card = tester.getRect(find.byType(GlacierDocumentCard).first);
      if (scenario.size.width == 800) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(followupToken));
        await settleFollowup(tester);
        expect(followupPanel, findsNothing);
        expect(find.byType(GlacierDialog), findsNothing);
        tester.widget<InkWell>(followupToken).focusNode!.requestFocus();
        await settleFollowup(tester);
        expect(followupPanel, findsNothing);
        expect(find.byType(GlacierDialog), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFollowup(tester);
        expect(find.byType(GlacierDialog), findsOneWidget);
        expect(find.text('Your activity'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleFollowup(tester);
        expect(find.byType(GlacierDialog), findsNothing);
        expect(
          tester.widget<InkWell>(followupToken).focusNode!.hasFocus,
          isTrue,
        );
      } else {
        await tester.tap(followupToken);
        await settleFollowup(tester);
        expect(followupPanel, findsOneWidget);
      }
      expect(tester.getRect(documentScroller), viewport);
      expect(tester.getRect(find.byType(GlacierDocumentCard).first), card);
      await endFollowupScroll(tester, documentScroller);
      final next = find.widgetWithText(GlacierButton, 'Next');
      final rect = tester.getRect(next);
      expect(
        viewport.contains(rect.center),
        isTrue,
        reason: 'viewport=$viewport next=$rect',
      );
      expectClearOfFollowupActivity(tester, rect);
      await tester.tap(next);
      await settleFollowup(tester);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('12 sample documents · 9–12 shown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
