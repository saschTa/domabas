import 'dart:convert';
import 'dart:io';

import 'package:domabas/ui/glacier.dart';
import 'package:domabas_widgetbook/catalog/catalog.dart';
import 'package:domabas_widgetbook/catalog/desktop_cases.dart';
import 'package:domabas_widgetbook/catalog/native_cases.dart';
import 'package:domabas_widgetbook/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleNative(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> openNative(WidgetTester tester, String id, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    CatalogPreview(
      entry: nativeCases().singleWhere((entry) => entry.id == id),
      reduceMotion: true,
    ),
  );
  await settleNative(tester);
}

void main() {
  testWidgets(
    'Linux leading Close-only preference has an explicit catalog story',
    (tester) async {
      await openNative(
        tester,
        'native-linux-leading-close-only',
        const Size(330, 740),
      );
      final frame = tester.widget<GlacierNativeFrame>(
        find.byType(GlacierNativeFrame),
      );
      expect(
        frame.state.controlLayout,
        GlacierNativeControlLayout.closeOnlyLeft,
      );
      expect(frame.state.captionCommands, [GlacierNativeCommand.close]);
      expect(
        tester.getRect(find.byType(GlacierNativeCaptionControls)).left,
        16,
      );
      expect(find.byTooltip('Minimize window'), findsNothing);
      await tester.tap(find.byTooltip('Close window'));
      await settleNative(tester);
      expect(find.textContaining('Close requested.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('all frozen native cases, contracts and interaction contexts are registered exactly', () {
    final manifest = jsonDecode(
      File('test/fixtures/glacier_native_reference.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final expected = {
      for (final item in manifest['cases'] as List) item['id'] as String,
    };
    final cases = catalogCases();
    expect(expected, hasLength(72));
    expect(nativeCases(), hasLength(86));
    expect(
      cases.any((entry) => entry.id == 'native-linux-leading-close-only'),
      isTrue,
    );
    expect({
      for (final item in cases)
        if (item.nativeCase != null) item.nativeCase!,
    }, expected);
    expect(
      {
        for (final item in cases)
          if (item.nativeComponent != null) item.nativeComponent!,
      },
      {for (final item in manifest['components'] as List) item['id'] as String},
    );
    expect(
      {
        for (final item in cases)
          if (item.nativeInteraction != null) item.nativeInteraction!,
      },
      {
        for (final item in manifest['interactionContexts'] as List)
          item['id'] as String,
      },
    );
    expect(cases.map((entry) => entry.id).toSet(), hasLength(cases.length));
    expect(
      cases.where((entry) => entry.mobile && entry.referenceScreen != null),
      hasLength(176),
    );
    expect(cases.any((entry) => entry.id == 'desktop-workspace'), isTrue);
    final nativeTypes = <String>{};
    for (final source
        in Directory('../lib/ui/glacier')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      nativeTypes.addAll(
        RegExp(
          r'class\s+(GlacierNative\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget|InheritedWidget)',
        ).allMatches(source.readAsStringSync()).map((match) => match.group(1)!),
      );
    }
    expect(nativeTypes, hasLength(8));
    const contextIds = {
      'native-context-titlebar': 'GlacierNativeTitleBar',
      'native-context-workspace-geometry': 'GlacierWorkspaceGeometry',
      'native-context-presentation-scope': 'GlacierNativePresentationScope',
      'native-context-content-insets': 'GlacierNativeContentInsets',
    };
    for (final context in contextIds.entries) {
      expect(
        cases.singleWhere((entry) => entry.id == context.key).widgetType,
        context.value,
      );
    }
    final isolated = cases
        .where(
          (entry) =>
              entry.nativeComponent != null || contextIds.containsKey(entry.id),
        )
        .map((entry) => entry.widgetType)
        .toSet();
    expect(nativeTypes.difference(isolated), isEmpty);
  });

  testWidgets(
    'real native Search remains below captions and window Close preserves the query task',
    (tester) async {
      await openNative(
        tester,
        'native-windows-documents-light',
        const Size(1440, 1000),
      );
      await tester.tap(find.text('Search').first);
      await settleNative(tester);
      expect(find.byType(GlacierSearchDialog), findsOneWidget);
      final bounds = tester.getRect(find.byType(GlacierSearchDialog));
      expect(bounds.top, greaterThanOrEqualTo(44));
      final captions = tester.getRect(
        find.byType(GlacierNativeCaptionControls),
      );
      expect(captions.bottom, lessThanOrEqualTo(44));
      await tester.tap(find.byTooltip('Close window'));
      await settleNative(tester);
      expect(find.byType(GlacierSearchDialog), findsOneWidget);
      expect(find.textContaining('Close requested.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleNative(tester);
      expect(find.byType(GlacierSearchDialog), findsNothing);
      expect(find.byType(GlacierWorkspace), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real native Reader keeps window controls outside its task boundary',
    (tester) async {
      await openNative(
        tester,
        'native-modal-close-request',
        const Size(1440, 1000),
      );
      expect(find.byType(GlacierReader), findsOneWidget);
      await tester.tap(find.byTooltip('Close window'));
      await settleNative(tester);
      expect(find.byType(GlacierReader), findsOneWidget);
      expect(find.textContaining('Close requested.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleNative(tester);
      expect(find.byType(GlacierReader), findsNothing);
      expect(find.byType(GlacierNativeCaptionControls), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native preview controls are inert while an app dialog is active',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await openNative(
          tester,
          'native-windows-documents-light',
          const Size(1440, 1000),
        );
        await tester.tap(find.text('Search').first);
        await settleNative(tester);
        final labels = tester.semantics
            .simulatedAccessibilityTraversal()
            .map((node) => node.getSemanticsData().label)
            .toList();
        expect(labels, isNot(contains('Window preview')));
        expect(labels, contains('Close window'));
        expect(find.byType(GlacierSearchDialog), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('compact drawer preserves its pointer layer and focus return', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await openNative(
        tester,
        'native-windows-minimum-330',
        const Size(330, 740),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Initial compact workspace',
      );
      await tester.tap(find.byTooltip('Open navigation'));
      await settleNative(tester);
      expect(tester.takeException(), isNull, reason: 'Opened native drawer');
      expect(find.byType(GlacierNativeCompactNavigation), findsOneWidget);
      final drawerSearch = find.descendant(
        of: find.byType(GlacierNativeCompactNavigation),
        matching: find.text('Search'),
      );
      expect(drawerSearch, findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Native drawer search',
      );
      final labels = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData().label)
          .toList();
      expect(labels, isNot(contains('Search · Cmd/Ctrl+K')));
      expect(labels, isNot(contains('Window preview')));
      await tester.tap(drawerSearch);
      await settleNative(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Search opened from drawer',
      );
      expect(find.byType(GlacierNativeCompactNavigation), findsNothing);
      expect(find.byType(GlacierSearchDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleNative(tester);
      expect(find.byType(GlacierSearchDialog), findsNothing);
      await tester.tap(find.byTooltip('Open navigation'));
      await settleNative(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleNative(tester);
      expect(find.byType(GlacierNativeCompactNavigation), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Native navigation trigger',
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('catalog maximize and restore retain equivalent keyboard focus', (
    tester,
  ) async {
    await openNative(
      tester,
      'native-caption-maximize-focus',
      const Size(800, 900),
    );
    final maximize = tester.widget<TextButton>(
      find.descendant(
        of: find.byTooltip('Maximize window'),
        matching: find.byType(TextButton),
      ),
    );
    maximize.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleNative(tester);
    expect(
      tester
          .widget<GlacierNativeFrame>(find.byType(GlacierNativeFrame))
          .state
          .mode,
      GlacierNativeWindowMode.maximized,
    );
    final restore = tester.widget<TextButton>(
      find.descendant(
        of: find.byTooltip('Restore window'),
        matching: find.byType(TextButton),
      ),
    );
    expect(restore.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleNative(tester);
    expect(
      tester
          .widget<GlacierNativeFrame>(find.byType(GlacierNativeFrame))
          .state
          .mode,
      GlacierNativeWindowMode.restored,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace collapse refreshes logical exclusion geometry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reports = <GlacierNativeWindowLayout>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: GlacierTheme.light(),
        home: GlacierNativeFrame(
          state: GlacierNativeWindowState(
            platform: GlacierNativePlatform.linux,
            controlLayout: GlacierNativeControlLayout.left,
            reduceMotion: true,
            devicePixelRatio: 2,
          ),
          commands: GlacierNativeWindowCommands(
            onClose: () {},
            onMinimize: () {},
            onMaximize: () {},
            onSystemMenu: () {},
            onLayoutChanged: reports.add,
          ),
          child: desktopWorkspace(),
        ),
      ),
    );
    await settleNative(tester);
    final before = reports.last;
    await tester.tap(find.byTooltip('Collapse sidebar'));
    await settleNative(tester);
    final after = reports.last;
    expect(after.interactiveExclusions, isNot(before.interactiveExclusions));
    expect(after.nativeControlReservations, before.nativeControlReservations);
    expect(after.viewport, const Size(1440, 1000));
    expect(after.devicePixelRatio, 2);
    expect(after.canDragAt(const Offset(700, 12)), isTrue);
    expect(tester.takeException(), isNull);
  });
}
